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
        let app = launch(["-seed", "archive", "-tab", "people", "-screen", "settings"])

        let wipe = app.buttons["Tyhjennä ja aloita alusta"]
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

    /// A wipe that cannot leave must stop, not shrug. The result of the leave
    /// used to be discarded: a failed leave wiped the store and renewed the
    /// Keychain identity anyway, leaving a member row in the family forever
    /// with nobody able to authenticate as it — a ghost that even counted
    /// against the last-member check. The seeded family has no client, which
    /// is the same refusal the real screen meets offline.
    func testAWipeThatCannotLeaveStopsAndSaysSo() {
        let app = launch(["-seed", "family", "-tab", "people", "-screen", "settings"])

        let wipe = app.buttons["Tyhjennä ja aloita alusta"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 10), "never arrived: Settings")
        wipe.tap()

        let confirm = app.buttons["Tyhjennä"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the wipe asked nothing first")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["Perheestä ei voitu poistua"].waitForExistence(timeout: 10),
            "the failed leave said nothing"
        )
        app.buttons["Selvä"].tap()

        // And nothing was emptied: the family row is still here, which means
        // the store and the identity both survived the refusal.
        XCTAssertTrue(
            app.buttons["Perheen jäsenet ja kutsut"].waitForExistence(timeout: 10),
            "the device was wiped despite the failed leave"
        )
    }
}
