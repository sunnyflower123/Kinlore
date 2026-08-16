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
                    // Before the catch-up, not after: if this device is carrying
                    // a purchase the server has not heard about, the minutes it
                    // needs are one call away.
                    await syncEntitlementIfPurchased()
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
                    // next launch to be written.
                    Task { await catchUp?.run() }
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
            OnboardingScreen(prefilledCode: $invitedCode)
        case .local, .inFamily:
            // Without a backend the app is a single-device archive and no join
            // screen is shown at all. That keeps development and demoing going
            // even when the Worker is down.
            RootView()
        }
    }

    /// Tells the server if this device has a purchase. The server verifies it
    /// with RevenueCat and spreads the entitlement to the whole family.
    private func syncEntitlementIfPurchased() async {
        let purchases = AppServices.purchases()
        guard await purchases.hasActivePurchase, let id = await purchases.customerID else { return }
        await session.syncPurchase(customerID: id)
    }

    /// `kinlore://join?code=...`
    private static func inviteCode(from url: URL) -> String? {
        guard url.scheme == "kinlore", url.host == "join" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "code" }?
            .value
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
