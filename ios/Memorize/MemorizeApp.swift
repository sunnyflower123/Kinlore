import SwiftUI

@main
struct MemorizeApp: App {
    /// Yksi jaettu tallennus koko sovellukselle. Korvautuu synkronoivalla
    /// toteutuksella jakson C lopussa — näkymät eivät tiedä eroa.
    @State private var store = MemoryStore()
    @State private var session = Session()
    @State private var sync: SyncEngine?

    @Environment(\.scenePhase) private var scenePhase

    /// Kutsulinkistä poimittu koodi, jos sovellus avattiin sellaisesta.
    @State private var invitedCode: String?

    var body: some Scene {
        WindowGroup {
            content
                .environment(store)
                .environment(session)
                .task {
                    // Moottori tarvitsee molemmat, joten se syntyy vasta täällä.
                    if sync == nil { sync = SyncEngine(store: store, session: session) }
                    RevenueCatPurchases.configure(memberID: session.identity.memberID)
                    await sync?.sync()
                    await syncEntitlementIfPurchased()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Etualalle palatessa: perhe on voinut kertoa muistoja sillä
                    // välin, ja oma jono voi olla purkamatta.
                    guard phase == .active else { return }
                    Task { await sync?.sync() }
                }
                .onOpenURL { url in
                    guard let code = Self.inviteCode(from: url) else { return }
                    invitedCode = code
                }
                #if DEBUG
                .task { await Self.reportBackendStatus(session: session) }
                #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.mode {
        case .needsFamily:
            OnboardingScreen(prefilledCode: invitedCode)
        case .local, .inFamily:
            // Ilman backendiä sovellus on yhden laitteen arkisto eikä
            // liittymisruutua näytetä lainkaan. Se pitää kehityksen ja
            // demoamisen käynnissä silloinkin kun Worker on alhaalla.
            RootView()
        }
    }

    /// Kertoo palvelimelle jos tällä laitteella on osto. Palvelin varmistaa
    /// sen RevenueCatilta ja levittää oikeuden koko perheelle.
    private func syncEntitlementIfPurchased() async {
        let purchases = AppServices.purchases()
        guard await purchases.hasActivePurchase, let id = await purchases.customerID else { return }
        await session.syncPurchase(customerID: id)
    }

    /// `memorize://join?code=...`
    private static func inviteCode(from url: URL) -> String? {
        guard url.scheme == "memorize", url.host == "join" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "code" }?
            .value
    }

    #if DEBUG
    /// Kertoo käynnistyksessä käytetäänkö stubeja vai oikeaa backendiä, ja
    /// vastaako backend. Ilman tätä väärä osoite näkyisi vasta siinä vaiheessa
    /// kun käyttäjä on jo puhunut minuutin ja tulos katoaa.
    private static func reportBackendStatus(session: Session) async {
        // Identiteetin alkupää lokiin. Jos Keychain ei toimi, tämä vaihtuu
        // joka käynnistyksellä — ja käyttäjä menettäisi perheensä hiljaa,
        // mikä olisi lähes mahdoton huomata ilman tätä riviä.
        print("[memorize] jäsen \(session.identity.memberID.prefix(8))… tila \(session.mode)")

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
