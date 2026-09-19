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

        // And the grid now stands in that order: the dated photograph under
        // its decade. Until 6 Sep 2026 the date reached the card and sorted
        // nothing (founder's-eye review, finding #10).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let heading = app.staticTexts["1950-luku"]
        for _ in 0 ..< 4 where !heading.exists { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "the grid did not group the photograph by its decade")
    }

    /// And the exact answer, which is the other half of rule 5 and was missing
    /// until 19 Sep 2026: a day somebody actually remembers must not be
    /// flattened into its year either. The screen asks it in three steps — the
    /// year, then the month, then the day — because the controls iOS has for a
    /// date in one step are a wheel and a graphical calendar, and neither one's
    /// text grows with Dynamic Type.
    ///
    /// The re-opening at the end is the part that is easy to get wrong without
    /// anybody noticing: a sheet that forgot the stored answer would look
    /// exactly like this one and start the family at 1900 every time.
    func testADayCanBeGivenAndIsKeptAsADay() {
        let app = launch(["-seed", "archive", "-tab", "memories"])

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "never arrived: the photo tile")
        photo.tap()

        let add = app.buttons["Lisää ajankohta"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the card offers no way to date the photo")
        add.tap()

        XCTAssertTrue(
            app.staticTexts["Kuinka tarkkaan tiedät?"].waitForExistence(timeout: 10),
            "never arrived: the date sheet"
        )
        app.buttons["Päivämäärä"].tap()

        let year = app.buttons["1957"]
        for _ in 0 ..< 12 where !year.exists { app.swipeUp() }
        XCTAssertTrue(year.waitForExistence(timeout: 10), "never arrived: the year to choose")
        year.tap()

        // Twelve rows, and the year above them so that the screen never shows a
        // month with nothing to attach it to.
        let month = app.buttons["kesäkuu"]
        XCTAssertTrue(month.waitForExistence(timeout: 10), "never arrived: the months of the chosen year")
        month.tap()

        let day = app.buttons["17"]
        for _ in 0 ..< 6 where !day.exists { app.swipeUp() }
        XCTAssertTrue(day.waitForExistence(timeout: 10), "never arrived: the days of the chosen month")
        day.tap()

        // Written the way the card writes it, rather than the way this test
        // guesses it would: the phone's own language and the archive's own
        // clock, which is Helsinki because that is where the date was built.
        var style = Date.FormatStyle.dateTime.day().month(.wide).year()
        style.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = style.timeZone
        let stored = calendar.date(from: DateComponents(year: 1957, month: 6, day: 17))!
        let written = stored.formatted(style)

        let row = app.buttons[written]
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "the day did not reach the card, or was rounded into something coarser"
        )

        // Opened again it stands on the day it holds, with the month and the
        // year one tap above — so correcting the 17th to the 18th is one tap
        // and not four.
        row.tap()
        // By predicate and not by label: the row holds two texts, the month it
        // stands on and the way back to it, and SwiftUI gives the button both
        // of them as one label — "kesäkuu 1957, Vaihda kuukausi", which is also
        // what VoiceOver reads and the reason it is left that way.
        let back = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Vaihda kuukausi")
        ).firstMatch
        XCTAssertTrue(
            back.waitForExistence(timeout: 10),
            "the sheet forgot the stored day and started from the beginning"
        )

        // And the month alone, which is the answer this screen is really for:
        // "kesäkuussa 1957" is remembered far more often than the seventeenth
        // is, and it lives above the days because that is where somebody
        // realises the day is the part they do not have.
        let wholeMonth = app.buttons["Koko kuukausi"]
        XCTAssertTrue(wholeMonth.waitForExistence(timeout: 10), "never arrived: the month as an answer of its own")
        wholeMonth.tap()

        var monthStyle = Date.FormatStyle.dateTime.month(.wide).year()
        monthStyle.timeZone = style.timeZone
        XCTAssertTrue(
            app.buttons[stored.formatted(monthStyle)].waitForExistence(timeout: 10),
            "the month did not reach the card, or was sharpened into a day"
        )
    }

    /// The row a family reads says when it was told. The export printed the
    /// day beside every telling from the first; the card never did (finding
    /// #9), so a story told last week and one told first looked the same.
    func testATellingSaysWhenItWasTold() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "never arrived: the photo tile")
        photo.tap()

        // The fixture's telling was made now, so the day is today's, in the
        // phone's own short form.
        let today = Date.now.formatted(date: .numeric, time: .omitted)
        let line = app.staticTexts["Mummo · \(today)"]
        for _ in 0 ..< 4 where !line.exists { app.swipeUp() }
        XCTAssertTrue(line.waitForExistence(timeout: 10), "the telling does not say when it was told")
    }
}
