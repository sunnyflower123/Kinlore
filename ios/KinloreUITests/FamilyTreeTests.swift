import XCTest

/// The family tree, on a family member's phone since 13 Sep 2026, and what
/// Ihmiset opens on there.
///
/// Where people land is `scripts/family-tree-layout-check.swift`'s question.
/// These ask what only a running app can answer: that Ihmiset opens on the
/// tree with the whole confirmed family in it, that the list is one tap away,
/// that a person in the tree opens their card or takes a new relative on the
/// spot, and that a grandparent's phone keeps the list.
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
        XCTAssertTrue(app.navigationBars["Sukupuu"].exists, "the tree is not titled as the tree")
        XCTAssertTrue(app.buttons["Kalle"].exists, "Kalle is not in the tree")
        XCTAssertTrue(app.buttons["Sanni"].exists, "somebody related to nobody is not in the picture")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the people related to nobody have no caption")
        XCTAssertFalse(app.buttons["Aino"].exists, "a name nobody has checked is drawn in the tree")
        XCTAssertTrue(app.buttons["Luettelo"].exists, "no way from the tree to the list")
        XCTAssertFalse(app.staticTexts["Sinä"].exists, "somebody is marked as you on a phone linked to no card")
    }

    /// The card this phone's member is linked to says so. `-you` links the
    /// demo family's "you" to Eeva's card, as `PATCH /family/me` does for real.
    func testYourOwnCardSaysItIsYou() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "tree", "-you", "demo-eeva"])
        XCTAssertTrue(app.buttons["Eeva, sinä"].waitForExistence(timeout: 10), "your card does not say it is you")
        XCTAssertTrue(app.staticTexts["Sinä"].exists, "no word under your name")
        XCTAssertTrue(app.buttons["Kalle"].exists, "somebody else was marked as you as well")
    }

    /// The list is one tap away and the tree one tap back, whichever the phone
    /// was left on, and the screen is titled for the one it shows. Ends on the
    /// tree, which is where a phone starts.
    func testTheListAndTheTreeAreOneTapApart() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "default"])
        let toTree = app.buttons["Sukupuu"]
        let toList = app.buttons["Luettelo"]
        XCTAssertTrue(toList.waitForExistence(timeout: 10) || toTree.exists, "Ihmiset")
        if toTree.exists { toTree.tap() }

        XCTAssertTrue(toList.waitForExistence(timeout: 10), "the tree")
        XCTAssertTrue(app.navigationBars["Sukupuu"].exists, "the tree is not titled as the tree")
        toList.tap()

        XCTAssertTrue(toTree.waitForExistence(timeout: 10), "the list did not open, or has no way back to the tree")
        XCTAssertTrue(app.navigationBars["Ihmiset"].exists, "the list is not titled Ihmiset")
        XCTAssertTrue(app.staticTexts["Eeva"].exists, "the list has nobody on it")
        toTree.tap()
        XCTAssertTrue(toList.waitForExistence(timeout: 10), "the tree did not come back")
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
        XCTAssertTrue(app.buttons["Luettelo"].exists, "adding a relative left the tree")
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
        XCTAssertTrue(app.buttons["Luettelo"].exists, "a zoom tap opened another screen")
    }

    /// A grandparent's phone keeps the list: no picture of lines, and no way to one.
    func testAGrandparentsPhoneKeepsTheList() {
        let app = launch(["-seed", "related", "-tab", "people", "-people", "default", "-elder.largerText", "YES"])
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the people list")
        XCTAssertTrue(app.navigationBars["Ihmiset"].exists, "a grandparent's list is not titled Ihmiset")
        XCTAssertFalse(app.buttons["Sukupuu"].exists, "the tree is offered on a grandparent's phone")
        XCTAssertFalse(app.buttons["Luettelo"].exists, "the tree is shown on a grandparent's phone")
    }
}
