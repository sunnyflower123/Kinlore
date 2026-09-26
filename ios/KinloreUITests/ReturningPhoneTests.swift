import XCTest

/// A phone that comes back to a family it is already in (docs/UX.md §4.5).
///
/// The identity lives in the Keychain, which keeps it when the app is deleted
/// and carries it to a new phone on the same Apple account. The family id lives
/// in UserDefaults, which does neither. Until 26 Sep 2026 such a phone was put
/// in front of the fork, where "Aloita perheen arkisto" ends in the server's
/// `member_exists` and "Liity kutsulinkillä" needs somebody to send an
/// invitation. Now the server is asked first (`Session.lookForFamily`), and
/// these pin where each kind of answer leads — above all, that only the
/// server's own no leads to the fork.
///
/// The simulator's Keychain keeps an identity from test to test, which is the
/// condition under test here and the reason every other test launches with
/// `-homecoming off` (`AccessibilityAudit.launch`). A test that needs the
/// question asked launches once first, so that it does not depend on running
/// after something else.
final class ReturningPhoneTests: XCTestCase {
    /// The server knows the identity: the page names the family, offers no
    /// fork, and its one button opens the archive on Albumi, a join's landing.
    func testAKnownPhoneIsOfferedItsFamily() {
        let app = launch(["-seed", "returning"], api: "http://127.0.0.1:9")
        XCTAssertTrue(
            app.staticTexts["Tervetuloa takaisin"].waitForExistence(timeout: 10),
            "never arrived: the page that offers the family back"
        )
        XCTAssertTrue(app.staticTexts["Virtaset"].exists, "the page does not name the family")
        assertNoFork(app, "a member was offered the fork")

        app.buttons["Avaa perheen arkisto"].tap()
        let album = app.tabBars.buttons["Albumi"]
        XCTAssertTrue(album.waitForExistence(timeout: 10), "the family's archive never opened")
        XCTAssertTrue(album.isSelected, "the archive did not open on Albumi")
    }

    /// Nothing answered, which is not a no, so not the fork either: the page
    /// says what it is waiting for, and asking again into the same silence
    /// ends on the same page.
    func testSilenceIsNotTakenAsNo() {
        launchOnceToHoldAnIdentity()
        let app = launch(["-homecoming", "ask"], api: "http://127.0.0.1:9")
        let waiting = app.staticTexts["Odotetaan yhteyttä"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 30), "never arrived: the page that waits for the server")
        assertNoFork(app, "silence was taken as a no")

        let again = app.buttons["Yritä uudelleen"]
        XCTAssertTrue(again.exists, "the waiting page has nothing to press")
        again.tap()
        XCTAssertTrue(waiting.waitForExistence(timeout: 30), "asking again left the waiting page")
        assertNoFork(app, "silence asked twice was taken as a no")
    }

    /// The server's own `unauthorized`, read through the same mapping as the
    /// real one: this identity is a member of nothing, and the fork is right.
    func testTheServersNoOpensTheFork() {
        launchOnceToHoldAnIdentity()
        let app = launch(["-homecoming", "unauthorized"], api: "http://127.0.0.1:9")
        XCTAssertTrue(
            app.buttons["Aloita perheen arkisto"].waitForExistence(timeout: 10),
            "the server's no did not open the fork"
        )
        XCTAssertTrue(app.buttons["Liity kutsulinkillä"].exists, "the fork has lost its way into joining")
        XCTAssertFalse(app.staticTexts["Odotetaan yhteyttä"].exists, "a no was taken as silence")
    }

    /// A launch makes an identity when the Keychain has none, and the question
    /// is asked only of one that was already there.
    private func launchOnceToHoldAnIdentity() {
        launch([], api: "http://127.0.0.1:9").terminate()
    }

    private func assertNoFork(_ app: XCUIApplication, _ message: String, line: UInt = #line) {
        XCTAssertFalse(app.buttons["Aloita perheen arkisto"].exists, "\(message): Aloita", line: line)
        XCTAssertFalse(app.buttons["Liity kutsulinkillä"].exists, "\(message): Liity", line: line)
    }
}
