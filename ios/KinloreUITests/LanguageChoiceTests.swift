import XCTest

/// The language chosen in Settings (`AppLanguage`): the one setting this app
/// keeps in a key the system reads, `AppleLanguages` in the app's own domain.
///
/// It is read at the next launch, so the test launches again between choosing
/// and looking. The app stays in Finnish throughout, because `launch` pins
/// `-AppleLanguages (fi)` in the argument domain, which outranks the app's
/// own; what is checked is what the app's own domain holds, as the picker
/// reads it back.
///
/// `tearDown` puts the simulator back whatever the test left. A leftover
/// `AppleLanguages` outlives the test, and any launch on that simulator that
/// does not pin a language of its own, as `launch` does, would open in
/// English.
///
/// The row is last on Settings, below the wipe row (`SettingsScreen` says
/// why), so every launch scrolls to it as a person would.
final class LanguageChoiceTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        launch(["-seed", "empty", "-appLanguage", "phone"]).terminate()
        super.tearDown()
    }

    func testTheChoiceIsKeptAndSameAsThePhoneRemovesIt() {
        let app = launch([
            "-seed", "archive", "-tab", "people", "-screen", "settings", "-appLanguage", "phone",
        ])
        XCTAssertTrue(app.navigationBars["Asetukset"].waitForExistence(timeout: 10), "never arrived: Settings")
        let row = scrollToTheLanguageRow(in: app)
        XCTAssertTrue(
            row.label.contains("Puhelimen kieli"),
            "a phone with no choice of its own does not read as the phone's language: \(row.label)"
        )
        row.tap()
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 10), "never arrived: the choice of language")
        english.tap()
        XCTAssertTrue(english.isSelected, "the choice did not take")
        // Back in Settings, the row names the choice before any relaunch.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10), "never arrived back: Settings")
        XCTAssertTrue(row.label.contains("English"), "the row does not name the choice: \(row.label)")
        app.terminate()

        // Opened again from its icon, with no argument about the language.
        var arguments = app.launchArguments
        if let at = arguments.firstIndex(of: "-appLanguage") {
            arguments.removeSubrange(at ... at + 1)
        }
        XCTAssertFalse(arguments.contains("-appLanguage"), "the relaunch still carries the argument")
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Asetukset"].waitForExistence(timeout: 10), "never arrived: Settings, launched again")
        scrollToTheLanguageRow(in: app)
        XCTAssertTrue(row.label.contains("English"), "the choice did not outlast the app: \(row.label)")
        row.tap()
        let phone = app.buttons["Puhelimen kieli"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10), "never arrived: the choice of language, launched again")
        XCTAssertTrue(app.buttons["English"].isSelected, "the picker does not read the kept choice")
        phone.tap()
        app.terminate()

        // "Same as the phone" is no choice at all: the key is gone, which is
        // the only state `AppLanguage.chosen` reads as the phone's language.
        app.launch()
        XCTAssertTrue(app.navigationBars["Asetukset"].waitForExistence(timeout: 10), "never arrived: Settings, launched a third time")
        scrollToTheLanguageRow(in: app)
        XCTAssertTrue(
            row.label.contains("Puhelimen kieli"),
            "the phone's language did not take the override away: \(row.label)"
        )
        app.terminate()
    }

    /// The language row, scrolled to until it is whole above the tab bar,
    /// where a tap is the row's and not the bar's.
    @discardableResult
    private func scrollToTheLanguageRow(in app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["language"]
        let bar = app.tabBars.firstMatch
        for _ in 0 ..< 6 where !(row.exists && row.frame.maxY <= bar.frame.minY) {
            app.swipeUp()
        }
        XCTAssertTrue(row.exists, "never arrived: the language row")
        XCTAssertLessThanOrEqual(row.frame.maxY, bar.frame.minY, "the language row stayed under the tab bar")
        return row
    }
}
