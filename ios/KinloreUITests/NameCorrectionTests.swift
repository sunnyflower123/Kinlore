import XCTest

/// Correcting a name after the telling is over.
///
/// The Tell screen's correction is the good moment and it was the only one.
/// Speech recognition is wrong about one proper noun in three, so a name missed
/// there used to be a wrong person in the family tree for good — and the
/// guessing round could then confirm that wrong person as fact. This is the way
/// back out, and it is worth a test that presses the buttons: the write itself
/// is `MemoryStore.rename`, which is well covered by the merge rules, but
/// nothing before this checked that a person can reach it.
final class NameCorrectionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The interview's rounds each propose names, and the loop-end result
    /// screen is their one at-telling correction moment. An assignment in
    /// `save` used to replace the list every round, so only the last round's
    /// names ever met "Kuulinko nimet oikein?" — the opening telling's people
    /// skipped this screen entirely, and their backstop was the person list.
    ///
    /// `-screen interviewed` runs the loop hands-free to its result: the
    /// typed opening mentions Kuopio (the stub reads names mid-sentence only,
    /// so Eevert — who opens his sentence — is never extracted), and the
    /// first recorded round rotates to the sample that mentions Aino. One
    /// name from each round must stand in the editable rows. The second round
    /// records for real, which is why the microphone prompt is answered here.
    func testInterviewRoundsAllReachTheNameCheck() throws {
        let app = launch(["-seed", "empty", "-screen", "interviewed"])
        allowTheMicrophone()

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 60),
            "the interview never reached its result screen"
        )

        let opening = app.textFields.matching(
            NSPredicate(format: "value == %@", "Kuopiossa")
        ).firstMatch
        let recorded = app.textFields.matching(
            NSPredicate(format: "value == %@", "Aino")
        ).firstMatch
        for _ in 0 ..< 4 where !opening.exists { app.swipeUp() }
        XCTAssertTrue(
            opening.waitForExistence(timeout: 10),
            "the opening telling's name skipped the check"
        )
        XCTAssertTrue(
            recorded.exists || recorded.waitForExistence(timeout: 5),
            "the recorded round's name is missing from the check"
        )
    }

    /// Answers the microphone prompt if it appears. The interviewed loop's
    /// first recording raises it a few seconds into the run, so this waits
    /// longer than the sibling in TakingBackTests.
    private func allowTheMicrophone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 20) else { return }
        let buttons = alert.buttons
        guard buttons.count > 0 else { return }
        buttons.element(boundBy: buttons.count - 1).tap()
    }

    func testACorrectedNameShowsOnTheCard() throws {
        let app = launch(["-seed", "archive", "-tab", "people"])

        let person = app.cells.firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10), "the people list")
        // The card is named after whoever the seed put first; the correction is
        // made relative to that rather than to a hard-coded name, so the test
        // does not break the next time the fixture changes.
        person.tap()

        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        let original = field.value as? String ?? ""
        XCTAssertFalse(original.isEmpty, "the field starts with the name it is correcting")

        // Appended rather than retyped: clearing a field is fiddly and proves
        // nothing extra, and the point is that what is typed reaches the card.
        field.tap()
        field.typeText("nen")
        app.buttons["Tallenna"].tap()

        let corrected = original + "nen"
        XCTAssertTrue(
            app.navigationBars[corrected].waitForExistence(timeout: 10),
            "the card shows the corrected name, not the one it was pushed with"
        )
    }

    /// A correction that lands on somebody the family already has is a merge:
    /// the two cards become one and this one's memories move across. It used to
    /// happen on the same tap as an ordinary rename, warned about only by a
    /// footer — and unlike a rename, nothing in the app undoes it.
    /// A merge carries the relationships across. Until 4 Sep 2026 it moved
    /// the memories and the mentions and left every edge pointing at the
    /// tombstone, so a confirmed spouse vanished from the survivor's tree the
    /// moment a name was tidied — in the one flow that exists to keep the
    /// tree right.
    func testAMergeKeepsTheRelationships() throws {
        // The fixture with Eeva and Kalle as spouses.
        let app = launch(["-seed", "related", "-tab", "people"])

        let eeva = app.staticTexts["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the people list")
        eeva.tap()
        XCTAssertTrue(app.staticTexts["Puoliso"].waitForExistence(timeout: 10), "the fixture's relationship is not on the card")

        // Then Eeva's name is corrected onto Aino, and the cards merge.
        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Aino")
        app.buttons["Tallenna"].tap()
        XCTAssertTrue(app.staticTexts["Yhdistetäänkö kortit?"].waitForExistence(timeout: 10), "the merge did not ask")
        app.buttons["Yhdistä"].tap()
        XCTAssertTrue(app.navigationBars["Ihmiset"].waitForExistence(timeout: 10), "the merged card stayed open")

        // Aino's card now holds the spouse Eeva had.
        let aino = app.staticTexts["Aino"]
        XCTAssertTrue(aino.waitForExistence(timeout: 10), "Aino is not on the list")
        aino.tap()
        let group = app.staticTexts["Puoliso"]
        for _ in 0 ..< 4 where !group.exists { app.swipeUp() }
        XCTAssertTrue(group.waitForExistence(timeout: 10), "the spouse did not follow the merge")
        XCTAssertTrue(app.staticTexts["Kalle"].exists, "the spouse is somebody else")
    }

    func testAMergeAsksBeforeItHappens() throws {
        let app = launch(["-seed", "archive", "-tab", "people"])

        // Eeva by name rather than by position: the merge needs a *second*
        // person to land on, and which of them is first in the list is the
        // fixture's business.
        let eeva = app.staticTexts["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the people list")
        eeva.tap()

        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        // Cleared this time, because the point is landing exactly on a name the
        // family already has.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Aino")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.staticTexts["Yhdistetäänkö kortit?"].waitForExistence(timeout: 10),
            "the merge happened without asking"
        )
        app.buttons["Yhdistä"].tap()

        // The card is a tombstone now and there is nothing left to look at, so
        // the screen goes back to the list — where there is one Aino and no
        // Eeva.
        XCTAssertTrue(
            app.navigationBars["Ihmiset"].waitForExistence(timeout: 10),
            "the merged card stayed open"
        )
        XCTAssertFalse(app.staticTexts["Eeva"].exists, "the merged person is still listed")
    }

    /// Nothing to save is nothing to press. Without this the sheet would happily
    /// write the name it already had, which is a no-op that still marks the row
    /// for sync and confuses the ordering counter for no reason.
    func testSavingIsRefusedUntilSomethingChanges() throws {
        let app = launch(["-seed", "archive", "-tab", "people"])

        let person = app.cells.firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.tap()

        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10))
        correct.tap()

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertFalse(save.isEnabled, "unchanged name, nothing to save")
    }
}
