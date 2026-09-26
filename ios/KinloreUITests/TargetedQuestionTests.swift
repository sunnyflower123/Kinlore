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

    /// A row on the card is the way to answer it. Until 26 Sep 2026 the rows
    /// were text: the question sat on the photograph's card with nothing to
    /// press, and answering it meant opening "Kerro tästä muisto" and finding
    /// the same words again below the button, under a title that asked for
    /// any telling at all.
    ///
    /// Aino's question, on somebody else's phone, is the case that matters:
    /// the aim narrows whose Kerro tab offers it, never who may answer, so on
    /// every other phone the card is the only place it is read. The tap opens
    /// the Tell screen on this photograph with the question as its title, the
    /// big button answers it through the stub pipeline, and the question
    /// leaves the card's open list while the other one stays.
    func testARowOnTheCardOpensTellingWithItsQuestion() {
        let app = launch(["-seed", "aimed", "-tab", "memories", "-voice", "stub"])
        openPhoto(in: app)

        let asked = "Mitä mökillä syötiin juhannuksena?"
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", asked)).firstMatch
        reach(row, in: app)
        // A list builds a row just above the tab bar. XCUITest calls it
        // hittable there all the same and taps a corner of it, which opens
        // nothing, so its middle is brought above the bar first.
        let bar = app.tabBars.firstMatch
        for _ in 0 ..< 3 where row.frame.midY > bar.frame.minY - 8 { app.swipeUp() }
        row.tap()

        XCTAssertTrue(app.buttons["Sulje"].waitForExistence(timeout: 10), "the row did not open the Tell screen")
        // By identifier: the question's words are on the card under the
        // sheet too, so a query by label finds them whatever the title says.
        let title = app.staticTexts["tell.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "never arrived: the Tell screen's title")
        XCTAssertEqual(title.label, asked, "the Tell screen's title is not the question it is answering")

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 5), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )
        // Anything under a second is discarded as an accident.
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()
        // A spoken answer goes straight on to its own first follow-up since
        // 26 Sep 2026 (`InterviewLoopTests`); ending the conversation there
        // is what lands on the result.
        let enough = app.buttons["Riittää tältä erää"]
        XCTAssertTrue(enough.waitForExistence(timeout: 30), "the answer did not go on to its follow-up")
        enough.tap()
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 15),
            "the answer was not saved"
        )

        let done = app.buttons["Valmis"]
        for _ in 0 ..< 6 where !done.isHittable { app.swipeUp() }
        done.tap()

        // Back on the card: answered is off the open list, and the question
        // nobody answered is still on it. Asked with the ask button below
        // the list on screen as well, because a list builds only the rows on
        // screen: with the rows on both sides of it built, a row missing
        // between them is gone rather than unbuilt.
        let other = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Kuka souti veneen saareen sinä aamuna?")
        ).firstMatch
        reach(other, in: app)
        reach(app.buttons["Kysy perheeltä"], in: app)
        XCTAssertTrue(other.exists, "the question nobody answered is not on screen with the ask button")
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", asked)).firstMatch.exists,
            "the answered question is still open on the card"
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

    /// The same sheet at the ordinary size, outside a family: no "Kenelle?",
    /// and a sentence under the field that the buttons covered at rest, cut
    /// through a line, while they were stacked (25 Sep 2026). The audit
    /// cannot see that once the bar is opaque — text under paper is not text
    /// it judges — so a frame is asked instead.
    ///
    /// Not asserted in a family, where it is not true: "Kenelle?" puts the
    /// sentence's last line under the buttons until the list is scrolled.
    func testTheAskSheetShowsItsSentenceAtTheOrdinarySize() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        openPhoto(in: app)
        reach(app.buttons["Kysy perheeltä"], in: app).tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "the field did not take the keyboard")
        let send = app.buttons["Lähetä kysymys"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "never arrived: the ask sheet")
        let sentence = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Kysymys näkyy koko perheelle"
        )).firstMatch
        XCTAssertTrue(sentence.waitForExistence(timeout: 10), "the sheet says nothing under the field")
        // The bar begins `Elder.screenPadding` (24 pt) above its buttons.
        XCTAssertTrue(
            settles { sentence.frame.maxY <= send.frame.minY - 24 + 1 },
            "the sentence is under the buttons: \(sentence.frame) against \(send.frame)"
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

    /// Answers the microphone prompt if it is showing, by position rather than
    /// label — permission alerts put the allowing answer last, whatever the
    /// simulator's language. Same helper as LocalModeTests.
    private func allowTheMicrophone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        let buttons = alert.buttons
        guard buttons.count > 0 else { return }
        buttons.element(boundBy: buttons.count - 1).tap()
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
