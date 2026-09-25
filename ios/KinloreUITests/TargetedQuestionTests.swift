import XCTest

/// A question asked of one member by name.
///
/// Everyone sees it on the photograph's card and anyone who knows may answer
/// it there. What the aim narrows is whose Kerro tab offers it — and both ways
/// of getting that wrong are silent: a question asked of Aino offered on every
/// phone reads as an ordinary family question, and one asked of you that is not
/// offered reads as nothing at all. `-seed aimed` puts one of each in the demo
/// archive, with the family seeded beside them for the ask sheet to choose from.
final class TargetedQuestionTests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = false
    }

    /// The Kerro tab offers the question asked of this phone's member, headed
    /// by the asker asking *you*, and says nothing of the one asked of Aino.
    func testTheKerroTabOffersOnlyWhatWasAskedOfYou() {
        let app = launch(["-seed", "aimed"])
        app.tabBars.buttons["Kerro"].tap()

        XCTAssertTrue(
            app.staticTexts["Mummo kysyy sinulta"].waitForExistence(timeout: 15),
            "the question asked of you is not offered by name"
        )
        XCTAssertTrue(
            app.staticTexts["Kuka souti veneen saareen sinä aamuna?"].exists,
            "the offer does not carry the question asked of you"
        )
        XCTAssertFalse(
            app.staticTexts["Mitä mökillä syötiin juhannuksena?"].exists,
            "a question asked of Aino is offered on somebody else's Kerro tab"
        )
    }

    /// The card shows both, because anyone who knows may answer — and says
    /// whose each one is.
    func testTheCardShowsBothAndSaysWhoseTheyAre() {
        let app = launch(["-seed", "aimed", "-tab", "memories"])
        openPhoto(in: app)

        let aino = reach(app.staticTexts["Kenelle: Aino"], in: app)
        XCTAssertTrue(aino.exists, "the card does not say the question is Aino's")
        XCTAssertTrue(
            app.staticTexts["Mitä mökillä syötiin juhannuksena?"].exists,
            "the question asked of Aino is missing from the card"
        )
        XCTAssertTrue(
            app.staticTexts["Mummo kysyy sinulta"].exists,
            "the card does not say which question was asked of you"
        )
    }

    /// Asked by name from the card: the sheet offers the family's other
    /// members, and what it sends carries the aim — the card says so at once,
    /// before any sync, because the name is written locally too.
    func testAQuestionAskedByNameSaysWhoseItIs() {
        let app = launch(["-seed", "aimed", "-tab", "memories"])
        openPhoto(in: app)
        reach(app.buttons["Kysy perheeltä"], in: app).tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the ask sheet")
        field.typeText("Kuka rakensi saunan?")
        choose("Ville", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@", "Kysymys näkyy koko perheelle, mutta"
            )).firstMatch.waitForExistence(timeout: 5),
            "the sheet does not say what asking by name changes"
        )
        app.buttons["Lähetä kysymys"].tap()

        let ville = reach(app.staticTexts["Kenelle: Ville"], in: app)
        XCTAssertTrue(ville.exists, "the card does not say whose the new question is")
    }

    /// The sheet at the largest text size, with the keyboard up and the choice
    /// of whom to ask on it. The audit forgives what sits under the keyboard,
    /// so this asks the two questions it cannot: is the send button above the
    /// keys, and is the field she is typing in between the bar and the
    /// buttons rather than under either.
    func testTheAskSheetFitsAtTheLargestTextSize() {
        let app = launch(["-seed", "aimed", "-tab", "memories"], textSize: Self.largest)
        openPhoto(in: app)
        reach(app.buttons["Kysy perheeltä"], in: app).tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "the field did not take the keyboard")
        let send = app.buttons["Lähetä kysymys"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "never arrived: the ask sheet")
        let field = app.textFields.firstMatch
        let bar = app.navigationBars.firstMatch
        // The keyboard slides in and the sheet moves with it, so the frames
        // are asked again until they have settled rather than read once.
        XCTAssertTrue(
            settles { send.frame.maxY <= keyboard.frame.minY + 1 },
            "the send button is under the keyboard: \(send.frame) against \(keyboard.frame)"
        )
        XCTAssertGreaterThanOrEqual(
            field.frame.minY, bar.frame.maxY - 1,
            "the field is under the navigation bar: \(field.frame) against \(bar.frame)"
        )
        // At least 60 pt of the field shows above the bar the buttons sit on,
        // which is `Elder.screenPadding` (24 pt) taller than they are. A line
        // at this size is some 55 pt: three and the padding make the field's
        // 187, measured 25 Sep 2026.
        XCTAssertLessThanOrEqual(
            field.frame.minY + 60, send.frame.minY - 24,
            "no line of the field shows above the buttons: \(field.frame) against \(send.frame)"
        )
    }

    // MARK: - Helpers

    /// True once the condition holds, asked again for up to five seconds.
    private func settles(_ condition: @escaping () -> Bool) -> Bool {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter().wait(for: [settled], timeout: 5) == .completed
    }

    private func openPhoto(in app: XCUIApplication) {
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch
        reach(tile, in: app).tap()
    }

    /// Scrolls until the element is there, then insists on it. The card is a
    /// list, and a list does not build the rows nobody can see.
    @discardableResult
    private func reach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        for _ in 0 ..< 6 where !element.exists {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10), "never arrived: \(element)", file: file, line: line)
        return element
    }

    /// Opens the "Kenelle?" menu and picks a member. A menu picker is one
    /// button whose label is its own label and the choice it shows, joined:
    /// "Kenelle?, Koko perhe" until somebody is chosen.
    private func choose(_ name: String, in app: XCUIApplication) {
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kenelle?,")).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "never arrived: the Kenelle? menu")
        menu.tap()
        let option = app.buttons[name]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "the menu does not offer \(name)")
        option.tap()
    }
}
