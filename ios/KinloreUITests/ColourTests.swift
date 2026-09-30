import XCTest

/// Colouring a photograph by what was told about it: the colours asked for
/// first, and what each answer leaves on the card.
///
/// The button opens the photograph's own telling with the colours as its
/// question (28 Sep 2026), and a telling saved there is coloured by at once,
/// with no tap between. Nothing on the question screen shows whether a
/// colouring will be kept: a proposal and a kept colouring look alike at the
/// moment the question is asked. So what is checked is the card afterwards.
/// "Kyllä" puts the colours beside the photograph with the name of whoever
/// said yes, and the telling that gave them under it. "En tiedä" keeps
/// nothing — rule 5's answer, and the one a hurried default would quietly
/// turn into a yes. "Ei, kerron lisää" asks for the colours again.
///
/// Written rather than spoken, because the keyboard is how a test puts words
/// into a telling; the hand-over after a spoken one is the same `.done`. The
/// model is the stub (`-api ""`): a warm tint with every edge where it was, so
/// the lock keeps it and nothing is spent. `-seed blind` is the fixture whose
/// photograph has both a picture and a telling, and `-seed film-untold` one
/// whose photograph has a picture and nothing told about it.
final class ColourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private let kept = "Väritetty kuva. Värit ovat tekoälyn arvaus kerrotun mukaan."
    private let colours = "Mekko oli tummansininen ja lato punainen."

    private func openPhotograph(_ app: XCUIApplication) {
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "never arrived: the photo tile")
        photo.tap()
    }

    /// Back up the card to its photograph, the first thing on it, and no
    /// further. The card opened out of its tile, and a pull down at its top
    /// closes it into the album (27 Sep 2026): six swipes can end there, and
    /// "nothing kept" would then hold on an album with no card to keep
    /// anything on. So the swipes stop once the photograph is under the
    /// title — read from frames, since `isHittable` fails outright on a row
    /// the list holds outside the window — and the card has to be open
    /// before anything is read off it. The photograph is untitled, so
    /// both it and the title are `displayTitle`'s *"Valokuva"*, and it is a
    /// button, since it opens to the whole screen (`PhotoViewer`).
    private func backToThePhotograph(_ app: XCUIApplication) {
        let photograph = app.buttons["Valokuva"]
        let title = app.navigationBars["Valokuva"]
        let inView = { photograph.exists && title.exists && photograph.frame.minY >= title.frame.maxY - 1 }
        for _ in 0 ..< 6 where !inView() { app.swipeDown() }
        XCTAssertTrue(title.exists, "the card closed on the way back up to its photograph")
        XCTAssertTrue(inView(), "never came back up to the photograph")
    }

    /// The card's button, and what it opens: the photograph's telling, with
    /// the colours as its title. By identifier, as the sweeps read it.
    private func askForColours(_ app: XCUIApplication) {
        openPhotograph(app)
        let colour = app.buttons["Väritä kerronnan mukaan"]
        for _ in 0 ..< 6 where !colour.exists { app.swipeUp() }
        XCTAssertTrue(colour.waitForExistence(timeout: 10), "the card offers no colouring")
        colour.tap()
        let title = app.staticTexts["tell.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the colouring did not ask for the colours first")
        XCTAssertEqual(title.label, "Mitä värejä muistat tästä kuvasta?", "the telling does not ask for the colours")
    }

    /// Written and saved — and then the question over the colouring, with
    /// nothing pressed in between.
    private func tell(_ words: String, _ app: XCUIApplication) {
        let write = app.buttons["Kirjoita sen sijaan"]
        XCTAssertTrue(write.waitForExistence(timeout: 10), "never arrived: the way to write it")
        write.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "never arrived: the editor")
        editor.typeText(words)
        app.buttons["Tallenna"].tap()
    }

    private func waitForTheQuestion(_ app: XCUIApplication, _ why: String) {
        XCTAssertTrue(app.staticTexts["Näyttääkö tältä?"].waitForExistence(timeout: 30), why)
    }

    /// Out of the sheet by one of its buttons, and back on the card. Waited
    /// on as the sheet's title leaving, not as the colour button coming back:
    /// every telling kept adds a row above the button, and on the lazy card
    /// it then sits below the fold, where it does not exist.
    private func leave(by button: XCUIElement, _ app: XCUIApplication) {
        let sheet = app.navigationBars["Värit kerronnan mukaan"]
        XCTAssertTrue(sheet.exists, "the way out is not on the colour sheet")
        button.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheet)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.navigationBars["Valokuva"].waitForExistence(timeout: 10), "never came back to the card")
    }

    /// The card's own count of what has been told under the photograph.
    private func toldCount(_ app: XCUIApplication) -> String {
        let heading = app.staticTexts["card.memoriesHeading"]
        for _ in 0 ..< 6 where !heading.exists { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "never arrived: the count of what was told")
        return heading.label
    }

    private func isOnTheCard(_ words: String, _ app: XCUIApplication) -> Bool {
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
        for _ in 0 ..< 6 where !row.exists { app.swipeUp() }
        return row.waitForExistence(timeout: 10)
    }

    func testYesKeepsTheColoursBesideThePhotograph() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        askForColours(app)
        tell(colours, app)
        waitForTheQuestion(app, "the saved telling was not coloured by")
        app.buttons["Kyllä, tallenna värit"].tap()

        backToThePhotograph(app)
        // A button, since it opens to the whole screen as the photograph does.
        XCTAssertTrue(app.buttons[kept].waitForExistence(timeout: 10), "the kept colouring is not on the card")
        // The name is the colouring's footer, and a card backed up to its
        // photograph can leave it below the window, where the lazy list has
        // not made it. Measured on the 17 Pro (30 Sep 2026): the colouring
        // stood at y 641–648 and ran 247 points down, past the window's 874,
        // and the footer did not exist at any of six reads over five seconds,
        // in each of three runs. `backToThePhotograph` stops wherever the
        // photograph is under the title, so where the footer lands varies
        // from run to run. It is scrolled to, then, not waited for, and in
        // short slow drags: a swipe's momentum can carry one line of text
        // past the whole window in one go.
        let by = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Vahvisti")).firstMatch
        let middle = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0 ..< 4 where !by.exists {
            middle.press(
                forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -200)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
        XCTAssertTrue(by.exists, "the card does not say whose word the colours stand on")
        XCTAssertTrue(isOnTheCard(colours, app), "the telling that gave the colours is not on the card")
    }

    /// The second way, from what was told before: nothing told on the way,
    /// and nothing kept after an uncertain answer.
    func testIDoNotKnowKeepsNothing() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        askForColours(app)
        app.buttons["Väritä jo kerrotun mukaan"].tap()
        waitForTheQuestion(app, "the second way did not colour from what was told")
        leave(by: app.buttons["En tiedä"], app)
        backToThePhotograph(app)
        // Either element, so that this cannot pass by asking for the wrong one.
        XCTAssertFalse(app.buttons[kept].exists || app.images[kept].exists, "an uncertain answer kept the colours")
        XCTAssertEqual(toldCount(app), "1 muisto", "the second way told something")
    }

    /// "Ei, kerron lisää" asks for the colours again, and the correction is
    /// coloured by the same way the first telling was. Both are kept, and
    /// neither colouring is.
    func testNoAsksForTheColoursAgain() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        askForColours(app)
        tell(colours, app)
        waitForTheQuestion(app, "the saved telling was not coloured by")
        app.buttons["Ei, kerron lisää"].tap()

        let title = app.staticTexts["tell.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "\"Ei, kerron lisää\" did not open the telling again")
        XCTAssertEqual(title.label, "Mitä värejä muistat tästä kuvasta?", "the correction is not asked for as colours")
        tell("Lato oli sittenkin keltainen.", app)
        waitForTheQuestion(app, "the correction was not coloured by")
        leave(by: app.buttons["En tiedä"], app)
        backToThePhotograph(app)
        XCTAssertFalse(app.buttons[kept].exists || app.images[kept].exists, "an uncertain answer kept the colours")
        XCTAssertEqual(toldCount(app), "3 muistoa", "the two tellings about the colours were not both kept")
    }

    /// A photograph nobody has told anything about is offered colours too,
    /// since the sheet asks for them first — and it has no second way, since
    /// there is nothing told to colour from.
    func testAnUntoldPhotographIsAskedBeforeItIsColoured() {
        let app = launch(["-seed", "film-untold", "-tab", "memories"])
        askForColours(app)
        XCTAssertFalse(
            app.buttons["Väritä jo kerrotun mukaan"].exists,
            "a photograph with nothing told offered to colour from what was told"
        )
        tell(colours, app)
        waitForTheQuestion(app, "the saved telling was not coloured by")
        leave(by: app.buttons["En tiedä"], app)
        backToThePhotograph(app)
        XCTAssertEqual(toldCount(app), "1 muisto", "the telling about the colours was not kept")
    }

    /// Telling is never paywalled (rule 2), and a spent month of colourings
    /// is not a wall in front of it: the telling saved on the way is kept, and
    /// the refusal says so. `-colour spent` answers the way the Worker's 402
    /// does.
    func testASpentMonthKeepsTheTelling() {
        let app = launch(["-seed", "blind", "-tab", "memories", "-colour", "spent"])
        askForColours(app)
        tell(colours, app)
        XCTAssertTrue(
            app.staticTexts["Tämän kuukauden väritykset on käytetty."].waitForExistence(timeout: 30),
            "a spent month did not say so"
        )
        XCTAssertTrue(
            app.staticTexts["Kertomasi on tallessa kuvan kortilla."].exists,
            "the refusal does not say the telling is kept"
        )
        leave(by: app.buttons["Sulje"], app)
        backToThePhotograph(app)
        XCTAssertTrue(isOnTheCard(colours, app), "a spent month lost the telling")
    }

    /// A phone told to keep its archive to itself is not offered colours at all.
    /// Its onboarding promised "Perheen palvelimelle ne eivät lähde", and
    /// colouring sends the photograph and those memories to the Worker — a
    /// refusal there would come after they had left. `-local_only YES` is the
    /// key the onboarding answer writes, and the dead loopback address makes
    /// this a phone that has a backend and chose not to use it
    /// (`isLocalByChoice`), as in `LocalModeTests`.
    ///
    /// Everything else the button needs is proven present first — the
    /// photograph itself, because a card still waiting for its picture offers
    /// no colouring either, and a missing button would then prove nothing. The
    /// telling under it is found first only as the sign that the card is
    /// drawn: the button has not waited for one since 28 Sep 2026.
    ///
    /// And the absence is looked for at every scroll position down the card.
    /// The card is a lazy list and the button sits below the fold: the first
    /// version of this test asked once, where the telling was found, and still
    /// passed with the gate deleted — a button that was never drawn does not
    /// exist whether or not it is offered.
    func testAPhoneKeptToItselfIsNotOfferedColours() {
        let app = launch(["-seed", "blind", "-tab", "memories", "-local_only", "YES"], api: "http://127.0.0.1:9")
        openPhotograph(app)

        let told = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] %@", "[0-9]+ muistoa?")).firstMatch
        for _ in 0 ..< 6 where !told.exists { app.swipeUp() }
        XCTAssertTrue(told.waitForExistence(timeout: 10), "never arrived: the telling under the photograph")
        // The card draws a spinner in the photograph's place until the picture
        // has loaded.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.activityIndicators.firstMatch)
        waitForExpectations(timeout: 10)

        let colour = app.buttons["Väritä kerronnan mukaan"]
        for _ in 0 ..< 6 {
            XCTAssertFalse(colour.exists, "a phone kept to itself was offered colours")
            app.swipeUp()
        }
        XCTAssertFalse(colour.exists, "a phone kept to itself was offered colours")
    }
}
