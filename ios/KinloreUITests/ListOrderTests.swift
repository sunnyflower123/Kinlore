import XCTest

/// The family's people and places read by name, in the alphabet of the
/// phone's own language (27 Sep 2026). Until then both stood newest first,
/// the order the store keeps, which is the order of nobody's memory: finding
/// one aunt among forty people meant reading the list until she came.
/// *Uutta perheeltä* keeps its own order, because what is new is a different
/// question from who is in the family.
///
/// Run in Finnish like every test here, and that is the point of the
/// fixture: `-seed alphabet` has an Ä and an Ö in it, which a Finnish phone
/// puts after Z and an English one beside A and O, and a card named in lower
/// case, which is where the order a machine counts characters in parts from
/// the order a person reads in.
final class ListOrderTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The people list, the album's places, and the places the map cannot
    /// draw — the three lists of the family's own cards — each A to Ö.
    func testThePeopleAndThePlacesReadInTheAlphabet() {
        let people = ["Aino", "mummo", "Zacharias", "Örjan"]
        let places = ["Kuopio", "mökki", "Vaasa", "Ähtäri"]

        var app = launch(["-seed", "alphabet", "-tab", "people"])
        XCTAssertEqual(order(of: people) { app.staticTexts[$0] }, people, "the people list")

        app.tabBars.buttons["Albumi"].tap()
        XCTAssertEqual(order(of: places) { row(named: $0, in: app) }, places, "the album's places")

        // None of them is on the map — a seeded launch looks nothing up — so
        // the map's count of what it cannot draw is all four.
        app = launch(["-seed", "alphabet", "-tab", "memories", "-screen", "placesMap"])
        let count = app.buttons["4 paikkaa ei vielä kartalla"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), "the map does not count the places it cannot draw")
        count.tap()
        XCTAssertTrue(app.navigationBars["Ei vielä kartalla"].waitForExistence(timeout: 10), "the count did not open its places")
        XCTAssertEqual(order(of: places) { row(named: $0, in: app) }, places, "the places the map cannot draw")
    }

    /// The names in the order they stand on the screen, top first — once
    /// every one of them is there, so a missing row fails as missing and not
    /// as out of order.
    private func order(of names: [String], _ element: (String) -> XCUIElement) -> [String] {
        for name in names {
            XCTAssertTrue(element(name).waitForExistence(timeout: 10), "\(name) is not on the screen")
        }
        let tops = Dictionary(uniqueKeysWithValues: names.map { ($0, element($0).frame.minY) })
        return names.sorted { tops[$0, default: 0] < tops[$1, default: 0] }
    }

    /// A place's row, whose label starts with the place's name.
    private func row(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }
}
