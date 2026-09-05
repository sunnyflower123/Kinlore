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

    /// The archive this phone keeps to itself, chosen rather than inferred.
    ///
    /// `.local` already meant "no backend configured", which is a build-time
    /// fact. This is a person's answer, so it has to outlive a launch and it has
    /// to beat the configuration: a device that can reach a Worker and has been
    /// told not to must not start syncing because the address is still there.
    private let localOnlyKey = "local_only"

    /// Set when a family is joined through an invitation, consumed by
    /// `RootView` the next time it decides its first tab: the one launch after
    /// joining opens on Muistot rather than Kerro, because an invitation is to
    /// something that already exists and the arrival should show it. Device
    /// state, one-shot, never synced. See docs/UX.md §4.3.
    ///
    /// `nonisolated`: a string constant needs no actor, and the tab decision
    /// that reads it runs outside one.
    nonisolated static let arrivalPendingKey = "arrival_pending"

    /// Whether this archive is one somebody chose to keep to this phone, as
    /// opposed to one that has no backend to sync to. The screens need the
    /// difference: only the first is a decision anybody made.
    var isLocalByChoice: Bool {
        UserDefaults.standard.bool(forKey: localOnlyKey) && AppServices.apiBaseURL != nil
    }
    private var client: FamilyClient? {
        guard let base = AppServices.apiBaseURL else { return nil }
        return FamilyClient(baseURL: base, token: identity.token)
    }

    private var entitlements: EntitlementClient? {
        guard let base = AppServices.apiBaseURL else { return nil }
        return EntitlementClient(baseURL: base, token: identity.token)
    }

    var isPaid: Bool { usage?.isPaid ?? false }

    /// The month's free telling is used up: the meter the server keeps, read
    /// on every phone. Not a device-local flag on purpose — the grandchild's
    /// phone never transcribes grandmother's recordings and would never learn
    /// it any other way, and it is her rows that read "valmistuu myöhemmin"
    /// on his screen. False whenever there is nothing to know: no family, no
    /// usage fetched yet, or a paid archive (founder's-eye review, 3 Sep 2026,
    /// findings #103–#105).
    var isOutOfMinutes: Bool {
        #if DEBUG
        // `-minutes-out <n>`: holds the state still for the audit and the
        // tests; the real one needs a family over its ceiling.
        if UserDefaults.standard.string(forKey: "minutes-out") != nil { return true }
        #endif
        guard let usage, !usage.isPaid, let limit = usage.aiSeconds.limit else { return false }
        return usage.aiSeconds.used >= limit
    }

    /// When the free minutes come back. The server's window is the UTC
    /// calendar month (quota.ts `period`), so this is the first moment of the
    /// next one — the date a row can promise instead of "myöhemmin".
    static func nextFreeMinutes(after now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return calendar.date(byAdding: .month, value: 1, to: start) ?? now
    }

    init() {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "seed") {
        case "family":
            seedDemoFamily()
            return
        case "arrival":
            // The joiner's landing, held still. The flag below is the same
            // one a real join sets, so the test exercises the mechanism that
            // chooses the first tab rather than simulating its outcome; the
            // gallery's waiting state is forced by the same seed value,
            // because it otherwise exists only while a pull is in flight.
            // The store empties itself for this seed — see `MemoryStore`.
            seedDemoFamily()
            UserDefaults.standard.set(true, forKey: Self.arrivalPendingKey)
            return
        case "alone":
            // A family of one: the state where the finished-memory screen's
            // offer slot carries the invitation instead of the paid archive.
            // See docs/UX.md §3.2.
            seedDemoFamily(alone: true)
            return
        default:
            break
        }
        #endif
        guard AppServices.apiBaseURL != nil else {
            mode = .local
            return
        }
        // The answer beats the address. Checked before the family id and not
        // after: a phone told to keep the archive to itself has no family id to
        // find, and reaching the branch below would put it on the join screen —
        // asking again, on every launch, a question that has been answered.
        guard !UserDefaults.standard.bool(forKey: localOnlyKey) else {
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
            // Made here, before the family id is stored and therefore before
            // any row can be pushed. PLAN.md §10 lever 3: a family whose first
            // memories went up in clear and whose later ones did not would be
            // the worst of both — unreadable to a new device, and readable to a
            // dump.
            FamilyKey.create()
            self.store(familyID: result.familyID)
        }
    }

    /// Joins a family. The `code` is what was shared, which since lever 3 is the
    /// server's invite code and the family's key separated by `#`.
    ///
    /// The key is adopted **before** the request, so that a device cannot end up
    /// a member of a family it has no way to read. Adoption is also the reason
    /// the two travel together in one string rather than in two fields: an
    /// invitation that can be half-copied is an invitation that produces exactly
    /// that device.
    ///
    /// A code with no key still joins. That is a family from before lever 3,
    /// and refusing it would be refusing the archives this was built to protect.
    func join(code: String, displayName: String) async {
        let parts = Self.split(shared: code)
        await perform { client in
            if let key = parts.key { FamilyKey.adopt(key) }
            let result = try await client.join(code: parts.code, displayName: displayName)
            // Before the mode flips: the flip is what creates the root view,
            // and the root view is what consumes this.
            UserDefaults.standard.set(true, forKey: Self.arrivalPendingKey)
            self.store(familyID: result.familyID)
        }
    }

    /// Splits `<code>#<key>` into its halves, tolerating either alone.
    ///
    /// Whitespace goes first: this string is read off a message and pasted, and
    /// a trailing newline from a chat app is the likeliest way for a correct
    /// invitation to be refused.
    static func split(shared: String) -> (code: String, key: String?) {
        let trimmed = shared.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.firstIndex(of: "#") else { return (trimmed, nil) }
        let key = String(trimmed[trimmed.index(after: hash)...])
        return (String(trimmed[..<hash]), key.isEmpty ? nil : key)
    }

    /// Keeps the archive to this phone. PLAN.md §10 lever 2.
    ///
    /// Not `async`, and it reaches no network at all — which is the whole of it.
    /// No family row is created, so there is nothing on the server to leave, to
    /// be a member of, or to be pulled back by. `SyncEngine` is already gated on
    /// `.inFamily`, so the queue simply never runs.
    ///
    /// It cannot fail, and that is worth saying next to `createFamily`, which
    /// can: the option exists for somebody uneasy about the server, and making
    /// it depend on the server answering would be a poor joke.
    ///
    /// Since finding B4, nothing leaves in this mode at all: it creates no
    /// member the server knows, every transcription call would be the same
    /// 401, so the attempt is skipped (`TellViewModel.canTranscribe`) and the
    /// screens say the text is not coming. This comment used to say the
    /// opposite — that the audio travels whatever this is set to — which was
    /// true while the mode still tried, and the consent notice has been
    /// rewritten in step with the code both times.
    func keepToThisPhone() {
        UserDefaults.standard.set(true, forKey: localOnlyKey)
        UserDefaults.standard.removeObject(forKey: familyKey)
        family = nil
        usage = nil
        lastError = nil
        mode = .local
    }

    /// The one way out of a single-device archive that does not cost the
    /// archive.
    ///
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
    ///
    /// **Returns whether the family actually has the archive now**, which is not
    /// the same as whether the call succeeded and matters more. Somebody has
    /// just paid: the one question worth answering is whether the thing they
    /// paid for exists yet. It was thrown away here — `try?`, then a dismissal —
    /// so a purchase made while the Worker was unreachable closed the sheet,
    /// left the family view saying *"Ilmainen"*, and said nothing at all to the
    /// person who had just been charged.
    ///
    /// The recovery has always been there: `syncEntitlementIfPurchased` reports
    /// it again on the app's own schedule, so nothing is lost and nobody needs
    /// to pay twice. What was missing is anyone saying so.
    @discardableResult
    func syncPurchase(customerID: String) async -> Bool {
        guard let entitlements else { return false }
        let reported = (try? await entitlements.sync(customerID: customerID)) != nil
        await refresh()
        return reported && isPaid
    }

    func createInvite(displayName: String = "") async -> String? {
        guard let client else { return nil }
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let code = try await client.createInvite(displayName: displayName)
            await refresh()
            return code
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Whether the server heard the revocation.
    ///
    /// "Poista" on an invite row is the family's one remedy for a link that
    /// went astray, and it used to fail in total silence — the exact shape
    /// the leave-family screen calls the worst possible answer to a
    /// deliberate act, on the one action §4 counts as part of the security
    /// boundary. A server that answers `revoked: false` is not a failure
    /// here: that code was already dead or never this family's, and the
    /// refresh clears the row either way.
    func revokeInvite(code: String) async -> Bool {
        guard let client else { return false }
        lastError = nil
        do {
            try await client.revokeInvite(code: code)
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
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
            lastError = String(localized: "Perheen palveluun ei juuri nyt saada yhteyttä. Muistot ovat tallessa tässä laitteessa.")
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
        // The key belongs to the family, not to this phone. Leaving keeps the
        // local copy — which is plaintext, so nothing on this device becomes
        // unreadable — but the means to read the family's rows goes with the
        // membership. Rejoining brings it back in the next invitation.
        FamilyKey.forget()
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
        // The family key goes too. "Tyhjennä tämä laite" says the memories are
        // gone for good on a device nobody else shares, and leaving the key
        // behind would be the one part of the archive that survived a wipe.
        FamilyKey.forget()
        identity = Identity.loadOrCreate()
        UserDefaults.standard.removeObject(forKey: familyKey)
        // And the answer to "keiden kesken", because afterwards the app is a
        // fresh install and a fresh install has not been asked yet. It is also
        // the one way back out of a single-device archive: the choice is made
        // once at setup and nothing else in the app unmakes it, so leaving it
        // set here would make "Tyhjennä tämä laite" the only door that does not
        // open either.
        UserDefaults.standard.removeObject(forKey: localOnlyKey)
        // A wiped device has not just joined anything.
        UserDefaults.standard.removeObject(forKey: Self.arrivalPendingKey)
        family = nil
        usage = nil
        mode = AppServices.apiBaseURL == nil ? .local : .needsFamily
    }

    // MARK: - Helpers

    #if DEBUG
    /// A family with no server behind it, for `-seed family`.
    ///
    /// The invite rows are the one part of this app nothing could ever look at.
    /// They are drawn entirely from what the Worker sends, so a device without a
    /// backend shows the offline note instead — which is how the button on that
    /// row was renamed from *"Mitätöi"* to *"Poista"* (§21) without any test or
    /// any screenshot run ever drawing it once. Same hole as the refused
    /// microphone and the result screen, and the same shape of answer.
    ///
    /// **Two invites on purpose.** The row reads *"Avoin kutsu"* or *"Käytetty
    /// n kertaa"* and those are different lengths beside the same button, so
    /// both are on screen at once or the audit only ever measures the short one.
    /// Three members for the same reason: one of them is you, and that row draws
    /// differently.
    ///
    /// The times are relative to the launch rather than fixed. An invite that
    /// expired last week is a screen about something else, and a fixture that
    /// rots into one is worse than no fixture.
    ///
    /// `refresh()` cannot overwrite this: it returns early without a client, and
    /// there is no client without an address. So the seed survives the screen's
    /// own `.task`, which is the only thing that would otherwise take it away.
    /// `alone` seeds the family as one person — its founder, before anybody
    /// has accepted an invitation. That is the state the offer slot answers
    /// with the invitation, and it cannot be reached by trimming the member
    /// list of the shared fixture in a test: the count is read at render time
    /// from this object.
    private func seedDemoFamily(alone: Bool = false) {
        let now = Date.now.timeIntervalSince1970
        let day: Double = 24 * 60 * 60
        mode = .inFamily(id: "demo-family")
        let you = Member(id: "demo-you", displayName: "Minä", role: "owner", joinedAt: now - 40 * day)
        family = Family(
            id: "demo-family",
            name: "Virtaset",
            entitlement: "free",
            you: Family.You(id: "demo-you", role: "owner", displayName: "Minä"),
            members: alone ? [you] : [
                you,
                Member(id: "demo-aino", displayName: "Aino", role: "member", joinedAt: now - 12 * day),
                Member(id: "demo-ville", displayName: "Ville", role: "member", joinedAt: now - 3 * day),
            ],
            invites: alone ? [] : [
                Invite(code: "demo-avoin", expiresAt: now + 6 * day, usedCount: 0),
                Invite(code: "demo-kaytetty", expiresAt: now + 2 * day, usedCount: 2),
            ]
        )
        // A free family with the month partly spent: the usage rows say a
        // fraction rather than "rajaton", which is the version with numbers in
        // it and the one that can overflow a row.
        usage = EntitlementClient.Usage(
            entitlement: "free",
            aiSeconds: .init(used: 7 * 60, limit: 10 * 60),
            photos: .init(used: 12, limit: 20)
        )
    }
    #endif

    private func store(familyID: String) {
        UserDefaults.standard.set(familyID, forKey: familyKey)
        // The answer to "keiden kesken" is unmade here and nowhere else — when
        // a family exists to send the archive to. It used to be unmade by the
        // button on EnableSharingScreen, before the create or the join had
        // been attempted: the mode went to .needsFamily on the tap, the root
        // view became the onboarding fork, and a month of memories vanished
        // from every screen until a network call succeeded — at a cottage with
        // no signal, on every relaunch, under a sentence saying there was no
        // way back (founder's-eye review, 3 Sep 2026, finding #117). Now the
        // fork is a sheet over the archive, and a failed or cancelled attempt
        // leaves the phone exactly as it was.
        UserDefaults.standard.removeObject(forKey: localOnlyKey)
        mode = .inFamily(id: familyID)
    }

    private func perform(_ work: (FamilyClient) async throws -> Void) async {
        guard let client else {
            // Not "Backendin osoitetta ei ole määritetty". That sentence is
            // written for whoever configured the build, and it was shown to the
            // person holding the phone — who can do nothing with the word
            // "backend" except conclude that they broke something.
            lastError = String(localized: "Perheen palveluun ei juuri nyt saada yhteyttä. Muistot ovat tallessa tässä laitteessa.")
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
