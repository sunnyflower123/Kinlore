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
///
/// And one photograph, since 30 Sep 2026, which is opened on its card rather
/// than left somewhere in the grid: chosen from the phone (`-library stub`,
/// one generated picture in place of the picker) or taken with the camera
/// (`-camera stub`, whose shutter saves the same picture). Two taken stay in
/// the album.
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
                app.navigationBars["Albumi"].waitForExistence(timeout: 10),
                "did not get back to the gallery"
            )
        }
    }

    /// One photograph chosen from the phone is the one somebody is about to
    /// tell about: its card opens, on the album's stack, and the pile's
    /// question is not asked of it.
    func testOnePhotoChosenFromThePhoneOpensItsCard() {
        let app = launch(["-seed", "archive", "-tab", "memories", "-library", "stub"])

        let add = app.buttons["Lisää kuvia"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "never arrived: the way to add photographs")
        add.tap()
        let choose = app.buttons["Valitse kuvista"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "never arrived: the row that picks from the phone")
        choose.tap()

        XCTAssertTrue(
            app.navigationBars["Valokuva"].waitForExistence(timeout: 10),
            "one photograph chosen did not open its card"
        )
        XCTAssertTrue(
            app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10),
            "the card that opened is not the photograph's"
        )
        XCTAssertFalse(
            app.staticTexts["Milloin nämä olivat?"].exists,
            "one photograph was asked the question meant for a pile"
        )
        // Back is the album: the card was pushed onto its stack.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Albumi"].waitForExistence(timeout: 10),
            "the card was not opened over the album"
        )
    }

    /// One photograph taken opens its card once the camera has closed.
    func testOnePhotographTakenOpensItsCardWhenTheCameraCloses() {
        let app = launch(["-seed", "empty", "-tab", "memories", "-camera", "stub"])

        photograph(1, in: app)

        XCTAssertTrue(
            app.navigationBars["Valokuva"].waitForExistence(timeout: 10),
            "one photograph taken did not open its card when the camera closed"
        )
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Albumi"].waitForExistence(timeout: 10),
            "the card was not opened over the album"
        )
    }

    /// Two taken stay in the album. The camera is for the sitting of thirty,
    /// and thirty cards opened one on another would be thirty ways back.
    func testTwoPhotographsTakenStayInTheAlbum() {
        let app = launch(["-seed", "empty", "-tab", "memories", "-camera", "stub"])

        photograph(2, in: app)

        XCTAssertTrue(
            app.navigationBars["Albumi"].waitForExistence(timeout: 10),
            "the camera did not close onto the album"
        )
        XCTAssertFalse(
            app.navigationBars["Valokuva"].waitForExistence(timeout: 3),
            "two photographs taken opened a card"
        )
        let tiles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva"))
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "never arrived: the photographs taken")
        XCTAssertEqual(tiles.count, 2, "the camera did not save two photographs")
    }

    /// Opens the camera from the empty album, presses the shutter `count`
    /// times, each once the last is counted, and closes it.
    private func photograph(_ count: Int, in app: XCUIApplication) {
        let camera = app.buttons["Kuvaa vanha valokuva"]
        XCTAssertTrue(camera.waitForExistence(timeout: 10), "never arrived: the way to the camera")
        camera.tap()
        let shutter = app.buttons["Kuvaa"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10), "never arrived: the shutter")
        for shot in 1 ... count {
            shutter.tap()
            let counted = shot == 1 ? "Kuvattu 1 kuva" : "Kuvattu \(shot) kuvaa"
            XCTAssertTrue(app.staticTexts[counted].waitForExistence(timeout: 10), "shot \(shot) was not saved")
        }
        app.buttons["Valmis"].tap()
    }
}
