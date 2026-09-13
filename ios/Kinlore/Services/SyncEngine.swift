import CryptoKit
import Foundation
import Network

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
        /// The server no longer knows this device — a 401, not weather. The
        /// realistic cause is the synchronizable Keychain: "Tyhjennä tämä
        /// laite" on another phone sharing the Apple ID renews the identity
        /// there and deletes this one's credentials with it. Kept apart from
        /// the network case because the network's promise — it fixes itself —
        /// is exactly the sentence that must not be said here.
        case refused
    }

    private(set) var state: State = .idle
    private(set) var lastSyncedAt: Date?

    /// The way back from `.refused`: a new invitation, joined without losing
    /// anything on this phone (`Session.rejoin`). Asked for by the note on
    /// Muistot or by a tapped link, presented by `KinloreApp`. Until 5 Sep
    /// 2026 the only mention of a refused device was a row on the Perhe screen
    /// with no action, and the documented way back ran through "Poistu
    /// perheestä" — which the same server refuses (founder's-eye review,
    /// finding #57).
    var isRejoining = false
    var rejoinCode: String?

    func askToRejoin(code: String? = nil) {
        rejoinCode = code
        isRejoining = true
    }

    /// `-sync refused` holds the state still for the audit and the tests: the
    /// real one needs a Worker that has forgotten this device.
    private var isHeld = false

    /// Photographs the free tier refused this round.
    ///
    /// Counted rather than swallowed: the refusal is an answer about the
    /// family's ceiling, not an outage, and without this the refused
    /// photograph looks normal in the grid while silently never reaching the
    /// family — the failure docs/UX.md §9 names. Recomputed every round; the
    /// retry is the ordinary lifecycle one (open, foreground, entitlement
    /// change), and going paid clears the count by making the uploads succeed.
    private(set) var photosOverQuota = 0

    /// The family's photographs and voices on this phone, all of them — see
    /// `FullCopy`. Started after every successful round, in the background.
    let fullCopy: FullCopy

    /// The network coming back, watched — for the phone that never left the
    /// hand.
    ///
    /// The lifecycle triggers retry when the phone is picked up again, and
    /// ARCHITECTURE.md §3 decided against timers on purpose. A joiner standing
    /// in a kitchen whose Wi-Fi dropped under the first pull is neither case:
    /// the family's memories are one round away, and until 6 Sep 2026 that
    /// round waited for her to put the phone down and pick it up again
    /// (founder's-eye review, finding #63). The path changing is an event the
    /// system delivers, like the foreground — so it is watched, and acted on
    /// only while a round is being waited for: an idle phone's network
    /// flapping costs nothing, and a refused device is not the network's.
    private let networkReturn = NWPathMonitor()
    /// The monitor's first report is the current path, not a change.
    private var hasSeenNetworkPath = false

    private let store: MemoryStore
    private let session: Session
    private var isRunning = false

    init(store: MemoryStore, session: Session) {
        self.store = store
        self.session = session
        fullCopy = FullCopy(ports: Self.ports(store: store, session: session))
        // Before any round can ask it — see `NetworkPrice.warm`.
        NetworkPrice.warm()
        networkReturn.pathUpdateHandler = { [weak self] path in
            let isBack = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.hasSeenNetworkPath else {
                    self.hasSeenNetworkPath = true
                    return
                }
                guard isBack, self.state == .waitingForNetwork else { return }
                await self.sync()
            }
        }
        networkReturn.start(queue: DispatchQueue(label: "kinlore.network-return"))
        #if DEBUG
        // `-copy waiting` holds the family screen's row in its longest state
        // — some fetched, the rest waiting for Wi-Fi — for the audit.
        if UserDefaults.standard.string(forKey: "copy") == "waiting" {
            fullCopy.hold(progress: .init(have: 3, total: 12), halt: .expensiveNetwork)
        }
        if UserDefaults.standard.string(forKey: "sync") == "refused" {
            state = .refused
            isHeld = true
        }
        #endif
    }

    /// Wires the copy to the phone: the rows, the media store, the same fetch
    /// the views use, the network's price and the disk.
    private static func ports(store: MemoryStore, session: Session) -> FullCopy.Ports {
        FullCopy.Ports(
            items: {
                // Voices, then photographs: what has a key and has not been
                // taken back. A merged card's memories moved with the merge.
                store.memories
                    .filter { $0.deletedAt == nil && $0.audioR2Key != nil }
                    .map { FullCopy.Item(id: $0.id, kind: .audio, key: $0.audioR2Key!, filename: $0.audioFilename) }
                + store.subjects
                    .filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.r2Key != nil }
                    .map { FullCopy.Item(id: $0.id, kind: .photo, key: $0.r2Key!, filename: $0.imageFilename) }
                // And the colours the family confirmed, which the copy fetches
                // after the photographs they colour.
                + store.subjects
                    .filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.colourR2Key != nil }
                    .map { FullCopy.Item(id: $0.id, kind: .colour, key: $0.colourR2Key!, filename: $0.colourImageFilename) }
            },
            exists: { MediaStore.exists($0) },
            fetch: { key in await MediaLoader.fetch(key: key, session: session) },
            save: { data, ext in MediaStore.saveRaw(data, extension: ext) },
            record: { item, filename in
                switch item.kind {
                case .audio: store.setLocalAudio(memoryID: item.id, filename: filename, saving: false)
                case .photo: store.setLocalImage(subjectID: item.id, filename: filename, saving: false)
                case .colour: store.setLocalColour(subjectID: item.id, filename: filename, saving: false)
                }
            },
            flush: { store.save() },
            networkIsCheap: { NetworkPrice.isCheap },
            freeBytes: {
                let values = try? URL.documentsDirectory.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                )
                return values?.volumeAvailableCapacityForImportantUsage
            }
        )
    }

    var isEnabled: Bool {
        if case .inFamily = session.mode { return AppServices.apiBaseURL != nil }
        return false
    }

    /// One round. Safe to call often — overlapping calls are ignored.
    func sync() async {
        guard isEnabled, !isRunning, !isHeld, let base = AppServices.apiBaseURL else { return }
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
            // A loop, for the reason the pull below is one: the server caps
            // every table of one request at `MemoryStore.maxRowsPerPush` and
            // writes no more than that. `pendingPayload` hands out at most
            // that much, so what is offered and what is stored are the same
            // set — which is the whole invariant `clearPending` rests on. It
            // did not hold until 10 Sep 2026: the payload was uncapped, the
            // server sliced the overflow away without saying so, and the
            // outbox was emptied of the rows that never arrived. An archive
            // opened to a family for the first time (`markAllPending`) is
            // exactly the case that overflows, and it is also the one case
            // where every row in it is the only copy.
            //
            // `clearPending` is given the payload as it was built rather than
            // as it was sent: it clears the outbox by row id, and the sealed
            // copy carries the same ids — but reading the plaintext one here
            // keeps it obvious that nothing downstream of the seal is expected
            // to be readable.
            //
            // The bound is the same kind of stop as the pull's: each round
            // clears what it sent, so the loop ends on its own, and 40 rounds
            // is twenty thousand rows of one table — far past any family
            // archive, and a ceiling rather than a schedule.
            var pushes = 0
            while pushes < 40 {
                let payload = store.pendingPayload()
                if payload.isEmpty { break }
                _ = try await client.push(sealing(payload))
                store.clearPending(payload)
                pushes += 1
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
            // The bytes, after the rows. Not awaited: the callers of `sync()`
            // go on to the catch-up and the places, and a family's whole
            // archive should not stand between them and that.
            Task { await fullCopy.run() }
        } catch {
            // Not shown to the user as an error. The memories are safe locally
            // and the queue drains by itself — a network error is not her
            // problem. A refused identity is told apart, because its waiting
            // never ends and the notes that promise otherwise must not.
            state = (error as? URLError)?.code == .userAuthenticationRequired
                ? .refused
                : .waitingForNetwork
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

        // A confirmed colouring, sealed like the photograph it colours. It is
        // outside the photo limit on the server, and a failure is simply tried
        // again next round: the yes stays on this phone, and does not travel,
        // until its file has a key.
        for subject in store.coloursAwaitingUpload() {
            guard let filename = subject.colourImageFilename,
                  let data = try? Data(contentsOf: MediaStore.url(for: filename))
            else { continue }
            if let key = try? await media.upload(data: seal(data, familyKey), kind: .colour) {
                store.setColourR2Key(subjectID: subject.id, key: key)
            }
        }

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

// MARK: - What the network costs

/// Whether the current path is one a family would want an archive fetched
/// over. Cellular and hotspots are "expensive" in the system's own word, and
/// Low Data Mode is "constrained"; either one stops the full copy.
///
/// **A monitor answers wrongly until its first report.** `currentPath` is
/// `unsatisfied` from `start()` until the first update arrives — 1 ms later
/// on a machine that was on Wi-Fi the whole time, measured 6 Sep 2026 — and
/// the monitor used to be started by the first question it was asked. That
/// question was the joiner's first copy: the round after joining fetched
/// nothing, halted as "waiting for Wi-Fi" on a Wi-Fi phone, and the family
/// screen said so until the next sync. Found by running the copy against a
/// real Worker for the first time (ARCHITECTURE §5), which the check script
/// cannot: the network arrives there as a closure. So the engine warms the
/// monitor at init, long before any round can complete.
@MainActor
enum NetworkPrice {
    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "kinlore.network-price"))
        return monitor
    }()

    /// Starts the monitor so that its first report has arrived by the time
    /// `isCheap` is asked.
    static func warm() {
        _ = monitor
    }

    static var isCheap: Bool {
        let path = monitor.currentPath
        return path.status == .satisfied && !path.isExpensive && !path.isConstrained
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
            // 401 kept apart from everything else: a device the server has
            // stopped knowing is not a dead cottage connection, and the
            // engine's state machine has a case for exactly that difference.
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                throw URLError(.userAuthenticationRequired)
            }
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
