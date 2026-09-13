import XCTest

/// The family tree, drawn on a family member's phone since 13 Sep 2026.
///
/// Where people land is `scripts/family-tree-layout-check.swift`'s question.
/// These ask what only a running app can answer: that the tree can be reached,
/// that it draws the confirmed family and nobody else, that a name in it opens
/// the person, and that a grandparent's phone keeps the list instead of a
/// picture of lines.
final class FamilyTreeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The fixture's Eeva and Kalle are a confirmed couple. Sanni is related to
    /// nobody, and Aino is a name heard and never checked.
    func testTheTreeDrawsTheConfirmedFamilyAndOpensAPerson() {
        let app = launch(["-seed", "related", "-tab", "people"])
        let tree = app.buttons["Sukupuu"]
        XCTAssertTrue(tree.waitForExistence(timeout: 10), "no way to the tree on a family member's phone")
        tree.tap()

        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "Eeva is not in the tree")
        XCTAssertTrue(app.buttons["Kalle"].exists, "Kalle is not in the tree")
        XCTAssertFalse(app.buttons["Aino"].exists, "a name nobody has checked is drawn in the tree")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the people outside the tree are not listed")
        XCTAssertTrue(app.buttons["Sanni"].exists, "Sanni is not reachable beneath the tree")

        app.buttons["Kalle"].tap()
        XCTAssertTrue(app.navigationBars["Kalle"].waitForExistence(timeout: 10), "a name in the tree did not open the person")
    }

    /// The two zoom buttons are the way for a hand that cannot pinch, and the
    /// tree has to survive both ends of them.
    func testTheTreeZoomsBothWays() {
        let app = launch(["-seed", "related", "-tab", "people", "-screen", "tree"])
        XCTAssertTrue(app.buttons["Eeva"].waitForExistence(timeout: 10), "the tree did not open")
        let larger = app.buttons["Suurenna"]
        let smaller = app.buttons["Pienennä"]
        XCTAssertTrue(larger.exists && smaller.exists, "the zoom buttons")
        for _ in 0 ..< 6 { larger.tap() }
        XCTAssertTrue(app.buttons["Eeva"].exists, "Eeva is gone at the largest zoom")
        for _ in 0 ..< 12 { smaller.tap() }
        XCTAssertTrue(app.buttons["Kalle"].exists, "Kalle is gone at the smallest zoom")
    }

    /// A grandparent's phone keeps the list: no picture of lines, and no way to one.
    func testAGrandparentsPhoneKeepsTheList() {
        let app = launch(["-seed", "related", "-tab", "people", "-elder.largerText", "YES"])
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the people list")
        XCTAssertFalse(app.buttons["Sukupuu"].exists, "the tree is offered on a grandparent's phone")
    }
}
