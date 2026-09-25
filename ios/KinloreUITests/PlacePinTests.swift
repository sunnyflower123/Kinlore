import XCTest

/// Putting a place's point where the place actually is, on the family's map.
///
/// The lookup answers at the scale of a municipality for almost every name
/// somebody says out loud — sixteen farm and hamlet names came back as sixteen
/// towns and not one pin (ARCHITECTURE §18) — so the circle on a place card is
/// usually the best a gazetteer can do and never the best the family can do.
/// The family's map is where somebody who has stood in the yard says where it
/// is: "Muuta sijaintia" turns the panel under the map into the editor, and a
/// tap on the map puts the mark where the finger was.
///
/// Every way of getting this wrong is silent. Looking around a place and
/// moving it with the look — the founder's report of 25 Sep 2026 about the
/// screen this replaced — leaves a point nobody chose. A save that never
/// reaches the archive leaves a card that looks exactly as it did. And a save
/// that fires without anybody tapping rounds fourteen kilometres of parish
/// into a pin on the municipal centre — rule 5 broken by a button press, and
/// drawn as a point somebody is entitled to believe.
final class PlacePinTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Looking is not editing. The map a place card opens pans like any map,
    /// and what proves nothing moved is the archive afterwards: the panel
    /// still says where the circle came from, and the card still speaks as
    /// a circle.
    func testLookingAroundMovesNothing() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumalasMap(in: app)

        let map = app.otherElements["Kartta. Jokainen paikka on nappi, joka avaa paikan kortin."]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "never arrived: the family's map")
        drag(map)

        XCTAssertTrue(
            app.staticTexts["Suunnilleen tällä seudulla. Haettu paikan nimellä."].exists,
            "looking around the place changed what the archive says about it"
        )
        app.navigationBars["Kartta"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Suunnilleen tällä seudulla kartalla"].waitForExistence(timeout: 10),
            "looking around the place moved it"
        )
    }

    /// Opening the editor is not an answer, and neither is dragging the map
    /// inside it: until somebody taps there is nothing to save, and the button
    /// says so by being inactive. A tap makes it an answer, and "Peruuta"
    /// throws that answer away without storing it.
    func testNothingIsSavedUntilSomebodyTaps() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumalasMap(in: app)
        startChanging(in: app)

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "never arrived: the editor's panel")
        XCTAssertFalse(save.isEnabled, "the untouched map offered to save a point nobody had placed")

        // Given the time a tap needs to arrive (`tapTheMap`), so that a drag
        // taken for a tap would be caught rather than read too early.
        drag(editableMap(in: app))
        XCTAssertFalse(
            save.wait(for: \.isEnabled, toEqual: true, timeout: 3),
            "dragging the map was taken for an answer"
        )

        tapTheMap(in: app)
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "a tap on the map left nothing to save")

        app.buttons["Peruuta"].tap()
        XCTAssertTrue(
            app.staticTexts["Suunnilleen tällä seudulla. Haettu paikan nimellä."].waitForExistence(timeout: 10),
            "\"Peruuta\" stored the tap, or did not give the map back"
        )
        XCTAssertTrue(app.buttons["Muuta sijaintia"].exists, "the editor outlived \"Peruuta\"")
    }

    /// And a tap is an answer. The mark goes where the finger was, and what
    /// proves it arrived is the archive speaking differently: the panel names
    /// the person whose word the point now is, and the card's own map speaks
    /// as a pin instead of a circle.
    func testATapPlacesThePointExactly() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumalasMap(in: app)
        startChanging(in: app)

        tapTheMap(in: app)
        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "a tap on the map left nothing to save")
        save.tap()

        // The seeded archive's author is the default, *"Minä"*, which is the
        // colours' caption on this phone too.
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

    /// "Around here" is an answer of its own: the tap says where the middle
    /// is and the row says how sure, so the archive stores a circle under the
    /// person's word and not a pin.
    func testAroundHereStoresACircle() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumalasMap(in: app)
        startChanging(in: app)

        tapTheMap(in: app)
        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "a tap on the map left nothing to save")
        let around = app.buttons["Suunnilleen tällä seudulla"]
        XCTAssertTrue(around.waitForExistence(timeout: 10), "the editor offers no way to say \"around here\"")
        around.tap()
        save.tap()

        XCTAssertTrue(
            app.staticTexts["Suunnilleen tällä seudulla. Vahvisti Minä."].waitForExistence(timeout: 10),
            "\"around here\" did not reach the archive as a circle under somebody's word"
        )
    }

    /// Taking the point off the map asks first, and says what stays: the
    /// place and its memories. What proves the removal is the map counting
    /// the place among those it cannot draw, and the card offering to put it
    /// on the map again.
    func testRemovingTakesThePlaceOffTheMap() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumalasMap(in: app)
        startChanging(in: app)

        app.buttons["Poista sijainti"].tap()
        XCTAssertTrue(
            app.staticTexts["Poistetaanko sijainti kartalta? Puumala ja sen muistot säilyvät."]
                .waitForExistence(timeout: 10),
            "the removal did not ask first, or did not say what stays"
        )
        app.buttons["Poista sijainti"].tap()

        XCTAssertTrue(
            app.buttons["1 paikka ei vielä kartalla"].waitForExistence(timeout: 10),
            "the removed place is not among the places the map cannot draw"
        )
        app.navigationBars["Kartta"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Merkitse kartalle"].waitForExistence(timeout: 10),
            "the card of a place taken off the map offers no way back onto it"
        )
    }

    /// "Sijainti on oikein": the gazetteer's circle vouched for as it stands.
    /// Nothing moves, and the panel names the person whose word it now is,
    /// which is what keeps a later lookup or a corrected name from taking it
    /// away (§18). A point with a word on it has nothing left to vouch for.
    func testTheLocationIsRight() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumalasMap(in: app)

        let right = app.buttons["Sijainti on oikein"]
        XCTAssertTrue(right.waitForExistence(timeout: 10), "a looked-up point cannot be vouched for")
        right.tap()

        XCTAssertTrue(
            app.staticTexts["Suunnilleen tällä seudulla. Vahvisti Minä."].waitForExistence(timeout: 10),
            "the vouched-for point did not reach the archive as somebody's word"
        )
        XCTAssertFalse(right.exists, "a point somebody vouched for still asks to be vouched for")
    }

    /// The map in the editor, which is one element with one sentence: a tap
    /// anywhere on it is the control.
    private func editableMap(in app: XCUIApplication) -> XCUIElement {
        let map = app.otherElements["Kartta. Napautus merkitsee kohdan."]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "never arrived: the map a tap marks")
        return map
    }

    /// A tap well inside the map and away from its middle, where the place
    /// the editor opened on is drawn: a tap that moved nothing would pass the
    /// five-metre rule no better than no tap at all.
    ///
    /// What the tap changes is waited for, never read at once. The panel
    /// answers a moment after XCUITest calls the tap done — a single tap on
    /// a map is only a tap once a second one has failed to follow, because a
    /// double tap zooms. Measured 25 Sep 2026, when every test that read the
    /// panel or pressed "Tallenna" straight after the tap failed, and the one
    /// that chose a row first passed.
    private func tapTheMap(in app: XCUIApplication) {
        editableMap(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
    }

    /// A drag across the upper part of the map rather than a swipe from an
    /// edge: an edge gesture is the system's, and the panel covers the
    /// lower part of the screen.
    private func drag(_ map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(
                forDuration: 0.1,
                thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            )
    }

    /// The card's map, which opens the family's map on the place. VoiceOver
    /// finds it by its own label and the hint beside it, which is what this
    /// finds it by — and it is tapped where a finger would tap it, for the
    /// reason `PlacesMapTests.tapTheMap(on:)` gives.
    private func openPuumalasMap(in app: XCUIApplication) {
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala"))
            .firstMatch
        for _ in 0 ..< 4 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "never arrived: the place's row in Albumi")
        row.tap()

        let map = app.buttons
            .matching(NSPredicate(format: "label ENDSWITH %@", "kartalla"))
            .firstMatch
        for _ in 0 ..< 4 where !map.exists { app.swipeUp() }
        XCTAssertTrue(map.waitForExistence(timeout: 10), "the place card offers no way to its map")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            app.navigationBars["Kartta"].waitForExistence(timeout: 10),
            "the card's map did not open the family's map"
        )
    }

    /// "Muuta sijaintia", which turns the panel into the editor on the same
    /// map. Two taps from the card since 25 Sep 2026, because looking is not
    /// editing.
    private func startChanging(in app: XCUIApplication) {
        let change = app.buttons["Muuta sijaintia"]
        XCTAssertTrue(change.waitForExistence(timeout: 10), "the family's map offers no way to move the point")
        change.tap()
    }
}
