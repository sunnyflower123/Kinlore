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

    /// The same, the day after: from the memory's own card instead of the
    /// result screen. The result screen is open for seconds; the card is where
    /// a telling is read back tomorrow, and "I did not mean to say that" comes
    /// more often then than right away. Until 3 Sep 2026 the card had no way.
    func testAMemoryCanBeTakenBackFromItsCard() {
        let app = launch(arguments)

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result screen"
        )

        // Leave the result screen the ordinary way, keeping the telling.
        let another = app.buttons["Kerro toinen muisto"]
        for _ in 0 ..< 4 where !another.exists { app.swipeUp() }
        XCTAssertTrue(another.waitForExistence(timeout: 10), "never arrived: the way on")
        another.tap()

        // Free dictation filed the telling under a moment of its own; with
        // the structuring deferred that moment is still untitled.
        app.tabBars.buttons["Muistot"].tap()
        let row = app.staticTexts["Kerrottu muisto"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery")
        row.tap()

        let remove = app.buttons["Poista tämä muisto"]
        for _ in 0 ..< 4 where !remove.exists { app.swipeUp() }
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "the card offers no way to take it back")
        remove.tap()

        // The same question, in the same words, as on the result screen.
        let confirm = app.buttons["Poista"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the removal asked nothing first")
        confirm.tap()

        // The moment held only this telling, so it went too, and the card
        // with it: back in the gallery, which is empty again.
        XCTAssertTrue(
            app.staticTexts["Ei vielä kuvia"].waitForExistence(timeout: 10),
            "the taken-back memory left something behind in the gallery"
        )
    }

    /// A photograph, not a telling: the wrong side of a print, a blurred one,
    /// the same one twice. Nothing has been told about it, so nothing is lost
    /// with it — and until 4 Sep 2026 it could not go at all.
    func testAPhotoNobodyHasToldAboutCanBeDeleted() {
        let app = launch(["-seed", "empty", "-tab", "memories", "-import", "2"])

        // The pile asks its date first; any answer will do.
        XCTAssertTrue(
            app.staticTexts["Milloin nämä olivat?"].waitForExistence(timeout: 10),
            "the import did not ask for a date"
        )
        app.buttons["Vuosikymmen"].tap()
        let fifties = app.buttons["1950-luku"]
        for _ in 0 ..< 4 where !fifties.exists { app.swipeUp() }
        XCTAssertTrue(fifties.waitForExistence(timeout: 10), "never arrived: the decade to choose")
        fifties.tap()

        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "never arrived: the imported photos")
        XCTAssertEqual(tiles.count, 2, "the import did not bring in two photos")
        wait(
            for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: tiles.firstMatch)],
            timeout: 10
        )
        tiles.firstMatch.tap()

        let remove = app.buttons["Poista kuva"]
        for _ in 0 ..< 4 where !remove.exists { app.swipeUp() }
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "the photo's card offers no way to delete it")
        remove.tap()

        let confirm = app.buttons["Poista"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the removal asked nothing first")
        confirm.tap()

        // Back in the gallery with one photo fewer — and the other still there.
        XCTAssertTrue(app.navigationBars["Muistot"].waitForExistence(timeout: 10), "did not get back to the gallery")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "the other photo went too")
        XCTAssertEqual(tiles.count, 1, "the deleted photo is still in the gallery")
    }

    /// Not taking back but correcting: the words the family reads, fixed by
    /// the one who said them. A wrong ordinary word in the one sentence that
    /// mattered is what the name step cannot reach, and from the card the day
    /// after is where it is noticed. In this file because it walks the same
    /// path as the taking back above, and until 4 Sep 2026 had no door either.
    func testTheTextOfAnOwnTellingCanBeCorrected() {
        let app = launch(arguments)

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result screen"
        )
        let another = app.buttons["Kerro toinen muisto"]
        for _ in 0 ..< 4 where !another.exists { app.swipeUp() }
        XCTAssertTrue(another.waitForExistence(timeout: 10), "never arrived: the way on")
        another.tap()

        app.tabBars.buttons["Muistot"].tap()
        let row = app.staticTexts["Kerrottu muisto"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery")
        row.tap()

        let edit = app.buttons["Muokkaa tekstiä"]
        for _ in 0 ..< 4 where !edit.exists { app.swipeUp() }
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "the card offers no way to correct the text")
        edit.tap()

        let field = app.descendants(matching: .any)["Muiston teksti"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the text to correct")
        field.tap()
        field.typeText(" Lisätty korjaus.")
        app.buttons["Tallenna"].tap()

        // The corrected words are what the card reads now.
        let corrected = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Lisätty korjaus."))
            .firstMatch
        XCTAssertTrue(corrected.waitForExistence(timeout: 10), "the correction did not reach the memory")
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

    /// The third exit, and the one both sheet sites had left unguarded: a Tell
    /// screen presented from a card carries a "Sulje" in its corner, and it
    /// used to destroy a running recording on one tap — or one swipe — past
    /// the exact guard the hidden tab bar and the confirmed discard put on the
    /// other two exits. This one also really records, so it answers the
    /// microphone prompt like the test above.
    func testClosingTheSheetMidRecordingAsksFirst() {
        let app = launch(["-seed", "archive", "-tab", "people", "-screen", "person"])

        let tell = app.buttons["Kerro tästä muisto"]
        XCTAssertTrue(tell.waitForExistence(timeout: 15), "never arrived: the person card")
        tell.tap()

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()

        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )

        // A swipe must not do what the button is guarded against.
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Kuuntelen"].exists, "a swipe dismissed a running recording")

        app.buttons["Sulje"].tap()

        // It asks first, in the same words as the in-screen discard. Only the
        // destructive row is asserted, as above: an action sheet's cancel row
        // is not in the app's element tree on iOS 26.
        let discard = app.buttons["Hylkää"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10), "Sulje asked nothing first")
        discard.tap()

        // The sheet is gone, the card is back, and nothing was saved.
        XCTAssertTrue(tell.waitForExistence(timeout: 10), "the sheet did not close after the discard")
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
