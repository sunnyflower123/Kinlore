import XCTest

/// Emptying the device, which on a single-device archive is the tap that ends
/// the archive.
///
/// The warning has always been right — it says to export first when nobody else
/// has a copy — but it said it in a dialog whose only action was the irreversible
/// one. An instruction to go and do something else is not prevention.
final class WipeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEmptyingOffersTheExportBeforeTheEmptying() {
        let app = launch(["-seed", "guess", "-tab", "people", "-screen", "settings"])

        let wipe = app.buttons["Tyhjennä tämä laite"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 10), "never arrived: Settings")
        wipe.tap()

        XCTAssertTrue(
            app.staticTexts["Tyhjennetäänkö tämä laite?"].waitForExistence(timeout: 10),
            "the device was emptied without asking"
        )
        XCTAssertTrue(
            app.buttons["Vie arkisto ensin"].exists,
            "the only offer was the irreversible one"
        )
        // Left where it was: the archive is what this test is protecting.
        XCTAssertTrue(app.buttons["Tyhjennä"].exists, "the emptying itself is still offered")
    }
}
