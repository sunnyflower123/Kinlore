import XCTest

/// Every screen, at the default size and at the largest one.
///
/// The guessing round's audit found four primary buttons below the contrast
/// minimum — on a screen that had been looked at in screenshots half a dozen
/// times. Contrast is not a thing eyes measure, and this app's user is the one
/// who pays for the difference. So the check is run everywhere rather than on
/// the screen that happened to prompt it.
///
/// The `-screen` and `-tab` launch arguments exist for exactly this: some of
/// these screens sit behind several taps, and a test run has no hands. See
/// docs/SETUP.md.
final class AccessibilitySweepTests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Waits for something the screen must have, and **fails if it never
    /// arrives**.
    ///
    /// Not `_ = waitForExistence(...)`, and not `guard … else { return }`. A
    /// settle step that gives up quietly leaves the audit running on whatever
    /// happens to be on screen — under the name of the screen it failed to
    /// reach. `testAskQuestionSheet` did exactly that: it tapped something that
    /// was not a photo tile, never opened the sheet, and audited the gallery
    /// twice while reporting itself green.
    ///
    /// An audit on the wrong screen is worse than no audit, because a green test
    /// is a claim that somebody checked.
    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: 10),
            "never arrived: \(what)",
            file: file,
            line: line
        )
        return element
    }

    /// The photo in the demo archive, found by the label it carries rather than
    /// by being the first image on the screen. It is not: the guessing round's
    /// card sits above the grid and has an icon in it, which is what
    /// `images.firstMatch` had been tapping.
    private func photoTile(in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva"))
            .firstMatch
    }

    /// Scrolls until the element is there, and then insists that it is.
    ///
    /// At the largest text size half of these screens are taller than the phone,
    /// and neither a `List` nor a `LazyVGrid` builds rows nobody can see — so an
    /// element below the fold does not merely sit off-screen, it does not exist
    /// and cannot be waited for.
    ///
    /// Only for something that is then *tapped through*. Scrolling before an
    /// audit is a different matter: it was tried on the gallery and made the
    /// measurement worse, because the audit sampled a view that was still
    /// moving. What is measured after this is the screen on the other side of
    /// the tap, which has settled.
    @discardableResult
    private func reach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ what: String
    ) -> XCUIElement {
        for _ in 0 ..< 4 where !element.exists {
            app.swipeUp()
        }
        return require(element, what)
    }

    private func reachPhotoTile(in app: XCUIApplication) -> XCUIElement {
        reach(photoTile(in: app), in: app, "the photo tile")
    }

    /// Audits a screen at both sizes in one test, so a failure names the screen
    /// rather than an index into a list.
    private func sweep(
        _ name: String,
        arguments: [String],
        api: String = "",
        settle: (XCUIApplication, Bool) -> Void = { _, _ in }
    ) throws {
        for size in [nil, Self.largest] {
            let app = launch(arguments, api: api, textSize: size)
            // The closure is told which size it is in, because a screen does not
            // hold the same things at both: at the largest size a list that fits
            // in one screenful no longer does, and what is worth waiting for
            // changes with it.
            settle(app, size != nil)
            let at = size == nil ? "default text size" : "largest text size"
            try audit(app, "\(name), \(at)")
            app.terminate()
        }
    }

    /// The first thing anybody sees, and the only screen an 80-year-old reaches
    /// before the app is hers. A non-empty address with nothing behind it is
    /// enough: nothing here is fetched.
    func testOnboarding() throws {
        try sweep("Onboarding", arguments: [], api: "http://127.0.0.1:9") { app, _ in
            require(app.buttons.firstMatch, "a button on the onboarding screen")
        }
    }

    func testMemoriesWithContent() throws {
        try sweep("Muistot", arguments: ["-seed", "guess", "-tab", "memories"]) { app, isLargest in
            require(app.navigationBars["Muistot"], "the gallery")
            // At the largest text size the round's card fills the screen on its
            // own and the grid falls below the fold — and a LazyVGrid does not
            // build rows nobody can see, so the tiles are not off-screen, they
            // do not exist. Scrolling to them was tried and made the audit
            // worse: it measured mid-scroll and reported text as low-contrast
            // that was perfectly readable once the view stopped.
            //
            // So each size is audited for what it actually shows — the round at
            // the largest, the tiles at the ordinary one. The gap is real and
            // named here rather than hidden: nothing measures a photo tile at
            // XXXL.
            if !isLargest {
                require(photoTile(in: app), "the photo in the demo archive")
            }
        }
    }

    /// An empty state is not a blank screen in this app — it is an invitation,
    /// with a button on it. PLAN.md §6.5.
    func testMemoriesEmpty() throws {
        try sweep("Muistot, empty", arguments: ["-seed", "empty", "-tab", "memories"]) { app, _ in
            require(app.buttons.firstMatch, "the invitation on the empty gallery")
        }
    }

    /// The screen the app opens on and the one it exists for.
    func testTell() throws {
        try sweep("Kerro", arguments: ["-seed", "guess"]) { app, _ in
            require(app.staticTexts["Paina ja ala puhua"], "the record button's caption")
        }
    }

    func testTellByTyping() throws {
        try sweep("Kerro, typing", arguments: ["-seed", "guess", "-screen", "write"]) { app, _ in
            require(app.textViews.firstMatch, "the typing field")
            // The keyboard comes up with the screen, and auditing mid-animation
            // reported three elements with no description that were gone a
            // second later. Wait for it to arrive before measuring anything.
            require(app.keyboards.firstMatch, "the keyboard")
        }
    }

    func testPeople() throws {
        try sweep("Ihmiset", arguments: ["-seed", "guess", "-tab", "people"]) { app, _ in
            require(app.staticTexts["Aino"], "a person in the demo archive")
        }
    }

    func testPeopleEmpty() throws {
        try sweep("Ihmiset, empty", arguments: ["-seed", "empty", "-tab", "people"]) { app, _ in
            require(app.staticTexts.firstMatch, "the empty people state")
        }
    }

    /// A person's card carries the proposal row and the relationships, which are
    /// the two places in the app where a colour means something.
    func testPersonCard() throws {
        try sweep(
            "Person card",
            arguments: ["-seed", "guess", "-tab", "people", "-screen", "person"]
        ) { app, _ in
            require(app.buttons["Kerro tästä muisto"], "the person card")
        }
    }

    func testSettings() throws {
        try sweep(
            "Asetukset",
            arguments: ["-seed", "guess", "-tab", "people", "-screen", "settings"]
        ) { app, _ in
            require(app.buttons.firstMatch, "a row in Settings")
        }
    }

    /// The photo's own screen: the memory list, the recognition line and the
    /// two things you can do to a subject.
    func testPhotoDetail() throws {
        try sweep("Photo detail", arguments: ["-seed", "guess", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            require(app.buttons["Kerro tästä muisto"], "the photo's own screen")
        }
    }

    /// The way out of a misheard name. A sheet with a text field on it is the
    /// shape most likely to stop working at the largest size, and this one has
    /// to keep working: it is the only correction the archive offers once the
    /// telling is over.
    func testCorrectNameSheet() throws {
        try sweep("Korjaa nimi", arguments: ["-seed", "guess", "-tab", "people"]) { app, _ in
            require(app.cells.firstMatch, "a person in the list").tap()
            reach(app.buttons["Korjaa nimi"], in: app, "the correction button").tap()
            require(app.buttons["Tallenna"], "the correction sheet")
        }
    }

    /// Asking is the other half of the question loop, and it is a sheet with a
    /// text field — the one control type nothing else here covers.
    func testAskQuestionSheet() throws {
        try sweep("Kysy perheeltä", arguments: ["-seed", "guess", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Kysy perheeltä"], in: app, "the ask button").tap()
            let field = require(app.textFields.firstMatch, "the question field")
            // Typed, so the sheet is audited in the state a person acts in. The
            // send button is disabled until there is a question, and a disabled
            // control is drawn dim on purpose — that is what "not yet" looks
            // like on iOS, and the contrast minimum exempts inactive controls
            // for the same reason. The state worth measuring is the live one.
            field.tap()
            field.typeText("Millainen kesä mökillä oli?")
            require(app.buttons["Lähetä kysymys"], "the ask sheet")
        }
    }
}
