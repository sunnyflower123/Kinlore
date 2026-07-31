import SwiftUI

@main
struct MemorizeApp: App {
    /// Yksi jaettu tallennus koko sovellukselle. Korvautuu Worker-clientilla
    /// kun synkronointi tulee — näkymät eivät tiedä eroa.
    @State private var store = MemoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                #if DEBUG
                .task { await Self.reportBackendStatus() }
                #endif
        }
    }

    #if DEBUG
    /// Kertoo käynnistyksessä käytetäänkö stubeja vai oikeaa backendiä, ja
    /// vastaako backend. Ilman tätä väärä osoite näkyisi vasta siinä vaiheessa
    /// kun käyttäjä on jo puhunut minuutin ja tulos katoaa.
    private static func reportBackendStatus() async {
        guard let base = AppServices.apiBaseURL else {
            print("[memorize] backend: ei määritetty — stubit käytössä")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(
                from: base.appendingPathComponent("health")
            )
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[memorize] backend \(base.absoluteString) → HTTP \(code) \(body)")
        } catch {
            print("[memorize] backend \(base.absoluteString) → VIRHE: \(error.localizedDescription)")
        }
    }
    #endif
}
