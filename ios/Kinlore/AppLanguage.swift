import Foundation

/// The language Kinlore is shown in, chosen in Settings (`LanguageScreen`)
/// since 29 Sep 2026: the phone's own, English or Finnish. The phone's own is
/// the default, so a phone that is not set to Finnish still opens in English.
///
/// **The setting iOS keeps, not one of the app's own.** A choice is the
/// `AppleLanguages` key in this app's defaults domain, which is what the
/// phone's own per-app language setting writes and what the system reads when
/// the app starts, so the two cannot disagree and nothing in the app looks a
/// string up by hand. *"Puhelimen kieli"* removes the key, and the phone's
/// list of languages decides again.
///
/// **At the next launch, and said so.** The system resolves the app's language
/// once, as the process starts, and every string on screen was looked up in
/// that language. Changing it under a running app would take swizzling the
/// bundle or quitting from under the person who asked, and either way some
/// screen is left half in one language. So the choice is written at once, read
/// at the next launch, and the screen it is made on says when.
///
/// The language the app hears follows it too. `SpokenLanguage.current` reads
/// the same resolved localisation, so after the next launch the prompts the
/// Worker transcribes and extracts with are the chosen language's.
///
/// It lives beside `KinloreApp` rather than among the services, and the device
/// wipe leaves it alone, as it leaves `TryIt`: it is the phone's setting for
/// this app, the one iOS keeps as well, not something the archive knows about
/// the person holding the phone (`scripts/device-wipe-check.mjs`).
enum AppLanguage: String, CaseIterable, Identifiable {
    case phone
    case english = "en"
    case finnish = "fi"

    var id: String { rawValue }

    static let key = "AppleLanguages"

    /// The choice as this app's own domain holds it. Not
    /// `UserDefaults.standard.object(forKey:)`, which always has an answer:
    /// the phone's list from the global domain when the app has no choice of
    /// its own, and under a UI test the argument domain's `-AppleLanguages
    /// (fi)`. Only the app's own domain tells a choice from none.
    static var chosen: AppLanguage {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap {
                UserDefaults.standard.persistentDomain(forName: $0)
            }
            guard let first = (domain?[key] as? [String])?.first else { return .phone }
            return Locale(identifier: first).language.languageCode == .finnish ? .finnish : .english
        }
        set {
            switch newValue {
            case .phone: UserDefaults.standard.removeObject(forKey: key)
            case .english, .finnish: UserDefaults.standard.set([newValue.rawValue], forKey: key)
            }
        }
    }

    /// The option's name, as the picker and the Settings row show it. English
    /// and Suomi are written in their own language whatever the app is in, so
    /// that somebody who cannot read the one on screen can still find theirs.
    var name: String {
        switch self {
        case .phone: String(localized: "Puhelimen kieli")
        case .english: "English"
        case .finnish: "Suomi"
        }
    }

    #if DEBUG
    /// `-appLanguage phone|en|fi` sets the choice as the picker would, before
    /// anything is drawn. `LanguageChoiceTests` puts its simulator back with
    /// it, whatever a failed test left: a leftover `AppleLanguages` outlives
    /// the test, and any launch there that does not pin a language of its own
    /// would open in English. See docs/SETUP.md.
    static func applyLaunchArgument() {
        guard let raw = UserDefaults.standard.string(forKey: "appLanguage"),
              let language = AppLanguage(rawValue: raw)
        else { return }
        chosen = language
    }
    #endif
}
