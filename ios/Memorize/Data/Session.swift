import Foundation

/// Family membership and its state.
///
/// The family id is kept locally so the app opens straight into use even without
/// a network. Membership is state, not a query — an 80-year-old must not be left
/// staring at a loading screen because there is no signal at the cottage.
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
        /// No backend configured: a single-device archive, no family. The app
        /// works fully, and the user is not bothered with a join screen.
        case local
        /// A backend exists but a family does not, yet.
        case needsFamily
        case inFamily(id: String)
    }

    private(set) var mode: Mode = .local
    private(set) var family: Family?
    /// The family's usage. The paywall needs this to say what is left BEFORE the
    /// limit is reached — told afterwards, it is only an obstacle.
    private(set) var usage: EntitlementClient.Usage?
    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Not a `let`: "Tyhjennä tämä laite" replaces it, and the clients read it
    /// on every call so the new token is in use immediately rather than after a
    /// restart.
    private(set) var identity = Identity.loadOrCreate()

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

    // MARK: - Joining

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

    /// Refreshes the family details. A failure does not throw the user out:
    /// membership is local state, not the result of a network query.
    func refresh() async {
        guard case .inFamily = mode, let client else { return }
        do {
            family = try await client.family()
        } catch {
            lastError = error.localizedDescription
        }
        // Usage is fetched separately rather than alongside the family: it
        // changes more often, and its failure must not hide the member list.
        usage = try? await entitlements?.usage()
    }

    /// Reports a purchase to the server. The server verifies it with RevenueCat —
    /// this is a hint, not a claim.
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

    // MARK: - Leaving

    /// Ends this device's membership. The memories stay with the family — see
    /// docs/ARCHITECTURE.md §14.
    ///
    /// Returns false and leaves everything as it was if the server refused, so
    /// the screen can say why. Local membership is only forgotten once the
    /// server has actually let go: forgetting it first would leave a member row
    /// nobody could ever reach again.
    func leaveFamily() async -> Bool {
        guard let client else {
            // Not "Backendin osoitetta ei ole määritetty". That sentence is
            // written for whoever configured the build, and it was shown to the
            // person holding the phone — who can do nothing with the word
            // "backend" except conclude that they broke something.
            lastError = "Perheen palveluun ei juuri nyt saada yhteyttä. Muistot ovat tallessa tässä laitteessa."
            return false
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await client.leave()
        } catch {
            lastError = error.localizedDescription
            return false
        }
        UserDefaults.standard.removeObject(forKey: familyKey)
        mode = .needsFamily
        family = nil
        usage = nil
        return true
    }

    /// The other half of "Tyhjennä tämä laite": forget the family and take a new
    /// identity.
    ///
    /// The new identity is what makes the wipe stick. Keeping the old one would
    /// leave this device a member on the server, and the next sync would pull
    /// the whole archive back — a wipe that undoes itself in the background is
    /// worse than no wipe at all.
    func renewIdentity() {
        Identity.forget()
        identity = Identity.loadOrCreate()
        UserDefaults.standard.removeObject(forKey: familyKey)
        family = nil
        usage = nil
        mode = AppServices.apiBaseURL == nil ? .local : .needsFamily
    }

    // MARK: - Helpers

    private func store(familyID: String) {
        UserDefaults.standard.set(familyID, forKey: familyKey)
        mode = .inFamily(id: familyID)
    }

    private func perform(_ work: (FamilyClient) async throws -> Void) async {
        guard let client else {
            // Not "Backendin osoitetta ei ole määritetty". That sentence is
            // written for whoever configured the build, and it was shown to the
            // person holding the phone — who can do nothing with the word
            // "backend" except conclude that they broke something.
            lastError = "Perheen palveluun ei juuri nyt saada yhteyttä. Muistot ovat tallessa tässä laitteessa."
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
