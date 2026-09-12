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

        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(app.staticTexts["Kerrotut hetket"].waitForExistence(timeout: 10), "never arrived: the gallery")
        XCTAssertFalse(app.staticTexts["Paikat"].exists, "a place nobody has checked became a card")
    }

    /// A proposal ignored at the result is answered on the telling itself,
    /// where the sentence is — not nowhere.
    func testATellingAnswersItsOwnHeardNames() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        app.tabBars.buttons["Muistot"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery")
        row.tap()

        let heard = app.staticTexts["Kuulin nämä"]
        for _ in 0 ..< 4 where !heard.exists { app.swipeUp() }
        XCTAssertTrue(heard.waitForExistence(timeout: 10), "the telling does not carry the names it heard")
        let confirm = app.buttons["Vahvista Aino"]
        for _ in 0 ..< 4 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no way to answer a name from the telling")
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10), "a confirmed name is still waiting on the telling")

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(app.staticTexts["Aino"].waitForExistence(timeout: 10), "a name confirmed from the telling did not join the list")
    }
}
