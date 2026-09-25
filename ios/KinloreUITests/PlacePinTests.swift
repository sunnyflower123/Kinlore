import XCTest

/// Moving a place's point to where the place actually is.
///
/// The lookup answers at the scale of a municipality for almost every name
/// somebody says out loud — sixteen farm and hamlet names came back as sixteen
/// towns and not one pin (ARCHITECTURE §18) — so the circle on a place card is
/// usually the best a gazetteer can do and never the best the family can do.
/// `PlacePinSheet` is where somebody who has stood in the yard says where it
/// is.
///
/// Both ways of getting this wrong are silent. A save that never reaches the
/// archive leaves a card that looks exactly as it did, and a save that fires
/// without anybody moving the mark rounds fourteen kilometres of parish into a
/// pin on the municipal centre — rule 5 broken by a button press, and drawn as
/// a point somebody is entitled to believe.
final class PlacePinTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Opening the map is not an answer. Until the mark has been moved there is
    /// nothing to save, and the button says so by being inactive.
    func testNothingIsSavedUntilTheMarkHasMoved() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumala(in: app)

        openTheMap(in: app)

        let save = app.buttons["Tallenna tämä paikka"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "never arrived: the map sheet")
        XCTAssertFalse(
            save.isEnabled,
            "the untouched map offered to save a point nobody had placed"
        )
    }

    /// And moving it is. The map is dragged, the save becomes an answer, and
    /// what proves it arrived is the card's own map speaking differently: a
    /// circle is *"suunnilleen tällä seudulla"* and a point is *"tarkka
    /// sijainti"*, so the label is the precision read back out of the archive.
    func testMovingTheMarkPlacesThePointExactly() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumala(in: app)

        XCTAssertTrue(
            app.buttons["Suunnilleen tällä seudulla kartalla"].waitForExistence(timeout: 10),
            "the fixture's place did not start as a circle, so this test proves nothing"
        )
        openTheMap(in: app)

        let map = app.otherElements["Kartta. Merkki pysyy keskellä ja kartta liikkuu sen alla."]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "never arrived: the map the mark sits on")
        // A drag across the middle of the map rather than a swipe from its
        // edge: an edge gesture is the system's, and what is being checked
        // here is that panning the map moves the mark with it.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(
                forDuration: 0.1,
                thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            )

        let save = app.buttons["Tallenna tämä paikka"]
        XCTAssertTrue(save.isEnabled, "the map was dragged and the save stayed inactive")
        save.tap()

        // The family's map is under the sheet, and its panel reads the
        // precision out of the archive: a circle was *"suunnilleen tällä
        // seudulla"*, and the point that replaced it is a *"tarkka kohta"* —
        // with who put it there, since 25 Sep 2026, because a placed point is
        // somebody's word. The seeded archive's author is the default,
        // *"Minä"*, which is the colours' caption on this phone too.
        XCTAssertTrue(
            app.staticTexts["Tarkka kohta. Vahvisti Minä."].waitForExistence(timeout: 10),
            "the placed point did not reach the archive as somebody's word, or did not reach the map that draws it"
        )
        // And the card under the map, which speaks the precision it holds, so
        // this is the archive answering rather than the screen remembering.
        app.navigationBars["Kartta"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Tarkka sijainti kartalla"].waitForExistence(timeout: 10),
            "the placed point did not reach the card that draws it"
        )
    }

    /// The card's map, which opens the family's map on the place, and the
    /// panel's "Muuta sijaintia", which opens the screen the point is moved
    /// on. Two taps since 25 Sep 2026, because looking is not editing: the
    /// card used to open the moving screen straight away, and every look
    /// around the place moved it. VoiceOver finds the card's map by its own
    /// label and the hint beside it, which is what this finds it by.
    private func openTheMap(in app: XCUIApplication) {
        let map = app.buttons
            .matching(NSPredicate(format: "label ENDSWITH %@", "kartalla"))
            .firstMatch
        for _ in 0 ..< 4 where !map.exists { app.swipeUp() }
        XCTAssertTrue(map.waitForExistence(timeout: 10), "the place card offers no way to its map")
        map.tap()

        let change = app.buttons["Muuta sijaintia"]
        XCTAssertTrue(change.waitForExistence(timeout: 10), "the family's map offers no way to move the point")
        change.tap()
    }

    /// The demo archive's confirmed place, opened from Albumi.
    private func openPuumala(in app: XCUIApplication) {
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala"))
            .firstMatch
        for _ in 0 ..< 4 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "never arrived: the place's row in Albumi")
        row.tap()
    }
}
