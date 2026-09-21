import XCTest

/// Browsing the family's places on a map, which is a third way to the same
/// card.
///
/// The map is the screen ARCHITECTURE §18 said did not exist on purpose until
/// 21 Sep 2026, and the only claim it makes is that a chip on it opens the
/// place's card — the card the Paikat list already opens, with the card's own
/// map on it. A map that drew the places and led nowhere would look exactly
/// like this one, which is why the test does not stop at the chips.
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
}
