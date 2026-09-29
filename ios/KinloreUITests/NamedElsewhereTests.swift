import XCTest

/// A person's card lists the way to each card whose tellings name her, beside
/// her own tellings — and the telling itself is read on the card it is filed
/// under.
///
/// Until 27 Sep 2026 the card listed them only while nothing was filed under
/// it, so the first telling of her own hid every photograph's that named her.
/// Until 30 Sep 2026 each was listed whole under its way, so a person named in
/// several was a long scroll. `-seed mentioned` is that card: Aino confirmed,
/// one telling about her, and the photograph's telling that names her.
final class NamedElsewhereTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testATellingOfHerOwnDoesNotHideWhereSheIsNamed() {
        let app = launch(["-seed", "mentioned", "-tab", "people", "-screen", "person", "-person", "demo-aino"])

        let own = app.staticTexts["Aino opetti minut uimaan."]
        reach(own, in: app, "her own telling")
        let home = app.buttons["card.namedElsewhere"]
        reach(home, in: app, "the way to the photograph that names her, beside her own telling")
        XCTAssertTrue(
            app.staticTexts["Mainittu muualla yhdessä muistossa"].exists,
            "the photograph's telling is not headed as filed elsewhere"
        )
        // The way and not the words: the telling is read where it is filed.
        let named = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Aino tuli mökille"))
            .firstMatch
        XCTAssertFalse(named.exists, "the photograph's telling is listed whole on her card")
        // Once: her own telling names her too, and it is not listed again
        // among the ones filed elsewhere.
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "Aino opetti minut uimaan.")).count, 1,
            "her own telling is listed twice"
        )

        XCTAssertEqual(home.label, "Valokuva", "the way does not name the card it opens")
        home.tap()
        XCTAssertTrue(
            app.navigationBars["Valokuva"].waitForExistence(timeout: 10),
            "the way did not open the photograph's card"
        )
        reach(named, in: app, "the whole telling, on the photograph's card")
        // On the same stack: back is her card, not the list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Aino"].waitForExistence(timeout: 10),
            "the photograph's card was not opened over hers"
        )
    }

    /// One way for each card, however many of its tellings name him, and the
    /// heading still counts the tellings (30 Sep 2026). `-seed film-family`'s
    /// Toivo is named in two tellings of the jetty photograph and in one of
    /// the second print, and has none of his own.
    func testOneWayForEachCardThatNamesHim() {
        let app = launch(["-seed", "film-family", "-tab", "people", "-screen", "person", "-person", "demo-film-toivo"])

        reach(app.staticTexts["Mainittu muualla 3 muistossa"], in: app, "the heading over the tellings that name him")
        let ways = app.buttons.matching(identifier: "card.namedElsewhere")
        reach(ways.element(boundBy: 1), in: app, "the way to the second card")
        XCTAssertEqual(ways.count, 2, "not one way for each card that names him")
    }

    /// Scrolls until the element is there, and then insists that it is. At
    /// the largest text size a list does not build the rows nobody can see.
    private func reach(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        for _ in 0 ..< 6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "never arrived: \(what)")
    }
}
