import XCTest

/// Where a name the extraction heard goes while nobody has checked it.
///
/// Until 12 Sep 2026 it went onto the family's lists at once: an orange
/// "Ehdotus" row among the people, a place card among the places, and a card
/// the front screen could offer. Now it waits inside the telling that heard
/// it and behind one quiet row at the bottom of the people list, with the
/// sentence it was heard in, until a person says it is somebody — or is not.
final class HeardNamesTests: XCTestCase {
    /// The canned telling names Aino and Toivo, whom the empty archive has
    /// never heard of.
    func testHeardNamesWaitBehindOneRow() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        app.tabBars.buttons["Ihmiset"].tap()
        let door = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "odottaa tarkistusta")).firstMatch
        XCTAssertTrue(door.waitForExistence(timeout: 10), "the names heard have no door")
        XCTAssertFalse(app.staticTexts["Aino"].exists, "an unchecked name is on the family's list")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "ehdotus")).firstMatch.exists,
            "the list still calls a name a proposal"
        )

        door.tap()
        XCTAssertTrue(app.staticTexts["Aino"].waitForExistence(timeout: 10), "never arrived: the names heard")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Aino oli siinä")).firstMatch.exists,
            "a name is listed without the sentence it was heard in"
        )

        // One answer, and the name joins the family; the door counts down.
        app.buttons["Vahvista Toivo"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Toivo"].waitForExistence(timeout: 10), "a confirmed name did not join the list")
        XCTAssertTrue(
            app.staticTexts["1 nimi odottaa tarkistusta"].waitForExistence(timeout: 10),
            "the door did not count down"
        )
    }

    /// The same telling names a place, and a place nobody has checked is not
    /// a card among the family's places.
    func testAnUncheckedPlaceIsNotAmongThePlaces() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        app.tabBars.buttons["Albumi"].tap()
        XCTAssertTrue(app.staticTexts["Kerrotut hetket"].waitForExistence(timeout: 10), "never arrived: the gallery")
        XCTAssertFalse(app.staticTexts["Paikat"].exists, "a place nobody has checked became a card")
    }

    /// A proposal ignored at the result is answered on the telling itself,
    /// where the sentence is — not nowhere. And each name there is the way to
    /// its own card, where a misheard one is corrected.
    func testATellingAnswersItsOwnHeardNames() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        app.tabBars.buttons["Albumi"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery")
        row.tap()

        let heard = app.staticTexts["Kuulin nämä"]
        for _ in 0 ..< 4 where !heard.exists { app.swipeUp() }
        XCTAssertTrue(heard.waitForExistence(timeout: 10), "the telling does not carry the names it heard")

        // Each name opens its own card, and nothing else on the telling
        // opens one. As links the names took the telling's whole row: a tap
        // on Aino, or on the story's words, pushed all three cards the
        // telling heard, Toivo's on top (28 Sep 2026).
        let telling = app.navigationBars.firstMatch.identifier
        let words = app.staticTexts.matching(identifier: "memory.body").firstMatch
        if !words.isHittable { app.swipeDown() }
        words.tap()
        XCTAssertFalse(app.navigationBars["Toivo"].waitForExistence(timeout: 2), "a tap on the telling's words opened a card")
        XCTAssertEqual(app.navigationBars.firstMatch.identifier, telling, "a tap on the telling's words left it")
        // Dragged up to the middle, clear of the tab bar, which lies over the
        // foot of the list without making what is under it any less hittable.
        let aino = app.staticTexts["Aino"]
        for _ in 0 ..< 4 where !(aino.exists && aino.isHittable) { app.swipeUp() }
        if aino.frame.midY > 560 {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 20, dy: aino.frame.midY)).press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: 20, dy: 320)),
                withVelocity: .slow,
                thenHoldForDuration: 0.5
            )
        }
        // At the row's middle and not on the word: the gap between the name
        // and its chevron, which a plain button leaves dead unless it is
        // given a shape.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: aino.frame.midY))
            .tap()
        XCTAssertTrue(app.navigationBars["Aino"].waitForExistence(timeout: 10), "the name did not open its own card")
        app.navigationBars["Aino"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars[telling].waitForExistence(timeout: 10), "one step back from the name is not the telling")

        let confirm = app.buttons["Vahvista Aino"]
        for _ in 0 ..< 4 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no way to answer a name from the telling")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10), "a confirmed name is still waiting on the telling")

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(app.staticTexts["Aino"].waitForExistence(timeout: 10), "a name confirmed from the telling did not join the list")
    }
}
