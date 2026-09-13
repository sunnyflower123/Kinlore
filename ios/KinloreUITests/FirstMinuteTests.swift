import XCTest

/// The first minute after an archive is created, since 13 Sep 2026: whose
/// memories it is for, their card, and an invitation made out to them — on
/// the phone of whoever set it up, and never on a grandparent's.
///
/// `-first_minute_pending YES` is the same UserDefaults key a real "Luo
/// arkisto" sets; a real create needs a server, and `-seed alone` is a family
/// of one without one. The invitation itself is not made here for the same
/// reason: its code comes from the Worker.
final class FirstMinuteTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheFirstMinuteMakesACardForWhoeverTheMemoriesAreFor() {
        let app = launch(["-seed", "alone", "-first_minute_pending", "YES"])
        XCTAssertTrue(
            app.staticTexts["Kenen muistot haluat tallentaa?"].waitForExistence(timeout: 10),
            "the first minute did not ask whose memories"
        )

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText("Mummo")
        app.buttons["Jatka"].tap()

        XCTAssertTrue(app.staticTexts["Mummo on nyt arkistossa"].waitForExistence(timeout: 10), "the second step")
        XCTAssertTrue(app.buttons["Omalla puhelimellaan"].exists, "no invitation offered for her own phone")
        // The answer for a grandmother with no smartphone: her card stays,
        // and nothing is sent.
        app.buttons["Tällä puhelimella"].tap()

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(app.staticTexts["Mummo"].waitForExistence(timeout: 10), "her card is not among the people")
    }

    /// Closing it at once creates nobody.
    func testClosingTheFirstMinuteLeavesNobodyBehind() {
        let app = launch(["-seed", "alone", "-first_minute_pending", "YES"])
        let close = app.buttons["Sulje"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "the way out of the first minute")
        close.tap()

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(app.staticTexts["Ei vielä ihmisiä"].waitForExistence(timeout: 10), "somebody was created by closing")
    }

    /// A grandparent's phone keeps her button: no question in front of it.
    func testAGrandparentsPhoneSkipsTheFirstMinute() {
        let app = launch(["-seed", "alone", "-first_minute_pending", "YES", "-elder.largerText", "YES"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "the app did not open")
        XCTAssertFalse(
            app.staticTexts["Kenen muistot haluat tallentaa?"].waitForExistence(timeout: 3),
            "the first minute was asked on a grandparent's phone"
        )
    }
}
