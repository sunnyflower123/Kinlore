import Foundation

/// An install somebody is trying the app out on, rather than living with: a
/// judge who cloned the repository and ran `scripts/try-it.sh`, or chose the
/// `Kinlore Production` scheme in Xcode. Both launch the app with `-tryIt YES`,
/// and nothing else ever does, so a phone that installed Kinlore any other way
/// and every simulator the demo film was shot on have never seen the key.
///
/// What it changes is one card. Before the family's first telling, the Tell
/// screen offers a sentence to read aloud (`sentence`) where the two opening
/// starters stand, and a way to have it typed (`IdleView.offersExample`); read
/// aloud, it stays on the listening screen (`TellViewModel.readingAloud`). The
/// starters are the right first rung for a grandmother, who has a life to tell
/// about. Somebody trying the app out has a minute and nothing in particular to
/// say, and the sentence shows in that minute what comes back from a person, a
/// relation, a place and a date as vague as people say them.
///
/// **Remembered, because the argument is not.** A launch argument lives in
/// `UserDefaults`' argument domain, which lasts as long as the process: the
/// judge who goes to the home screen and opens Kinlore again from its icon
/// launches it with no arguments at all, and the card would be gone between
/// two tries. So a launch that carries the argument writes its value into the
/// app's own domain, where the next launch without one finds it. `-tryIt NO`
/// is written down the same way, which is how the UI tests put an install back
/// (`AccessibilityAudit.launch`).
///
/// It lives beside `KinloreApp` rather than among the services, and the device
/// wipe leaves it alone: it records how the app was launched, not anything
/// about the person holding the phone, which is what *"Tyhjennä tämä laite"*
/// promises to forget (`scripts/device-wipe-check.mjs`). A trial install that
/// is emptied to start again is still a trial.
enum TryIt {
    static let key = "tryIt"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Called from `KinloreApp.init`, before anything has read `isOn`.
    static func remember() {
        guard ProcessInfo.processInfo.arguments.contains("-\(key)") else { return }
        // The argument domain outranks the app's own, so this reads the
        // argument and writes it where it outlives the process.
        UserDefaults.standard.set(UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    /// The sentence to read aloud: a person, how she is related, a place and
    /// a decade said the way people say one, and nobody real in it.
    ///
    /// The English is not a translation of the Finnish, and on purpose: each
    /// is written for the recogniser that will hear it. The bench scores names
    /// at 60 % in English and 65 % in Finnish (docs/DETAILS.md, *Measured, not
    /// claimed*), so the names are ones either language hears every day —
    /// Anna, and Helsinki, and the husband Walter, who is Valtteri in Finnish
    /// — rather than a first try that opens on a misheard one.
    static var sentence: String {
        String(localized: "Mummoni Anna kasvoi Helsingissä. Hän meni naimisiin Valtterin kanssa joskus viisikymmentäluvulla, ja kamera oli aina Valtterilla.")
    }
}
