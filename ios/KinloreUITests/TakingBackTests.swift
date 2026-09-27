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
        app.tabBars.buttons["Albumi"].tap()
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
        app.tabBars.buttons["Albumi"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
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
        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "did not get back to the gallery")
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

        app.tabBars.buttons["Albumi"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
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

    /// A person nobody has told about: the checkmark hit instead of the
    /// cross, or a name the recognition invented. The fixture's Aino is a
    /// proposal with no story of her own and nobody related to her.
    func testAPersonNobodyHasToldAboutCanBeDeleted() {
        let app = launch(["-seed", "archive", "-tab", "people"])

        // Aino is a name nobody has checked, so since 12 Sep 2026 she is
        // behind the door at the bottom of the list rather than on it.
        let door = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "odottaa tarkistusta")).firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 10), "never arrived: the people list's door")
        door.tap()
        let aino = app.staticTexts["Aino"]
        XCTAssertTrue(aino.waitForExistence(timeout: 10), "never arrived: the names heard")
        aino.tap()

        let remove = app.buttons["Poista henkilö"]
        for _ in 0 ..< 4 where !remove.exists { app.swipeUp() }
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "the person's card offers no way to delete her")
        remove.tap()

        let confirm = app.buttons["Poista"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the removal asked nothing first")
        confirm.tap()

        // Back behind the door, and she is not there either.
        XCTAssertTrue(app.navigationBars["Kuullut nimet"].waitForExistence(timeout: 10), "did not get back to the names heard")
        XCTAssertFalse(app.staticTexts["Aino"].exists, "the deleted person is still listed")
    }

    /// The other half: a recording abandoned while it is still running.
    ///
    /// This one really records, so the run needs the microphone. A simulator
    /// that has never been asked shows the system prompt on the first launch —
    /// it is answered here rather than worked around, because a test that
    /// quietly skipped itself would be a green claim that nobody checked.
    /// Where the AI filed the telling, corrected. The placement line was the
    /// most important piece of the result and the one nothing could change
    /// (founder's-eye review, finding #27): the sheet offers the family's
    /// people, places and events, and the sentence follows the choice.
    func testATellingCanBeMovedToAnotherCard() {
        let app = launch(["-seed", "archive", "-tab", "tell", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        let move = app.buttons["Siirrä toiselle kortille"]
        for _ in 0 ..< 3 where !move.exists { app.swipeUp() }
        XCTAssertTrue(move.waitForExistence(timeout: 10), "the placement could not be corrected")
        move.tap()

        XCTAssertTrue(app.navigationBars["Mihin muisto kuuluu?"].waitForExistence(timeout: 10), "the sheet did not open")
        let sanni = app.buttons["Sanni"]
        for _ in 0 ..< 3 where !sanni.exists { app.swipeUp() }
        XCTAssertTrue(sanni.waitForExistence(timeout: 10), "the family's people were not offered")
        sanni.tap()

        XCTAssertTrue(
            app.staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Muisto on nyt kohteessa", "Sanni"))
                .firstMatch.waitForExistence(timeout: 10),
            "the placement line did not follow the move"
        )
    }

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
        app.tabBars.buttons["Albumi"].tap()
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

    /// The way back (§19, 26 Sep 2026). A telling taken back from its card
    /// is offered back to its teller on the same card for thirty days, as a
    /// quiet row where the memories end and not as a list of its own; one
    /// tap brings it back, with no question asked, because a telling brought
    /// back by mistake can be taken back again. `-seed restorable` files
    /// three tellings of this phone's own under the photograph: one live, one
    /// taken back three days ago and one forty days ago.
    func testATellingTakenBackFromItsCardCanBeBroughtBack() {
        let app = launch(["-seed", "restorable", "-tab", "memories"])

        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "never arrived: the photo tile")
        tiles.firstMatch.tap()

        // The card lists its tellings newest first and builds a row only as
        // it comes into view, and the live telling is the second row, under
        // Mummo's — so the way back under both is reached first, which builds
        // the telling's row on the way. One row: the three-day-old
        // taking-back. The forty-day-old one is outside the window and is
        // not offered.
        let rows = app.buttons.matching(identifier: "card.restoreMemory")
        for _ in 0 ..< 8 where rows.firstMatch.exists == false { app.swipeUp() }
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the card offers no way back")
        XCTAssertEqual(rows.count, 1, "the card offers back what is outside the window")

        let own = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Laiturin päässä")).firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10), "the live telling is not on the card")

        // Take the live telling back from the card, the ordinary way. Only
        // the teller's own row offers it; Mummo's does not.
        let remove = app.buttons["Poista tämä muisto"]
        for _ in 0 ..< 4 where !remove.exists { app.swipeUp() }
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "the card offers no way to take it back")
        remove.tap()
        let confirm = app.buttons["Poista"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the removal asked nothing first")
        confirm.tap()

        // Gone from the card, and offered back on it: the newest taking-back
        // sits first, where the eye lands.
        XCTAssertTrue(own.waitForNonExistence(timeout: 10), "the telling is still on the card")
        for _ in 0 ..< 4 where rows.count < 2 { app.swipeUp() }
        XCTAssertEqual(rows.count, 2, "the taking-back is not offered back")
        rows.firstMatch.tap()

        // Back on the card, and the row for it gone; the older one stays.
        // The list keeps its place while the telling's row goes back in
        // above the way back, so each is looked for where it now sits.
        for _ in 0 ..< 4 where !own.exists { app.swipeDown() }
        XCTAssertTrue(own.waitForExistence(timeout: 10), "the telling did not come back")
        for _ in 0 ..< 4 where rows.count < 1 { app.swipeUp() }
        XCTAssertEqual(rows.count, 1, "the row outlived the bringing-back")
    }

    /// The window is thirty days and it is the card's: a taking-back older
    /// than that is not offered, and bringing the three-day-old one back does
    /// not bring the forty-day-old one with it.
    func testATellingTakenBackLongerAgoThanThirtyDaysIsNotOffered() {
        let app = launch(["-seed", "restorable", "-tab", "memories"])

        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "never arrived: the photo tile")
        tiles.firstMatch.tap()

        let rows = app.buttons.matching(identifier: "card.restoreMemory")
        for _ in 0 ..< 4 where rows.firstMatch.exists == false { app.swipeUp() }
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the card offers no way back")
        XCTAssertEqual(rows.count, 1, "a taking-back older than the window is offered back")
        rows.firstMatch.tap()

        let recent = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Rantaan tuli joka kesä")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10), "the three-day-old telling did not come back")
        let old = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Saunan takana")).firstMatch
        XCTAssertFalse(old.exists, "the forty-day-old telling came back with it")
        XCTAssertEqual(rows.count, 0, "a row is still offered after the last bringing-back")
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
