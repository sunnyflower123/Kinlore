import XCTest

/// Correcting a name after the telling is over.
///
/// The Tell screen's correction is the good moment and it was the only one.
/// Speech recognition is wrong about one proper noun in three, so a name missed
/// there used to be a wrong person in the family tree for good — and the
/// guessing round could then confirm that wrong person as fact. This is the way
/// back out, and it is worth a test that presses the buttons: the write itself
/// is `MemoryStore.rename`, which is well covered by the merge rules, but
/// nothing before this checked that a person can reach it.
final class NameCorrectionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The interview's rounds each propose names, and the loop-end result
    /// screen is their one at-telling correction moment. An assignment in
    /// `save` used to replace the list every round, so only the last round's
    /// names ever met "Kuulinko nimet oikein?" — the opening telling's people
    /// skipped this screen entirely, and their backstop was the person list.
    ///
    /// `-screen interviewed` runs the loop hands-free to its result: the
    /// typed opening mentions Kuopio (the stub reads names mid-sentence only,
    /// so Eevert — who opens his sentence — is never extracted), and the
    /// first recorded round rotates to the sample that mentions Aino. One
    /// name from each round must stand in the editable rows. The second round
    /// records for real, which is why the microphone prompt is answered here.
    func testInterviewRoundsAllReachTheNameCheck() throws {
        let app = launch(["-seed", "empty", "-screen", "interviewed"])
        allowTheMicrophone()

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 60),
            "the interview never reached its result screen"
        )

        let opening = app.textFields.matching(
            NSPredicate(format: "value == %@", "Kuopiossa")
        ).firstMatch
        let recorded = app.textFields.matching(
            NSPredicate(format: "value == %@", "Aino")
        ).firstMatch
        for _ in 0 ..< 4 where !opening.exists { app.swipeUp() }
        XCTAssertTrue(
            opening.waitForExistence(timeout: 10),
            "the opening telling's name skipped the check"
        )
        XCTAssertTrue(
            recorded.exists || recorded.waitForExistence(timeout: 5),
            "the recorded round's name is missing from the check"
        )
    }

    /// Answers the microphone prompt if it appears. The interviewed loop's
    /// first recording raises it a few seconds into the run, so this waits
    /// longer than the sibling in TakingBackTests.
    private func allowTheMicrophone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 20) else { return }
        let buttons = alert.buttons
        guard buttons.count > 0 else { return }
        buttons.element(boundBy: buttons.count - 1).tap()
    }

    func testACorrectedNameShowsOnTheCard() throws {
        let app = launch(["-seed", "archive", "-tab", "people"])

        let person = app.cells.firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10), "the people list")
        // The card is named after whoever the seed put first; the correction is
        // made relative to that rather than to a hard-coded name, so the test
        // does not break the next time the fixture changes.
        person.tap()

        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        let original = field.value as? String ?? ""
        XCTAssertFalse(original.isEmpty, "the field starts with the name it is correcting")

        // Appended rather than retyped: clearing a field is fiddly and proves
        // nothing extra, and the point is that what is typed reaches the card.
        field.tap()
        field.typeText("nen")
        app.buttons["Tallenna"].tap()
        // A telling whose words say the name keeps the sheet up for a step
        // that says so (§17), and whether the fixture's first person has one
        // is the fixture's business too.
        let done = app.buttons["Valmis"]
        if done.waitForExistence(timeout: 5) { done.tap() }

        let corrected = original + "nen"
        XCTAssertTrue(
            app.navigationBars[corrected].waitForExistence(timeout: 10),
            "the card shows the corrected name, not the one it was pushed with"
        )
    }

    /// A correction that lands on somebody the family already has is a merge:
    /// the two cards become one and this one's memories move across. It used to
    /// happen on the same tap as an ordinary rename, warned about only by a
    /// footer — and unlike a rename, nothing in the app undoes it.
    /// A merge carries the relationships across. Until 4 Sep 2026 it moved
    /// the memories and the mentions and left every edge pointing at the
    /// tombstone, so a confirmed spouse vanished from the survivor's tree the
    /// moment a name was tidied — in the one flow that exists to keep the
    /// tree right.
    func testAMergeKeepsTheRelationships() throws {
        // The fixture with Eeva and Kalle as spouses.
        let app = launch(["-seed", "related", "-tab", "people"])

        let eeva = app.staticTexts["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the people list")
        eeva.tap()
        XCTAssertTrue(app.buttons["Kalle, Puoliso"].waitForExistence(timeout: 10), "the fixture's relationship is not on the card")

        // Then Eeva's name is corrected onto Aino, and the cards merge.
        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Aino")
        app.buttons["Tallenna"].tap()
        XCTAssertTrue(app.staticTexts["Yhdistetäänkö kortit?"].waitForExistence(timeout: 10), "the merge did not ask")
        app.buttons["Yhdistä"].tap()
        // Mummo's telling says "Eeva", so the sheet says whose words those
        // are before it goes (`testAMergeAsksBeforeItHappens` reads it).
        let done = app.buttons["Valmis"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the sheet's last step never came")
        done.tap()
        XCTAssertTrue(app.navigationBars["Ihmiset"].waitForExistence(timeout: 10), "the merged card stayed open")

        // Aino's card now holds the spouse Eeva had.
        let aino = app.staticTexts["Aino"]
        XCTAssertTrue(aino.waitForExistence(timeout: 10), "Aino is not on the list")
        aino.tap()
        // The row is one element since 21 Sep 2026: the name and the caption
        // in one label, "Kalle, Puoliso", and a link to his card since
        // 27 Sep 2026.
        let spouse = app.buttons["Kalle, Puoliso"]
        for _ in 0 ..< 4 where !spouse.exists { app.swipeUp() }
        XCTAssertTrue(spouse.waitForExistence(timeout: 10), "the spouse did not follow the merge, or is somebody else")
    }

    /// A familiar name can be told apart at the moment of telling. The fixture
    /// knows Toivo; the canned telling names him; "Eri henkilö" makes a fresh
    /// proposal of the same name, where it can be renamed and confirmed.
    func testAFamiliarNameCanBeToldApart() throws {
        let app = launch(["-seed", "related", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "never arrived: the result screen")

        let familiar = app.staticTexts["Tutut nimet"]
        for _ in 0 ..< 4 where !familiar.exists { app.swipeUp() }
        XCTAssertTrue(familiar.waitForExistence(timeout: 10), "the familiar names are not shown")
        let other = app.buttons["Eri henkilö kuin Toivo"]
        XCTAssertTrue(other.waitForExistence(timeout: 10), "Toivo was not offered as possibly another person")
        other.tap()

        // A second Toivo, unconfirmed, in the name check — and the familiar
        // row is gone, because there is nothing familiar left to tell apart.
        let proposal = app.textFields.matching(NSPredicate(format: "value == %@", "Toivo")).firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 10), "the split name did not become a proposal")
        XCTAssertTrue(other.waitForNonExistence(timeout: 10), "the familiar row stayed after the split")
    }

    func testAMergeAsksBeforeItHappens() throws {
        let app = launch(["-seed", "archive", "-tab", "people"])

        // Eeva by name rather than by position: the merge needs a *second*
        // person to land on, and which of them is first in the list is the
        // fixture's business.
        let eeva = app.staticTexts["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the people list")
        eeva.tap()

        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        // Cleared this time, because the point is landing exactly on a name the
        // family already has.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Aino")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.staticTexts["Yhdistetäänkö kortit?"].waitForExistence(timeout: 10),
            "the merge happened without asking"
        )
        app.buttons["Yhdistä"].tap()

        // The fixture's one telling about Eeva is Mummo's and says her name.
        // Only Mummo's phone can change its words, so there is nothing to
        // offer, and the sheet says why the story will still read "Eeva"
        // instead of closing on it (28 Sep 2026, §17).
        XCTAssertTrue(
            app.staticTexts[
                "Yksi muisto, jossa nimi lukee, on tallennettu toisen puhelimella. Sen tekstiä voi muuttaa vain se, joka sen tallensi."
            ].waitForExistence(timeout: 10),
            "the sheet closed without saying whose words still say the old name"
        )
        XCTAssertFalse(app.buttons["Korjaa nimi myös muistoon"].exists, "an offer for words this phone cannot change")
        app.buttons["Valmis"].tap()

        // The card is a tombstone now and there is nothing left to look at, so
        // the screen goes back to the list — where there is one Aino and no
        // Eeva.
        XCTAssertTrue(
            app.navigationBars["Ihmiset"].waitForExistence(timeout: 10),
            "the merged card stayed open"
        )
        XCTAssertFalse(app.staticTexts["Eeva"].exists, "the merged person is still listed")
    }

    /// Nothing to save is nothing to press. Without this the sheet would happily
    /// write the name it already had, which is a no-op that still marks the row
    /// for sync and confuses the ordering counter for no reason.
    func testSavingIsRefusedUntilSomethingChanges() throws {
        let app = launch(["-seed", "archive", "-tab", "people"])

        let person = app.cells.firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 10))
        person.tap()

        let correct = app.buttons["Korjaa nimi"]
        XCTAssertTrue(correct.waitForExistence(timeout: 10))
        correct.tap()

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertFalse(save.isEnabled, "unchanged name, nothing to save")
    }

    /// A name confirmed as it was heard, noticed in a story and corrected from
    /// there, words and all (28 Sep 2026, ARCHITECTURE §17). `-seed misheard`
    /// has "Hilda", where the tellers meant Hilma, in three tellings: two of
    /// this phone's own — one under the photograph, one on her card — and one
    /// of Mummo's. The reader starts where a wrong name is noticed, in the
    /// photograph's story, and the name under it is the way to her card.
    /// Until this day a checked name in a story led nowhere, and the card's
    /// correction left every story saying the old name.
    ///
    /// The offer says how many, and the tap rewrites this phone's own and
    /// nothing else: Mummo's words are hers, and the server takes a telling's
    /// text only from whoever saved it.
    func testANameReadInAStoryIsCorrectedWordsAndAll() throws {
        let app = launch(["-seed", "misheard", "-tab", "memories"])

        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "the photograph's tile")
        tile.tap()
        let story = app.staticTexts["Hilda souti meidät saareen, ja Hildan kahvipannu kulki aina mukana."]
        reach(story, in: app, "the story that says the misheard name")
        // The name is a chip of its own and the words are only words: as a
        // `NavigationLink` the chip took the whole row, and a tap on the
        // story opened her card.
        story.tap()
        XCTAssertFalse(app.navigationBars["Hilda"].waitForExistence(timeout: 2), "a tap on the story's words opened a card")
        let name = app.buttons["Hilda"]
        reach(name, in: app, "the name under the story, as the way to her card")
        name.tap()
        XCTAssertTrue(app.navigationBars["Hilda"].waitForExistence(timeout: 10), "the name did not open her card")

        correctTheName(to: "Hilma", in: app)

        // Counted and said, and nothing rewritten before the tap.
        XCTAssertTrue(app.staticTexts["Nimi on nyt Hilma."].waitForExistence(timeout: 10), "the offer never came")
        XCTAssertTrue(app.staticTexts["2 muistossa lukee yhä Hilda."].exists, "the offer does not say how many")
        XCTAssertTrue(
            app.staticTexts[
                "Yksi muisto, jossa nimi lukee, on tallennettu toisen puhelimella. Sen tekstiä voi muuttaa vain se, joka sen tallensi."
            ].exists,
            "the offer does not account for Mummo's telling"
        )
        app.buttons["Korjaa nimi myös muistoihin"].tap()
        XCTAssertTrue(
            app.staticTexts["Nimi korjattiin 2 muistoon."].waitForExistence(timeout: 30),
            "the words were not corrected, or the sheet did not say so"
        )
        app.buttons["Valmis"].tap()

        XCTAssertTrue(app.navigationBars["Hilma"].waitForExistence(timeout: 10), "the card does not carry the corrected name")
        // The stub replaces the name's letters, which is enough to see that
        // the words went through the correction; the model inflects.
        reach(app.staticTexts["Hilmalla oli sininen huivi."], in: app, "her own telling, corrected")
        reach(app.staticTexts["Hilda lauloi rannalla."], in: app, "Mummo's telling, as Mummo left it")
        XCTAssertFalse(app.staticTexts["Hildalla oli sininen huivi."].exists, "her own telling kept the old name")

        // And the story it all started from.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reach(
            app.staticTexts["Hilma souti meidät saareen, ja Hilman kahvipannu kulki aina mukana."],
            in: app, "the photograph's story, corrected"
        )
    }

    /// Words change on the tap and on nothing else: saved and then left as
    /// they were, the card has the new name and the stories their old words.
    func testLeavingTheWordsAloneLeavesThem() throws {
        let app = launch(["-seed", "misheard", "-tab", "people", "-screen", "person", "-person", "demo-hilda"])
        XCTAssertTrue(app.navigationBars["Hilda"].waitForExistence(timeout: 15), "her card")

        correctTheName(to: "Hilma", in: app)
        let leave = app.buttons["Jätä teksti ennalleen"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10), "the offer never came")
        leave.tap()

        XCTAssertTrue(app.navigationBars["Hilma"].waitForExistence(timeout: 10), "the card does not carry the corrected name")
        reach(app.staticTexts["Hildalla oli sininen huivi."], in: app, "her own telling, as it was")
    }

    /// A name typed into a row of the result and then ticked is the name as
    /// typed. Until 28 Sep 2026 the tick confirmed the name as heard and
    /// dropped what was typed, with nothing on the screen to say so:
    /// "Toivonen" typed, the tick, and "Toivo" in the family.
    func testATickConfirmsTheNameAsTyped() throws {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 40), "never arrived: the result screen")

        let field = app.textFields.matching(NSPredicate(format: "value == %@", "Toivo")).firstMatch
        for _ in 0 ..< 6 where !(field.exists && field.isHittable) { app.swipeUp() }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the heard name's row")
        field.tap()
        field.typeText("nen")
        // The keyboard's own last key, done, so the tick is not under the keys.
        app.keyboards.buttons.element(boundBy: app.keyboards.buttons.count - 1).tap()

        let tick = app.buttons["Vahvista Toivonen"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "the tick does not say the name it confirms")
        tick.tap()

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(app.staticTexts["Toivonen"].waitForExistence(timeout: 15), "the typed name is not in the family")
        XCTAssertFalse(app.staticTexts["Toivo"].exists, "the name as heard is in the family")
    }

    /// Scrolls until the element is there, and then insists that it is.
    private func reach(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        for _ in 0 ..< 6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "never arrived: \(what)")
    }

    /// The card's pencil, the name cleared and typed anew, and saved. The
    /// return key lets the keyboard go first, as a person would.
    private func correctTheName(to name: String, in app: XCUIApplication) {
        let correct = app.buttons["Korjaa nimi"]
        for _ in 0 ..< 4 where !correct.exists { app.swipeUp() }
        XCTAssertTrue(correct.waitForExistence(timeout: 10), "the correction button")
        correct.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + name + "\n")
        app.buttons["Tallenna"].tap()
    }
}
