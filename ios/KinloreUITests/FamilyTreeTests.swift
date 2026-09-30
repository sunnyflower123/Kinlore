import XCTest

/// The family tree, on a family member's phone since 13 Sep 2026, and what
/// Ihmiset opens on there — rebuilt from zero on 25 Sep 2026, with a word on
/// every card in place of a rail of generation words pinned to the window.
///
/// Where people land is `scripts/family-tree-layout-check.swift`'s question,
/// and which word a card gets is `scripts/kinship-check.swift`'s. These ask
/// what only a running app can answer: that Ihmiset opens on the tree with
/// the whole confirmed family in it and nothing else on the screen but the
/// menu and the gear to Settings, that the list and every other door are
/// behind the menu, that a person in the tree opens their card or takes a
/// new relative on the spot, that every word is inside the drawing, that the
/// picture zooms under two fingers and keeps its people as tap targets at
/// the smallest size, that a phone linked to no card opens on the oldest
/// generation and not on paper, and that a grandparent's phone keeps the
/// list.
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
        XCTAssertTrue(app.buttons["Koko suku"].exists, "no way to fit the whole family")
        // Nothing else. The drawing is the screen, and the doors the list
        // keeps in its bar wait behind the menu — all but the gear, over the
        // tree since 30 Sep 2026 and in the menu as well.
        XCTAssertFalse(app.buttons["Luettelo"].exists, "the way to the list stands on the tree rather than in the menu")
        XCTAssertFalse(app.buttons["Lisää henkilö"].exists, "the way to add a person stands on the tree rather than in the menu")
        XCTAssertTrue(app.buttons["settings"].exists, "the tree has no gear, which the list has")
        // A phone linked to no card has nobody to say *Sinä* about, and no
        // card to fly home to.
        XCTAssertFalse(app.staticTexts["Sinä"].exists, "somebody is marked as you on a phone linked to no card")
        XCTAssertFalse(app.buttons["Sinä"].exists, "a way to your own card on a phone linked to no card")
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
        // The menu's row, and not the gear on the bar beneath the sheet.
        let settingsRow = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "Asetukset", "settings")
        ).firstMatch
        XCTAssertTrue(settingsRow.exists, "the menu has no way to the settings")
        XCTAssertTrue(app.staticTexts["Mitä viivat tarkoittavat"].exists, "the menu does not say what the lines mean")
        let door = app.buttons["1 nimi odottaa tarkistusta"]
        XCTAssertTrue(door.exists, "the name heard and never checked has no door in the menu")
        door.tap()
        XCTAssertTrue(app.navigationBars["Kuullut nimet"].waitForExistence(timeout: 10), "the door to the names heard did not open")
    }

    /// The card this phone's member is linked to says so, and every other
    /// card says what that person is to them: Kalle is Eeva's husband, so
    /// his card reads *Puolisosi*, and Sanni is related to nobody and gets no
    /// word — a wrong relationship is worse than a missing one. `-you` links
    /// the demo family's "you" to Eeva's card, as `PATCH /family/me` does for
    /// real. The words are read inside each card's own button: *Sinä* is
    /// also the name of the button that flies home.
    func testYourOwnCardSaysItIsYouAndTheOthersSayWhatTheyAreToYou() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree", "-you", "demo-eeva"])
        let eeva = app.buttons["Eeva, sinä"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "your card does not say it is you")
        XCTAssertTrue(eeva.staticTexts["Sinä"].exists, "no word under your name")
        let kalle = app.buttons["Kalle"]
        XCTAssertTrue(kalle.exists, "somebody else was marked as you as well")
        XCTAssertTrue(kalle.staticTexts["Puolisosi"].exists, "your husband's card does not say what he is to you")
        let sanni = app.buttons["Sanni"]
        XCTAssertTrue(sanni.exists, "somebody related to nobody is not in the picture")
        XCTAssertEqual(sanni.staticTexts.count, kalle.staticTexts.count - 1,
                       "somebody related to nobody was given a word")
        XCTAssertTrue(app.buttons["Sinä"].exists, "no way to your own card")
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
        // The fixture gives Kalle one memory, and the sheet says so before
        // the card is opened — the count the person list shows under him.
        XCTAssertTrue(app.staticTexts["1 muisto"].exists, "the sheet does not say how much the archive holds about Kalle")
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

    /// The drawing zooms under two fingers, and the people survive both ends
    /// of it. Zoomed in, a name is drawn larger. Zoomed out past 0.65 the
    /// names are not drawn at all and the discs stay, each still a tap
    /// target — a name at that size is ink in the shape of a word. And
    /// *Koko suku* brings a family that fits the window back to its natural
    /// size, names and all.
    func testTheTreeZoomsUnderTwoFingersAndKeepsItsPeople() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        let eeva = app.buttons["Eeva"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the tree did not open")
        let map = app.scrollViews.firstMatch
        XCTAssertTrue(map.exists, "the drawing is not in a scroll view")
        let name = app.staticTexts["Eeva"].frame.height

        map.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "Eeva's name is gone after zooming in")
        XCTAssertGreaterThan(app.staticTexts["Eeva"].frame.height, name * 1.5, "the name did not grow with the pinch")
        // The fingers of a pinch land on cards more often than not, and
        // the cards' presses run on through it: measured as two taps and
        // a sheet where a zoom should have been.
        XCTAssertFalse(app.buttons["Avaa kortti"].exists, "a pinch that began on two cards opened a sheet")

        map.pinch(withScale: 0.2, velocity: -1)
        XCTAssertTrue(app.staticTexts["Eeva"].waitForNonExistence(timeout: 10), "a name is still drawn at the smallest zoom")
        XCTAssertTrue(eeva.exists, "Eeva is gone at the smallest zoom")
        XCTAssertTrue(app.buttons["Kalle"].exists, "Kalle is gone at the smallest zoom")
        XCTAssertGreaterThanOrEqual(eeva.frame.width, 44, "a place is too narrow to tap at the smallest zoom")
        XCTAssertGreaterThanOrEqual(eeva.frame.height, 44, "a place is too short to tap at the smallest zoom")

        app.buttons["Koko suku"].tap()
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the names did not come back when the family was fitted")
        XCTAssertEqual(app.staticTexts["Eeva"].frame.height, name, accuracy: 1, "a family that fits the window is not drawn at its natural size")
        XCTAssertTrue(app.buttons["Valikko"].exists, "zooming opened another screen")
    }

    /// Every word is inside the drawing, in the card it is about. The shape
    /// before this one pinned the generation words to the window's edge over
    /// a drawing that moved under them, and on a 375-point phone the words
    /// stood over the names in any family wider than a place and a half.
    /// Nothing is pinned now: *Sinä* is inside your own card's frame and
    /// *Puolisosi* inside your husband's, and both are descendants of the
    /// scroll view that carries the drawing.
    func testEveryWordIsInsideTheDrawing() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree", "-you", "demo-eeva"])
        let eeva = app.buttons["Eeva, sinä"]
        XCTAssertTrue(eeva.waitForExistence(timeout: 10), "the tree did not open")
        let map = app.scrollViews.firstMatch
        XCTAssertTrue(map.buttons["Eeva, sinä"].exists, "your card is not inside the drawing")
        let you = eeva.staticTexts["Sinä"]
        XCTAssertTrue(you.exists, "no word under your name")
        XCTAssertTrue(eeva.frame.contains(you.frame), "the word under your name stands outside your card")
        let kalle = app.buttons["Kalle"]
        let word = kalle.staticTexts["Puolisosi"]
        XCTAssertTrue(word.exists, "no word under your husband's name")
        XCTAssertTrue(kalle.frame.contains(word.frame), "the word stands outside the card it is about")
        XCTAssertTrue(map.staticTexts["Puolisosi"].exists, "the word is not inside the drawing")
        XCTAssertFalse(word.frame.intersects(eeva.frame), "your husband's word stands over your own card")
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
        XCTAssertTrue(jonne.staticTexts["Ystäväsi"].exists, "the friend's card does not say what he is to you")
        let loose = app.staticTexts["Ei vielä sukupuussa"]
        XCTAssertTrue(loose.exists, "the people related to nobody lost their caption")
        XCTAssertLessThan(friends.frame.minY, jonne.frame.minY, "the friend stands above his own caption")
        XCTAssertLessThan(jonne.frame.minY, loose.frame.minY, "the friend is among the people related to nobody")
        let rauha = app.buttons["Rauha"]
        XCTAssertTrue(rauha.exists, "somebody's kin is missing")
        XCTAssertLessThan(rauha.frame.minY, friends.frame.minY, "somebody's kin is drawn among the friends")
    }

    /// And no caption over nobody: the fixture of three has no friend in it.
    func testTheFriendsCaptionWaitsForAFriend() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "the tree")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the caption over the people related to nobody")
        XCTAssertFalse(app.staticTexts["Ystävät"].exists, "a caption over no friends")
    }

    /// A phone linked to no card opens on somebody, not on paper. Until
    /// 27 Sep 2026 the drawing opened at its own top left corner on such a
    /// phone, and the oldest row's first card is not there: the rows below
    /// are wider, so the oldest generation stands over the middle of its
    /// descendants, and at the largest text size `-seed clan` filled the
    /// window with nothing at all. It opens on the first card of the oldest
    /// row now, at the place your own card takes. That row is one spouse
    /// chain here — Aapo, married twice, between his wives, and Hilma to
    /// his left because she comes first in `people` order — and the layout
    /// owns that order, so the test takes whichever of the three it drew
    /// leftmost rather than naming her. Measured on the fix's first run:
    /// the test named Aapo, and his card began one card to the right of
    /// the window's edge. At rest: nothing is dragged, pinched or pressed
    /// before the frames are read.
    func testAPhoneLinkedToNoCardOpensOnTheOldestGeneration() {
        let app = launch(
            ["-seed", "clan", "-tab", "people", "-people", "tree"],
            textSize: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(app.buttons["Valikko"].waitForExistence(timeout: 20), "the tree did not open")
        XCTAssertFalse(app.buttons["Sinä"].exists, "a way to your own card on a phone linked to no card")
        let oldest = ["Aapo", "Hilma", "Lyyli"].map { app.buttons[$0] }
        for card in oldest {
            XCTAssertTrue(card.waitForExistence(timeout: 10), "the oldest generation is not in the tree")
        }
        guard let first = oldest.min(by: { $0.frame.minX < $1.frame.minX }) else { return }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(
            window.contains(first.frame),
            "the oldest row's first card is not in the window where the tree opens: \(first.label) at \(first.frame) against \(window)"
        )
        XCTAssertTrue(first.isHittable, "the oldest row's first card cannot be tapped where the tree opens")
    }
}
