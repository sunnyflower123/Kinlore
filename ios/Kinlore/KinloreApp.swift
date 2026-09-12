import SwiftUI

@main
struct KinloreApp: App {
    /// One shared store for the whole app.
    @State private var store = MemoryStore()
    @State private var session = Session()
    /// One player for the whole app: two simultaneous sounds would be confusing.
    @State private var player = AudioPlayer()
    @State private var sync: SyncEngine?
    /// Finishes the memories whose text never arrived. Driven from here for the
    /// same reason as sync: they both run on the app's lifecycle, not on a tap.
    @State private var catchUp: TranscriptionCatchUp?
    /// One resolver for the whole app, so that its record of names nothing
    /// recognised survives from screen to screen.
    @State private var places = PlaceResolver()

    @Environment(\.scenePhase) private var scenePhase

    /// The code picked out of an invite link, if the app was opened from one.
    @State private var invitedCode: String?

    /// What to say when an invite link arrives on a device that cannot use it.
    ///
    /// A parsed link used to be dropped in silence here — the code was stored
    /// and nothing outside onboarding ever read it — and the likeliest wrong
    /// time is the most human one: the app was opened and looked at first, an
    /// archive got created with the big blue button, and *then* the
    /// grandchild's link was tapped. See docs/UX.md §4.1.
    @State private var linkNotice: LinkNotice?

