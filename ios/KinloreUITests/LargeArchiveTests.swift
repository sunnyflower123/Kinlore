import XCTest

/// The app at the size of a family's archive a year or two in: `-seed large`
/// (`LargeArchiveFixture`), a hundred and fifty photographs, sixty people,
/// twenty-five places and some two hundred and fifty tellings.
///
/// Every other test runs on an archive of a handful of cards, where nothing
/// that depends on size can go wrong. This one opens the four screens such an
/// archive fills, and prints how long each took to arrive, so that a run is
/// also a rough measurement. A smoke test and no more: it asks that each
/// screen opens and carries the archive, not how any of them looks.
final class LargeArchiveTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheAlbumMapPeopleAndTreeOpenOnALargeArchive() {
        var clock = Date()
        func lap(_ what: String) {
            print("[large] \(what): \(String(format: "%.1f", Date().timeIntervalSince(clock))) s")
            clock = Date()
        }

        // The first launch on a simulator draws the photographs before the
        // first screen, about a second of it; a later launch finds them
        // drawn. The long timeout is for a busy machine.
        let app = launch(["-seed", "large", "-tab", "memories"])
        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 180), "the album never arrived")
        lap("launch to the album")

        // The oldest decade opens the photographs, with the archive's oldest
        // photograph in it.
        let oldest = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Aapo valokuvaamossa")).firstMatch
        for _ in 0 ..< 4 where !oldest.exists { app.swipeUp() }
        XCTAssertTrue(oldest.waitForExistence(timeout: 10), "the oldest photograph is not at the top of the album")
        XCTAssertTrue(app.staticTexts["1900-luku"].exists, "the album's first decade has no heading")
        lap("to the first photograph")

        // Down through the decades, which is where a hundred and fifty
        // photographs are felt. Every decade's heading is on the screen's
        // list from the start and only the tiles are built as they come, so
        // the heading is followed up to the middle of the screen rather than
        // looked for.
        let fifties = app.staticTexts["1950-luku"]
        XCTAssertTrue(fifties.waitForExistence(timeout: 10), "the album has no fifties")
        let middle = app.windows.firstMatch.frame.midY
        for _ in 0 ..< 30 where fifties.frame.minY > middle { app.swipeUp() }
        XCTAssertLessThanOrEqual(fifties.frame.minY, middle, "scrolling never reached the fifties")
        lap("scrolled to the fifties")

        // The map of places, from the album's bar, and back.
        let map = app.navigationBars["Albumi"].buttons["Kartta"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "the album's bar offers no map")
        map.tap()
        XCTAssertTrue(app.navigationBars["Kartta"].waitForExistence(timeout: 20), "the map of places never arrived")
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "Puumala is not on the map")
        lap("the map")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "the map did not lead back to the album")

        // The search reads every telling and every name: Puumala is a word
        // in a few tellings, inflected, and in the names of two places and
        // a photograph.
        let magnifier = app.navigationBars.buttons["Etsi"]
        XCTAssertTrue(magnifier.waitForExistence(timeout: 10), "the album offers no search")
        magnifier.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the search field")
        field.tap()
        field.typeText("Puumala")
        clock = Date()
        let found = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Puumala")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 20), "the search found nothing about Puumala")
        lap("search for Puumala")
        // Closed again, because its keyboard stands over the tab bar.
        app.navigationBars["Albumi"].buttons["Sulje"].tap()
        XCTAssertTrue(magnifier.waitForExistence(timeout: 10), "the search did not close")

        // The people, as a list: sixty names from Aapo on, and the door to
        // the five names the tellings raised and nobody has confirmed.
        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(app.staticTexts["Aapo"].waitForExistence(timeout: 20), "the people list never arrived")
        lap("the people list")
        let heard = app.staticTexts["5 nimeä odottaa tarkistusta"]
        for _ in 0 ..< 30 where !heard.exists { app.swipeUp() }
        XCTAssertTrue(heard.waitForExistence(timeout: 10), "the heard names are not at the foot of the list")
        lap("scrolled to the heard names")

        // And the tree, which the list's launch argument holds off: a
        // second launch, over the photographs the first one drew.
        app.terminate()
        clock = Date()
        let tree = launch(["-seed", "large", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(tree.buttons["Elina, sinä"].waitForExistence(timeout: 60), "the tree never arrived at Elina's card")
        lap("second launch to the tree")
    }
}
