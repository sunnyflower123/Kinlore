import XCTest

/// Colouring a photograph by what was told about it, and what each answer
/// leaves on the card.
///
/// Nothing on the question screen shows whether a colouring will be kept: a
/// proposal and a kept colouring look alike at the moment the question is
/// asked. So what is checked is the card afterwards. "Kyllä" puts the colours
/// beside the photograph with the name of whoever said yes. "En tiedä" keeps
/// nothing — rule 5's answer, and the one a hurried default would quietly turn
/// into a yes. "Ei, kerron lisää" opens the telling for the same photograph.
///
/// The model is the stub (`-api ""`): a warm tint with every edge where it was,
/// so the lock keeps it and nothing is spent. `-seed blind` is the fixture
/// whose photograph has both a picture and a telling.
final class ColourTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private let kept = "Väritetty kuva. Värit ovat tekoälyn arvaus kerrotun mukaan."

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

    private func askForColours(_ app: XCUIApplication) {
        openPhotograph(app)
        let colour = app.buttons["Väritä kerronnan mukaan"]
        for _ in 0 ..< 6 where !colour.exists { app.swipeUp() }
        XCTAssertTrue(colour.waitForExistence(timeout: 10), "the card offers no colouring")
        colour.tap()
        XCTAssertTrue(
            app.staticTexts["Näyttääkö tältä?"].waitForExistence(timeout: 20),
            "never arrived: the question over the colouring"
        )
    }

    func testYesKeepsTheColoursBesideThePhotograph() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        askForColours(app)
        app.buttons["Kyllä, tallenna värit"].tap()

        backToThePhotograph(app)
        // A button, since it opens to the whole screen as the photograph does.
        let colours = app.buttons[kept]
        XCTAssertTrue(colours.waitForExistence(timeout: 10), "the kept colouring is not on the card")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Vahvisti")).firstMatch.exists,
            "the card does not say whose word the colours stand on"
        )
    }

    func testIDoNotKnowKeepsNothing() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        askForColours(app)
        app.buttons["En tiedä"].tap()

        XCTAssertTrue(
            app.buttons["Väritä kerronnan mukaan"].waitForExistence(timeout: 10),
            "never came back to the card"
        )
        backToThePhotograph(app)
        // Either element, so that this cannot pass by asking for the wrong one.
        XCTAssertFalse(app.buttons[kept].exists || app.images[kept].exists, "an uncertain answer kept the colours")
    }

    func testNoOpensTheTellingForThePhotograph() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        askForColours(app)
        app.buttons["Ei, kerron lisää"].tap()

        XCTAssertTrue(
            app.buttons["Aloita kertominen"].waitForExistence(timeout: 10),
            "the telling did not open after the colouring was answered no"
        )
    }

    /// A phone told to keep its archive to itself is not offered colours at all.
    /// Its onboarding promised "Perheen palvelimelle ne eivät lähde", and
    /// colouring sends the photograph and those memories to the Worker — a
    /// refusal there would come after they had left. `-local_only YES` is the
    /// key the onboarding answer writes, and the dead loopback address makes
    /// this a phone that has a backend and chose not to use it
    /// (`isLocalByChoice`), as in `LocalModeTests`.
    ///
    /// Everything else the button needs is proven present first — the telling
    /// under the photograph, and the photograph itself, because a card still
    /// waiting for its picture offers no colouring either, and a missing button
    /// would then prove nothing.
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
