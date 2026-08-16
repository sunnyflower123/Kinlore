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
