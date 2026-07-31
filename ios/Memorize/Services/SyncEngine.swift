import Foundation

/// Synkronoinnin ajuri: työnnä ensin, vedä sitten.
///
/// Järjestys on tärkeä. Jos vetäisi ensin, juuri kerrottu muisto olisi vielä
/// vain paikallisesti ja etäversio voisi ylikirjoittaa sen. Työntö ensin
/// tarkoittaa että oma työ on turvassa ennen kuin mitään sovelletaan päälle.
@MainActor
@Observable
final class SyncEngine {
    enum State: Equatable {
        case idle
        case syncing
        /// Epäonnistuminen ei ole virhetila vaan odotustila: paikallinen data on
        /// tallessa ja jono purkautuu kun yhteys palaa.
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

    /// Yksi kierros. Turvallinen kutsua usein — päällekkäiset kutsut ohitetaan.
    func sync() async {
        guard isEnabled, !isRunning, let base = AppServices.apiBaseURL else { return }
        isRunning = true
        state = .syncing
        defer { isRunning = false }

        let client = SyncClient(baseURL: base, token: session.identity.token)

        do {
            // 0. Lataa media ENNEN työntöä, jotta rivit kulkevat avaimineen.
            //    Muuten toinen laite näkisi muiston mutta ei kuvaa johon se
            //    liittyy, ja korjaus tulisi vasta seuraavalla kierroksella.
            await uploadPendingMedia(base: base)

            // 1. Työnnä oma työ.
            let payload = store.pendingPayload()
            if store.hasPendingChanges {
                let result = try await client.push(payload)
                store.clearPending(payload)
                store.advance(seq: result.seq)
            }

            // 2. Vedä muiden työ. Silmukka, koska palvelin rajaa yhden
            //    vastauksen kokoa: ensimmäinen synkronointi voi tuoda satoja
            //    rivejä useassa erässä.
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
            // Ei näytetä käyttäjälle. Muistot ovat tallessa paikallisesti, ja
            // jono purkautuu itsestään — verkkovirhe ei ole hänen ongelmansa.
            state = .waitingForNetwork
        }
    }

    /// Lataa odottavat kuvat ja äänet. Yksi epäonnistunut tiedosto ei estä
    /// muita: kuva voi olla rikki, mutta muiston pitää silti päästä perille.
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

// MARK: - Kuljetus

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
