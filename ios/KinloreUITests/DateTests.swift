import XCTest

/// Putting a date on a photograph by hand.
///
/// `date_start`, `date_end` and `date_precision` have been in the schema from the
/// first day and only the extraction could write them, so what a granddaughter
/// knows about a photograph the model never heard a year for had nowhere to go.
///
/// What is checked is the uncertain answer rather than the exact one: rule 5 is
/// that "joskus viisikymmentäluvulla" is stored as a decade and not rounded into
/// a day, and a date screen that quietly demanded a day would break the rule
/// while looking like a feature.
final class DateTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testADecadeCanBeGivenAndIsKeptAsADecade() {
        let app = launch(["-seed", "archive", "-tab", "memories"])

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "never arrived: the photo tile")
        photo.tap()

        // The demo photograph has no date, so the row is an invitation rather
        // than a value — which is the state this whole screen exists for.
        let add = app.buttons["Lisää ajankohta"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the card offers no way to date the photo")
        add.tap()

        XCTAssertTrue(
            app.staticTexts["Kuinka tarkkaan tiedät?"].waitForExistence(timeout: 10),
            "never arrived: the date sheet"
        )
        // The sureness is chosen before the answer, so an uncertain answer is
        // one tap rather than a compromise — and then choosing is answering:
        // the decade saves and closes the sheet on the same tap.
        app.buttons["Vuosikymmen"].tap()

        let fifties = app.buttons["1950-luku"]
        for _ in 0 ..< 4 where !fifties.exists { app.swipeUp() }
        XCTAssertTrue(fifties.waitForExistence(timeout: 10), "never arrived: the decade to choose")
        fifties.tap()

        XCTAssertTrue(
            app.buttons["1950-luku"].waitForExistence(timeout: 10),
            "the decade did not reach the card, or was rounded into something else"
        )
    }
}
