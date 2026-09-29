import XCTest

/// A relative on a person's card is a way to that relative's own card
/// (27 Sep 2026). Until then the row said who somebody was and led nowhere:
/// Matti's card named his father, and the way to his father's card was back
/// to the list and down it by name — on a grandparent's phone, where no tree
/// is drawn, the only way there was.
///
/// And the caption under a name says what that one person is, *Vanhempi*
/// and not *Vanhemmat*: every row is one person, and VoiceOver reads the
/// name and the caption as one phrase.
final class RelativeRowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Matti's card in the clan: two parents, two children and a third child
    /// nobody has confirmed, and a spouse. Every confirmed row is a
    /// link under a caption in the singular. The proposal stays the row it
    /// was, with its *Vahvista*, and leads nowhere: a card reached through a
    /// guess is the guess drawn as fact (rule 4). His father's row opens his
    /// father's card, which names Matti as a child, and back is Matti's card.
    func testARelativesRowOpensTheirCard() {
        let app = launch(["-seed", "clan", "-tab", "people", "-screen", "person", "-person", "clan-matti"])
        XCTAssertTrue(app.navigationBars["Matti"].waitForExistence(timeout: 10), "Matti's card")

        let father = app.buttons["Toivo, Vanhempi"]
        reach(father, in: app)
        XCTAssertTrue(father.exists, "the father's row is not a way to his card, or its caption is not one parent")
        bringAboveTheTabBar(father, in: app)
        father.tap()
        XCTAssertTrue(app.navigationBars["Toivo"].waitForExistence(timeout: 10), "the row did not open Toivo's card")
        let son = app.buttons["Matti, Lapsi"]
        reach(son, in: app)
        XCTAssertTrue(son.exists, "Toivo's card does not lead back to his son")
        app.navigationBars["Toivo"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Matti"].waitForExistence(timeout: 10), "back did not return to Matti's card")

        // The rest of the card, top to bottom in the order the groups stand.
        for label in ["Anneli, Vanhempi", "Elina, Lapsi", "Jukka, Lapsi"] {
            let row = app.buttons[label]
            reach(row, in: app)
            XCTAssertTrue(row.exists, "no link reads \"\(label)\"")
        }
        let proposal = app.staticTexts["Eeva, Lapsi"]
        reach(proposal, in: app)
        XCTAssertTrue(proposal.exists, "the proposed child is not on the card as a proposal")
        XCTAssertFalse(app.buttons["Eeva, Lapsi"].exists, "a proposal leads to the card it is a guess about")
        XCTAssertTrue(app.buttons["Vahvista"].exists, "the proposal lost its Vahvista")
        let spouse = app.buttons["Ritva, Puoliso"]
        reach(spouse, in: app)
        XCTAssertTrue(spouse.exists, "no link reads \"Ritva, Puoliso\"")
    }

    /// *Lisää sukulainen* at the top of a person's card (30 Sep 2026): on
    /// the screen the card opens on, above the story, and the card's only
    /// one. Until then it stood at the foot of the relatives, under the
    /// story and its tellings, and the card of a name just confirmed — which
    /// says the person gets a place in the tree once a relative is added —
    /// had to be scrolled to find it. Toivo's card in `-seed story` has a
    /// story and nobody related to him; a spouse is added through the
    /// button, and she is listed under the story with no second way to add
    /// a relative beside her, where the old row stood.
    func testTheWayToAddARelativeStandsAboveTheStoryOnce() {
        let app = launch([
            "-seed", "story", "-tab", "people", "-screen", "person", "-person", "demo-story-toivo", "-story", "stub",
        ])
        XCTAssertTrue(app.navigationBars["Toivo"].waitForExistence(timeout: 10), "Toivo's card")
        let add = app.buttons["Lisää sukulainen"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no way to add a relative on the card as it opens")
        XCTAssertEqual(adds(in: app).count, 1, "more than one way to add a relative on the card")
        let bar = app.tabBars.firstMatch.frame
        XCTAssertLessThanOrEqual(add.frame.maxY, bar.minY, "the button is not on the screen the card opens on: \(add.frame), tab bar at \(bar.minY)")

        // Above the story: the button dragged to the top of the screen, so
        // that the story under it is drawn too, and the two frames compared.
        let top = app.navigationBars.firstMatch.frame.maxY
        let story = app.otherElements["storyCard.story"]
        for _ in 0 ..< 3 where !story.exists && add.frame.minY > top + 40 {
            let start = add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -min(200, add.frame.minY - top - 16))),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
        XCTAssertTrue(story.waitForExistence(timeout: 10), "the story is not on screen under the button")
        XCTAssertTrue(add.exists, "the button left the screen before the story came onto it")
        XCTAssertLessThanOrEqual(add.frame.maxY, story.frame.minY, "the button is not above the story: button \(add.frame), story \(story.frame)")

        // A spouse through the button, and her row under the story.
        add.tap()
        let spouse = app.buttons["Lisää puoliso"]
        XCTAssertTrue(spouse.waitForExistence(timeout: 10), "the button opened no sheet of relatives")
        spouse.tap()
        let someoneNew = app.buttons["Joku uusi"]
        XCTAssertTrue(someoneNew.waitForExistence(timeout: 10), "the picker")
        someoneNew.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText("Aili")
        app.buttons["Tallenna"].tap()

        let row = app.buttons["Aili, Puoliso"]
        reach(row, in: app)
        XCTAssertTrue(row.exists, "the spouse added through the button is not on the card")
        for other in adds(in: app) {
            XCTAssertLessThan(
                other.frame.maxY, row.frame.minY,
                "a way to add a relative stands among the relatives again: \(other.frame), the spouse's row \(row.frame)"
            )
        }
    }

    /// Every button on screen that adds a relative.
    private func adds(in app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label == %@", "Lisää sukulainen")).allElementsBoundByIndex
    }

    /// Scrolls down until the element is there. A list does not build the
    /// rows nobody can see, and every row this test asks for stands below
    /// the one before it.
    private func reach(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 6 where !element.exists { app.swipeUp() }
    }

    /// A row under the tab bar is in the tree as well, and a tap at its
    /// centre lands on the bar (`FriendTests`); `isHittable` answers yes
    /// under the glass, so the frames are compared. Dragged slowly, so the
    /// card stops where the finger lets go.
    private func bringAboveTheTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        let bar = app.tabBars.firstMatch.frame
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0 ..< 4 where element.frame.maxY > bar.minY {
            middle.press(
                forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -200)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
        XCTAssertLessThanOrEqual(element.frame.maxY, bar.minY, "the row never came out from under the tab bar")
    }
}
