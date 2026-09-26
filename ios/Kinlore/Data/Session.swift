import Foundation
import Network

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
        /// The person card this member is in the tree, or nil while they are
        /// linked to none. An id only — the same one the card has on every
        /// phone, so the title comes from the store. Absent from a server that
        /// predates it. Since 13 Sep 2026.
        let personSubjectID: String?
    }

    struct Invite: Identifiable, Decodable, Hashable {
        var id: String { code }
        let code: String
        let expiresAt: Double
        /// Always 0 since 5 Sep 2026 — a code admits one person and the server
        /// lists only the codes nobody has used — and still decoded, because
        /// the server still sends it for the app that was built before.
        let usedCount: Int
        /// Who the invitation was made for, as the inviter typed it. Absent from
        /// a server that predates it.
        let displayName: String?
    }

    struct Family: Decodable, Equatable {
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
            /// This member's own card, as the server has it. See
            /// `Member.personSubjectID` and `linkMe(personSubjectID:)`.
            let personSubjectID: String?
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

    /// What a phone with no family id finds out about the identity it holds
    /// (`lookForFamily`). Since 26 Sep 2026.
    enum Homecoming: Equatable {
        /// Nothing to find out: the identity was made by this launch, or the
        /// server has said it knows it as a member of nothing.
        case none
        /// The question is out.
        case asking
        /// Asked, and nothing answered. Not taken as a no: offline, a timeout
        /// and a server in trouble all look like this, and a no would send a
        /// member to the fork.
        case unanswered
        /// The server knows this identity as a member of this family.
        case found(Family)
    }

    private(set) var mode: Mode = .local
    private(set) var homecoming: Homecoming = .none
    private(set) var family: Family?
    /// Who this phone is in the family, while nobody has been told — see
    /// `sharedIdentityKey`. Nil in every ordinary case.
    private(set) var sharedIdentityName: String? = UserDefaults.standard.string(forKey: Session.sharedIdentityKey)
    /// The family's usage. The paywall needs this to say what is left BEFORE the
    /// limit is reached — told afterwards, it is only an obstacle.
    private(set) var usage: EntitlementClient.Usage?
    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Not a `let`: "Tyhjennä tämä laite" replaces it, and the clients read it
    /// on every call so the new token is in use immediately rather than after a
    /// restart.
    private(set) var identity: Identity

    /// One question at a time: the foreground, the network coming back and
    /// the button can all ask at once.
    private var isLookingForFamily = false
    /// The network coming back is an answer worth asking again for, the way
    /// `SyncEngine` watches for it under a round. Started only once a
    /// question has gone unanswered, which on most phones is never.
    private let networkReturn = NWPathMonitor()
    private var isWatchingNetwork = false
    /// The monitor's first report is the current path, not a change.
    private var hasSeenNetworkPath = false

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

    /// Set when a family is created here, consumed by `RootView` on its first
    /// appearance: on the phone of whoever set the archive up, the first thing
    /// after "Luo arkisto" is the question of whose memories it is for, and how
    /// that person will tell them. A grandparent's phone skips it and keeps
    /// her button. Device state, one-shot, never synced — the same shape as
    /// `arrivalPendingKey`, and set at the same moment. Since 13 Sep 2026.
    nonisolated static let firstMinutePendingKey = "first_minute_pending"

    /// The card this member is to be linked to once the server holds it: the
    /// founder's own, made on this phone when the family is created, or the
    /// one an invitation named before its inviter's phone had synced it.
    /// `SyncEngine` links it after a round, `linkMe` clears it, and it goes
    /// with the membership. Device state, never synced. Since 13 Sep 2026.
    private static let pendingPersonLinkKey = "pending_person_link"

    /// The name of the member a join made this phone, when that member was
    /// already in the family and is not who joined (`joinedAsSomebodyElse`).
    /// Owed until `RootView`'s notice has been read, and then gone: said once,
    /// not on every launch. Device state, never synced, the same shape as
    /// `arrivalPendingKey`. Since 26 Sep 2026.
    private static let sharedIdentityKey = "shared_identity_notice"

    var pendingPersonLink: String? {
        UserDefaults.standard.string(forKey: Self.pendingPersonLinkKey)
    }

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

    /// The month's free transcription time is used up: the meter the server
    /// keeps, read on every phone. Not a device-local flag on purpose — the
    /// grandchild's phone never transcribes grandmother's recordings and would
    /// never learn it any other way, and it is her rows that read "valmistuu
    /// myöhemmin" on his screen. False whenever there is nothing to know: no
    /// family, no usage fetched yet, or a paid archive (founder's-eye review,
    /// 3 Sep 2026, findings #103–#105).
    var isOutOfMinutes: Bool {
        #if DEBUG
        // `-minutes-out <n>`: holds the state still for the audit and the
        // tests; the real one needs a family over its ceiling.
        if UserDefaults.standard.string(forKey: "minutes-out") != nil { return true }
        #endif
        guard let usage, !usage.isPaid, let limit = usage.aiSeconds.limit else { return false }
        return usage.aiSeconds.used >= limit
    }

    /// The family is at its free photographs, as the server last counted them.
    /// That count is the one its refusal reads (`checkPhotoCount`), cards
    /// without a file included, so a photograph that has not reached the
    /// server by now is one it will not take until there is room. False
    /// whenever there is nothing to know, as above.
    var isOutOfPhotos: Bool {
        guard let usage, !usage.isPaid, let limit = usage.photos.limit else { return false }
        return usage.photos.used >= limit
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
        // Read before anything is made: whether the identity was already here
        // is the one question below that the Keychain can answer.
        let held = Identity.load()
        identity = held ?? Identity.loadOrCreate()
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "seed") {
        case "family":
            seedDemoFamily()
            // `-entitlement archive`: the same family once somebody has
            // bought, as the buy stub leaves it at the end of RevenueCat's
            // sheet. That sheet was the only road to the paid Perhe screen,
            // and no audit can take it — so the rows a paying family reads
            // said "rajaton" until 26 Sep 2026 without any test drawing them.
            if UserDefaults.standard.string(forKey: "entitlement") == "archive" {
                openArchiveWithoutAServer()
            }
            return
        case "returning":
            // A phone the server knows and whose family id is gone, held at
            // the moment the answer has arrived. The family is the shared
            // fixture's, and taking it stores no family id
            // (`returnToFamily`), so the next launch comes back to the same
            // page. The store empties itself for this seed — see `MemoryStore`.
            seedDemoFamily()
            // `-joinedAs <name>` names the member the server holds for this
            // phone, as it does below; the fixture's own is the placeholder
            // word, which the page does not say (`OnboardingScreen.name(of:)`).
            if let name = UserDefaults.standard.string(forKey: "joinedAs"), let seeded = family {
                family = Self.renaming(seeded, to: name)
            }
            if let family { homecoming = .found(family) }
            family = nil
            usage = nil
            mode = .needsFamily
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
        case "joined":
            // A join that has just returned, at the moment `join` decides
            // whether a notice is owed, with no server: the family is the
            // shared fixture's, whose invitations are one made for Kaarina
            // (`demo-kaarina`) and one made for nobody (`demo-nimeton`).
            // `-joinedAs <name>` is the name the server holds for this
            // phone, `-joinTyped <name>` what the form held, `-joinCode
            // <code>` the code. With none of the last two, the launch is a
            // later one, and keeps whatever notice the one before left owed.
            // The store empties itself for this seed — see `MemoryStore`.
            let owed = UserDefaults.standard.string(forKey: Self.sharedIdentityKey)
            seedDemoFamily()
            if let name = UserDefaults.standard.string(forKey: "joinedAs"), let seeded = family {
                family = Self.renaming(seeded, to: name)
            }
            let typed = UserDefaults.standard.string(forKey: "joinTyped")
            let code = UserDefaults.standard.string(forKey: "joinCode")
            if typed != nil || code != nil {
                if let family, let name = Self.joinedAsSomebodyElse(
                    typed: typed ?? "", code: code ?? "", family: family
                ) {
                    owe(sharedIdentityNotice: name)
                }
            } else if let owed {
                owe(sharedIdentityNotice: owed)
            }
            return
        case "aimed":
            // The store seeds two questions asked by name (`MemoryStore`);
            // the family is what the ask sheet's "Kenelle?" chooses from.
            seedDemoFamily()
            return
        case "alone":
            // A family of one: the state where the finished-memory screen's
            // offer slot carries the invitation instead of the paid archive.
            // See docs/UX.md §3.2.
            seedDemoFamily(alone: true)
            return
        case "unarrived":
            // A family at its twenty photographs, the ceiling past which the
            // server refuses a file and keeps its card. The store seeds the
            // photographs that are on the grid and not on this phone
            // (`MemoryStore`); this is what their card reads to say why.
            seedDemoFamily(photosUsed: 20)
            return
        default:
            // `-you <card id>` with any store seed: a family whose "you" is
            // linked to that card, as `PATCH /family/me` links it for real,
            // for the tree's "Sinä" with no server behind it. `-you none` is
            // the same family with "you" linked to no card — the member an
            // invitation made for nobody in particular let in — and
            // `-theirs <card id>` makes another member that card (26 Sep
            // 2026, the person card's "Tämä olen minä").
            if UserDefaults.standard.string(forKey: "you") != nil {
                seedDemoFamily()
                return
            }
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
            // An identity that was here before this launch may be a member
            // already. The Keychain keeps it when the app is deleted and hands
            // it to the next phone on the same Apple account; the family id
            // above goes in both cases. Until 26 Sep 2026 such a phone got the
            // fork, where creating a family ends in "Tämä laite kuuluu jo
            // toiseen perheeseen" and joining needs an invitation somebody has
            // to send. So the server is asked first. An identity this launch
            // made is a member of nothing and is not asked about.
            var asks = held != nil
            #if DEBUG
            // `-homecoming off`: the simulator's Keychain keeps an identity
            // from one test to the next, which a phone out of the box does
            // not. The suite says this unless a test names `-homecoming`
            // itself (`AccessibilityAudit.launch`).
            if UserDefaults.standard.string(forKey: "homecoming") == "off" { asks = false }
            #endif
            if asks { homecoming = .asking }
        }
    }

    // MARK: - Joining

    /// `archive` is where the founder's own card is made — see below.
    func createFamily(named familyName: String, displayName: String, archive: MemoryStore) async {
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
            // The founder's own card in the tree, from the name just given, so
            // the tree has its first person and knows which one is "you".
            // After the server has said yes, so a failed attempt leaves the
            // phone as it was (`store(familyID:)`); before the mode flips, so
            // the first round carries the card up. The link itself waits for
            // that round, because the server refuses a card it does not hold
            // (`SyncEngine.linkOwnCard`). No name typed, no card.
            if let card = archive.addPerson(named: displayName) {
                UserDefaults.standard.set(card.id, forKey: Self.pendingPersonLinkKey)
            }
            // Before the mode flips, for the reason `join` gives: the flip is
            // what creates the root view, and the root view consumes this.
            UserDefaults.standard.set(true, forKey: Self.firstMinutePendingKey)
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
    /// Since 26 Sep 2026 such a phone syncs nothing until an invitation brings
    /// the key (`SyncEngine.State.keyMissing`, `rejoin`).
    func join(code: String, displayName: String) async {
        let parts = Self.split(shared: code)
        await perform { client in
            if let key = parts.key { FamilyKey.adopt(key) }
            let result = try await client.join(code: parts.code, displayName: displayName)
            // The card the invitation was made for. Already linked if the
            // server held it; if not, linked from here once a pull brings it
            // (`SyncEngine.linkOwnCard`).
            if let card = result.personSubjectID {
                UserDefaults.standard.set(card, forKey: Self.pendingPersonLinkKey)
            }
            // Before the mode flips: the flip is what creates the root view,
            // and the root view is what consumes this.
            UserDefaults.standard.set(true, forKey: Self.arrivalPendingKey)
            self.store(familyID: result.familyID)
        }
        // After `perform`, whose refresh is what brings the name the server
        // holds for this phone.
        if let family, let name = Self.joinedAsSomebodyElse(typed: displayName, code: code, family: family) {
            owe(sharedIdentityNotice: name)
        }
    }

    /// The member a join made this phone, when that member is not the person
    /// who joined; nil when it is, and whenever nothing can tell.
    ///
    /// The server lets an identity it already knows back into its family
    /// without renaming it or claiming the code (`joinFamily`, "the same
    /// device rejoining"). That is right for a reinstall, and it is also what
    /// happens on a second phone on the same Apple ID, whose Keychain hands it
    /// the first phone's identity (rule 6): whatever was typed, the phone
    /// joins as the first phone's member, and each then reads the other's
    /// tellings as its own (`NewFromFamily`). Measured 26 Sep 2026 against a
    /// local Worker; the same join from an identity of its own took the
    /// typed name, or the invitation's.
    ///
    /// Two ways to tell, and only these. A typed name that is not the name the
    /// server holds, letter case and outer spaces aside, since the server
    /// trims. And with nothing typed, the name the invitation was made for,
    /// when it names somebody else. That invitation is still listed after
    /// such a join because nothing claimed it, while a code that let a new
    /// member in is gone from the list, so it is found only in the case this
    /// looks for. Every member is sent the list, owner or not. An invitation
    /// made for nobody, or for this member, says nothing either way.
    static func joinedAsSomebodyElse(typed: String, code: String, family: Family) -> String? {
        func same(_ a: String, _ b: String) -> Bool {
            a.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
        let you = family.you.displayName
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            return same(typed, you) ? nil : you
        }
        let code = split(shared: code).code
        guard let invited = family.invites.first(where: { $0.code == code })?.displayName,
              !invited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return same(invited, you) ? nil : you
    }

    private func owe(sharedIdentityNotice name: String) {
        UserDefaults.standard.set(name, forKey: Self.sharedIdentityKey)
        sharedIdentityName = name
    }

    /// The notice has been read (`RootView`), and is not owed again.
    func acknowledgeSharedIdentity() {
        UserDefaults.standard.removeObject(forKey: Self.sharedIdentityKey)
        sharedIdentityName = nil
    }

    /// Joins the same family again, on a device the server has stopped
    /// knowing (`SyncEngine.State.refused`). Nothing on this phone changes:
    /// the rows stay, the key stays, the mode stays. What changes is on the
    /// server — a new member row for this identity — and the next sync then
    /// goes through.
    ///
    /// The same family only. The rows on this phone belong to it, and a code
    /// for another family would push them into that one on the next sync. A
    /// lever-3 invitation carries its family's key, so a key that differs
    /// from this phone's is another family's and is refused before any
    /// request; an invitation with no key (a family from before lever 3) is
    /// checked against the family id the server answers with, and a join that
    /// turns out to be elsewhere is left again at once.
    ///
    /// And the way back for a phone that has lost the key
    /// (`SyncEngine.State.keyMissing`): the invitation's key is taken, but only
    /// after that same answer has placed the code in this family. With no key
    /// of its own to compare, nothing earlier can tell (`FamilyKey.onRejoin`).
    func rejoin(code: String, displayName: String) async -> Bool {
        guard case .inFamily(let currentID) = mode else { return false }
        let parts = Self.split(shared: code)
        let elsewhere = String(localized: "Tämä kutsu on toiseen perheeseen. Tämän puhelimen muistot kuuluvat omaan perheeseensä.")
        let onKey = FamilyKey.onRejoin(invited: parts.key, held: FamilyKey.shareable())
        if onKey == .elsewhere {
            lastError = elsewhere
            return false
        }
        var joined = false
        await perform { client in
            let result = try await client.join(code: parts.code, displayName: displayName)
            if result.familyID != currentID {
                try? await client.leave()
                throw FamilyError.message(elsewhere)
            }
            if case .adopt(let shared) = onKey { FamilyKey.adopt(shared) }
            // The card the invitation named, as in `join`.
            if let card = result.personSubjectID {
                UserDefaults.standard.set(card, forKey: Self.pendingPersonLinkKey)
            }
            joined = true
        }
        return joined && lastError == nil
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

    /// Asks the server whether the identity this phone holds is a member
    /// already, and of which family (`init` decides who asks).
    ///
    /// Only the server's own `unauthorized` is a no. Everything else that is
    /// not an answer — no network, a timeout, a 5xx, even a family it cannot
    /// find — leaves the question open and says so, because a no sends the
    /// phone to the fork, and for a member the fork is the dead end this
    /// question exists to avoid. It is asked again when the app comes to the
    /// foreground, when the network comes back, and from the button.
    func lookForFamily() async {
        guard mode == .needsFamily, !isLookingForFamily else { return }
        guard let client else {
            homecoming = .none
            return
        }
        isLookingForFamily = true
        defer { isLookingForFamily = false }
        homecoming = .asking
        do {
            #if DEBUG
            // `-homecoming unauthorized`: the server's no, read the way the
            // real one is (`FamilyError.forStatus`), for a test that has no
            // server to say it.
            if UserDefaults.standard.string(forKey: "homecoming") == "unauthorized" {
                throw FamilyError.forStatus(401, data: Data(#"{"error":"unauthorized"}"#.utf8))
            }
            #endif
            homecoming = .found(try await client.family())
        } catch FamilyError.unauthorized {
            homecoming = .none
        } catch {
            homecoming = .unanswered
            watchForNetwork()
        }
    }

    private func watchForNetwork() {
        guard !isWatchingNetwork else { return }
        isWatchingNetwork = true
        networkReturn.pathUpdateHandler = { [weak self] path in
            let isBack = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.hasSeenNetworkPath else {
                    self.hasSeenNetworkPath = true
                    return
                }
                guard isBack, self.homecoming == .unanswered else { return }
                await self.lookForFamily()
            }
        }
        networkReturn.start(queue: DispatchQueue(label: "kinlore.homecoming"))
    }

    /// Takes the answer: this phone is back in the family the server named.
    ///
    /// The family id is all it writes. The key is wherever the Keychain has
    /// it — beside the identity that brought the phone here — and a phone
    /// whose key did not come along pushes nothing in the clear: `SyncEngine`
    /// holds it at `.keyMissing` until an invitation brings the key
    /// (`rejoin`), as it holds any member without one. Nor is a card left
    /// waiting for its link, since the server has this member's link already
    /// and says it in `you` on every refresh.
    func returnToFamily() async {
        guard case .found(let found) = homecoming else { return }
        homecoming = .none
        family = found
        // A join's landing: what the family already has, on Albumi, while the
        // first pull fills it in.
        UserDefaults.standard.set(true, forKey: Self.arrivalPendingKey)
        #if DEBUG
        // `-seed returning` keeps no family id, so that the next launch comes
        // back to the same page rather than into a family with no server.
        if UserDefaults.standard.string(forKey: "seed") == "returning" {
            mode = .inFamily(id: found.id)
            return
        }
        #endif
        store(familyID: found.id)
        // The family came with the answer; the meters did not, and `perform`
        // fetches them after a join for the same reason.
        usage = try? await entitlements?.usage()
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
        #if DEBUG
        // The stubbed world has no server to ask, so until 24 Sep 2026 a
        // completed purchase here always ended in the alert that says the
        // archive did not open. That is the right answer when a family's
        // entitlement lives on a server that is not there — and the wrong
        // thing to put in front of somebody being shown the app, because the
        // last word on buying becomes a notice that the thing bought has not
        // arrived. Transcription, extraction and colourisation each have a
        // stub for exactly this reason; the entitlement was the one service
        // without one.
        //
        // Narrow on purpose: DEBUG, no address, and a seeded demo. A build
        // with `-api` or a Release build still asks the server and still
        // reports exactly what it answered. A device that has bought stays
        // bought across launches (`syncEntitlementIfPurchased`), so a take
        // that needs the offer card runs on an app installed fresh.
        if AppServices.apiBaseURL == nil, UserDefaults.standard.string(forKey: "seed") != nil {
            // The wait is not decoration. `PaywallSheet` declines exactly one
            // dismissal request after a purchase — RevenueCatUI sends one the
            // turn after `onPurchaseCompleted` — and closes the sheet itself
            // once the family has the archive. Answering instantly inverts
            // that order: the sheet's own `dismiss()` lands while the
            // purchase is still animating, is dropped, and then the declined
            // request is the only one left, so the sheet stays open for ever.
            // Measured on the first recorded take, 24 Sep 2026. A server
            // round trip is never this fast; neither is this.
            try? await Task.sleep(for: .milliseconds(700))
            openArchiveWithoutAServer()
            return true
        }
        #endif
        guard let entitlements else { return false }
        let reported = (try? await entitlements.sync(customerID: customerID)) != nil
        await refresh()
        return reported && isPaid
    }

    /// `personSubjectID` is the card the invitation is made for, if any. The
    /// caller pushes that card first (`SyncEngine.syncAfterRoundInFlight`) so
    /// that the join finds it; the server lets the join through without it.
    func createInvite(displayName: String = "", personSubjectID: String? = nil) async -> String? {
        guard let client else { return nil }
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let code = try await client.createInvite(displayName: displayName, personSubjectID: personSubjectID)
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

    /// Whether the server heard the removal.
    ///
    /// The owner's remedy for a link that went astray — see
    /// `FamilyClient.removeMember`. Like `revokeInvite`, a server that answers
    /// `removed: false` is not a failure here: that person was already gone,
    /// and the refresh shows the list as it is.
    func removeMember(id: String) async -> Bool {
        guard let client else { return false }
        lastError = nil
        do {
            try await client.removeMember(id: id)
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// The member's own name, changed. Lives on the server only: the server
    /// resolves every author's name from the member row at pull time, so
    /// this reaches the family's tellings — this phone's too — on the next
    /// pull, and `family` is refreshed so the Perhe screen agrees at once.
    /// Until 6 Sep 2026 the name was written at the join and never again
    /// (founder's-eye review, finding #64).
    func rename(displayName: String) async -> Bool {
        guard let client else { return false }
        lastError = nil
        do {
            _ = try await client.rename(displayName: displayName)
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// This member's own card in the tree — "this one is me" — or no card,
    /// with nil. `PATCH /family/me`; the family reads it back as
    /// `personSubjectID` on `GET /family`.
    ///
    /// Returns whether the server made the link, and says nothing itself: its
    /// first caller is the link after a sync (`SyncEngine.linkOwnCard`), where
    /// a refusal only means the card has not reached the server yet, and a
    /// sentence on whatever screen is open would be about nothing anybody did.
    /// A link that was made clears the card waiting for one, so a deliberate
    /// choice is not overwritten later by the automatic one.
    @discardableResult
    func linkMe(personSubjectID: String?) async -> Bool {
        guard let client else { return false }
        do {
            _ = try await client.link(personSubjectID: personSubjectID)
        } catch {
            return false
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingPersonLinkKey)
        await refresh()
        return true
    }

    /// "Tämä olen minä" on a person card (26 Sep 2026): the link, or the card
    /// left waiting for the round that can make it. The server refuses a card
    /// it does not hold yet, and a phone with no network reaches no server;
    /// both are answered by `SyncEngine.linkOwnCard` after the next round
    /// that gets through, exactly as the founder's own card is. Returns
    /// whether the link was made now rather than left waiting.
    @discardableResult
    func linkMeOrLater(personSubjectID: String) async -> Bool {
        if await linkMe(personSubjectID: personSubjectID) { return true }
        UserDefaults.standard.set(personSubjectID, forKey: Self.pendingPersonLinkKey)
        return false
    }

    /// "Tämä olet sinä" taken back (26 Sep 2026). A card the server holds as
    /// this member's is unlinked there, with null — the other half of
    /// `PATCH /family/me`, which the app had never called; a card only
    /// waiting for the round that would link it is simply no longer waiting,
    /// and no request is needed. Neither leaves a card waiting, or the next
    /// round would put the link back. Returns whether the mark is gone: a
    /// server that could not be reached changes nothing.
    func unlinkMe() async -> Bool {
        if family?.you.personSubjectID == nil {
            UserDefaults.standard.removeObject(forKey: Self.pendingPersonLinkKey)
            return true
        }
        return await linkMe(personSubjectID: nil)
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
        // A card still waiting for its link is this family's, and goes with it.
        UserDefaults.standard.removeObject(forKey: Self.pendingPersonLinkKey)
        // So does a notice about who this phone was in it.
        acknowledgeSharedIdentity()
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
        // A wiped device has not just joined anything, or created anything.
        UserDefaults.standard.removeObject(forKey: Self.arrivalPendingKey)
        UserDefaults.standard.removeObject(forKey: Self.firstMinutePendingKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingPersonLinkKey)
        UserDefaults.standard.removeObject(forKey: Self.sharedIdentityKey)
        sharedIdentityName = nil
        family = nil
        usage = nil
        mode = AppServices.apiBaseURL == nil ? .local : .needsFamily
    }

    // MARK: - Helpers

    #if DEBUG
    /// The paid state as the server would have reported it: neither meter
    /// limited, and the family row reading `archive` so that every screen
    /// asking a different question of the same fact agrees — `FamilyScreen`
    /// reads `family.entitlement`, the offer slot reads `usage`.
    private func openArchiveWithoutAServer() {
        if let family {
            self.family = Family(
                id: family.id, name: family.name, entitlement: "archive",
                you: family.you, members: family.members, invites: family.invites
            )
        }
        usage = EntitlementClient.Usage(
            entitlement: "archive",
            aiSeconds: .init(used: usage?.aiSeconds.used ?? 0, limit: nil),
            photos: .init(used: usage?.photos.used ?? 0, limit: nil)
        )
    }

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
    /// from this object. `photosUsed` is the family's count against its free
    /// twenty, which `-seed unarrived` puts at the ceiling.
    /// The same family with its member under another name, for the two
    /// fixtures that take `-joinedAs`.
    private static func renaming(_ seeded: Family, to name: String) -> Family {
        Family(
            id: seeded.id, name: seeded.name, entitlement: seeded.entitlement,
            you: Family.You(
                id: seeded.you.id, role: seeded.you.role, displayName: name,
                personSubjectID: seeded.you.personSubjectID
            ),
            members: seeded.members, invites: seeded.invites
        )
    }

    private func seedDemoFamily(alone: Bool = false, photosUsed: Int = 12) {
        let now = Date.now.timeIntervalSince1970
        let day: Double = 24 * 60 * 60
        mode = .inFamily(id: "demo-family")
        // `none` is a family whose "you" is linked to no card — see `init`.
        let yourCard = UserDefaults.standard.string(forKey: "you").flatMap { $0 == "none" ? nil : $0 }
        // `-theirs <card id>`: a card another member already is, which the
        // person card then does not offer as "Tämä olen minä".
        let theirCard = UserDefaults.standard.string(forKey: "theirs")
        // The card a previous launch left waiting for its link is device
        // state (`pendingPersonLinkKey`), and a seeded launch starts from
        // none — or the row that offered a card in one test would find it
        // already waiting in the next.
        UserDefaults.standard.removeObject(forKey: Self.pendingPersonLinkKey)
        // Nor has a seeded launch just joined as anybody.
        acknowledgeSharedIdentity()
        // A word rather than a name, so it is looked up like the author's is.
        // A member's `displayName` reaches the list through `Text(member
        // .displayName)` and `Text("\(member.displayName) (sinä)")`, neither
        // of which looks up a `String` — and this fixture is what the film and
        // the judging see, both of them in English.
        let mine = String(localized: "Minä")
        let you = Member(
            id: "demo-you", displayName: mine, role: "owner", joinedAt: now - 40 * day, personSubjectID: yourCard
        )
        family = Family(
            id: "demo-family",
            name: "Virtaset",
            entitlement: "free",
            you: Family.You(id: "demo-you", role: "owner", displayName: mine, personSubjectID: yourCard),
            members: alone ? [you] : [
                you,
                Member(
                    id: "demo-aino", displayName: "Aino", role: "member", joinedAt: now - 12 * day, personSubjectID: nil
                ),
                Member(
                    id: "demo-ville", displayName: "Ville", role: "member", joinedAt: now - 3 * day,
                    personSubjectID: theirCard
                ),
            ],
            // Two open invitations, as the server lists them since a code
            // admits one person: one made for somebody by name, one without.
            invites: alone ? [] : [
                Invite(code: "demo-kaarina", expiresAt: now + 6 * day, usedCount: 0, displayName: "Kaarina"),
                Invite(code: "demo-nimeton", expiresAt: now + 2 * day, usedCount: 0, displayName: nil),
            ]
        )
        // A free family with the month partly spent: the usage rows say a
        // fraction, which is the longer of their two forms and the one that
        // can overflow a row. `-entitlement archive` turns the same numbers
        // into the paid rows, which say only what has been used.
        usage = EntitlementClient.Usage(
            entitlement: "free",
            aiSeconds: .init(used: 7 * 60, limit: 10 * 60),
            photos: .init(used: photosUsed, limit: 20)
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
