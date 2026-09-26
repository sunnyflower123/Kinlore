import XCTest

/// The two names nothing could change after the fact.
///
/// A photograph's title was whatever its first telling left, and its card
/// could date the picture but not name it; a member's own name was written at
/// the join and never again, so a joiner who left the field empty was
/// "Perheenjäsen" beside every telling for good (founder's-eye review,
/// findings #12 and #64). Both go through `NameSheet` since 6 Sep 2026.
final class NamingTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The name reaches the card's title and the tile on Muistot, which reads
    /// it aloud in place of "Valokuva".
    func testAPhotographCanBeNamedFromItsCard() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "never arrived: the photo tile")
        photo.tap()

        let name = app.buttons["Anna kuvalle nimi"]
        for _ in 0 ..< 4 where !name.exists { app.swipeUp() }
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the card offers no way to name the photograph")
        name.tap()

        let field = app.textFields["Nimi"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the name sheet")
        field.tap()
        field.typeText("Mökin ranta")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.navigationBars["Mökin ranta"].waitForExistence(timeout: 10),
            "the name did not reach the card"
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.buttons["Mökin ranta, 1 muisto"].waitForExistence(timeout: 10),
            "the tile does not carry the name"
        )
    }

    /// The own name lives on the server, and the server can be out of reach.
    /// `-seed family` has no server behind it, so this is the failed save:
    /// said in the sheet, which stays open, rather than closed over in silence.
    func testAMemberIsToldWhenTheirNameCouldNotBeChanged() {
        let app = launch(["-seed", "family", "-tab", "people", "-screen", "family"])
        let change = app.buttons["Vaihda nimi"]
        for _ in 0 ..< 4 where !change.exists { app.swipeUp() }
        XCTAssertTrue(change.waitForExistence(timeout: 10), "the family screen offers no way to change one's own name")
        change.tap()

        let field = app.textFields["Nimi"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the name sheet")
        XCTAssertEqual(field.value as? String, "Minä", "the field did not start from the current name")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "Mummo")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.staticTexts["Nimi ei nyt vaihtunut. Yritä uudelleen, kun verkkoyhteys toimii."]
                .waitForExistence(timeout: 10),
            "a failed change was not said"
        )
        XCTAssertTrue(field.exists, "the sheet closed over a failure")
    }
}
