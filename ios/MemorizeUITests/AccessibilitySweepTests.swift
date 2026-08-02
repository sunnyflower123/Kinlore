import XCTest

/// Every screen, at the default size and at the largest one.
///
/// The guessing round's audit found four primary buttons below the contrast
/// minimum — on a screen that had been looked at in screenshots half a dozen
/// times. Contrast is not a thing eyes measure, and this app's user is the one
/// who pays for the difference. So the check is run everywhere rather than on
/// the screen that happened to prompt it.
///
/// The `-screen` and `-tab` launch arguments exist for exactly this: some of
/// these screens sit behind several taps, and a test run has no hands. See
/// docs/SETUP.md.
final class AccessibilitySweepTests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Audits a screen at both sizes in one test, so a failure names the screen
    /// rather than an index into a list.
    private func sweep(
        _ name: String,
        arguments: [String],
        api: String = "",
        settle: (XCUIApplication) -> Void = { _ in }
    ) throws {
        for size in [nil, Self.largest] {
            let app = launch(arguments, api: api, textSize: size)
            settle(app)
            let at = size == nil ? "default text size" : "largest text size"
            try audit(app, "\(name), \(at)")
            app.terminate()
        }
    }

    /// The first thing anybody sees, and the only screen an 80-year-old reaches
    /// before the app is hers. A non-empty address with nothing behind it is
    /// enough: nothing here is fetched.
    func testOnboarding() throws {
        try sweep("Onboarding", arguments: [], api: "http://127.0.0.1:9") { app in
            _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
        }
    }

    func testMemoriesWithContent() throws {
        try sweep("Muistot", arguments: ["-seed", "guess", "-tab", "memories"]) { app in
            _ = app.images.firstMatch.waitForExistence(timeout: 10)
        }
    }

    /// An empty state is not a blank screen in this app — it is an invitation,
    /// with a button on it. PLAN.md §6.5.
    func testMemoriesEmpty() throws {
        try sweep("Muistot, empty", arguments: ["-seed", "empty", "-tab", "memories"]) { app in
            _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
        }
    }

    /// The screen the app opens on and the one it exists for.
    func testTell() throws {
        try sweep("Kerro", arguments: ["-seed", "guess"]) { app in
            _ = app.staticTexts["Paina ja ala puhua"].waitForExistence(timeout: 10)
        }
    }

    func testTellByTyping() throws {
        try sweep("Kerro, typing", arguments: ["-seed", "guess", "-screen", "write"]) { app in
            _ = app.textViews.firstMatch.waitForExistence(timeout: 10)
            // The keyboard comes up with the screen, and auditing mid-animation
            // reported three elements with no description that were gone a
            // second later. Wait for it to arrive before measuring anything.
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        }
    }

    func testPeople() throws {
        try sweep("Ihmiset", arguments: ["-seed", "guess", "-tab", "people"]) { app in
            _ = app.staticTexts["Aino"].waitForExistence(timeout: 10)
        }
    }

    func testPeopleEmpty() throws {
        try sweep("Ihmiset, empty", arguments: ["-seed", "empty", "-tab", "people"]) { app in
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
        }
    }

    /// A person's card carries the proposal row and the relationships, which are
    /// the two places in the app where a colour means something.
    func testPersonCard() throws {
        try sweep(
            "Person card",
            arguments: ["-seed", "guess", "-tab", "people", "-screen", "person"]
        ) { app in
            _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
        }
    }

    func testSettings() throws {
        try sweep(
            "Asetukset",
            arguments: ["-seed", "guess", "-tab", "people", "-screen", "settings"]
        ) { app in
            _ = app.buttons.firstMatch.waitForExistence(timeout: 10)
        }
    }

    /// The photo's own screen: the memory list, the recognition line and the
    /// two things you can do to a subject.
    func testPhotoDetail() throws {
        try sweep("Photo detail", arguments: ["-seed", "guess", "-tab", "memories"]) { app in
            // The tile is the only image on the memories screen.
            let tile = app.images.firstMatch
            guard tile.waitForExistence(timeout: 10) else { return }
            tile.tap()
            _ = app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10)
        }
    }

    /// Asking is the other half of the question loop, and it is a sheet with a
    /// text field — the one control type nothing else here covers.
    /// The way out of a misheard name. A sheet with a text field on it is the
    /// shape most likely to stop working at the largest size, and this one has
    /// to keep working: it is the only correction the archive offers once the
    /// telling is over.
    func testCorrectNameSheet() throws {
        try sweep("Korjaa nimi", arguments: ["-seed", "guess", "-tab", "people"]) { app in
            let person = app.cells.firstMatch
            guard person.waitForExistence(timeout: 10) else { return }
            person.tap()
            let correct = app.buttons["Korjaa nimi"]
            guard correct.waitForExistence(timeout: 10) else { return }
            correct.tap()
            _ = app.buttons["Tallenna"].waitForExistence(timeout: 10)
        }
    }

    func testAskQuestionSheet() throws {
        try sweep("Kysy perheeltä", arguments: ["-seed", "guess", "-tab", "memories"]) { app in
            let tile = app.images.firstMatch
            guard tile.waitForExistence(timeout: 10) else { return }
            tile.tap()
            let ask = app.buttons["Kysy perheeltä"]
            guard ask.waitForExistence(timeout: 10) else { return }
            ask.tap()
            _ = app.buttons["Lähetä kysymys"].waitForExistence(timeout: 10)
        }
    }
}
