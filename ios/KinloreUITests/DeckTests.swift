import XCTest

/// The card on the Kerro tab.
///
/// The screen it replaced said *"Kerro mitä muistat"* over a button, which is
/// a blank page — and a blank page is the most reliable way there is to get
/// nothing from somebody who does not believe they remember anything worth
/// saying. What the deck does is answer *which card*, out of state the app
/// already had; what it must never do is trap her on one she cannot answer.
final class DeckTests: XCTestCase {
    /// A photograph she does not recognise has to have a way past it, and the
    /// deck has to know when to stop offering them.
    ///
    /// **This is the failure mode the whole idea has to be designed against,
    /// and it is silent:** nothing crashes, she simply meets a run of pictures
    /// she cannot place and concludes that an app built to tell her she
    /// remembers a great deal has decided otherwise. `Deck.patience` is three
    /// per session — the ladder already holds the same opinion in numbers, one
    /// strained answer for a whole level, because for this user one wall costs
    /// more than a run of easy questions.
    ///
    /// Written this way rather than counting cards on purpose: what the
    /// archive holds is the fixture's business and may change, but three
    /// pushes ending it is the promise.
    func testTheDeckStopsOfferingAfterThreePushesAside() {
        let app = launch(["-seed", "deck"])

        XCTAssertTrue(
            app.staticTexts["Kuka tässä kuvassa on?"].waitForExistence(timeout: 15),
            "never arrived: the card"
        )

        // Three, which is `Deck.patience` — the app target's constant is not
        // visible from here, so the number is written out and this sentence is
        // what couples them.
        for push in 1 ... 3 {
            let skip = app.buttons["En muista tätä"]
            XCTAssertTrue(
                skip.waitForExistence(timeout: 10),
                "the deck stopped offering after \(push - 1) pushes, before its patience ran out"
            )
            skip.tap()
        }

        XCTAssertTrue(
            app.staticTexts["Kerro mitä muistat"].waitForExistence(timeout: 10),
            "the deck went on offering cards past its patience"
        )
        XCTAssertFalse(
            app.buttons["En muista tätä"].exists,
            "a way past a card that is no longer offered"
        )
    }

    /// A question somebody in the family asked outranks any card.
    ///
    /// *"Mummo kysyy"* turns a prompt into a request from a person, which is
    /// the strongest pull this app has — and the deck can hide it without
    /// breaking anything visible: giving the screen a subject makes it offer
    /// *that subject's* questions, and the family's question about something
    /// else quietly stops being on screen. It did, for one commit, and only
    /// `VideoSceneTests` noticed because the demo video's fourth scene is that
    /// question being answered aloud. This says it in its own words so the
    /// rule does not depend on a film.
    func testAFamilyQuestionOutranksTheDeck() {
        let app = launch(["-seed", "unseen"])

        app.tabBars.buttons["Kerro"].tap()

        XCTAssertTrue(
            app.staticTexts["Mummo kysyy"].waitForExistence(timeout: 15),
            "the family's question is not offered on the Tell screen"
        )
        XCTAssertFalse(
            app.buttons["En muista tätä"].exists,
            "the deck stepped over a question a person asked"
        )
    }

    /// And the blank button is still what an empty archive gets. The deck adds
    /// a card where there is something to ask about; where there is nothing it
    /// must add nothing at all — including its own way past.
    func testAnEmptyArchiveKeepsTheBlankButton() {
        let app = launch(["-seed", "empty"])

        XCTAssertTrue(
            app.staticTexts["Kerro mitä muistat"].waitForExistence(timeout: 15),
            "never arrived: the Tell screen"
        )
        XCTAssertFalse(
            app.buttons["En muista tätä"].exists,
            "an empty archive offered a way past a card it does not have"
        )
    }

