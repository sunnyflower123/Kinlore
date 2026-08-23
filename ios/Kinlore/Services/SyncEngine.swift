import CryptoKit
import Foundation

/// The sync driver: push first, then pull.
///
/// The order matters. Pulling first would leave a memory that was just told
/// only local, and the remote version could overwrite it. Pushing first means
/// our own work is safe before anything is applied on top of it.
@MainActor
@Observable
final class SyncEngine {
    enum State: Equatable {
        case idle
        case syncing
        /// A failure is not an error state but a waiting state: the local data
        /// is safe and the queue drains when the connection returns.
        case waitingForNetwork
    }

    private(set) var state: State = .idle
    private(set) var lastSyncedAt: Date?

    /// Photographs the free tier refused this round.
    ///
    /// Counted rather than swallowed: the refusal is an answer about the
    /// family's ceiling, not an outage, and without this the refused
    /// photograph looks normal in the grid while silently never reaching the
    /// family — the failure docs/UX.md §9 names. Recomputed every round; the
    /// retry is the ordinary lifecycle one (open, foreground, entitlement
    /// change), and going paid clears the count by making the uploads succeed.
    private(set) var photosOverQuota = 0

    private let store: MemoryStore
    private let session: Session
    private var isRunning = false

    init(store: MemoryStore, session: Session) {
        self.store = store
        self.session = session
    }

    var isEnabled: Bool {
        if case .inFamily = session.mode { return AppServices.apiBaseURL != nil }
        return false
    }

    /// One round. Safe to call often — overlapping calls are ignored.
    func sync() async {
        guard isEnabled, !isRunning, let base = AppServices.apiBaseURL else { return }
        isRunning = true
        state = .syncing
        defer { isRunning = false }

        let client = SyncClient(baseURL: base, token: session.identity.token)

        do {
            // 0. Upload media BEFORE pushing, so the rows travel with their
            //    keys. Otherwise the other device would see the memory but not
            //    the photo it belongs to, and the fix would only arrive on the
            //    next round.
            await uploadPendingMedia(base: base)

            // 1. Push our own work, sealed. PLAN.md §10 lever 3.
            //
            // `clearPending` is given the payload as it was built rather than
            // as it was sent: it clears the outbox by row id, and the sealed
            // copy carries the same ids — but reading the plaintext one here
            // keeps it obvious that nothing downstream of the seal is expected
            // to be readable.
            let payload = store.pendingPayload()
            if !payload.isEmpty {
                _ = try await client.push(sealing(payload))
                store.clearPending(payload)
                // The cursor does not move here. The push reply's number is
                // the family-global counter, and jumping to it would step
                // past anything the others committed since this device last
                // pulled — their tellings would then never be fetched, on
                // this round or any later one, with nothing on any screen to
                // say so. The pull below returns this device's own rows once
                // more; `applyRemote` re-applies them unchanged, which costs
                // a little bandwidth and loses nothing.
            }

            // 2. Pull everyone else's work. A loop, because the server caps the
            //    size of one response: the first sync can bring hundreds of
            //    rows in several batches.
            var rounds = 0
            while rounds < 20 {
                let reply = try await client.pull(since: store.syncSeq)
                store.applyRemote(opening(reply))
                rounds += 1
                if !reply.more { break }
            }

            lastSyncedAt = .now
            state = .idle
        } catch {
            // Not shown to the user. The memories are safe locally and the
            // queue drains by itself — a network error is not her problem.
            state = .waitingForNetwork
        }
    }

    // MARK: - Encryption at rest

    /// PLAN.md §10 lever 3. Without a key nothing is sealed and the payload
    /// travels as it always did.
    ///
    /// That fallback is the honest one rather than the safe-looking one. The
    /// alternative — refusing to sync without a key — turns a missing Keychain
    /// entry into an archive that silently stops leaving the phone, which is
    /// the failure this app is least able to notice. A family created before
    /// lever 3 has no key and keeps working; one created after always has one,
    /// because `createFamily` makes it before the first row can exist.
    private func sealing(_ payload: SyncPayload) -> SyncPayload {
        guard let key = FamilyKey.current() else { return payload }
        return payload.sealed(with: key)
    }

    private func opening(_ reply: SyncPullReply) -> SyncPullReply {
        guard let key = FamilyKey.current() else { return reply }
        return reply.opened(with: key)
    }

    /// Uploads pending photos and audio. One failed file does not block the
    /// others: a photo may be broken, but the memory still has to get through.
    ///
    /// The bytes are sealed before they leave. R2 is where rule 3 lives — the
    /// original audio is the product — and it is the one store where the thing
    /// a breach hands out and the thing the family came for are the same file.
    /// Sealing is not re-encoding: what is uploaded is the recorded bytes
    /// inside an envelope, and `MediaLoader` takes them back out.
    private func uploadPendingMedia(base: URL) async {
        let media = MediaClient(baseURL: base, token: session.identity.token)
        let familyKey = FamilyKey.current()

        var refused = 0
        for subject in store.subjectsAwaitingUpload() {
            guard let filename = subject.imageFilename,
                  let data = try? Data(contentsOf: MediaStore.url(for: filename))
            else { continue }
            do {
                let key = try await media.upload(data: seal(data, familyKey), kind: .photo)
                store.setR2Key(subjectID: subject.id, key: key)
            } catch RemoteError.quotaExceeded {
                // The ceiling, not the network. Counted so the gallery can say
                // so; the photo stays queued and travels the day there is room.
                refused += 1
            } catch {
                // Transient — the next lifecycle round retries, as ever.
            }
        }
        photosOverQuota = refused

        for memory in store.memoriesAwaitingUpload() {
            guard let filename = memory.audioFilename,
                  let data = try? Data(contentsOf: MediaStore.url(for: filename))
            else { continue }
            if let key = try? await media.upload(data: seal(data, familyKey), kind: .audio) {
                store.setAudioR2Key(memoryID: memory.id, key: key)
            }
        }
    }

    /// Sealing that cannot lose the file. If the seal fails there is nothing
    /// useful to do with a photograph except send it as it is — the row is
    /// already queued, and dropping it would leave a memory pointing at a
    /// recording that never arrives.
    private func seal(_ data: Data, _ key: SymmetricKey?) -> Data {
        guard let key else { return data }
        return FamilyCrypto.seal(data, with: key) ?? data
    }
}

// MARK: - Transport

private struct SyncClient {
    let baseURL: URL
    let token: String

    struct PushResult: Decodable {
        let seq: Int
        let accepted: Int
    }

    func push(_ payload: SyncPayload) async throws -> PushResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return try await perform(request)
    }

    func pull(since: Int) async throws -> SyncPullReply {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("sync"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "since", value: String(since))]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
