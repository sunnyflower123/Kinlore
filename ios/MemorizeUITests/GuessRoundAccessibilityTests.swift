import XCTest

/// What a VoiceOver user gets from the guessing round.
///
/// VoiceOver reads the accessibility tree; XCUITest queries the same tree, and
/// `performAccessibilityAudit()` walks it for the failures a screenshot cannot
/// show — an unlabelled control, a tap target under the minimum, text that clips
/// instead of wrapping at the largest size.
///
/// The round is the right thing to test first. It is the only screen in the app
/// whose content is deliberately incomplete: the answer is a gap in a sentence,
/// and a gap that VoiceOver skips is a screen with no question on it.
final class GuessRoundAccessibilityTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// `-seed guess` replaces the archive with a fixture, so the round is the
    /// same every run. See `MemoryStore.seedDemoArchiveIfRequested`.
    private func launchOnTheRound(textSize: String? = nil) -> XCUIApplication {
        launch(["-seed", "guess", "-tab", "memories"], textSize: textSize)
    }

    private func card(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "kertoi tämän")
        ).firstMatch
    }

    // MARK: - The gap has to be spoken

    func testTheGapIsSpokenAsAWordRatherThanSkipped() {
        let app = launchOnTheRound()
        let card = card(in: app)
        XCTAssertTrue(
            card.waitForExistence(timeout: 10),
            "The round card never appeared. Tree:\n\(app.debugDescription)"
        )

        let label = card.label

        // The mask is an em dash run. VoiceOver reads a run of dashes as nothing
        // at all or as punctuation, and either way the question disappears: the
        // sentence is spoken as if the name had simply not been said. The label
        // puts a word in the hole instead.
        XCTAssertFalse(
            label.contains("———"),
            "The em dash mask reached the accessibility label. Spoken aloud the "
                + "gap vanishes and the card asks nothing. Label: \(label)"
        )
        XCTAssertTrue(
            label.contains("joku"),
            "The gap is not spoken as a word. Label: \(label)"
        )
        // The answer must not be in the label either — the whole point is that
        // it is hidden, and a sighted user seeing a gap while VoiceOver reads
        // the name out is the worst of both.
        XCTAssertFalse(
            label.contains("Aino"),
            "The masked name is in the accessibility label: VoiceOver gives the "
                + "answer away. Label: \(label)"
        )
        XCTAssertTrue(label.contains("Kuka hän oli?"), "The card does not ask anything: \(label)")
    }

    // MARK: - Every control has to be reachable and named

    func testEveryAnswerIsAButtonWithAName() {
        let app = launchOnTheRound()
        let card = card(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        for name in ["Aino", "Eeva", "Kalle", "Sanni"] {
            XCTAssertTrue(
                app.buttons[name].waitForExistence(timeout: 5),
                "\(name) is not reachable as a named button"
            )
        }
        XCTAssertTrue(
            app.buttons["En muista"].exists,
            "Not knowing has no button, so the only way out of the screen is a wrong answer"
        )
    }

    func testTheAnswerIsAnnouncedInText() {
        let app = launchOnTheRound()
        let card = card(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.buttons["Aino"].waitForExistence(timeout: 5))
        app.buttons["Aino"].tap()

        // The result is carried by words, not by a colour or a checkmark alone —
        // this app's user is precisely the one who cannot rely on either.
        let verdict = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Hän oli Aino")
        ).firstMatch
        XCTAssertTrue(
            verdict.waitForExistence(timeout: 5),
            "The reveal does not state the answer in text"
        )
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Kerro sinäkin hänestä")
            ).firstMatch.exists,
            "The offer to tell about the person is not reachable after the reveal"
        )
    }

    /// "En muista" is an answer, and it has to end somewhere other than a dead
    /// end: the person who did not know is the one who most needs telling.
    func testNotKnowingStillRevealsTheAnswer() {
        let app = launchOnTheRound()
        let card = card(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.buttons["En muista"].waitForExistence(timeout: 5))
        app.buttons["En muista"].tap()

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Hän oli Aino")
            ).firstMatch.waitForExistence(timeout: 5),
            "\"En muista\" does not reveal who it was"
        )
    }

    // MARK: - The audit

    func testTheRoundPassesTheAccessibilityAudit() throws {
        let app = launchOnTheRound()
        let card = card(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        try audit(app, "The memories screen with a round waiting")

        card.tap()
        XCTAssertTrue(app.buttons["Aino"].waitForExistence(timeout: 5))
        try audit(app, "The round itself")
    }

    /// Rule 1: if a screen does not work at the largest text size, it is not
    /// done. The audit catches the clipping and the truncation that a person
    /// reading a screenshot talks themselves out of.
    func testTheRoundPassesTheAuditAtTheLargestTextSize() throws {
        let app = launchOnTheRound(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let card = card(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        try audit(app, "The memories screen at the largest text size")

        card.tap()
        XCTAssertTrue(app.buttons["Aino"].waitForExistence(timeout: 10))
        try audit(app, "The round itself at the largest text size")
    }
}
