import XCTest

/// The story on a card (ARCHITECTURE §27): since 28 Sep 2026 the top of the
/// one card every photograph, person and place has.
///
/// What the card says is composed from what was told, and every way that can
/// go wrong reads well in a screenshot: a story composed over a person's
/// correction, a proposal that wrote itself in, a telling taken back from
/// under a person's story with nothing said, a place drawn that nobody
/// vouched for. `-seed story` holds one card in each state — a composed story
/// on the jetty, an edited one on the kitchen with a telling waiting under
/// it, two tellings and no story on Aino, an edited story on the sauna with
/// one of its two tellings gone and one on the porch with its only telling
/// gone — and `-story stub` composes without a model or a Worker, one
/// sentence per telling, so what a test reads back is what was sent.
final class StoryCardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A composed story reads above its tellings, says what it is made of,
    /// and the tellings are folded under one button — the log is what was
    /// told and when, and the story is a reading of it (rule 3). Unfolded,
    /// they are the rows every card has, newest first, the teller's own
    /// with its one button.
    func testAStoryReadsAboveItsTellingsFoldedUnderIt() {
        let app = open("demo-story-jetty")
        require(story(in: app), "the jetty's story", in: app)
        XCTAssertTrue(
            storyText(in: app).hasPrefix("Mummo kertoo, että kuvassa ollaan mökin rannassa Puumalassa."),
            "the story is not the one the archive holds: \(storyText(in: app))"
        )
        XCTAssertTrue(app.staticTexts["Koottu 3 muistosta"].exists, "the card does not say what the story is made of")

        let logs = bring(app.buttons["storyCard.logs"], in: app, "the log's button")
        XCTAssertTrue(logs.label.contains("Näytä 3 muistoa"), "the log's button does not count the tellings: \(logs.label)")
        let bodies = app.staticTexts.matching(identifier: "memory.body")
        XCTAssertEqual(bodies.count, 0, "the tellings are not folded under a story the card opened with")
        logs.tap()
        XCTAssertTrue(
            waitUntil { logs.label.contains("Piilota muistot") },
            "the log's button does not offer to fold it: \(logs.label)"
        )

        let newest = bring(bodies.firstMatch, in: app, "the first telling in the log")
        XCTAssertTrue(
            newest.label.hasPrefix("Mummo kertoi tästä laiturista aina"),
            "the log is not newest first: \(newest.label)"
        )
        // Pekka's telling is this phone's own (no author id), so its row
        // carries the one button H67 put there.
        XCTAssertTrue(
            bring(app.buttons["Muokkaa tai poista"], in: app, "the own telling's button").exists,
            "the log's rows are not the card's own rows"
        )
        // Read on the way down, since a row swiped past may leave the tree.
        var told: [String] = []
        for _ in 0 ..< 6 {
            for body in bodies.allElementsBoundByIndex where !told.contains(body.label) {
                told.append(body.label)
            }
            if told.count >= 3 { break }
            app.swipeUp()
        }
        XCTAssertEqual(told.count, 3, "the log does not hold every telling: \(told)")
        XCTAssertTrue(
            told.last?.hasPrefix("Siinä kuvassa ollaan sen mökin rannassa") == true,
            "the log's last telling is not the oldest: \(told)"
        )
    }

    /// Tellings with no story yet compose one, once, from all of them — and
    /// the card says what it does with the tellings before it does it. The
    /// tellings were open when the story came, and stay open under it.
    func testTellingsWithNoStoryComposeOne() {
        let app = open("demo-story-aino")
        require(story(in: app), "the story the stub composed for Aino", in: app)
        let text = storyText(in: app)
        XCTAssertTrue(text.hasPrefix("Mummo kertoo, että"), "the story does not start with the oldest telling: \(text)")
        XCTAssertTrue(text.contains("Pekka kertoo, että"), "the story does not carry the second telling: \(text)")
        XCTAssertTrue(app.staticTexts["Koottu 2 muistosta"].exists, "the card does not say the story is made of two tellings")
        let consent = bring(consentLine(in: app), in: app, "the line that says where the tellings go")
        XCTAssertTrue(consent.exists)
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "the card is composing again a story it has")
        let logs = bring(app.buttons["storyCard.logs"], in: app, "the log's button")
        XCTAssertTrue(logs.label.contains("Piilota muistot"), "a story that came folded the tellings away: \(logs.label)")
    }

    /// A telling made after a person corrected the story is proposed under
    /// it, never written into it (rule 4's shape); accepted, it is the
    /// story's last paragraph and the story is still the person's.
    func testATellingAfterAnEditIsProposedAndAcceptedAsAParagraph() {
        let app = open("demo-story-kitchen")
        require(story(in: app), "the kitchen's story", in: app)
        let before = storyText(in: app)
        XCTAssertTrue(before.hasPrefix("Mummo kertoo, että heillä oli semmoinen puutalo Kuopiossa."), before)
        XCTAssertFalse(before.contains("puuhella"), "the telling made after the edit was written into the story")
        XCTAssertTrue(app.staticTexts["Muokattu käsin"].exists, "the card does not say the story is the person's")

        let proposal = bring(app.staticTexts["storyCard.proposal"], in: app, "the proposal under the story")
        XCTAssertEqual(
            proposal.label,
            "Pekka kertoo, että siinä keittiössä oli iso puuhella, ja Mummo paistoi siinä lettuja joka sunnuntai."
        )
        bring(app.buttons["storyCard.acceptProposal"], in: app, "the accept button").tap()

        XCTAssertTrue(
            waitUntil { self.storyText(in: app).hasSuffix("lettuja joka sunnuntai.") },
            "the accepted telling did not become the story's last paragraph: \(storyText(in: app))"
        )
        XCTAssertTrue(storyText(in: app).hasPrefix(before), "accepting rewrote the person's words")
        XCTAssertTrue(app.staticTexts["Muokattu käsin"].exists, "the story stopped being the person's")
        XCTAssertFalse(proposal.exists, "the proposal is still under the story after being accepted")
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "accepting a proposal asked the model again")
    }

    /// Dismissed, the proposal goes and the story stays word for word — and
    /// nothing asks about that telling again.
    func testAProposalDismissedLeavesTheStoryAsItWas() {
        let app = open("demo-story-kitchen")
        require(story(in: app), "the kitchen's story", in: app)
        let before = storyText(in: app)
        let proposal = app.staticTexts["storyCard.proposal"]
        bring(app.buttons["storyCard.dismissProposal"], in: app, "the dismiss button").tap()

        XCTAssertTrue(waitUntil { !proposal.exists }, "the proposal is still under the story after being dismissed")
        XCTAssertEqual(storyText(in: app), before, "dismissing a proposal changed the story")
        XCTAssertTrue(app.staticTexts["Muokattu käsin"].exists)
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "dismissing a proposal asked the model again")
    }

    /// A question on the card is answered from the card: its row opens the
    /// Tell screen on this photograph with the question as the title, the
    /// way the memories tab's card does (TargetedQuestionTests).
    func testAQuestionOnTheCardOpensTellingWithIt() {
        let app = open("demo-story-jetty", more: ["-voice", "stub"])
        require(story(in: app), "the jetty's story", in: app)
        let asked = "Kuka muu oli laiturilla sinä päivänä?"
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", asked)).firstMatch
        bring(row, in: app, "the question's row").tap()

        XCTAssertTrue(app.buttons["Sulje"].waitForExistence(timeout: 10), "the row did not open the Tell screen")
        let title = app.staticTexts["tell.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "never arrived: the Tell screen's title")
        XCTAssertEqual(title.label, asked, "the Tell screen's title is not the question it is answering")
        app.buttons["Sulje"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "closing the Tell screen did not return to the card")
    }

    /// The composer failing is said on the card, with another try offered,
    /// and the tellings are on the card as before: a story is a reading of
    /// them, and the reading failing is not the memory failing.
    func testAFailedComposeSaysSoAndKeepsTheTellings() {
        let app = open("demo-story-aino", story: "fail")
        XCTAssertTrue(
            app.staticTexts["Tarinaa ei saatu koottua nyt. Muistot ovat tallessa."].waitForExistence(timeout: 20),
            "the card does not say the story could not be composed"
        )
        XCTAssertTrue(app.buttons["Yritä uudelleen"].exists, "no second try is offered")
        XCTAssertFalse(story(in: app).exists, "a story is on the card although nothing composed one")
        let heading = bring(app.staticTexts["card.memoriesHeading"], in: app, "the tellings' heading")
        XCTAssertEqual(heading.label, "2 muistoa", "the tellings are not all on the card")
    }

    /// A family server deployed before the story card has no `/story` and
    /// says 404: the card is then the card it was — the tellings, and not a
    /// word about a story that never came, no failure, no second try, and
    /// no line saying the tellings leave the phone for one.
    func testAServerWithNoStoryLeavesTheCardAsItWas() {
        let app = open("demo-story-aino", story: "missing")
        let heading = bring(app.staticTexts["card.memoriesHeading"], in: app, "the tellings' heading")
        XCTAssertEqual(heading.label, "2 muistoa", "the tellings are not all on the card")
        // The answer comes in 200 ms; a note that was going to come has
        // come well inside three seconds.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(
            app.staticTexts["Tarinaa ei saatu koottua nyt. Muistot ovat tallessa."].exists,
            "a server with no story reads as a failure"
        )
        XCTAssertFalse(app.buttons["Yritä uudelleen"].exists, "a second try is offered where none will work")
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "the card is still composing")
        XCTAssertFalse(story(in: app).exists, "a story is on the card although nothing composed one")
        XCTAssertFalse(consentLine(in: app).exists, "the card says the tellings leave for a story that is not composed")
        XCTAssertFalse(app.buttons["storyCard.logs"].exists, "the tellings are folded under a story that is not there")
    }

    /// A telling taken back from under a story a person corrected is said
    /// on the card, and nothing is composed over the person's words. Kept,
    /// the story stays word for word, the note goes, and the model is not
    /// asked.
    func testATellingTakenBackUnderAnEditedStoryCanBeKept() {
        let app = open("demo-story-sauna")
        require(story(in: app), "the sauna's story", in: app)
        let before = storyText(in: app)
        XCTAssertTrue(before.contains("saunan ovi narisi"), "the story does not carry the taken-back telling's words: \(before)")
        XCTAssertTrue(app.staticTexts["Muokattu käsin"].exists, "the card does not say the story is the person's")
        let note = bring(app.staticTexts["Yksi tarinan muistoista on poistettu"], in: app, "the taken-back note")
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "the plan composed over a person's story")
        bring(app.buttons["storyCard.keepStory"], in: app, "the keep button").tap()

        XCTAssertTrue(waitUntil { !note.exists }, "the note is still on the card after the story was kept")
        XCTAssertEqual(storyText(in: app), before, "keeping the story changed it")
        XCTAssertTrue(app.staticTexts["Muokattu käsin"].exists, "the story stopped being the person's")
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "keeping the story asked the model")
    }

    /// Composed again — after the card asked once more, since the person's
    /// own words go with it — the story is the stub's sentence for the one
    /// telling left, the taken-back telling's words are gone from it, and
    /// it is the model's again.
    func testATellingTakenBackUnderAnEditedStoryCanBeComposedAgain() {
        let app = open("demo-story-sauna")
        require(story(in: app), "the sauna's story", in: app)
        let before = storyText(in: app)
        bring(app.buttons["storyCard.recomposeStory"], in: app, "the compose-again button").tap()
        let asked = app.alerts["Kootaanko tarina uudelleen?"]
        XCTAssertTrue(asked.waitForExistence(timeout: 5), "composing again did not ask first")
        asked.buttons["Kokoa uudelleen"].tap()

        XCTAssertTrue(
            waitUntil(timeout: 20) { self.story(in: app).exists && self.storyText(in: app) != before },
            "the story was not composed again: \(storyText(in: app))"
        )
        let after = storyText(in: app)
        XCTAssertTrue(after.hasPrefix("Mummo kertoo, että"), "the story is not the stub's: \(after)")
        XCTAssertFalse(after.contains("narisi"), "the taken-back telling's words are still in the story: \(after)")
        XCTAssertTrue(
            app.staticTexts["Koottu yhdestä muistosta"].waitForExistence(timeout: 5),
            "the card does not say what the story is made of now"
        )
        XCTAssertFalse(app.staticTexts["Muokattu käsin"].exists, "the story is still marked as the person's")
        XCTAssertFalse(app.staticTexts["storyCard.takenBack"].exists, "the note is still on the card")
    }

    /// The only telling gone from under a person's story: the card offers to
    /// delete the story rather than compose one from nothing, asks once
    /// more, and is then the empty card — the story was a reading of what
    /// was told, and nothing is.
    func testAStoryWhoseOnlyTellingIsGoneCanBeDeleted() {
        let app = open("demo-story-porch")
        require(story(in: app), "the porch's story", in: app)
        bring(app.staticTexts["Tarinan ainoa muisto on poistettu"], in: app, "the taken-back note")
        XCTAssertFalse(app.buttons["storyCard.recomposeStory"].exists, "the card offers to compose a story from nothing")
        bring(app.buttons["storyCard.removeStory"], in: app, "the delete button").tap()
        let asked = app.alerts["Poistetaanko tarina?"]
        XCTAssertTrue(asked.waitForExistence(timeout: 5), "deleting the story did not ask first")
        asked.buttons["Poista tarina"].tap()

        XCTAssertTrue(waitUntil { !self.story(in: app).exists }, "the story is still on the card")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kukaan ei ole vielä kertonut mitään"))
                .firstMatch.waitForExistence(timeout: 5),
            "the card is not the empty one"
        )
        XCTAssertFalse(app.staticTexts["Kootaan tarinaa…"].exists, "the card is composing a story from nothing")
    }

    // MARK: - The caption's place

    /// The caption says where the card's tellings happened, beside the date,
    /// and a tap opens the family's map on that place — the one the tellings
    /// name most, here Puumala, named twice.
    func testTheCaptionsPlaceOpensTheMapOnIt() {
        let app = open("demo-story-jetty")
        let place = bring(app.buttons["card.place"], in: app, "the caption's place")
        XCTAssertEqual(place.label, "Paikka: Puumala", "VoiceOver does not hear which place it is")
        place.tap()
        XCTAssertTrue(
            app.buttons["Muuta sijaintia"].waitForExistence(timeout: 10),
            "the place did not open the map on itself"
        )
    }

    /// A confirmed place with no point — a farm the gazetteer does not know
    /// — opens the map already placing it, the way its own card's "Merkitse
    /// kartalle" does. No form: the map is where a place is put.
    func testAPlaceWithNoPointOpensTheMapPlacingIt() {
        let app = open("demo-story-sauna")
        let place = bring(app.buttons["card.place"], in: app, "the caption's place")
        XCTAssertEqual(place.label, "Paikka: Mäkelä")
        place.tap()
        XCTAssertTrue(
            app.staticTexts["Napauta karttaa kohtaan, jossa Mäkelä on."].waitForExistence(timeout: 10),
            "the place did not open the map placing it"
        )
    }

    /// A place heard and confirmed by nobody is said as waiting, and opens
    /// its own card, where it can be confirmed — never the map, where it
    /// would be a guess drawn as fact (rule 4).
    func testAnUnconfirmedPlaceOpensItsCardAndNeverTheMap() {
        let app = open("demo-story-aino")
        let place = bring(app.buttons["card.place"], in: app, "the caption's place")
        XCTAssertEqual(place.label, "Paikka, odottaa tarkistusta: Kotasaari")
        place.tap()
        XCTAssertTrue(app.navigationBars["Kotasaari"].waitForExistence(timeout: 10), "the place did not open its card")
        XCTAssertFalse(app.buttons["Muuta sijaintia"].exists, "an unconfirmed place opened the map")
    }

    /// No line on a place's own card, which is the place, and none on a
    /// card whose tellings name no place.
    func testNoPlaceLineOnAPlaceOrWhereNoPlaceIsNamed() {
        for card in ["demo-story-puumala", "demo-story-eevertti"] {
            let app = open(card)
            require(app.buttons["subject.rename"], "the caption on \(card)", in: app)
            XCTAssertFalse(app.buttons["card.place"].exists, "\(card) has a place line")
            app.terminate()
        }
    }

    /// An English phone reads the story's card in English — the provenance
    /// line, the log's button and the place are looked up, not shown as
    /// their keys.
    func testTheCardReadsInEnglishOnAnEnglishPhone() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-api", "", "-people", "list", "-homecoming", "off",
            "-seed", "story", "-tab", "people", "-screen", "person", "-person", "demo-story-jetty",
            "-story", "stub",
        ]
        app.launch()
        require(story(in: app), "the jetty's story on an English phone", in: app)
        XCTAssertTrue(app.staticTexts["Put together from 3 memories"].exists, "the provenance line is not in English")
        XCTAssertEqual(app.buttons["card.place"].label, "Place: Puumala", "the place is not in English")
        let logs = bring(app.buttons["storyCard.logs"], in: app, "the log's button")
        XCTAssertTrue(logs.label.contains("Show 3 memories"), "the log's button is not in English: \(logs.label)")
    }

    // MARK: - Helpers

    private func open(_ card: String, story: String = "stub", more: [String] = []) -> XCUIApplication {
        launch(["-seed", "story", "-tab", "people", "-screen", "person", "-person", card, "-story", story] + more)
    }

    /// The story's container: its paragraphs are its children.
    private func story(in app: XCUIApplication) -> XCUIElement {
        app.otherElements["storyCard.story"]
    }

    private func storyText(in app: XCUIApplication) -> String {
        story(in: app).staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n\n")
    }

    /// By a prefix: the sentence has a colon in it, which the subscript form
    /// reads as query syntax and refuses.
    private func consentLine(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Tarina kootaan kerrotuista muistoista: ne lähetetään OpenRouter-palvelun kautta")
        ).firstMatch
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ what: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "never arrived: \(what)", file: file, line: line)
        return element
    }

    /// Swipes until the element is on screen and clear of the tab bar, so a
    /// tap lands on it and not on a corner of it (TargetedQuestionTests).
    /// The card is a list, which builds its rows as they come on screen, so
    /// an element below the fold may not exist until it is swiped to.
    @discardableResult
    private func bring(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let bar = app.tabBars.firstMatch
        for _ in 0 ..< 10 {
            if element.waitForExistence(timeout: 3), element.isHittable,
               !(bar.exists && element.frame.midY > bar.frame.minY - 8) {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "never arrived: \(what)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "not on screen: \(what)", file: file, line: line)
        return element
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }
}
