import XCTest

/// What the result screen says after a telling, and what it must not.
///
/// The screen is the magic moment (PLAN.md §4), and it used to claim more than
/// one telling can carry: *"Sijoitin sen kohteeseen Kesä Puumalassa"* named a
/// moment nobody had named, and three questions the model thought of stood
/// under names with no sentence to recognise them by. Since 12 Sep 2026 it
/// says what was heard, in the words it was heard in, and names nothing.
final class ResultScreenTests: XCTestCase {
    /// The canned telling as free dictation on an empty archive: the case
    /// where the app used to make up a moment and title it.
    func testTheResultClaimsNothingItInferred() {
        let app = launch(["-seed", "empty", "-screen", "result"])

        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        // No placement sentence. The memory is a memory; a person moves it
        // with "Siirrä toiselle kortille" if it belongs somewhere.
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sijoitin sen kohteeseen")).firstMatch.exists,
            "the screen named a moment nobody named"
        )
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Lisäsin sen kohteeseen")).firstMatch.exists,
            "the screen announced a placement"
        )

        // The names, each with the sentence it was heard in.
        let heard = app.staticTexts["Kuulin nämä"]
        for _ in 0 ..< 4 where !heard.exists { app.swipeUp() }
        XCTAssertTrue(heard.waitForExistence(timeout: 10), "never arrived: the names heard")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Aino oli siinä")).firstMatch.exists,
            "a name is on the screen without the sentence it was heard in"
        )

        // Two questions, not three: the third is still stored, for the
        // subject's own Tell screen and the interview loop.
        XCTAssertLessThanOrEqual(
            app.images.matching(identifier: "questionmark.circle.fill").count, 2,
            "more than two questions on the result"
        )
    }

    /// A free dictation is shown under the day it was told, not under a title
    /// the model wrote. "Nimeä hetki" is how it gets a name.
    func testAFreeDictationIsShownUnderItsDay() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        app.tabBars.buttons["Albumi"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery under its day")
        XCTAssertFalse(app.staticTexts["Kerrottu muisto"].exists, "the old placeholder is back")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1950-luku")).firstMatch.exists,
            "the model's title named the moment"
        )
    }
}
