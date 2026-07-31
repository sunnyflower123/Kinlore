import Foundation

/// Perheen jäsenyys ja sen tila.
///
/// Perheen tunniste säilytetään paikallisesti, jotta sovellus avautuu
/// suoraan käyttöön myös ilman verkkoa. Perhe on tila, ei kysely — 80-vuotias
/// ei saa jäädä latausruutuun siksi että mökillä ei ole kenttää.
@MainActor
@Observable
final class Session {
    struct Member: Identifiable, Decodable, Hashable {
        let id: String
        let displayName: String
        let role: String
        let joinedAt: Double
    }

    struct Invite: Identifiable, Decodable, Hashable {
        var id: String { code }
        let code: String
        let expiresAt: Double
        let usedCount: Int
    }

    struct Family: Decodable {
        let id: String
        let name: String
        let entitlement: String
        let you: You
        let members: [Member]
        let invites: [Invite]

        struct You: Decodable, Hashable {
            let id: String
            let role: String
            let displayName: String
        }
    }

    enum Mode: Equatable {
        /// Backendiä ei ole määritetty: yhden laitteen arkisto, ei perhettä.
        /// Sovellus toimii täysin, eikä käyttäjää kiusata liittymisruudulla.
        case local
        /// Backend on olemassa mutta perhettä ei vielä.
        case needsFamily
        case inFamily(id: String)
    }

    private(set) var mode: Mode = .local
    private(set) var family: Family?
    /// Perheen käyttötilanne. Paywall tarvitsee tämän kertoakseen mitä on
    /// jäljellä ENNEN kuin raja tulee vastaan — jälkikäteen kerrottuna se on
    /// vain este.
    private(set) var usage: EntitlementClient.Usage?
    private(set) var isWorking = false
    private(set) var lastError: String?

    let identity = Identity.loadOrCreate()

    private let familyKey = "family_id"
    private var client: FamilyClient? {
        guard let base = AppServices.apiBaseURL else { return nil }
        return FamilyClient(baseURL: base, token: identity.token)
    }

    private var entitlements: EntitlementClient? {
        guard let base = AppServices.apiBaseURL else { return nil }
        return EntitlementClient(baseURL: base, token: identity.token)
    }

    var isPaid: Bool { usage?.isPaid ?? false }

    init() {
        guard AppServices.apiBaseURL != nil else {
            mode = .local
            return
        }
        if let familyID = UserDefaults.standard.string(forKey: familyKey), !familyID.isEmpty {
            mode = .inFamily(id: familyID)
        } else {
            mode = .needsFamily
        }
    }

    // MARK: - Liittyminen

    func createFamily(named familyName: String, displayName: String) async {
        await perform { client in
            let result = try await client.createFamily(
                familyName: familyName,
                displayName: displayName
            )
            self.store(familyID: result.familyID)
        }
    }

    func join(code: String, displayName: String) async {
        await perform { client in
            let result = try await client.join(code: code, displayName: displayName)
            self.store(familyID: result.familyID)
        }
    }

    /// Päivittää perheen tiedot. Epäonnistuminen ei pudota käyttäjää ulos:
    /// jäsenyys on paikallinen tila, ei verkkokyselyn tulos.
    func refresh() async {
        guard case .inFamily = mode, let client else { return }
        do {
            family = try await client.family()
        } catch {
            lastError = error.localizedDescription
        }
        // Käyttötilanne haetaan erikseen eikä perheen mukana: se muuttuu
        // useammin, ja sen epäonnistuminen ei saa piilottaa jäsenlistaa.
        usage = try? await entitlements?.usage()
    }

    /// Kertoo palvelimelle ostosta. Palvelin varmistaa sen RevenueCatilta —
    /// tämä on vihje, ei väite.
    func syncPurchase(customerID: String) async {
        guard let entitlements else { return }
        _ = try? await entitlements.sync(customerID: customerID)
        await refresh()
    }

    func createInvite() async -> String? {
        guard let client else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let code = try await client.createInvite()
            await refresh()
            return code
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func revokeInvite(code: String) async {
        guard let client else { return }
        try? await client.revokeInvite(code: code)
        await refresh()
    }

    // MARK: - Apurit

    private func store(familyID: String) {
        UserDefaults.standard.set(familyID, forKey: familyKey)
        mode = .inFamily(id: familyID)
    }

    private func perform(_ work: (FamilyClient) async throws -> Void) async {
        guard let client else {
            lastError = "Backendin osoitetta ei ole määritetty."
            return
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await work(client)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
