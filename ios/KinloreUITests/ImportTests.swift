import XCTest

/// Thirty scanned photographs, and the one thing they have in common.
///
/// A grandchild importing an album gets thirty untitled, undated cards, and the
/// app had no way to say anything about them except one at a time — which is a
/// way of saying nobody will. The import asks once, for all of them, in the same
/// three answers the single card offers.
///
/// `-import 3` stands in for the system photo picker, which a test run cannot
/// drive. What it does is exactly what a real import does at the end: hand the
/// sheet the subjects that just arrived.
final class ImportTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testOneAnswerDatesEveryPhotoTheImportBroughtIn() {
        let app = launch(["-seed", "empty", "-tab", "memories", "-import", "3"])

        XCTAssertTrue(
            app.staticTexts["Milloin nämä olivat?"].waitForExistence(timeout: 10),
            "the import asked nothing about when the photos were from"
        )

        app.buttons["Vuosikymmen"].tap()
        let fifties = app.buttons["1950-luku"]
        for _ in 0 ..< 4 where !fifties.exists { app.swipeUp() }
        XCTAssertTrue(fifties.waitForExistence(timeout: 10), "never arrived: the decade to choose")
        fifties.tap()

        // Every one of them, not merely the first. One answer for the pile is
        // the whole point — if it only reached one card the feature would be a
        // slower way of doing what the card already did.
        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "never arrived: the imported photos")
        XCTAssertEqual(tiles.count, 3, "the import did not bring in three photos")

        for index in 0 ..< 3 {
            let tile = tiles.element(boundBy: index)
            // Waited for rather than tapped at: coming back from a card leaves
            // the grid on screen a moment before it accepts a tap, and a test
            // that races that is a test that fails on a slow morning.
            wait(
                for: [expectation(
                    for: NSPredicate(format: "isHittable == true"),
                    evaluatedWith: tile
                )],
                timeout: 10
            )
            tile.tap()
            XCTAssertTrue(
                app.buttons["1950-luku"].waitForExistence(timeout: 10),
                "photo \(index + 1) did not get the date the import was given"
            )
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(
                app.navigationBars["Muistot"].waitForExistence(timeout: 10),
                "did not get back to the gallery"
            )
        }
    }
}
