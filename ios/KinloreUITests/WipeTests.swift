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

    /// The sentence every branch of the warning now ends on, asserted rather
    /// than merely written: *"Sovellus avautuu ensimmäiselle näytölle."*
    ///
    /// A local archive is the one wipe that completes without a server —
    /// `canLeave` is false and the mode is not `.inFamily`, so nothing is asked
    /// of a Worker that is not there. That makes this the only path on which a
    /// *successful* wipe can be walked end to end, and the test above covers
    /// only the refusal. The promise the label was renamed for had no test at
    /// all until this one.
    ///
    /// What it pins is the landing, not the emptying: `renewIdentity` clears
    /// `local_only` and `family_id` and then re-decides the mode by the same
    /// two-branch rule a fresh install uses, so the way this can break is a
    /// third branch appearing on one side and not the other.
    func testAWipeLandsOnTheFirstScreen() {
        let app = launch(
            ["-seed", "archive", "-local_only", "YES", "-tab", "people", "-screen", "settings"],
            api: "http://127.0.0.1:9"
        )

        let wipe = app.buttons["Tyhjennä ja aloita alusta"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 10), "never arrived: Settings")
        wipe.tap()

        let confirm = app.buttons["Tyhjennä"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the wipe asked nothing first")
        confirm.tap()

        // The onboarding fork, which is what a fresh install meets.
        XCTAssertTrue(
            app.buttons["Aloita perheen arkisto"].waitForExistence(timeout: 15),
            "the wipe did not land on the first screen its dialog promises"
        )
        XCTAssertTrue(
            app.buttons["Liity kutsulinkillä"].exists,
            "the first screen arrived without the second of its two doors"
        )
        // And the archive went with it. The tabs belong to a device that has
        // one; an emptied device has no tab bar at all, so this is the cheapest
        // assertion that the app did not merely change screen.
        XCTAssertFalse(
            app.buttons["Kerro"].exists,
            "the app returned to onboarding with the old archive still behind it"
        )
    }
}
