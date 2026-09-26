import XCTest

/// A second phone on the same Apple ID, which joins as the first phone's
/// member (docs/UX.md §4.5, `Session.joinedAsSomebodyElse`).
///
/// The identity is a Keychain item that iCloud carries to every phone on the
/// account (rule 6), and the server lets an identity it knows back into its
/// family without a question — no new member, no rename, no code claimed. So
/// whatever the second phone's owner typed, the phone becomes the first
/// phone's member, and each phone reads the other's tellings as its own.
/// Nothing said so until 26 Sep 2026. These pin who is told, and that the
/// telling happens once: a notice owed until read, and never after.
///
/// `-seed joined` holds a join at the moment it returns, with no server: the
/// same decision the real one makes, over the shared fixture's family, whose
/// invitations are one made for Kaarina and one made for nobody.
final class SharedAppleIDTests: XCTestCase {
    private let notice = "Tällä puhelimella olet Kinloressa Aino"

    /// A name typed that is not the member's: told, with the member's name
    /// in the title and in the message, and gone once read.
    func testAnotherNameTypedIsTold() {
        let app = join(as: "Aino", typed: "Eino")
        let alert = app.alerts[notice]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "a phone that joined as Aino was not told so")
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@", "Tämä puhelin käyttää samaa Apple ID:tä kuin Aino"
            )).firstMatch.exists,
            "the notice does not name the Apple ID's member in its message"
        )
        alert.buttons["Selvä"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "the notice did not close on Selvä")
    }

    /// The member's own name, whatever its case and spaces: nothing to tell.
    func testTheSameNameIsNotTold() {
        let app = join(as: "Aino", typed: " aino ")
        assertNotTold(app, "the member's own name, typed in lower case, was taken for somebody else's")
    }

    /// Nothing typed, over an invitation made for somebody else: the only
    /// way left to tell, and the one a grandparent's phone takes.
    func testAnInvitationForSomebodyElseIsTold() {
        let app = join(as: "Aino", code: "demo-kaarina")
        let alert = app.alerts[notice]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 10),
            "a phone let in on Kaarina's invitation as Aino was not told so"
        )
        // Read before the test ends: unread, it is owed to the next launch on
        // this device, and most seeds open the archive it is shown over.
        alert.buttons["Selvä"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "the notice did not close on Selvä")
    }

    /// Nothing typed, over an invitation made for nobody: nothing to compare,
    /// so nothing is said.
    func testAnInvitationForNobodyIsNotTold() {
        let app = join(as: "Aino", code: "demo-nimeton")
        assertNotTold(app, "an invitation made for nobody was taken for somebody else's")
    }

    /// Nothing typed, over the invitation made for this very member: the
    /// member it was made for is the one the phone became.
    func testAnInvitationForThisMemberIsNotTold() {
        let app = join(as: "Kaarina", code: "demo-kaarina")
        let notYou = app.alerts["Tällä puhelimella olet Kinloressa Kaarina"]
        XCTAssertTrue(app.tabBars.buttons["Albumi"].waitForExistence(timeout: 10), "the archive never opened")
        XCTAssertFalse(notYou.waitForExistence(timeout: 3), "Kaarina's own invitation was taken for somebody else's")
    }

    /// Once means until read: a launch that left the notice unread brings it
    /// back, and a launch after "Selvä" does not.
    func testTheNoticeWaitsUntilRead() {
        let first = join(as: "Aino", typed: "Eino")
        XCTAssertTrue(first.alerts[notice].waitForExistence(timeout: 10), "the notice was never shown")
        first.terminate()

        let unread = launch(["-seed", "joined", "-joinedAs", "Aino"])
        let alert = unread.alerts[notice]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "a notice nobody had read was gone at the next launch")
        alert.buttons["Selvä"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "the notice did not close on Selvä")
        unread.terminate()

        let read = launch(["-seed", "joined", "-joinedAs", "Aino"])
        assertNotTold(read, "a notice already read was said again")
    }

    private func join(as member: String, typed: String? = nil, code: String? = nil) -> XCUIApplication {
        var arguments = ["-seed", "joined", "-joinedAs", member]
        if let typed { arguments += ["-joinTyped", typed] }
        if let code { arguments += ["-joinCode", code] }
        return launch(arguments)
    }

    /// Waits for the archive first, so that "no notice" is measured on an app
    /// that has arrived rather than on one still starting.
    private func assertNotTold(_ app: XCUIApplication, _ message: String, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.buttons["Albumi"].waitForExistence(timeout: 10), "the archive never opened", line: line)
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 3), message, line: line)
    }
}
