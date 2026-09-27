import XCTest

/// A person's card lists the tellings that name her and are filed under
/// something else, beside her own — and each opens the card it is filed under.
///
/// Until 27 Sep 2026 the card listed them only while nothing was filed under
/// it, so the first telling of her own hid every photograph's that named her.
/// `-seed mentioned` is that card: Aino confirmed, one telling about her, and
/// the photograph's telling that names her.
final class NamedElsewhereTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testATellingOfHerOwnDoesNotHideWhereSheIsNamed() {
        let app = launch(["-seed", "mentioned", "-tab", "people", "-screen", "person", "-person", "demo-aino"])

        let own = app.staticTexts["Aino opetti minut uimaan."]
        reach(own, in: app, "her own telling")
        let named = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Aino tuli mökille"))
            .firstMatch
        reach(named, in: app, "the photograph's telling that names her, beside her own")
        XCTAssertTrue(
            app.staticTexts["Mainittu muualla yhdessä muistossa"].exists,
            "the photograph's telling is not headed as filed elsewhere"
        )
        // Once: her own telling names her too, and it is not listed again
        // among the ones filed elsewhere.
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "Aino opetti minut uimaan.")).count, 1,
            "her own telling is listed twice"
        )

        // Above the telling it leads from, so the swipes that reached the
        // telling may have carried it past the top.
        let home = app.buttons["card.namedElsewhere"]
        XCTAssertTrue(home.waitForExistence(timeout: 5), "never arrived: the way to the photograph the telling is filed under")
        if !home.isHittable { app.swipeDown() }
        XCTAssertEqual(home.label, "Valokuva", "the way does not name the card it opens")
        home.tap()
        XCTAssertTrue(
            app.navigationBars["Valokuva"].waitForExistence(timeout: 10),
            "the way did not open the photograph's card"
        )
        // On the same stack: back is her card, not the list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Aino"].waitForExistence(timeout: 10),
            "the photograph's card was not opened over hers"
        )
    }

    /// Scrolls until the element is there, and then insists that it is. At
    /// the largest text size a list does not build the rows nobody can see.
    private func reach(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        for _ in 0 ..< 6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "never arrived: \(what)")
    }
}
