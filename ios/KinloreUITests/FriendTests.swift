import XCTest

/// A friend in the archive (21 Sep 2026): a person card like any other,
/// joined to somebody by a relationship the tree does not draw as kin.
///
/// Where a friend lands in the drawing is `FamilyTreeTests`' question and the
/// layout check's. These ask what the card does: that a friend is added from
/// it and listed on it apart from the relatives — under *Ystävät*, never
/// under *Suku*, since a friend is not suku (ARCHITECTURE §21) — and that
/// taking the friendship back asks in the friendship's own words and takes
/// only the friendship.
final class FriendTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// From Eeva's card: Lisää sukulainen, Lisää ystävä, Joku uusi, a name —
    /// and the friend is on the card under a heading of her own, while the
    /// spouse stays under Suku.
    func testAFriendIsAddedFromTheCardAndListedApart() {
        let app = launch(["-seed", "related", "-tab", "people"])
        let eeva = app.staticTexts["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the people list")
        eeva.tap()
        // A relative's row is one element, "Kalle, Puoliso": the name and
        // what they are to this person, read in one breath — and since
        // 27 Sep 2026 a link to his card, so a button. Reached since the
        // relatives went under the card's tellings (ARCHITECTURE §27): a
        // list builds its rows as they come, and his is below the fold.
        XCTAssertTrue(app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10), "the card")
        let kalle = app.buttons["Kalle, Puoliso"]
        for _ in 0 ..< 4 where !kalle.exists { app.swipeUp() }
        XCTAssertTrue(kalle.waitForExistence(timeout: 10), "the spouse's row")
        XCTAssertFalse(app.staticTexts["Ystävät"].exists, "a heading over no friends")

        addFriend(named: "Ritva", in: app)

        let heading = app.staticTexts["Ystävät"]
        for _ in 0 ..< 4 where !heading.exists { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "the friend has no heading of her own")
        XCTAssertTrue(app.buttons["Ritva, Ystävä"].exists, "the friend is not on the card, or the row does not say what she is")
        XCTAssertTrue(app.buttons["Kalle, Puoliso"].exists, "the spouse is gone, or lost his caption")
    }

    /// Taking a friendship back asks about a friendship, not about kinship,
    /// and takes the friend off the card while the spouse stays.
    func testAFriendshipIsTakenBackInItsOwnWords() {
        let app = launch(["-seed", "related", "-tab", "people"])
        let eeva = app.staticTexts["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the people list")
        eeva.tap()
        XCTAssertTrue(app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10), "the card")
        addFriend(named: "Ritva", in: app)

        let ritva = app.buttons["Ritva, Ystävä"]
        for _ in 0 ..< 4 where !ritva.exists { app.swipeUp() }
        XCTAssertTrue(ritva.waitForExistence(timeout: 10), "the friend is not on the card")
        // In the tree is not on screen. A row under the tab bar is in the tree
        // as well, and a swipe on it lands on the bar, which slides the
        // selection over to Albumi — read from the recording of a failed run
        // on 27 Sep 2026, whose Poista was then looked for on the album. So
        // the card is dragged up, slowly enough to stop where the finger
        // lets go, until her row clears the bar.
        let bar = app.tabBars.firstMatch.frame
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0 ..< 4 where ritva.frame.maxY > bar.minY {
            middle.press(
                forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -200)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
        XCTAssertLessThanOrEqual(ritva.frame.maxY, bar.minY, "the friend's row never came out from under the tab bar")
        ritva.swipeLeft()
        let remove = app.buttons["Poista"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "no way to take the friendship back")
        remove.tap()

        XCTAssertTrue(app.staticTexts["Poistetaanko ystävyys?"].waitForExistence(timeout: 10), "the question is not about a friendship")
        XCTAssertFalse(app.staticTexts["Poistetaanko sukulaisuus?"].exists, "a friend is asked about as kin")
        app.alerts.buttons["Poista"].tap()

        XCTAssertTrue(app.buttons["Kalle, Puoliso"].waitForExistence(timeout: 10), "the spouse went with the friend")
        XCTAssertFalse(ritva.exists, "the friend is still on the card")
        XCTAssertFalse(app.staticTexts["Ystävät"].exists, "an empty heading was left behind")
    }

    /// The card's row, the friend's button on the sheet it opens, and somebody
    /// new by name.
    private func addFriend(named name: String, in app: XCUIApplication) {
        let row = app.buttons["Lisää sukulainen"]
        for _ in 0 ..< 4 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the way to add a relative")
        // Since the relatives became tiles (27 Sep 2026) the row stands
        // under the tab bar on Eeva's card at the default size, and a tap
        // at its centre lands on the bar: the sheet never came, in both
        // tests. `isHittable` answers yes under the glass, so the frames are
        // compared, and the card is dragged up the way the friend's row is
        // before its swipe.
        let bar = app.tabBars.firstMatch.frame
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0 ..< 4 where row.frame.maxY > bar.minY {
            middle.press(
                forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -200)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
        XCTAssertLessThanOrEqual(row.frame.maxY, bar.minY, "the row that adds a relative never came out from under the tab bar")
        row.tap()
        let friend = app.buttons["Lisää ystävä"]
        XCTAssertTrue(friend.waitForExistence(timeout: 10), "the sheet offers no friend")
        friend.tap()

        XCTAssertTrue(app.navigationBars["Kuka on ystävä?"].waitForExistence(timeout: 10), "the picker does not ask for a friend")
        let someoneNew = app.buttons["Joku uusi"]
        XCTAssertTrue(someoneNew.waitForExistence(timeout: 10), "the picker")
        someoneNew.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText(name)
        app.buttons["Tallenna"].tap()
    }
}
