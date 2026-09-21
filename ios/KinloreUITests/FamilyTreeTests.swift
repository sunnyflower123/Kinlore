import XCTest

/// The family tree, on a family member's phone since 13 Sep 2026, and what
/// Ihmiset opens on there.
///
/// Where people land is `scripts/family-tree-layout-check.swift`'s question.
/// These ask what only a running app can answer: that Ihmiset opens on the
/// tree with the whole confirmed family in it and nothing else on the screen,
/// that the list and every other door are behind the one menu button, that a
/// person in the tree opens their card or takes a new relative on the spot,
/// and that a grandparent's phone keeps the list.
///
/// The suite's launch helper passes `-people list`, so the tests written about
/// the list keep testing the list. These pass `-people tree`, or `default` to
/// read what the phone itself would show.
final class FamilyTreeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The fixture's Eeva and Kalle are a confirmed couple, Sanni is related
    /// to nobody and is drawn below them, and Aino is a name heard and never
    /// checked. `-people.showsList NO` reads the phone as nobody has switched
    /// it yet.
    func testIhmisetOpensOnTheTreeWithEverybodyInIt() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "default", "-people.showsList", "NO"])
        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "Ihmiset did not open on the tree")
        XCTAssertTrue(app.tabBars.buttons["Sukupuu"].exists, "the tab is not named for the tree")
        XCTAssertFalse(app.navigationBars["Sukupuu"].exists, "the tree carries a title over the drawing")
        XCTAssertTrue(app.buttons["Kalle"].exists, "Kalle is not in the tree")
        XCTAssertTrue(app.buttons["Sanni"].exists, "somebody related to nobody is not in the picture")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the people related to nobody have no caption")
        XCTAssertFalse(app.buttons["Aino"].exists, "a name nobody has checked is drawn in the tree")
        XCTAssertTrue(app.buttons["Valikko"].exists, "no menu over the tree")
        // Nothing else. Since 19 Sep 2026 the drawing is the screen, and the
        // three doors the list keeps in its bar wait behind the menu.
        XCTAssertFalse(app.buttons["Luettelo"].exists, "the way to the list stands on the tree rather than in the menu")
        XCTAssertFalse(app.buttons["Lisää henkilö"].exists, "the way to add a person stands on the tree rather than in the menu")
        XCTAssertFalse(app.buttons["Asetukset"].exists, "the settings stand on the tree rather than in the menu")
        XCTAssertFalse(app.staticTexts["Sinä"].exists, "somebody is marked as you on a phone linked to no card")
    }

    /// The menu holds everything the tree does not show: the list, a new
    /// person, the settings, and the door to the names heard — with the same
    /// words on it as under the list, so the tree hides nothing the list
    /// shows. And a door chosen in it opens: the sheet goes down first and the
    /// screen is pushed after, which is the one order that works.
    func testTheMenuHoldsEverythingTheTreeDoesNot() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "the tree")
        app.buttons["Valikko"].tap()
        XCTAssertTrue(app.buttons["Luettelo"].waitForExistence(timeout: 10), "the menu has no way to the list")
        XCTAssertTrue(app.buttons["Lisää henkilö"].exists, "the menu has no way to add a person")
        XCTAssertTrue(app.buttons["Asetukset"].exists, "the menu has no way to the settings")
        XCTAssertTrue(app.staticTexts["Mitä viivat tarkoittavat"].exists, "the menu does not say what the lines mean")
        let door = app.buttons["1 nimi odottaa tarkistusta"]
        XCTAssertTrue(door.exists, "the name heard and never checked has no door in the menu")
        door.tap()
        XCTAssertTrue(app.navigationBars["Kuullut nimet"].waitForExistence(timeout: 10), "the door to the names heard did not open")
    }

    /// The card this phone's member is linked to says so. `-you` links the
    /// demo family's "you" to Eeva's card, as `PATCH /family/me` does for real.
    func testYourOwnCardSaysItIsYou() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree", "-you", "demo-eeva"])
        XCTAssertTrue(app.buttons["Eeva, sinä"].waitForExistence(timeout: 10), "your card does not say it is you")
        XCTAssertTrue(app.staticTexts["Sinä"].exists, "no word under your name")
        XCTAssertTrue(app.buttons["Kalle"].exists, "somebody else was marked as you as well")
    }

    /// The list is two taps away through the menu and the tree one tap back,
    /// whichever the phone was left on, and the list is titled while the tree
    /// is not. Ends on the tree, which is where a phone starts.
    func testTheListAndTheTreeAreATapOrTwoApart() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "default"])
        // On the list the tab says Ihmiset, so this is the bar's button alone.
        let toTree = app.buttons["Sukupuu"]
        let menu = app.buttons["Valikko"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10) || toTree.exists, "Ihmiset")
        if !menu.exists { toTree.tap() }

        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the tree")
        XCTAssertFalse(app.navigationBars["Sukupuu"].exists, "the tree is titled over the drawing")
        menu.tap()
        let toList = app.buttons["Luettelo"]
        XCTAssertTrue(toList.waitForExistence(timeout: 10), "the menu has no way to the list")
        toList.tap()

        XCTAssertTrue(toTree.waitForExistence(timeout: 10), "the list did not open, or has no way back to the tree")
        XCTAssertTrue(app.navigationBars["Ihmiset"].exists, "the list is not titled Ihmiset")
        XCTAssertTrue(app.staticTexts["Eeva"].exists, "the list has nobody on it")
        XCTAssertFalse(menu.exists, "the tree's menu is over the list")
        toTree.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the tree did not come back")
    }

    /// A person in the tree opens their card from their sheet.
    func testAPersonInTheTreeOpensTheirCard() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        let kalle = app.buttons["Kalle"]
        XCTAssertTrue(kalle.waitForExistence(timeout: 10), "the tree")
        kalle.tap()

        let open = app.buttons["Avaa kortti"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the person's sheet in the tree")
        open.tap()
        XCTAssertTrue(app.navigationBars["Kalle"].waitForExistence(timeout: 10), "the card did not open")
    }

    /// A relative added from the tree: a child for Eeva, somebody new, typed in
    /// and drawn in the tree without leaving it.
    func testARelativeIsAddedWithoutLeavingTheTree() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        let eeva = app.buttons["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the tree")
        eeva.tap()

        let child = app.buttons["Lisää lapsi"]
        XCTAssertTrue(child.waitForExistence(timeout: 10), "the person's sheet in the tree")
        child.tap()

        let someoneNew = app.buttons["Joku uusi"]
        XCTAssertTrue(someoneNew.waitForExistence(timeout: 10), "the relative picker")
        someoneNew.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the name field")
        field.tap()
        field.typeText("Helmi")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(app.buttons["Helmi"].waitForExistence(timeout: 10), "the new child is not in the tree")
        XCTAssertTrue(app.buttons["Valikko"].exists, "adding a relative left the tree")
    }

    /// The two zoom buttons are the way for a hand that cannot pinch, and the
    /// tree has to survive both ends of them.
    func testTheTreeZoomsBothWays() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "the tree did not open")
        let larger = app.buttons["Suurenna"]
        let smaller = app.buttons["Pienennä"]
        XCTAssertTrue(larger.exists && smaller.exists, "the zoom buttons")
        for _ in 0 ..< 6 { larger.tap() }
        XCTAssertTrue(app.buttons["Eeva"].exists, "Eeva is gone at the largest zoom")
        for _ in 0 ..< 12 { smaller.tap() }
        XCTAssertTrue(app.buttons["Kalle"].exists, "Kalle is gone at the smallest zoom")
        // Every tap has to land on the button it was aimed at. While the
        // buttons scrolled with the tree, a tap landed on the door to the
        // names heard instead, and the test ended on that screen.
        XCTAssertTrue(app.buttons["Valikko"].exists, "a zoom tap opened another screen")
    }

    /// A grandparent's phone keeps the list: no picture of lines, and no way to
    /// one — including on the tab bar, which on her phone keeps the older word
    /// rather than naming a tree she is never shown.
    func testAGrandparentsPhoneKeepsTheList() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "default", "-elder.largerText", "YES"])
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the people list")
        XCTAssertTrue(app.navigationBars["Ihmiset"].exists, "a grandparent's list is not titled Ihmiset")
        XCTAssertTrue(app.tabBars.buttons["Ihmiset"].exists, "her tab does not say Ihmiset")
        XCTAssertFalse(app.buttons["Sukupuu"].exists, "the tree is offered on a grandparent's phone")
        XCTAssertFalse(app.buttons["Valikko"].exists, "the tree is shown on a grandparent's phone")
    }

    /// The tab bar is the only name the app gives itself before it is touched,
    /// and until 19 Sep 2026 it said "Ihmiset" over a screen titled "Sukupuu".
    /// One decision now answers both, so the tab follows the view the phone is
    /// on — including back to the older word when the list is chosen.
    /// No `-people.showsList` in this one, unlike the tests above: a value in
    /// the argument domain outranks whatever the app writes, so the switch
    /// would move the screen while the tab bar kept reading the launch
    /// argument. That is a fault of the harness and it looked exactly like a
    /// fault of the app. So this starts from whichever view the phone was left
    /// on, and asserts the pair rather than a word.
    func testTheTabIsNamedForTheScreenItOpens() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "default"])
        let menu = app.buttons["Valikko"]
        let toTree = app.tabBars.buttons["Sukupuu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10) || app.buttons["Sukupuu"].exists, "Ihmiset")
        if !menu.exists { app.buttons["Sukupuu"].tap() }

        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the tree")
        XCTAssertTrue(toTree.exists, "the tab does not name the tree it opens")
        XCTAssertFalse(app.tabBars.buttons["Ihmiset"].exists, "the tab still says Ihmiset over the tree")

        menu.tap()
        let toList = app.buttons["Luettelo"]
        XCTAssertTrue(toList.waitForExistence(timeout: 10), "the menu has no way to the list")
        toList.tap()
        XCTAssertTrue(app.tabBars.buttons["Ihmiset"].waitForExistence(timeout: 10), "the tab kept the tree's name over the list")
        XCTAssertFalse(toTree.exists, "two words for one tab")

        // Back to the tree, which is where a phone starts.
        app.buttons["Sukupuu"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the tree did not come back")
    }

    /// A friend is in the picture and apart from it (21 Sep 2026): under the
    /// generations and over the people related to nobody, with a caption of
    /// its own and no line, because a friend is not a generation. `-seed
    /// clan` has Jonne, Elina's friend and nobody's kin — and Rauha, Helmi's
    /// sister as well as her friend, whom the kinship places.
    func testAFriendIsDrawnApartUnderItsOwnCaption() {
        let app = launch(["-seed", "clan", "-tab", "people", "-people", "tree", "-you", "clan-elina"])
        let friends = app.staticTexts["Ystävät"]
        XCTAssertTrue(friends.waitForExistence(timeout: 20), "the friends have no caption")
        let jonne = app.buttons["Jonne"]
        XCTAssertTrue(jonne.exists, "the friend is not in the picture")
        let loose = app.staticTexts["Ei vielä sukupuussa"]
        XCTAssertTrue(loose.exists, "the people related to nobody lost their caption")
        XCTAssertLessThan(friends.frame.minY, jonne.frame.minY, "the friend stands above his own caption")
        XCTAssertLessThan(jonne.frame.minY, loose.frame.minY, "the friend is among the people related to nobody")
        let rauha = app.buttons["Rauha"]
        XCTAssertTrue(rauha.exists, "somebody's kin is missing")
        XCTAssertLessThan(rauha.frame.minY, friends.frame.minY, "somebody's kin is drawn among the friends")
    }

    /// And no caption over nobody: the fixture of five has no friend in it.
    func testTheFriendsCaptionWaitsForAFriend() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "the tree")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the caption over the people related to nobody")
        XCTAssertFalse(app.staticTexts["Ystävät"].exists, "a caption over no friends")
    }
}
