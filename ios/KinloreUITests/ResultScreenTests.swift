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

    /// A name confirmed here says where it went: into the family, not yet
    /// into the tree, and the one tap to the card where a relative is added
    /// (30 Sep 2026). Until then the row went away and nothing said so. The
    /// names still waiting keep rule 4's sentence above them, and a place
    /// confirmed is not said to join anything.
    func testAConfirmedNameSaysWhereItWent() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result")

        let tick = app.buttons["Vahvista Toivo"]
        for _ in 0 ..< 6 where !(tick.exists && tick.isHittable) { app.swipeUp() }
        XCTAssertTrue(tick.waitForExistence(timeout: 10), "never arrived: the heard name's row")
        tick.tap()

        let added = app.staticTexts["Toivo on nyt lisätty sukuun."]
        XCTAssertTrue(added.waitForExistence(timeout: 10), "a confirmed name said nothing about where it went")
        XCTAssertTrue(
            app.staticTexts["Hän saa paikan sukupuussa, kun hänen kortilleen lisätään sukulainen."].exists,
            "nothing said that the tree waits for a relative"
        )
        XCTAssertTrue(
            app.staticTexts["Kirjoita nimi uudelleen jos kuulin väärin. Emme lisää sukuun ketään jota et ole hyväksynyt."].exists,
            "rule 4's sentence went while names are still waiting"
        )

        // The card, where the relative is added, and back to the same note.
        app.buttons["Avaa kortti: Toivo"].tap()
        XCTAssertTrue(app.navigationBars["Toivo"].waitForExistence(timeout: 10), "the note did not open his card")
        let relative = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Lisää sukulainen")).firstMatch
        for _ in 0 ..< 6 where !relative.exists { app.swipeUp() }
        XCTAssertTrue(relative.exists, "the card the note opened has no way to add a relative")
        app.navigationBars["Toivo"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(added.waitForExistence(timeout: 10), "back from the card is not the result with its note")

        // The place the telling heard is confirmed with no note of its own.
        let place = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Vahvista Puumala")).firstMatch
        for _ in 0 ..< 6 where !(place.exists && place.isHittable) { app.swipeUp() }
        XCTAssertTrue(place.waitForExistence(timeout: 10), "never arrived: the place's row")
        place.tap()
        XCTAssertTrue(place.waitForNonExistence(timeout: 10), "the place was not confirmed")
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "on nyt lisätty sukuun.")).count, 1,
            "a place was said to have been added to the family"
        )
    }

    /// The paid archive is offered on a reader's phone and never on a
    /// grandparent's, where the one who pays is somebody else (docs/PLAN.md
    /// §9) — and never on a phone with no store to buy from, where an offer is
    /// a sentence about money with nothing to tap. `upsell-rhythm-check.swift`
    /// pins both rules; this pins that the screen asks them with the phone's
    /// own answers, which the check cannot see.
    ///
    /// All three launches are the same telling, the same family and the rhythm
    /// due (`-tellings-since-upsell 2`, as in the film's paywall take). The
    /// first is a reader's phone with a store, and it is what makes the other
    /// two absences mean anything — a card that never came would be missing
    /// from all three. The second differs from it only in the text floor, the
    /// third only in having no key.
    ///
    /// The key is a placeholder in a key's shape and never the Test Store's:
    /// it is all `RevenueCatPurchases.configuredKey` asks for, and whatever the
    /// SDK then asks RevenueCat with it is refused where no screen shows it.
    func testTheArchiveIsOfferedOnlyOnAReadersPhoneWithAStore() {
        let offer = "Maksullisessa arkistossa on enemmän tilaa kuville ja enemmän litterointiaikaa, ja yksi maksaja avaa sen koko perheelle."
        let arguments = ["-seed", "family", "-defer", "structure", "-screen", "interview", "-tellings-since-upsell", "2"]
        let store = ["-rcKey", "test_placeholder"]

        let reader = launch(arguments + store)
        XCTAssertTrue(reader.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 60), "never arrived: the result")
        let offered = reader.staticTexts[offer]
        for _ in 0 ..< 6 where !offered.exists { reader.swipeUp() }
        XCTAssertTrue(offered.waitForExistence(timeout: 10), "a reader's phone was not offered the archive")
        XCTAssertTrue(reader.buttons["Avaa koko arkisto"].exists, "the offer came without its button")
        reader.terminate()

        let grandparent = launch(arguments + store + ["-elder.largerText", "YES"])
        XCTAssertTrue(grandparent.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 60), "never arrived: the result")
        for _ in 0 ..< 6 {
            XCTAssertFalse(grandparent.staticTexts[offer].exists, "a grandparent's phone was offered the archive")
            grandparent.swipeUp()
        }
        XCTAssertFalse(grandparent.staticTexts[offer].exists, "a grandparent's phone was offered the archive")
        grandparent.terminate()

        let keyless = launch(arguments)
        XCTAssertTrue(keyless.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 60), "never arrived: the result")
        for _ in 0 ..< 6 {
            XCTAssertFalse(keyless.staticTexts[offer].exists, "a phone with no store was offered the archive")
            keyless.swipeUp()
        }
        XCTAssertFalse(keyless.staticTexts[offer].exists, "a phone with no store was offered the archive")
    }
}
