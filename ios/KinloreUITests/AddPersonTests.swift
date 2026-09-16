import XCTest

/// A person typed by hand, since 13 Sep 2026 (ARCHITECTURE §8). Until then a
/// person could only come out of a telling, so nothing had ever walked these
/// paths: the button beside the gear on Ihmiset, the card it opens, and a typed
/// name the family already had.
final class AddPersonTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The row, the sheet, and the card it leads to — then back on the list.
    func testATypedNameBecomesACardOnTheList() {
        let app = launch(["-seed", "archive", "-tab", "people"])
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the people list")

        addPerson(named: "Helmi", in: app)

        XCTAssertTrue(app.navigationBars["Helmi"].waitForExistence(timeout: 10), "the new card did not open")
        app.navigationBars["Helmi"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Helmi"].waitForExistence(timeout: 10), "Helmi is not on the list")
    }

    /// The fixture's Aino is a name heard and not checked, waiting behind the
    /// door rather than on the list. Typing her name vouches for her: the same
    /// card, confirmed and on the list — and not a second Aino beside her.
    func testTypingAHeardNameConfirmsItRatherThanDoublingIt() {
        let app = launch(["-seed", "archive", "-tab", "people"])
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the people list")
        XCTAssertFalse(app.staticTexts["Aino"].exists, "the heard name was on the list before anybody vouched for her")

        addPerson(named: "Aino", in: app)

        XCTAssertTrue(app.navigationBars["Aino"].waitForExistence(timeout: 10), "her card did not open")
        app.navigationBars["Aino"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Aino"].waitForExistence(timeout: 10), "Aino is not on the list")
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "Aino")).count, 1,
            "a second Aino beside the first"
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "odottaa tarkistusta")).firstMatch.exists,
            "Aino is still waiting to be checked"
        )
    }

    /// One way in, in one place. It stood beneath the empty state as well
    /// until 16 Sep 2026, and the first person typed in took that copy away:
    /// the button somebody had just used was gone from where they had used it,
    /// and the one that was left had never been looked at. So the test is not
    /// that the button exists — it is that there is one of it and it does not
    /// move.
    ///
    /// The second half found a defect the first half had not: with the button
    /// beside the gear, the same first person moved it 90 pt to the left
    /// (x 218 → x 128), because the tree/list switch joins that group as soon
    /// as there is somebody to draw. Hence the leading corner, and hence
    /// comparing the frame rather than only counting the buttons.
    func testTheWayToAddAPersonIsInOnePlaceBeforeAndAfter() {
        let app = launch(["-seed", "empty", "-tab", "people"])
        XCTAssertTrue(app.staticTexts["Ei vielä ihmisiä"].waitForExistence(timeout: 10), "the empty Ihmiset")

        let add = app.buttons["Lisää henkilö"]
        XCTAssertTrue(add.exists, "no way to add a person on an empty Ihmiset")
        XCTAssertEqual(app.buttons.matching(identifier: "Lisää henkilö").count, 1, "two ways in, in two places")
        let before = add.frame
        XCTAssertLessThan(before.midY, app.frame.height / 4, "the way in is not at the top of the screen")

        addPerson(named: "Helmi", in: app)
        app.navigationBars["Helmi"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Helmi"].waitForExistence(timeout: 10), "Helmi is not on the list")

        XCTAssertEqual(app.buttons.matching(identifier: "Lisää henkilö").count, 1, "the family is no longer empty and there are two")
        XCTAssertEqual(add.frame, before, "the way to add a person moved once somebody was in the family")
    }

    private func addPerson(named name: String, in app: XCUIApplication) {
        let add = app.buttons["Lisää henkilö"]
        for _ in 0 ..< 4 where !add.exists { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the way to add a person")
        add.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText(name)
        app.buttons["Tallenna"].tap()
    }
}
