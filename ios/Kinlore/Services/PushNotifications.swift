import SwiftUI
import UIKit
import UserNotifications

/// Apple push, on the phone's side. `backend/src/apns.ts` is the other half.
///
/// Two notifications exist and nothing else rings this phone: somebody asked
/// this member something by name, and somebody answered a question this member
/// asked. Neither carries a word of either — the question and the telling are
/// sealed on the phone, so the Worker has none to send — and the sentence is a
/// key looked up here, in Localizable.strings, in the phone's own language.
///
/// **Quiet, and never asked for.** Authorization is provisional: iOS grants it
/// without a dialog and delivers to Notification Center only — no banner, no
/// sound, nothing on the lock screen — and offers to keep them or turn them
/// off on the first one that arrives. A permission dialog is a question from
/// the system about something the person did not start, and the rule since
/// 25 Sep 2026 is that the app does not put one in front of her when the
/// feature can work without it. A grandchild who wants banners turns them on
/// from that first notification, or in the phone's own settings.
///
/// Registration is tried on every launch in a family, because a token can
/// change and the server's upsert makes a repeat cost one request. A build
/// signed without the `aps-environment` entitlement is refused by iOS; that is
/// logged and nothing else, and the questions are on the card either way.
@MainActor
@Observable
final class PushNotifications {
    static let shared = PushNotifications()

    enum Route: Equatable {
        /// Somebody asked this member something: the Kerro tab offers it first.
        case tell
        /// A question this member asked was answered: the telling is at the
        /// top of "Uutta perheeltä" on Albumi.
        case album
    }

    /// Where a tapped notification leads, until `RootView` has gone there.
    var route: Route?

    /// The token iOS handed over this launch, as hex. In memory only: it is the
    /// phone's rather than a record about anybody, so a wipe has nothing of it
    /// to forget on the device — only on the server, under the old identity.
    private(set) var deviceToken: String?

    /// Who the next token is registered for.
    private var registrant: Identity?

    /// Quiet delivery, and a token for this member. Called at launch and on
    /// joining; outside a family there is nobody to be told anything.
    func register(identity: Identity) async {
        registrant = identity
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .provisional])) ?? false
        // Turned off in the phone's settings. Nothing is asked again.
        guard granted else { return }
        // The token is already known when this is a join in the same launch:
        // the new member needs it recorded under them now.
        if let deviceToken {
            await send(deviceToken, for: identity)
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// iOS's answer to `registerForRemoteNotifications`.
    func didRegister(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        let changed = hex != deviceToken
        deviceToken = hex
        guard changed, let registrant else { return }
        Task { await send(hex, for: registrant) }
    }

    /// Before a wipe renews the identity: the old member's row goes, or this
    /// phone would go on being told about questions asked of somebody it no
    /// longer is — with the asker's name on each one. Best effort: offline,
    /// the row stays until this phone registers under its next identity, which
    /// moves the token rather than adding a second one.
    func forget(identity: Identity) {
        registrant = nil
        guard let deviceToken, let base = AppServices.apiBaseURL else { return }
        let client = FamilyClient(baseURL: base, token: identity.token)
        Task { try? await client.unregisterPush(token: deviceToken) }
    }

    private func send(_ token: String, for identity: Identity) async {
        guard let base = AppServices.apiBaseURL else { return }
        do {
            try await FamilyClient(baseURL: base, token: identity.token)
                .registerPush(token: token, environment: Self.environment)
        } catch {
            // The type only: the error of a request carrying a token is not
            // somewhere to print one. The next launch registers again.
            print("[push] not recorded: \(type(of: error))")
        }
    }

    /// Which of Apple's two push servers issued this phone's token. A build
    /// installed from Xcode is development-signed even in Release, and its
    /// token is only known to the sandbox; TestFlight and the App Store carry
    /// production. The provisioning profile says which, and the App Store's
    /// builds have none.
    static var environment: String {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // A signed envelope around a plist; the plist is plain text in it.
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>aps-environment</key>"),
              let open = text.range(of: "<string>", range: key.upperBound ..< text.endIndex),
              let close = text.range(of: "</string>", range: open.upperBound ..< text.endIndex)
        else { return "production" }
        return text[open.upperBound ..< close.lowerBound] == "development" ? "sandbox" : "production"
        #endif
    }
}

/// The callbacks push needs that SwiftUI has no modifier for: the token, and a
/// tap on one of ours. Being the app's one delegate, it is also where the
/// navigation bar's font is set, once there is an application to set it on.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Elder.roundNavigationTitles()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotifications.shared.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Most often a build signed before the App ID had push.
        print("[push] not registered: \((error as NSError).domain) \((error as NSError).code)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let kinlore = info["kinlore"] as? [String: Any],
              let kind = kinlore["kind"] as? String else { return }
        await MainActor.run {
            PushNotifications.shared.route = kind == "asked" ? .tell : .album
        }
    }

    /// Arriving while the app is open. Kept in Notification Center rather than
    /// laid over the screen she is using; the question itself arrives with the
    /// next sync.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.list]
    }
}
