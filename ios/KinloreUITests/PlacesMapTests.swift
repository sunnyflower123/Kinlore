import XCTest

/// Browsing the family's places on a map, which is a third way to the same
/// card.
///
/// The map is the screen ARCHITECTURE §18 said did not exist on purpose until
/// 21 Sep 2026. Its first claim is that a chip on it opens the place's card —
/// the card the Paikat list already opens, with the card's own map on it. A
/// map that drew the places and led nowhere would look exactly like this one,
/// which is why the test does not stop at the chips. Its other claims arrived
/// on 25 Sep 2026 with its doors: the album's bar, a place card's own map on
/// either tab, and an album with nothing on it yet.
final class PlacesMapTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// From the album's Paikat section to the map, and from Puumala's chip to
    /// Puumala's card. The card's map is what proves arrival, by the circle's
    /// wording and not the pin's: Puumala is a municipality, so rule 5 says
    /// the card draws an area, and a pin's label here would mean the
    /// precision had been rounded somewhere on the way.
    func testChipOpensThePlaceCard() {
        let app = launch(["-seed", "archive", "-tab", "memories"])

        let button = app.buttons["Näytä kartalla"]
        for _ in 0 ..< 8 where !button.exists { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the album offers no map")
        button.tap()

        XCTAssertTrue(
            app.navigationBars["Kartta"].waitForExistence(timeout: 10),
            "the map of places never arrived"
        )
        let chip = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala"))
            .firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Puumala is not on the map")
        chip.tap()

        XCTAssertTrue(
            app.buttons["Suunnilleen tällä seudulla kartalla"].waitForExistence(timeout: 10),
            "the chip did not open the place card, or opened one without its map"
        )
    }

    /// The door in the album's bar, which is there whether or not the album
    /// has a Paikat section to scroll to: the first thing on the screen, not
    /// the last.
    func testTheBarOpensTheMap() {
        let app = launch(["-seed", "archive", "-tab", "memories"])

        let button = app.buttons["Kartta"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the album's bar offers no map")
        button.tap()

        XCTAssertTrue(
            app.navigationBars["Kartta"].waitForExistence(timeout: 10),
            "the map of places never arrived"
        )
        XCTAssertTrue(chip("Puumala", in: app).waitForExistence(timeout: 10), "Puumala is not on the map")
    }

    /// A place card's own map opens the family's map on that place, and the
    /// panel under it is about that place: its name, how sure the archive is
    /// of the point, and the two ways on. Puumala's own chip is left off —
    /// the panel names it, and the chip would lead back to the card just
    /// left — and "Näytä kaikki paikat" gives the map back to every place,
    /// which is when the chip returns. Both halves are checked, because a
    /// chip that was never drawn at all would pass the first one alone.
    func testTheCardOpensTheMapOnItsPlace() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPuumala(in: app)

        let cardMap = app.buttons["Suunnilleen tällä seudulla kartalla"]
        XCTAssertTrue(cardMap.waitForExistence(timeout: 10), "the place card has no map")
        tapTheMap(on: cardMap)

        XCTAssertTrue(
            app.staticTexts["Suunnilleen tällä seudulla. Haettu paikan nimellä."]
                .waitForExistence(timeout: 10),
            "the map did not open on the place, or its panel does not say how sure the point is"
        )
        XCTAssertTrue(app.buttons["Muuta sijaintia"].exists, "the panel offers no way to move the point")
        XCTAssertFalse(
            chip("Puumala", in: app).exists,
            "the place the map was opened on carries a chip back to its own card"
        )

        app.buttons["Näytä kaikki paikat"].tap()
        XCTAssertTrue(
            chip("Puumala", in: app).waitForExistence(timeout: 10),
            "letting go of the place did not give its chip back"
        )
        XCTAssertFalse(app.buttons["Muuta sijaintia"].exists, "the panel outlived the focus")
    }

    /// The same door from the people tab, where a place card opens too — and
    /// where the map is a destination of its own stack. A link to a value no
    /// destination is registered for does nothing at all, which from the
    /// outside looks exactly like a tap that missed.
    func testThePeopleTabOpensTheMap() {
        let app = launch([
            "-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-puumala",
        ])

        let cardMap = app.buttons["Suunnilleen tällä seudulla kartalla"]
        for _ in 0 ..< 4 where !cardMap.exists { app.swipeUp() }
        XCTAssertTrue(cardMap.waitForExistence(timeout: 10), "Puumala's card never arrived on the people tab")
        tapTheMap(on: cardMap)

        XCTAssertTrue(
            app.navigationBars["Kartta"].waitForExistence(timeout: 10),
            "the people tab's stack has no way to the map"
        )
        XCTAssertTrue(app.buttons["Muuta sijaintia"].exists, "the map did not open on the place")
    }

    /// A family that has told about no place yet still has the door, and the
    /// map behind it says what will come rather than showing an empty sea.
    func testAnEmptyArchiveStillHasAMap() {
        let app = launch(["-seed", "empty", "-tab", "memories"])

        let button = app.buttons["Kartta"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the empty album's bar offers no map")
        button.tap()

        XCTAssertTrue(
            app.staticTexts["Kun kerrotte paikoista, ne tulevat tähän kartalle."]
                .waitForExistence(timeout: 10),
            "the empty map does not say what it is for"
        )
    }

    /// A confirmed place with nothing to draw — a farm the gazetteer did not
    /// know, which is most of them (§18) — says "Merkitse kartalle" where its
    /// map would be, and that opens the family's map already placing it.
    /// "Peruuta" comes straight back to the card, which is where the change
    /// began; a tap and "Tallenna" leave a card with a map on it.
    func testTheCardMarksAPlaceWithNoPoint() {
        let app = launch(["-seed", "unplaced", "-tab", "memories"])
        open("Koivula", in: app)

        let mark = app.buttons["Merkitse kartalle"]
        for _ in 0 ..< 4 where !mark.exists { app.swipeUp() }
        XCTAssertTrue(mark.waitForExistence(timeout: 10), "a place with no point offers no way onto the map")
        mark.tap()
        XCTAssertTrue(
            app.staticTexts["Napauta karttaa kohtaan, jossa Koivula on."].waitForExistence(timeout: 10),
            "the map did not open placing the place"
        )

        app.buttons["Peruuta"].tap()
        XCTAssertTrue(mark.waitForExistence(timeout: 10), "\"Peruuta\" did not come back to the card")

        mark.tap()
        tapTheEditableMap(in: app)
        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "the tap on the map left nothing to save")
        save.tap()
        XCTAssertTrue(
            app.staticTexts["Tarkka kohta. Vahvisti Minä."].waitForExistence(timeout: 10),
            "the point never reached the archive as somebody's word"
        )
        app.navigationBars["Kartta"].buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Tarkka sijainti kartalla"].waitForExistence(timeout: 10),
            "the card of the placed place draws no map"
        )
    }

    /// The map counts the places it cannot draw, and the count is a door: a
    /// sheet of those places, where a row starts placing its place on the
    /// map under the sheet. Once placed, the place has a chip like any other
    /// and the count has nothing left to count.
    func testTheMapListsThePlacesItCannotDraw() {
        let app = launch(["-seed", "unplaced", "-tab", "memories", "-screen", "placesMap"])

        let count = app.buttons["1 paikka ei vielä kartalla"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), "the map does not say what it cannot draw")
        count.tap()
        XCTAssertTrue(
            app.navigationBars["Ei vielä kartalla"].waitForExistence(timeout: 10),
            "the count did not open the places it counts"
        )
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Koivula"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Koivula is not among the places the map cannot draw")
        row.tap()
        XCTAssertTrue(
            app.staticTexts["Napauta karttaa kohtaan, jossa Koivula on."].waitForExistence(timeout: 10),
            "choosing the place did not start placing it"
        )

        tapTheEditableMap(in: app)
        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 10), "the tap on the map left nothing to save")
        save.tap()
        XCTAssertTrue(
            app.staticTexts["Tarkka kohta. Vahvisti Minä."].waitForExistence(timeout: 10),
            "the point never reached the archive as somebody's word"
        )
        app.buttons["Näytä kaikki paikat"].tap()
        XCTAssertTrue(chip("Koivula", in: app).waitForExistence(timeout: 10), "the placed place has no chip")
        XCTAssertFalse(count.exists, "the map still counts a place it now draws")
    }

    /// A place's chip: a button inside the map whose label starts with the
    /// place's name. Inside the map, because the back button to a place card
    /// is called by the card's title as well.
    private func chip(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.otherElements["Kartta. Jokainen paikka on nappi, joka avaa paikan kortin."]
            .buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", name))
            .firstMatch
    }

    /// A place card's map, tapped where a finger would tap it rather than
    /// where XCUITest judges it hittable. MapKit hands its own elements — the
    /// names printed on the map — to the accessibility tree some time after
    /// the tiles, and until then the hit test at the card's centre falls
    /// through to the list section behind it. Measured 25 Sep 2026: the
    /// people tab's card was "not hittable" four runs in four with a `Map`
    /// that had no children yet, while the album's, with Puumala's own label
    /// under the centre, tapped every time. A finger is not an accessibility
    /// hit test, and the link answers a finger either way.
    private func tapTheMap(on card: XCUIElement) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The map while a place is being placed, tapped well inside it and away
    /// from its middle. One element with one sentence: a tap anywhere on it
    /// is the control. What the tap changes is waited for, for the reason
    /// `PlacePinTests.tapTheMap(in:)` gives.
    private func tapTheEditableMap(in app: XCUIApplication) {
        let map = app.otherElements["Kartta. Napautus merkitsee kohdan."]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "never arrived: the map a tap marks")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
    }

    /// The demo archive's confirmed place, opened from Albumi.
    private func openPuumala(in app: XCUIApplication) {
        open("Puumala", in: app)
    }

    /// A place, opened from Albumi by its row.
    private func open(_ name: String, in app: XCUIApplication) {
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", name))
            .firstMatch
        for _ in 0 ..< 4 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "never arrived: the place's row in Albumi")
        row.tap()
    }
}
