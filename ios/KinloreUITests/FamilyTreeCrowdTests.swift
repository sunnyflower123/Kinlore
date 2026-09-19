import XCTest

/// The family tree at the size a family actually reaches, drawn from
/// `-seed clan`: six generations, fifty-three confirmed people, a remarriage,
/// two cousin marriages, a childless couple, a marriage the generations cannot
/// hold, siblings with no parents entered, two families sharing nobody, and
/// seven people related to nobody yet.
///
/// `FamilyTreeTests` asks whether the screen works, over a family of five.
/// Everything here only happens at size: a generation wider than the screen,
/// a row you cannot name because you scrolled away from its label, a drawing
/// that is one long picture of identical lines. The first look at one
/// (16 Sep 2026) is what these were written from.
final class FamilyTreeCrowdTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The whole crowd is drawn, and rule 4 still holds at this size: the one
    /// person nobody has confirmed is not in the picture, however many are.
    func testTheWholeCrowdIsDrawn() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the oldest generation")
        XCTAssertTrue(app.buttons["Hilma"].exists, "his wife")
        XCTAssertTrue(app.buttons["Lyyli"].exists, "the second wife is not drawn")
        XCTAssertTrue(app.buttons["Kustaa"].exists, "somebody related to nobody is not in the picture")
        shot(app, "crowd-top")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the people related to nobody have no caption")
        XCTAssertFalse(app.buttons["Eeva"].exists, "a person nobody has confirmed is drawn in the tree")
    }

    /// Which generation a row is, in words, counted from your own. Without
    /// this the tree is discs and lines and nothing says what a row means —
    /// which was the first thing asked of it after the first evening's use.
    func testEachGenerationIsNamedFromYourOwn() {
        let app = crowd()
        XCTAssertTrue(app.staticTexts["Sinun polvesi"].waitForExistence(timeout: 20), "your own generation is not named")
        XCTAssertTrue(app.staticTexts["Vanhemmat"].exists, "the generation above you is not named")
        XCTAssertTrue(app.staticTexts["Isovanhemmat"].exists, "two above you is not named")
        XCTAssertTrue(app.staticTexts["Isoisovanhemmat"].exists, "three above you is not named")
        XCTAssertTrue(app.staticTexts["Lapset"].exists, "the generation below you is not named")
        // Four above and further has no name in Finnish that anybody says, so
        // it is counted instead of invented.
        XCTAssertTrue(app.staticTexts["4 polvea ylempänä"].exists, "the oldest generation is not named at all")
    }

    /// A phone linked to no card has nobody to count from, and says so by
    /// numbering the drawing's own rows rather than claiming a relationship.
    func testAPhoneLinkedToNoCardNumbersTheGenerationsInstead() {
        let app = launch(["-seed", "clan", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(app.staticTexts["1. polvi"].waitForExistence(timeout: 20), "the generations are not named at all")
        XCTAssertTrue(app.staticTexts["5. polvi"].exists, "only the first generations are named")
        XCTAssertFalse(app.staticTexts["Sinun polvesi"].exists, "a generation is called yours on a phone linked to no card")
        XCTAssertFalse(app.staticTexts["Vanhemmat"].exists, "a row is called your parents' with no you in the tree")
    }

    /// The labels are beside the drawing rather than in it, so they are still
    /// there after scrolling sideways to somebody at the far end of a
    /// generation — which in a family this wide is most of it.
    ///
    /// That the drawing moved at all is measured on the drawing rather than
    /// asserted of whoever happens to be at the far end of one flick. Naming
    /// a person there costs a recalibration every time the picture starts
    /// somewhere new: this swiped three times until 19 Sep 2026 and passed on
    /// a screen showing Otto and Helmi, a family that shares nobody with
    /// Elina's, so the assertion under it was the rail's own defect written
    /// down as a requirement; one swipe then landed on Oiva, and the morning's
    /// second fix — opening on you rather than in the corner — moved the
    /// landing again. Elina's own card carries the answer in every version:
    /// if the drawing scrolled sideways, she went left with it.
    func testTheGenerationsStayNamedAfterScrollingAcrossTheFamily() {
        let app = crowd()
        XCTAssertTrue(app.staticTexts["Sinun polvesi"].waitForExistence(timeout: 20), "the generation labels")
        let labels = app.staticTexts["Sinun polvesi"].frame
        let you = app.buttons["Elina, sinä"].frame
        app.swipeLeft()
        shot(app, "crowd-across")
        XCTAssertLessThan(app.buttons["Elina, sinä"].frame.minX, you.minX - 100,
                          "the drawing did not scroll sideways at all")
        XCTAssertTrue(app.staticTexts["Sinun polvesi"].exists, "the generation labels scrolled away with the tree")
        XCTAssertEqual(app.staticTexts["Sinun polvesi"].frame.minX, labels.minX, accuracy: 1,
                       "the labels moved sideways with the drawing")
    }

    /// And they stop where your own family does. The rail is one column for
    /// the whole picture, so its words — counted from your own row — used to
    /// go on standing beside whatever you scrolled to. Otto and Helmi share
    /// nobody with Elina's family and start at row 0 because nothing is known
    /// about their age either way, so *Isovanhemmat* beside them is a
    /// relationship nobody entered: the same fault as a marriage drawn
    /// through a third person, under the same rule.
    func testTheGenerationsAreNotNamedOverAFamilyThatSharesNobody() {
        let app = crowd()
        XCTAssertTrue(app.staticTexts["Sinun polvesi"].waitForExistence(timeout: 20), "the generation labels")
        // Sixteen places from where the drawing now opens, which is several
        // screens of a picture this wide. The scroll view clamps at the far
        // end, so more swipes than the distance needs cost nothing — and
        // asking whether Otto can be reached before he is on screen costs a
        // test: `isHittable` on somebody outside the window fails outright
        // rather than answering no ("Activation point invalid", 19 Sep 2026).
        for _ in 0 ..< 8 { app.swipeLeft() }
        shot(app, "crowd-other-family")
        XCTAssertTrue(app.buttons["Otto"].isHittable, "the far family cannot be scrolled to")
        XCTAssertFalse(app.staticTexts["Sinun polvesi"].exists,
                       "a row of a family that shares nobody with you is called your own generation")
        XCTAssertFalse(app.staticTexts["Isovanhemmat"].exists,
                       "another family's oldest generation is named as your grandparents'")
        XCTAssertTrue(app.staticTexts["Toinen perhe"].exists,
                      "the words went and nothing says why")
    }

    /// The drawing opens on the part of the family whose phone this is. A
    /// family of 53 is 2376 points wide against a 324-point canvas, so a
    /// picture that opens at its own left edge opens on whichever branch was
    /// drawn first — measured 19 Sep 2026, Hilma, Aapo and half of Lyyli, six
    /// of fifty-three, with Elina four places away and nothing to say which
    /// way to look for her. It now opens on her own line instead: Urho, Sulo
    /// and Kerttu above Reino, Sirkka and Eemeli.
    ///
    /// Her column and not her row. The drawing does not scroll downwards on
    /// opening, and `FamilyTreeView.show` records what that cost and why.
    func testTheTreeOpensOnYourOwnLine() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Elina, sinä"].waitForExistence(timeout: 20), "your own card is not in the tree")
        shot(app, "crowd-opens")
        // Her frame and not her hittability, since she is below the fold:
        // what is asserted is that the drawing carried her column into the
        // window, not that she can be tapped without scrolling to her.
        let you = app.buttons["Elina, sinä"].frame
        XCTAssertGreaterThan(you.midX, 0, "the tree opens to the left of your own line")
        XCTAssertLessThan(you.midX, app.windows.firstMatch.frame.width,
                          "the tree opens to the right of your own line")
        XCTAssertTrue(app.buttons["Sulo"].isHittable, "your own line is not on the screen")
    }

    /// What the lines mean, before the drawing rather than after it. Three
    /// kinds of line are drawn and they are not guessable: a couple is two
    /// lines, children hang from a bracket, siblings from a bar.
    func testTheDrawingSaysWhatItsLinesMeanBeforeTheDrawing() {
        let app = crowd()
        XCTAssertTrue(app.staticTexts["Pariskunta"].waitForExistence(timeout: 20), "nothing says what a couple's line is")
        XCTAssertTrue(app.staticTexts["Sisarukset"].exists, "nothing says what a sibling bar is")
        XCTAssertLessThan(app.staticTexts["Pariskunta"].frame.maxY, app.buttons["Aapo"].frame.minY,
                          "the key is under the picture it is for")
        for _ in 0 ..< 4 { app.swipeUp() }
        shot(app, "crowd-down")
        XCTAssertTrue(app.buttons["Venla"].exists, "the youngest generation cannot be scrolled to")
    }

    /// The people related to nobody follow the tree instead of a dead
    /// generation. The layout leaves an empty row for the caption and the
    /// screen takes the air back out of it: before 16 Sep 2026 the gap under
    /// the last generation was a whole generation tall, 134 points of nothing
    /// at the default text size.
    ///
    /// Measured against the drawing's own generation height — the distance
    /// between two rows of it — so it holds at every text size.
    func testTheCaptionFollowsTheTreeInsteadOfADeadGeneration() {
        let app = launch(["-seed", "clan", "-tab", "people", "-people", "tree", "-you", "clan-elina"])
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the tree")
        let generation = app.buttons["Väinö"].frame.minY - app.buttons["Aapo"].frame.minY
        XCTAssertGreaterThan(generation, 1, "two generations are drawn at the same height")
        let caption = app.staticTexts["Ei vielä sukupuussa"].frame
        let youngest = app.buttons["Venla"].frame
        XCTAssertGreaterThan(caption.minY, youngest.maxY, "the caption is above the last generation")
        XCTAssertLessThan(caption.minY - youngest.maxY, generation,
                          "a whole empty generation sits between the tree and the caption")
    }

    /// Zoomed out to see a family this size, the words are still words: the
    /// labels and the legend keep their own size while the drawing shrinks.
    func testZoomingOutLeavesTheWordsReadable() {
        let app = crowd()
        XCTAssertTrue(app.staticTexts["Sinun polvesi"].waitForExistence(timeout: 20), "the generation labels")
        let before = app.staticTexts["Sinun polvesi"].frame.height
        let smaller = app.buttons["Pienennä"]
        for _ in 0 ..< 5 { smaller.tap() }
        XCTAssertTrue(app.buttons["Aapo"].exists, "the oldest generation is gone at the smallest zoom")
        XCTAssertEqual(app.staticTexts["Sinun polvesi"].frame.height, before, accuracy: 1,
                       "the generation labels shrank with the drawing")
        XCTAssertTrue(app.staticTexts["Pariskunta"].exists, "the legend is gone at the smallest zoom")
        shot(app, "crowd-small")
    }

    /// A picture of what a test was looking at, when
    /// `TEST_RUNNER_KINLORE_TREE_SHOT=/some/dir/prefix` is on the xcodebuild
    /// line, and nothing at all when it is not.
    ///
    /// The same affordance as the audit's shot, for the same reason: this
    /// machine has no simulator panel, so a screen nobody can tap is a screen
    /// nobody can look at. A drawing is the one thing here that has to be
    /// looked at — every defect the first look found was a matter of air,
    /// crossing lines and words too small, and no assertion in this file would
    /// have reported any of them.
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["KINLORE_TREE_SHOT"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)-\(name).png"))
    }

    /// The fixture's family, on a phone whose card is Elina's — four
    /// generations down from the oldest and one up from the youngest, so every
    /// word the rail has is on screen at once.
    private func crowd() -> XCUIApplication {
        launch(["-seed", "clan", "-tab", "people", "-people", "tree", "-you", "clan-elina"])
    }
}
