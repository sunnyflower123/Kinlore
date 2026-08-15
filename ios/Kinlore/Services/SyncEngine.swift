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

            // 1. Push our own work.
            let payload = store.pendingPayload()
            if !payload.isEmpty {
                let result = try await client.push(payload)
                store.clearPending(payload)
                store.advance(seq: result.seq)
            }

            // 2. Pull everyone else's work. A loop, because the server caps the
            //    size of one response: the first sync can bring hundreds of
            //    rows in several batches.
            var rounds = 0
            while rounds < 20 {
                let reply = try await client.pull(since: store.syncSeq)
                store.applyRemote(reply)
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

    /// Uploads pending photos and audio. One failed file does not block the
    /// others: a photo may be broken, but the memory still has to get through.
    private func uploadPendingMedia(base: URL) async {
        let media = MediaClient(baseURL: base, token: session.identity.token)

        for subject in store.subjectsAwaitingUpload() {
            guard let filename = subject.imageFilename,
                  let data = try? Data(contentsOf: MediaStore.url(for: filename))
            else { continue }
            if let key = try? await media.upload(data: data, kind: .photo) {
                store.setR2Key(subjectID: subject.id, key: key)
            }
        }

        for memory in store.memoriesAwaitingUpload() {
            guard let filename = memory.audioFilename,
                  let data = try? Data(contentsOf: MediaStore.url(for: filename))
            else { continue }
            if let key = try? await media.upload(data: data, kind: .audio) {
                store.setAudioR2Key(memoryID: memory.id, key: key)
            }
        }
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
