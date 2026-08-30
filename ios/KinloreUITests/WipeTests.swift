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

    /// The one answer that used to outlive the archive it was given for.
    ///
    /// `elder.largerText` is device state like the ladder's comfort — the
    /// answer to *"kenen puhelin tämä on"*, asked in onboarding — and it was
    /// the last thing the wipe left behind. The cost was small and exactly
    /// wrong-shaped: a device returned to its first screen met that screen's
    /// own question with the previous household's answer already in it.
    ///
    /// Set through the Settings toggle rather than a launch argument, because
    /// the argument domain is volatile and outranks the persistent one — an
    /// argument-seeded value would survive `removeObject` and fail this test
    /// for a reason that has nothing to do with the wipe.
    func testEmptyingForgetsWhosePhoneThisIs() {
        let app = launch(
            ["-seed", "archive", "-local_only", "YES", "-tab", "people", "-screen", "settings"],
            api: "http://127.0.0.1:9"
        )

        let toggle = app.switches["Isompi teksti"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "never arrived: Settings")
        // The control and not the row. A `Toggle` in a `List` exposes the whole
        // row as the switch element, so a plain `.tap()` lands in the gap
        // between the label and the control and changes nothing — measured,
        // and it reads exactly like a wipe that failed to clear the answer.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(
            toggle.waitForValueEqual("1", timeout: 5),
            "the toggle did not take the answer"
        )

        app.buttons["Tyhjennä ja aloita alusta"].tap()
        let confirm = app.buttons["Tyhjennä"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the wipe asked nothing first")
        confirm.tap()

        let create = app.buttons["Aloita perheen arkisto"]
        XCTAssertTrue(create.waitForExistence(timeout: 15), "never arrived: the first screen")
        create.tap()

        // The inline picker draws both answers as rows and marks the chosen
        // one, so the question can be read without touching it.
        let mine = app.buttons["Minun"]
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "never arrived: whose phone this is")
        XCTAssertTrue(
            mine.isSelected,
            "the emptied device still remembered whose phone it was"
        )
    }
}

private extension XCUIElement {
    /// `waitForExistence` for a value rather than for existence. A toggle is
    /// there before it is on, so the only thing worth waiting for here is what
    /// it says.
    func waitForValueEqual(_ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if value as? String == expected { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return value as? String == expected
    }
}
