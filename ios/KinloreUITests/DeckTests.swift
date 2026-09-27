import XCTest

/// The card on the Kerro tab — and, since 12 Sep 2026, what the tab is allowed
/// to put in front of somebody at all: a photograph the family added, a
/// question a person asked, or the plain button. Never a name the extraction
/// heard, never a question it thought of. Those stay beside the telling they
/// came from.
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

    /// A name is never a card.
    ///
    /// People nobody had spoken about were cards until 12 Sep 2026, ranked
    /// after the photographs — and the names that reach the table are mostly
    /// the extraction's, unconfirmed. The founder met one on the second
    /// launch: *"Kerro hänestä – Toivo"*, a name nobody had vouched for, asked
    /// about as if it were somebody. The plain archive carries exactly that
    /// case: Aino, unconfirmed and untold, and no photograph left to offer.
    func testTheDeckNeverOffersAName() {
        let app = launch(["-seed", "archive", "-tab", "tell"])

        XCTAssertTrue(
            app.staticTexts["Kerro mitä muistat"].waitForExistence(timeout: 15),
            "never arrived: the Tell screen"
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Kerro hänestä")
            ).firstMatch.exists,
            "the deck put a name in front of her"
        )
        XCTAssertFalse(app.buttons["En muista tätä"].exists, "a way past a card that must not exist")
    }

    /// And the front screen carries none of the model's questions.
    ///
    /// A telling leaves two or three follow-ups open, and until 12 Sep 2026
    /// they stood on the idle screen under *"Tai vastaa aiempaan kysymykseen"*
    /// — questions the app had thought of by itself, on the screen somebody
    /// opens cold. They are still asked, by the interview loop and on the
    /// subject's own Tell screen; this screen is for a person's question
    /// (`testAFamilyQuestionOutranksTheDeck`) or the plain button.
    func testTheFrontScreenCarriesNoneOfTheModelsQuestions() {
        let app = launch(["-seed", "archive", "-tab", "tell", "-screen", "result"])

        let another = app.buttons["Kerro toinen muisto"]
        XCTAssertTrue(another.waitForExistence(timeout: 30), "never arrived: the result screen")
        for _ in 0 ..< 4 where !another.isHittable { app.swipeUp() }
        another.tap()

        XCTAssertTrue(
            app.staticTexts["Kerro mitä muistat"].waitForExistence(timeout: 10),
            "finishing did not return to the plain button"
        )
        XCTAssertFalse(
            app.staticTexts["Tai vastaa aiempaan kysymykseen"].exists,
            "the model's follow-ups are on the front screen"
        )
        // The canned telling names Toivo, whom the archive did not have: an
        // unconfirmed, untold person, which is the exact card that must not be.
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Kerro hänestä")
            ).firstMatch.exists,
            "a name the telling produced became a card"
        )
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

    /// Every way on from this screen is above the tab bar before anybody
    /// scrolls — under the plain button, a photograph's card and a family
    /// member's question and on a first launch, on a reader's phone and on a
    /// grandparent's — and at the largest text size, the record button. The
    /// first launch runs in English as well, because its title takes two
    /// lines there and the screen is taller for it.
    ///
    /// The accessibility audit cannot see this, for the reason
    /// `BlindConfirmationTests` records: the tree keeps a button's whole frame
    /// when the floating tab bar is drawn over it. And a way on under the bar
    /// is not one swipe away for the person this screen is for, because she
    /// does not scroll a screen with one big button on it. Measured in Finnish
    /// on 26 and 27 Sep 2026 on an iPhone SE, whose bar begins at 584, before
    /// the screen measured its room: under a photograph's card "En muista
    /// tätä" ended at 704 on a reader's phone and 711 on a grandparent's,
    /// under a family member's question "Kirjoita sen sijaan" at 677 and 727,
    /// and on a first launch at 663 and 680 — in English at 704 and 723. On a
    /// 13 mini, whose bar begins at 729, the rows under a card reached 5 and
    /// 12 points into it, the question's 28 and the first launch's in English
    /// 4 and 24.
    ///
    /// At accessibility sizes the page is taller than the phone on purpose,
    /// and the quiet rows are below the fold by design; the record button is
    /// not, and on the SE at the largest size it ended at 641 on the plain
    /// screen, 662 under a card and 711 on a first launch in English — on the
    /// mini at 741 there, 12 points into its bar.
    ///
    /// Before the screen measured its room this failed 18 times on the SE,
    /// once for every way on under the bar. Since, it passes there, on the
    /// 13 mini and on the 17 Pro, each on a simulator of its own.
    ///
    /// The frames are read at rest, because the screen gives way in steps
    /// after it has measured itself and a frame read in between is one she
    /// never sees. On the 17 Pro this suite usually runs on there was room
    /// before any of it, so this passes there either way — run it on a small
    /// phone as well.
    func testEveryWayOnClearsTheTabBarAtRest() {
        struct State {
            let name: String
            let seed: [String]
            var skip = false
            var question = false
            var english = false
        }
        let states = [
            State(name: "the plain button", seed: ["-seed", "archive"]),
            State(name: "a photograph's card", seed: ["-seed", "deck"], skip: true),
            State(name: "a family member's question", seed: ["-seed", "unseen"], question: true),
            State(name: "the first launch", seed: ["-seed", "empty"]),
            // Later than `launch`'s own Finnish, so it is the one that counts.
            State(
                name: "the first launch in English",
                seed: ["-seed", "empty", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
                english: true
            ),
        ]
        let phones: [(name: String, arguments: [String])] = [
            ("a reader's phone", []),
            ("a grandparent's phone", ["-elder.largerText", "YES"]),
        ]
        for state in states {
            for phone in phones {
                let place = "\(state.name) on \(phone.name)"
                let app = launch(state.seed + phone.arguments + ["-tab", "tell"])
                let record = app.buttons[state.english ? "Start telling" : "Aloita kertominen"]
                XCTAssertTrue(record.waitForExistence(timeout: 15), "never arrived: \(place)")

                let write = app.buttons[state.english ? "Write instead" : "Kirjoita sen sijaan"]
                atRest(write)

                var ways: [(String, XCUIElement)] = [("the record button", record), ("\"\(write.label)\"", write)]
                if state.skip {
                    let skip = app.buttons["En muista tätä"]
                    XCTAssertTrue(skip.exists, "no way past the card: \(place)")
                    ways.append(("\"En muista tätä\"", skip))
                }
                if state.question {
                    let question = app.buttons.matching(
                        NSPredicate(format: "label BEGINSWITH %@", "Mummo kysyy")
                    ).firstMatch
                    XCTAssertTrue(question.exists, "the family's question is not offered: \(place)")
                    ways.append(("Mummo's question", question))
                }

                let bar = app.tabBars.firstMatch.frame
                for (name, way) in ways {
                    XCTAssertLessThanOrEqual(
                        way.frame.maxY, bar.minY,
                        "on \(place), \(name) ends at \(way.frame.maxY), under the tab bar that begins at \(bar.minY)"
                    )
                }
                app.terminate()
            }
        }

        for state in states {
            let place = "\(state.name) at the largest text size"
            let app = launch(
                state.seed + ["-tab", "tell"],
                textSize: "UICTContentSizeCategoryAccessibilityXXXL"
            )
            let record = app.buttons[state.english ? "Start telling" : "Aloita kertominen"]
            XCTAssertTrue(record.waitForExistence(timeout: 15), "never arrived: \(place)")

            let bottom = atRest(record).maxY
            let bar = app.tabBars.firstMatch.frame
            XCTAssertLessThanOrEqual(
                bottom, bar.minY,
                "on \(place), the record button ends at \(bottom), under the tab bar that begins at \(bar.minY)"
            )
            app.terminate()
        }
    }

    /// An element's frame once the screen has stopped moving it: the same
    /// twice, a second apart.
    @discardableResult
    private func atRest(_ element: XCUIElement) -> CGRect {
        var settled = CGRect.null
        for _ in 0 ..< 10 {
            sleep(1)
            let now = element.frame
            if now == settled { break }
            settled = now
        }
        return settled
    }
}