    /// A telling about the card ends back on the idle screen — never on a
    /// button that goes nowhere.
    ///
    /// The result screen's *Valmis* closes the sheet a photo's card opens the
    /// Tell screen on, and it used to appear whenever the telling had a
    /// subject, because only a sheet ever had one. The deck gave the tab a
    /// subject on 29 Aug 2026; from then on a telling about its card ended on
    /// a *Valmis* whose `dismiss()` had nothing to dismiss — a tap, and the
    /// same screen. Found by a thumb on 12 Sep 2026, and by nothing else: a
    /// button that does nothing raises no error and fails no audit.
    func testFinishingACardTellingOffersNoDeadDoneButton() {
        // `-screen result` runs a canned telling through the stub pipeline on
        // whatever subject the Tell screen opened on — here the deck's card.
        let app = launch(["-seed", "deck", "-screen", "result"])

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result screen"
        )
        XCTAssertFalse(
            app.buttons["Valmis"].exists,
            "the tab grew a Valmis that closes nothing"
        )

        let another = app.buttons["Kerro toinen muisto"]
        for _ in 0 ..< 4 where !another.isHittable { app.swipeUp() }
        XCTAssertTrue(another.waitForExistence(timeout: 10), "never arrived: the way on")
        another.tap()

        // Back on the idle screen, and still with nothing that closes nothing.
        // Which prompt the screen then carries is the next test's question.
        XCTAssertTrue(
            app.buttons["Aloita kertominen"].waitForExistence(timeout: 10),
            "finishing did not return to the idle screen"
        )
        XCTAssertFalse(app.buttons["Valmis"].exists, "a Valmis appeared on the way back")
    }

    /// The pack goes on from photograph to photograph — past the telling's
    /// own follow-up questions.
    ///
    /// A family member's question outranks the deck, and until 12 Sep 2026
    /// so did every open question: the extraction makes two or three from
    /// each telling, so the first card told about took the deck off the
    /// screen until its follow-ups were answered, and a pack meant to go from
    /// photograph to photograph stopped at one. Nothing failed — the blank
    /// button with questions under it is a screen this app has — and the
    /// first run of the test above found it there, expecting the card.
    /// `testAFamilyQuestionOutranksTheDeck` holds the other half of the rule.
    func testTheDeckGoesOnPastTheTellingsOwnQuestions() {
        let app = launch(["-seed", "deck", "-screen", "result"])

        let another = app.buttons["Kerro toinen muisto"]
        XCTAssertTrue(another.waitForExistence(timeout: 30), "never arrived: the result screen")
        for _ in 0 ..< 4 where !another.isHittable { app.swipeUp() }
        another.tap()

        // The telling has left follow-ups open, the card told about carries a
        // memory now, and the fixture has two more photographs: the next one
        // is on the screen, not the questions.
        XCTAssertTrue(
            app.staticTexts["Kuka tässä kuvassa on?"].waitForExistence(timeout: 10),
            "the telling's own follow-up questions took the deck off the screen"
        )
        XCTAssertTrue(app.buttons["En muista tätä"].exists, "the next card has no way past it")
    }

    /// The other side of the same rule: where the Tell screen *is* a sheet,
    /// *Valmis* is there and closes it. Read off the presenter, not the
    /// subject — which is the whole of the fix above, and this is what keeps
    /// it from being fixed back the other way.
    func testDoneOnAPhotographsSheetReturnsToThePhotograph() {
        // `-screen result` is read by every Tell screen, so it runs the canned
        // telling inside the sheet the photo's card opens.
        let app = launch(["-seed", "archive", "-tab", "memories", "-screen", "result"])

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "never arrived: the photo tile")
        photo.tap()

        let tell = app.buttons["Kerro tästä muisto"]
        for _ in 0 ..< 4 where !tell.isHittable { app.swipeUp() }
        XCTAssertTrue(tell.waitForExistence(timeout: 10), "never arrived: the photo's card")
        tell.tap()

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result screen in the sheet"
        )
        let done = app.buttons["Valmis"]
        for _ in 0 ..< 4 where !done.isHittable { app.swipeUp() }
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the sheet's result screen has no Valmis")
        done.tap()

        // The sheet is gone and the photo's card is back.
        XCTAssertTrue(tell.waitForExistence(timeout: 10), "Valmis did not close the sheet")
        XCTAssertFalse(
            app.staticTexts["Muisto tallennettu"].exists,
            "the result screen is still up"
        )
    }
}