    private enum LinkNotice: String, Identifiable {
        case deviceInFamily
        case deviceHasLocalArchive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deviceInFamily: String(localized: "Tämä laite kuuluu jo perheeseen")
            case .deviceHasLocalArchive: String(localized: "Tällä laitteella on jo oma arkisto")
            }
        }

        var message: String {
            switch self {
            case .deviceInFamily:
                String(localized: "Laite voi kuulua yhteen perheeseen kerrallaan. Voit poistua perheestä Asetuksista ja liittyä sitten kutsulla.")
            case .deviceHasLocalArchive:
                String(localized: "Sait kutsun perheeseen. Tämän puhelimen arkisto on erillinen. Voit tyhjentää laitteen Asetuksista ja liittyä sitten kutsulla.")
            }
        }
    }

    /// Set once during setup, on the phone that is being handed over. See
    /// `Elder.largerTextKey`.
    @AppStorage(Elder.largerTextKey) private var largerText = false

    var body: some Scene {
        WindowGroup {
            content
                // A floor, applied to the whole app rather than screen by
                // screen: the person it is for does not know which screen she is
                // on, and a size that changed between them would read as the app
                // being broken. `.xSmall...` is the same as no floor at all —
                // xSmall is the bottom of the scale.
                .dynamicTypeSize(largerText ? Elder.textFloor... : DynamicTypeSize.xSmall...)
                // Light, deliberately, for all of v1. Elder.swift's colours
                // were measured against white and its own comments carry the
                // ratios; measured against dark backgrounds on 23 Aug 2026,
                // destructive lands at ≈2.6:1 and the accent itself at
                // ≈2.7:1 — under the minimum on exactly the labels rule 1
                // exists for, on every phone a grandchild has set to dark.
                // Dark variants for the whole system are a designed piece of
                // work (ARCHITECTURE §15), not a toggle; until somebody does
                // it, one committed appearance beats an unmeasured second one.
                .preferredColorScheme(.light)
                .environment(store)
                .environment(session)
                .environment(player)
                // Nil until the first `task` runs, which is why the readers take
                // it as an optional. Before it exists nothing has been sent and
                // nothing has failed, and a screen with no engine to ask says
                // nothing — which is the correct answer for that instant.
                .environment(sync)
                .task {
                    // The engine needs both, so it is created here.
                    if sync == nil {
                        let engine = SyncEngine(store: store, session: session)
                        sync = engine
                        catchUp = TranscriptionCatchUp(
                            store: store, session: session, sync: engine
                        )
                    }
                    RevenueCatPurchases.configure(memberID: session.identity.memberID)
                    await sync?.sync()
                    // The family's details, beside the rows. They had no other
                    // writer on this path: `session.family` and `usage` were
                    // populated only by a visit to Asetukset → Perhe, so from
                    // the second launch on, the result screen's offer slot
                    // read nil, rendered nothing — and the rhythm counter was
                    // spent on the empty view all the same.
                    await session.refresh()
                    // Before the catch-up, not after: if this device is carrying
                    // a purchase the server has not heard about, the minutes it
                    // needs are one call away.
                    await syncEntitlementIfPurchased()
                    // A telling the app was killed under, adopted before the
                    // catch-up runs so its text is written in the same round.
                    RecordingRecovery.sweep(into: store)
                    await catchUp?.run()
                    // Last, and after sync: a place another device has already
                    // looked up arrives with the pull, and looking it up again
                    // here would be work for an answer we now have. Nothing on
                    // screen waits for it.
                    await places.resolvePending(in: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    // Coming back to the foreground: the family may have told
                    // memories in the meantime, and our own queue may be
                    // undrained.
                    guard phase == .active else { return }
                    Task {
                        await sync?.sync()
                        // The details refresh here too — and this is what
                        // carries a webhook's verdict to the devices that
                        // never bought anything. The payer is not the
                        // beneficiary, and until now only the payer's device
                        // ever asked: a family whose subscription renewed, or
                        // ended, learned of it on everyone else's phone only
                        // through Asetukset → Perhe.
                        await session.refresh()
                        // The network is the usual reason a transcription was
                        // deferred, and being opened again is the best evidence
                        // there is that it came back.
                        await catchUp?.run()
                        // Places told about since the last sweep.
                        await places.resolvePending(in: store)
                        // And a purchase the server never heard about. This ran
                        // at launch only, so a phone that is never quit — which
                        // is most phones — could carry a paid-for archive the
                        // family did not have for days. The guard costs a cached
                        // lookup and answers false on every device that has
                        // bought nothing.
                        await syncEntitlementIfPurchased()
                    }
                }
                .onChange(of: session.family?.entitlement) { _, _ in
                    // The family has just gone paid — or a webhook says it no
                    // longer is. The upgrade is the case that matters: the
                    // memory the quota interrupted is usually the very reason
                    // somebody bought, and it should not have to wait for the
                    // next launch to be written. Sync first, for the same
                    // reason: the photographs the free ceiling refused now
                    // fit, and the note about them should clear without
                    // waiting for a foreground.
                    Task {
                        await sync?.sync()
                        await catchUp?.run()
                    }
                }
                .onChange(of: store.outboxCount) { old, new in
                    // A telling leaves for the family the moment it exists.
                    // The lifecycle triggers cover the phone being picked up
                    // again; this covers the phone that never left the hand —
                    // without it, the ordinary flow (open, tell, put it down)
                    // shipped the memory on the NEXT opening, while Muistot
                    // promised it would leave by itself. The same argument
                    // already added the joiner's mode-flip trigger and the
                    // push after a deferred completion; the ordinary telling
                    // was the argument left unwired. Growth only: a wipe and
                    // a successful push both empty the outbox too.
                    guard new > old else { return }
                    Task { await sync?.sync() }
                }
                .onChange(of: session.mode) { _, mode in
                    // Joining is the case this exists for: the joiner has just
                    // landed on Muistot, and the family's memories are only on
                    // the server until this pull. The first sync used to wait
                    // for the next launch or foreground — on a phone that is
                    // never quit, that is an arrival with nothing arriving.
                    guard case .inFamily = mode else { return }
                    Task { await sync?.sync() }
                }
                .onOpenURL { url in
                    guard let code = Self.inviteCode(from: url) else { return }
                    handle(inviteCode: code)
                }
                .alert(
                    linkNotice?.title ?? "",
                    isPresented: Binding(
                        get: { linkNotice != nil },
                        set: { if !$0 { linkNotice = nil } }
                    ),
                    presenting: linkNotice
                ) { _ in
                    Button("Selvä") {}
                } message: { notice in
                    Text(notice.message)
                }
                #if DEBUG
                .task {
                    // `-invite <code-or-url>`: feeds the link handler at
                    // launch, so a test can reach the wrong-time alert — and,
                    // given a full kinlore:// URL, drives the real parser, so
                    // the fragment that carries the family key is exercised
                    // rather than bypassed. See docs/SETUP.md.
                    if let raw = UserDefaults.standard.string(forKey: "invite") {
                        // The engine is made by the task beside this one, and a
                        // refused device is told apart by asking it. A real tap
                        // arrives after launch and always finds it there; a
                        // link fed at launch waits for it the same way.
                        for _ in 0 ..< 40 where sync == nil {
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        if raw.hasPrefix("kinlore://"), let url = URL(string: raw) {
                            if let code = Self.inviteCode(from: url) {
                                handle(inviteCode: code)
                            }
                        } else {
                            handle(inviteCode: raw)
                        }
                    }
                    await Self.reportBackendStatus(session: session)
                }
                #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.mode {
        case .needsFamily:
            OnboardingScreen(prefilledCode: $invitedCode)
        case .local, .inFamily:
            // Without a backend the app is a single-device archive and no join
            // screen is shown at all. That keeps development and demoing going
            // even when the Worker is down.
            RootView(opensOnNewFromFamily: !NewFromFamily.unseen(
                in: store, me: session.identity.memberID
            ).isEmpty)
        }
    }

    /// Tells the server if this device has a purchase. The server verifies it
    /// with RevenueCat and spreads the entitlement to the whole family.
    private func syncEntitlementIfPurchased() async {
        let purchases = AppServices.purchases()
        guard await purchases.hasActivePurchase, let id = await purchases.customerID else { return }
        await session.syncPurchase(customerID: id)
    }

    /// A link is answered whatever state it arrives in. In `.needsFamily` it
    /// fills the join form, as ever; on a device that already has an archive
    /// it gets a sentence instead of silence. The server would refuse the
    /// join anyway (`member_exists`) — this says so before there is a request
    /// to refuse, in the app's own words, and leaves the one-family-per-device
    /// rule exactly where it was.
    private func handle(inviteCode: String) {
        switch session.mode {
        case .needsFamily: invitedCode = inviteCode
        case .inFamily:
            // A device the server has stopped knowing is the one case where a
            // link into "its own" family is the right thing: the grandchild
            // sent a fresh invitation, and this is it.
            if sync?.state == .refused {
                sync?.askToRejoin(code: inviteCode)
            } else {
                linkNotice = .deviceInFamily
            }
        case .local: linkNotice = .deviceHasLocalArchive
        }
    }

    /// `kinlore://join?code=<code>#<familyKey>`
    ///
    /// The family key rides the link as its **fragment** (PLAN §10 lever 3),
    /// and a fragment never reaches `queryItems` — reading only those dropped
    /// the key on exactly the tapped-link path, so a joiner who tapped joined
    /// a family they had no way to read, while pasting the same text, which
    /// hands the whole string to `Session.split`, worked. Reattached here so
    /// both paths deliver the identical string.
    /// Not private: the join form's paste button reads the same text through
    /// the same parser. Two readings of one format is how the fragment got
    /// dropped the first time.
    static func inviteCode(from url: URL) -> String? {
        guard url.scheme == "kinlore", url.host == "join",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        guard let key = components.fragment, !key.isEmpty else { return code }
        return "\(code)#\(key)"
    }

    #if DEBUG
    /// Reports at launch whether stubs or a real backend are in use, and whether
    /// the backend answers. Without this, a wrong address would only surface
    /// once the user had already spoken for a minute and the result vanished.
    private static func reportBackendStatus(session: Session) async {
        // The start of the identity goes into the log. If the Keychain is not
        // working, this changes on every launch — and the user would silently
        // lose their family, which is nearly impossible to notice without this
        // one line.
        print("[kinlore] member \(session.identity.memberID.prefix(8))… mode \(session.mode)")

        guard let base = AppServices.apiBaseURL else {
            print("[kinlore] backend: not configured — using stubs")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(
                from: base.appendingPathComponent("health")
            )
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[kinlore] backend \(base.absoluteString) → HTTP \(code) \(body)")
        } catch {
            print("[kinlore] backend \(base.absoluteString) → ERROR: \(error.localizedDescription)")
        }
    }
    #endif
}
