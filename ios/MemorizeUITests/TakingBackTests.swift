import XCTest

/// The way out of a telling.
///
/// The recording screen's only button both stopped and saved, and nothing in the
/// app removed a memory afterwards — so a telling begun by accident had to be
/// finished, transcribed and then lived with. Rule 3 is about the pipeline never
/// deciding that something told is worth discarding; it was never about holding
/// the teller to words they did not mean to give.
///
/// What is checked here is the archive on the other side of the taking-back, not
/// that a button exists.
final class TakingBackTests: XCTestCase {
    /// `-defer structure` keeps the result screen still: with the organising
    /// failing there are no follow-up questions, so nothing carries the run on
    /// into an interview while the test is looking at the screen.
    private let arguments = ["-seed", "empty", "-defer", "structure", "-screen", "interview"]

    func testAMemoryCanBeTakenBackAndTakesItsSubjectWithIt() {
        let app = launch(arguments)

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result screen"
        )

        let remove = app.buttons["Poista tämä muisto"]
        for _ in 0 ..< 4 where !remove.exists { app.swipeUp() }
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "never arrived: the way out")
        remove.tap()

        // Confirmed rather than done on one tap: this cannot be undone, and the
        // person holding the phone is 80.
        let confirm = app.buttons["Poista"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the removal asked nothing first")
        confirm.tap()

        // Back where telling starts.
        XCTAssertTrue(
            app.staticTexts["Paina ja ala puhua"].waitForExistence(timeout: 10),
            "the screen did not return to telling"
        )

        // And the archive is empty again — not merely missing the memory. Free
        // dictation made a subject to hold it, and a subject whose only telling
        // has been taken back is an empty card nobody can explain.
        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(
            app.staticTexts["Ei vielä kuvia"].waitForExistence(timeout: 10),
            "the taken-back memory left something behind in the gallery"
        )
    }

    /// The other half: a recording abandoned while it is still running.
    ///
    /// This one really records, so the run needs the microphone. A simulator
    /// that has never been asked shows the system prompt on the first launch —
    /// it is answered here rather than worked around, because a test that
    /// quietly skipped itself would be a green claim that nobody checked.
    func testAnAbandonedRecordingLeavesNothingBehind() {
        let app = launch(["-seed", "empty"])

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()

        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )

        let abandon = app.buttons["Älä tallenna tätä"]
        for _ in 0 ..< 4 where !abandon.exists { app.swipeUp() }
        XCTAssertTrue(abandon.waitForExistence(timeout: 10), "never arrived: the way out")
        abandon.tap()

        // It asks before it throws anything away. Only the destructive row is
        // asserted: an action sheet's cancel row is not in the app's element
        // tree on iOS 26, and the recording carrying on when it is chosen is
        // true by construction — nothing stops the recorder until `Hylkää`.
        let discard = app.buttons["Hylkää"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10), "the discard asked nothing first")
        discard.tap()

        XCTAssertTrue(
            app.staticTexts["Paina ja ala puhua"].waitForExistence(timeout: 10),
            "the screen did not return to telling"
        )
        // Nothing was saved: no result screen went past, and the gallery is as
        // empty as it was before the button was pressed.
        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(
            app.staticTexts["Ei vielä kuvia"].waitForExistence(timeout: 10),
            "an abandoned recording was saved anyway"
        )
    }

    /// Answers the microphone prompt if it is showing. The label depends on the
    /// simulator's own language, so the button is found by position in the
    /// alert rather than by what it says: permission alerts put the allowing
    /// answer last.
    private func allowTheMicrophone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        let buttons = alert.buttons
        guard buttons.count > 0 else { return }
        buttons.element(boundBy: buttons.count - 1).tap()
    }
}
