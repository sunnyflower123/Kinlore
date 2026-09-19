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

    /// And when it happened, asked on the screen where it is known.
    ///
    /// The date could be given only on the subject's own card until 19 Sep
    /// 2026 — two screens away from the one moment somebody has just said it
    /// out loud. The row is the row the card carries and it opens the same
    /// `DateSheet`; what this test is about is the step after the tap, that
    /// the answer reaches the archive rather than only the button under the
    /// thumb. The row reads `placedNow`, which is the store and not the value
    /// the telling was saved with, and that is the half that would have failed
    /// silently.
    ///
    /// **The row opens on what is stored, not on an invitation**, and that was
    /// measured rather than assumed: the canned telling says *"joskus
    /// 50-luvulla"*, so the extraction has already put a decade there and the
    /// row reads *"1950-luku"* before anything is tapped. Which makes this the
    /// more useful of the two cases — the screen is not adding a first date
    /// but sharpening one the model proposed, which is rule 4's shape and rule
    /// 5's: the decade was honest, and the person who was there knows the year.
    ///
    /// 1950 is the answer because the sheet opens standing on the fifties, so
    /// it is one tap with no scrolling. What is measured is the path, not the
    /// arithmetic — `DateTests` measures the years, the months and the days.
    func testTheDateCanBeGivenWhereTheTellingEnds() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        let row = app.buttons["1950-luku"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "the telling ends with no way to say when it happened, or the row does not read what is stored"
        )
        row.tap()

        XCTAssertTrue(
            app.staticTexts["Milloin tämä oli?"].waitForExistence(timeout: 10),
            "never arrived: the date sheet"
        )

        // The sheet opens standing on the answer it holds, which is `load()`
        // doing its job: the decade list is scrolled to the fifties, so the
        // question above it is off the top of a lazy `Form` and has to be
        // scrolled back to.
        let sureness = app.buttons["Vuosi"]
        for _ in 0 ..< 6 where !sureness.exists { app.swipeDown() }
        XCTAssertTrue(sureness.waitForExistence(timeout: 10), "never arrived: the question above the answers")
        sureness.tap()

        // And the years arrive around the decade that was stored rather than at
        // 1900, which is the same courtesy one step finer.
        let year = app.buttons["1950"]
        XCTAssertTrue(year.waitForExistence(timeout: 10), "never arrived: the years, near the decade already stored")
        year.tap()

        // Back on the result screen, sharpened rather than merely re-stated:
        // the row reads the year and the decade is gone from it.
        XCTAssertTrue(
            app.buttons["1950"].waitForExistence(timeout: 10),
            "the date did not come back to the screen it was given on"
        )
        XCTAssertFalse(
            app.buttons["1950-luku"].exists,
            "the answer was stored as the decade it started from"
        )
    }
}
