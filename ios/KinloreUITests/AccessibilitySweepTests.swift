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
///
/// **`testMemoriesWithContent` has failed once in a whole-suite run and passed
/// alone.** Measured 16 Aug 2026: 49 tests, 1170 seconds, that one red; the same
/// test, alone, on the same simulator and the same commit minutes later, green
/// in 27 seconds.
///
/// It was **not** the shared device. CLAUDE.md's usual explanation for a phantom
/// audit failure is two sessions on one simulator, and this run had a simulator
/// created for it and used by nothing else. So that explanation is spent here,
/// and the cause is unknown — which is why this note stops at what was measured
/// instead of naming one. The nearest suspicion, recorded as a suspicion: this
/// is the audit that ends in a screenshot through `ContrastMeter`, and a grid
/// still loading its content is a plausible place for `hasStoppedDrawing` to
/// answer a frame early. Nobody has shown that.
///
/// It is written down because of what a flaky audit costs rather than what it
/// broke. This suite is the only check on a rule the eye cannot apply, and a
/// test that is green alone and red in company is one whose red gets explained
/// away. The next person to see this failure should reproduce it before
/// believing it, and should also not shrug at it twice.
///
/// **`testCreateFamilyForm` joined it on 17 Aug 2026**, on a screen that run's
/// changes had not touched: two contrast findings with *no element and no
/// frame*, at the default size, red in an eleven-test run and green alone on
/// the same commit and the same private simulator minutes later. That is two
/// tests now with the same shape, both ending in unattributable findings —
/// which strengthens the suspicion above without confirming it, and keeps the
/// instruction the same: reproduce alone before believing a company red.
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

    /// Waits until an element has stopped moving.
    ///
    /// `reach` leaves a list mid-scroll, and an audit that samples a moving view
    /// reports colours nothing ever drew — that is what happened when the
    /// gallery's tiles were scrolled to, and it is why scrolling before an audit
    /// is otherwise avoided here. Polling the frame is deterministic where a
    /// sleep is a guess: two identical reads a beat apart mean the scroll is
    /// over, and a screen that never stops moving is a failure worth being told
    /// about rather than measuring anyway.
    private func settle(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var previous = element.frame
        for _ in 0 ..< 30 {
            Thread.sleep(forTimeInterval: 0.1)
            let current = element.frame
            if current == previous, current != .zero { return }
            previous = current
        }
        XCTFail("never stopped moving: \(element)", file: file, line: line)
    }

    /// Waits until the screen has stopped **being drawn**, which is not the same
    /// as `settle(_:)` above waiting until one element has stopped moving.
    ///
    /// A frame comes to rest before the drawing does: a scroll's deceleration,
    /// the tab bar's blur, a fade still compositing. That gap is what
    /// *"Potentially inaccessible text"* is made of — element detection compares
    /// the rendered image against the accessibility tree, so it is the one
    /// finding that can appear and vanish on identical code, with no element and
    /// no frame to point at. Two screenshots that come back byte for byte
    /// identical are the only honest way to say the screen is done.
    ///
    /// **Never on a screen that animates by design.** Four in this app cannot
    /// ever settle and would spend the whole deadline proving it: the record
    /// button pulsing `repeatForever`, the waveform redrawing from the
    /// recorder's levels every 50 ms, the asking screen's speaker symbol under
    /// `.symbolEffect`, and every `ProgressView` — the processing screens, the
    /// import overlay, the playback button's loading state.
    ///
    /// **And a fifth that is on no list of animations: a focused text field
    /// blinks.** `AskQuestionSheet` focuses itself on appear and the typing view
    /// is focused by the test, so both draw a caret about once a second for as
    /// long as they are open. `CorrectNameSheet` does not focus itself, which is
    /// the whole reason it can be waited for. Before using this on a screen, ask
    /// what is still moving on it — the answer is often a cursor.
    ///
    /// Returns whether it settled, and **the caller must not ignore the
    /// answer.** Auditing a screen that never stopped is measuring a moving
    /// view; proceeding quietly is the failure `require` was written against.
    private func hasStoppedDrawing(_ app: XCUIApplication, tries: Int = 20) -> Bool {
        var previous: Data?
        for _ in 0 ..< tries {
            let drawn = app.screenshot().pngRepresentation
            if drawn == previous { return true }
            previous = drawn
            Thread.sleep(forTimeInterval: 0.15)
        }
        return false
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
        settle: (XCUIApplication, Bool) throws -> Void = { _, _ in }
    ) throws {
        for size in [nil, Self.largest] {
            let app = launch(arguments, api: api, textSize: size)
            // The closure is told which size it is in, because a screen does not
            // hold the same things at both: at the largest size a list that fits
            // in one screenful no longer does, and what is worth waiting for
            // changes with it. It may also audit on its own — a screen whose
            // top and bottom cannot be on screen together has to be measured
            // twice, and only the closure knows where its landmarks are.
            try settle(app, size != nil)
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

    /// The two forms behind the onboarding buttons. Nothing had ever measured
    /// either of them — `testOnboarding` stops at the two buttons in front — and
    /// the blank form audited at six issues the first time it was looked at.
    ///
    /// Audited blank, which is how they are met and the state that used to grey
    /// the button out. Setup is also where the phone's owner is now asked about,
    /// and a question nobody can read sets up the wrong phone.
    func testCreateFamilyForm() throws {
        try sweep("Uusi arkisto", arguments: [], api: "http://127.0.0.1:9") { app, _ in
            require(app.buttons["Aloita perheen arkisto"], "the way into setup").tap()
            // The form's first section, because a `Form` does not build rows
            // nobody can see: at the largest text size a landmark further down
            // has not been made yet, and waiting for it reads as "the form never
            // arrived". That is what happened when §10 lever 2 put a section
            // above the one this used to watch for.
            require(app.staticTexts["Keiden kesken"], "the setup form")
        }
    }

    /// The one an 80-year-old reaches on her own, from a link, with nobody
    /// beside her.
    func testJoinFamilyForm() throws {
        try sweep("Liity perheeseen", arguments: [], api: "http://127.0.0.1:9") { app, _ in
            require(app.buttons["Liity kutsulinkillä"], "the way into joining").tap()
            require(app.staticTexts["Kutsu"], "the join form")
        }
    }

    /// Members, usage and the invite rows.
    ///
    /// Nothing had ever measured this screen, and nothing could: the rows come
    /// from what the Worker sends, so every run without a backend reached the
    /// offline note instead. `-seed family` is the missing half — the same hole
    /// `-mic denied` and `-screen result` were written to close, and this one had
    /// already let a button be renamed without being drawn.
    ///
    /// Both invite rows are asked for by name. They read *"Avoin kutsu"* and
    /// *"Käytetty 2 kertaa"* beside the same button, which is the length that
    /// matters at the largest text size.
    ///
    /// The rows are below the fold at both sizes — three sections sit above them
    /// — so this audits twice: the top as it opens, and the invites after a
    /// scroll. The top used to be a named gap — "nothing measures the members
    /// and the usage rows above" — and the gap was hiding a real failure for as
    /// long as it stood open: `LabeledContent` draws its values in the
    /// framework's own grey, which measured 3.44:1 on these rows. The colour is
    /// now said out loud in `FamilyScreen`, and this is what keeps it said.
    func testFamily() throws {
        try sweep(
            "Perhe",
            arguments: ["-seed", "family", "-tab", "people", "-screen", "family"]
        ) { app, isLargest in
            require(app.navigationBars["Perhe"], "the family screen")
            // By label *or* value: `LabeledContent` folds the row into one
            // element whose label is "Nimi" and whose value is the name, so
            // `staticTexts["Virtaset"]` matches nothing — measured here, the
            // first time this landmark was asked for.
            require(
                app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "label CONTAINS %@ OR value CONTAINS %@",
                        "Virtaset", "Virtaset"
                    ))
                    .firstMatch,
                "the family's name row"
            )
            XCTAssertTrue(
                hasStoppedDrawing(app),
                "the top of the Perhe screen was still being drawn when the audit ran"
            )
            try audit(
                app,
                "Perhe ylälaita, \(isLargest ? "largest text size" : "default text size")"
            )
            let open = reach(app.staticTexts["Avoin kutsu"], in: app, "the invite nobody has used")
            reach(app.staticTexts["Käytetty 2 kertaa"], in: app, "the invite somebody has")
            reach(app.buttons["Poista"].firstMatch, in: app, "the way to take an invite back")
            settle(open)
            // And then wait for the drawing, not only for the frame. This screen
            // reported "Potentially inaccessible text" once at the largest size
            // and not on the runs either side of it, on identical code — element
            // detection reads the rendered image, so a scroll that has stopped
            // moving but not stopped compositing is exactly what it catches.
            //
            // Asserted rather than merely waited on: the Perhe screen has no
            // animation of its own, so a screen still being drawn three seconds
            // later is news rather than weather.
            XCTAssertTrue(
                hasStoppedDrawing(app),
                "the Perhe screen was still being drawn when the audit ran"
            )
        }
    }

    func testMemoriesWithContent() throws {
        try sweep("Muistot", arguments: ["-seed", "archive", "-tab", "memories"]) { app, isLargest in
            require(app.navigationBars["Muistot"], "the gallery")
            // The gap that used to be here is closed. The guessing round's
            // card filled the screen at the largest text size and pushed the
            // grid below the fold, and a LazyVGrid does not build rows nobody
            // can see — so nothing measured a photo tile at XXXL, and two
            // attempts at scrolling first reported contrast failures on
            // elements the tree had at their pre-scroll frames. Cutting the
            // round (PLAN.md §5) took the card away, and the tiles are on
            // screen at both sizes again.
            require(photoTile(in: app), "the photo in the demo archive")
        }
    }

    /// The note that says a telling has not left the phone.
    ///
    /// It cannot be seeded: the demo archive is canned as already sent, so the
    /// waiting telling is made here — an address with nothing behind it, a
    /// family id, and one memory told into that. See `SyncVisibilityTests`.
    func testMemoriesWaitingToBeSent() throws {
        try sweep(
            "Muistot, odottaa lähetystä",
            arguments: ["-seed", "empty", "-defer", "structure", "-screen", "interview", "-family_id", "demo"],
            api: "http://127.0.0.1:9"
        ) { app, _ in
            require(app.staticTexts["Muisto tallennettu"], "a telling to be waiting for")
            app.tabBars.buttons["Muistot"].tap()
            require(
                app.staticTexts
                    .containing(NSPredicate(format: "label CONTAINS %@", "vain tässä puhelimessa"))
                    .firstMatch,
                "the waiting note"
            )
        }
    }

    /// The dead end at the end of a fruitless search. A search field, a keyboard
    /// and an empty state at once — three things that each cost a screen, on the
    /// screen that has the least room to spare.
    func testMemoriesSearching() throws {
        try sweep("Muistot, haku", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            require(app.navigationBars["Muistot"], "the gallery")
            let field = app.searchFields.firstMatch
            for _ in 0 ..< 3 where !field.exists { app.swipeDown() }
            require(field, "the search field").tap()
            field.typeText("traktori")
            require(app.staticTexts["Ei osumia"], "the fruitless search")
        }
    }

    /// An empty state is not a blank screen in this app — it is an invitation,
    /// with a button on it. PLAN.md §6.5.
    func testMemoriesEmpty() throws {
        try sweep("Muistot, empty", arguments: ["-seed", "empty", "-tab", "memories"]) { app, _ in
            require(app.buttons.firstMatch, "the invitation on the empty gallery")
        }
    }

    /// Where a telling ends: the saved line, the memory itself, and the two ways
    /// on from it. Nothing had ever audited this screen, and it carries the one
    /// green thing in the app — *"Muisto tallennettu"*.
    ///
    /// `-defer structure` is what holds it still: with no follow-up questions
    /// there is no interview to carry the run onwards. The proposal rows are not
    /// on it for the same reason, and nothing measures those yet.
    func testResult() throws {
        try sweep(
            "Tulos",
            arguments: ["-seed", "empty", "-defer", "structure", "-screen", "interview"]
        ) { app, _ in
            require(app.staticTexts["Muisto tallennettu"], "the result screen")
        }
    }

    /// The result screen **with its name proposals on it**, which is where a
    /// misheard name is caught before it becomes a person (rule 4).
    ///
    /// Nothing had measured these rows: a text field, a caption that turns the
    /// accent colour when it is edited, and two icon buttons. `-screen result`
    /// exists because the screen could not be held still otherwise — the
    /// interview starts talking a second later, and the verbatim path reaches
    /// the same screen with no proposals on it at all.
    func testResultWithProposals() throws {
        try sweep(
            "Tulos, nimiehdotukset",
            arguments: ["-seed", "empty", "-screen", "result"]
        ) { app, _ in
            require(app.staticTexts["Kuulinko nimet oikein?"], "the proposals")
        }
    }

    /// Where a telling lands when the text could not be made: the audio is
    /// safe, and three buttons lead on. Nothing had ever measured this screen —
    /// its real trigger is a spent quota or a dead connection, neither of which
    /// a run can schedule — and unmeasured it had failed worse than anything
    /// else seen at the largest size: the title clipped off the top, "Kirjoita
    /// se itse" truncated to one line, and the other two buttons sat below the
    /// bottom edge of a screen that could not scroll.
    ///
    /// `-defer once` records the couple of seconds by itself, so the run stays
    /// hands-free — except for the system's microphone prompt, which is real on
    /// a fresh device and pauses the recording under it. A `-mic granted` stub
    /// was tried instead and does not work: skipping the question skips nothing,
    /// because `record()` raises the same prompt itself a moment later. So the
    /// test answers the prompt the one way anything can — by tapping it. The
    /// grant sticks to the device, and the second size's run meets no prompt.
    func testAudioSaved() throws {
        try sweep(
            "Ääni tallessa",
            arguments: ["-seed", "empty", "-defer", "once"]
        ) { app, _ in
            // The alert belongs to SpringBoard, not to the app, and only a
            // device that has never been asked shows it. "Allow" is the
            // simulator's own locale — English on every device the CLAUDE.md
            // instructions create.
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            require(app.staticTexts["Äänesi on tallessa"], "the audio-saved screen")
            // No animation of its own once the recording has stopped, so still
            // being drawn is news — the same claim testFamily makes.
            XCTAssertTrue(
                hasStoppedDrawing(app),
                "the audio-saved screen was still being drawn when the audit ran"
            )
        }
    }

    /// The screen an 80-year-old is on while actually telling — and the one no
    /// sweep had ever audited: it animates continuously, so the settling the
    /// other tests wait for never comes, and it had been left out entirely.
    /// The audit itself needs no settled screen; what an animation costs is
    /// element-detection noise, so exactly that category is forgiven and every
    /// other — contrast, clipping, hit regions, Dynamic Type — is measured
    /// here for the first time. Not written through `sweep(...)` on purpose:
    /// verify.sh counts sweeps as settled-screen audits, and this one is the
    /// exception it would miscount. It really records and answers the prompt,
    /// like testAudioSaved.
    func testRecordingInProgressIsAudited() throws {
        for size in [nil, Self.largest] {
            let app = launch(["-seed", "empty"], textSize: size)
            require(app.buttons["Aloita kertominen"], "the record button").tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            require(app.staticTexts["Kuuntelen"], "the recording screen")
            let at = size == nil ? "default text size" : "largest text size"
            try audit(app, "Kuuntelen, \(at)", alsoAllowing: { issue in
                issue.auditType == .elementDetection
            })
            app.terminate()
        }
    }

    /// The screen behind a refused microphone. Two buttons and a paragraph, and
    /// nothing had ever looked at it — reaching it by hand means answering a
    /// system prompt with "Älä salli" and then digging the app out of iOS
    /// Settings again.
    func testMicrophoneDenied() throws {
        try sweep("Mikrofoni kielletty", arguments: ["-seed", "empty", "-mic", "denied"]) { app, _ in
            require(app.buttons["Aloita kertominen"], "the record button").tap()
            require(app.staticTexts["Mikrofoni ei ole käytössä"], "the refusal screen")
        }
    }

    /// The screen the app opens on and the one it exists for.
    func testTell() throws {
        try sweep("Kerro", arguments: ["-seed", "archive"]) { app, _ in
            require(app.staticTexts["Paina ja ala puhua"], "the record button's caption")
        }
    }

    /// The same screen on the first launch, which is a different screen: no
    /// memories means no open questions, so the two opening starters are on it
    /// instead. They are two cards below a 200 pt button on the app's most
    /// vertically crowded screen — exactly the shape of thing that pushes
    /// "Kirjoita sen sijaan" under the tab bar at the largest text size, and it
    /// is the one Tell screen an 80-year-old is handed cold.
    func testTellFirstLaunch() throws {
        try sweep("Kerro, first launch", arguments: ["-seed", "empty"]) { app, _ in
            require(
                app.staticTexts["Kuka on vanhin ihminen, jonka muistat?"],
                "the opening starter"
            )
        }
    }

    /// The tightest this screen ever gets, and the only version of it a person
    /// sees more than once by accident: an empty archive puts two starters below
    /// the button, and the microphone has not been asked about yet, so the
    /// sentence above it is the one about the permission.
    ///
    /// Both of those arrived from opposite ends and land on the same screen —
    /// which is why it is measured rather than reasoned about.
    func testTellPermissionUnasked() throws {
        try sweep(
            "Kerro, lupaa ei ole kysytty",
            arguments: ["-seed", "empty", "-mic", "unasked"]
        ) { app, isLargest in
            require(
                app.staticTexts
                    .containing(NSPredicate(format: "label BEGINSWITH %@", "Puhelin kysyy ensin"))
                    .firstMatch,
                "the sentence before the system prompt"
            )
            require(app.staticTexts["Paina ja ala puhua"], "the record button's caption")
            let typing = require(app.buttons["Kirjoita sen sijaan"], "the way that needs no permission")

            // Not merely present — *above the bar*. Existing is not the same as
            // reachable here: this screen is a ScrollView, so everything on it
            // exists whether or not anybody can see it, and the audit is told to
            // forgive contrast underneath the floating tab bar. Between them,
            // the one thing an added sentence actually does to this screen is
            // the one thing nothing was measuring — and it happened while this
            // very test was being written: two lines instead of one put the
            // keyboard way out under the bar.
            //
            // At the largest size the screen is taller than the phone on
            // purpose and scrolling is the design, so this is asked at the size
            // where it is a promise.
            if !isLargest {
                let bar = app.tabBars.firstMatch
                XCTAssertTrue(
                    bar.exists && typing.frame.maxY <= bar.frame.minY,
                    "\"Kirjoita sen sijaan\" is under the tab bar: "
                        + "\(NSCoder.string(for: typing.frame)) against \(NSCoder.string(for: bar.frame))"
                )
            }
        }
    }

    func testTellByTyping() throws {
        try sweep("Kerro, typing", arguments: ["-seed", "archive", "-screen", "write"]) { app, _ in
            require(app.textViews.firstMatch, "the typing field")
            // The keyboard comes up with the screen, and auditing mid-animation
            // reported three elements with no description that were gone a
            // second later. Wait for it to arrive before measuring anything.
            require(app.keyboards.firstMatch, "the keyboard")
        }
    }

    func testPeople() throws {
        try sweep("Ihmiset", arguments: ["-seed", "archive", "-tab", "people"]) { app, _ in
            require(app.staticTexts["Aino"], "a person in the demo archive")
        }
    }

    func testPeopleEmpty() throws {
        try sweep("Ihmiset, empty", arguments: ["-seed", "empty", "-tab", "people"]) { app, _ in
            require(app.staticTexts.firstMatch, "the empty people state")
        }
    }

    /// The memory row's own way out, which shows only on a telling of one's
    /// own. The fixture's memories are all Mummo's, so this one is told first
    /// and read back from its card, the way it would be the day after.
    func testMemoryCardOwnTelling() throws {
        try sweep(
            "Memory card with an own telling",
            arguments: ["-seed", "empty", "-defer", "structure", "-screen", "interview"]
        ) { app, _ in
            require(app.staticTexts["Muisto tallennettu"], "the result screen")
            let another = app.buttons["Kerro toinen muisto"]
            for _ in 0 ..< 4 where !another.exists { app.swipeUp() }
            require(another, "the way on from the result screen")
            another.tap()
            app.tabBars.buttons["Muistot"].tap()
            let row = app.staticTexts["Kerrottu muisto"].firstMatch
            require(row, "the telling in the gallery")
            row.tap()
            // On screen for the audit: at the largest size it is below the fold.
            let remove = app.buttons["Poista tämä muisto"]
            for _ in 0 ..< 4 where !remove.exists { app.swipeUp() }
            require(remove, "the card's way to take the telling back")
        }
    }

    /// The photo's own screen while nothing has been told about it, which is
    /// when it can be deleted: the fixture's photograph carries stories, so
    /// this one is imported empty.
    func testPhotoDetailWithoutAStory() throws {
        try sweep(
            "Photo detail without a story",
            arguments: ["-seed", "empty", "-tab", "memories", "-import", "2"]
        ) { app, _ in
            require(app.staticTexts["Milloin nämä olivat?"], "the import's date question")
            app.buttons["Vuosikymmen"].tap()
            reach(app.buttons["1950-luku"], in: app, "the decade to choose").tap()
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Poista kuva"], in: app, "the way to delete the photo")
        }
    }

    /// A person's card carries the proposal row and the relationships, which are
    /// the two places in the app where a colour means something.
    func testPersonCard() throws {
        try sweep(
            "Person card",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "person"]
        ) { app, _ in
            require(app.buttons["Kerro tästä muisto"], "the person card")
        }
    }

    func testSettings() throws {
        try sweep(
            "Asetukset",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "settings"]
        ) { app, _ in
            require(app.buttons.firstMatch, "a row in Settings")
        }
    }

    /// The Kerro tab with a card on it — a photograph nobody has spoken about,
    /// chosen by the deck rather than navigated to.
    ///
    /// The screen it replaces is a blank button, and this one is taller than
    /// any state it has had: a picture, a title, a starter question, the record
    /// button and two ways past it. The one thing that must survive is the
    /// order — the words are pinned and the picture yields, which is what makes
    /// it hold at the largest text size.
    func testTellWithACard() throws {
        try sweep("Kerro, kortti", arguments: ["-seed", "deck"]) { app, _ in
            // The question *is* the title on a card. Asked for by its own
            // words, because that is the change: the screen stopped saying
            // "tell about this" and started asking something answerable.
            require(app.staticTexts["Kuka tässä kuvassa on?"], "the card's question")
            require(app.buttons["En muista tätä"], "the way past a card")
        }
    }

    /// Photographing a paper photograph — the screen the shoebox comes in
    /// through. `-camera stub` draws the controls over an empty preview,
    /// because the simulator has no camera and `.ready` is otherwise
    /// unreachable on the one device every audit runs on.
    ///
    /// The words sit on a solid ground below the preview rather than over it,
    /// which is what makes this measurable at all: text on a live camera image
    /// has no contrast to measure.
    func testCameraCapture() throws {
        try sweep(
            "Kuvaus",
            arguments: ["-seed", "empty", "-tab", "memories", "-screen", "camera", "-camera", "stub"]
        ) { app, _ in
            require(app.buttons["Kuvaa"], "the shutter")
        }
    }

    /// A refused camera, which is a screen rather than a message — the same
    /// trade as the refused microphone: the dead end is replaced by the way
    /// out of it.
    func testCameraDenied() throws {
        try sweep(
            "Kamera evätty",
            arguments: ["-seed", "empty", "-tab", "memories", "-screen", "camera", "-camera", "denied"]
        ) { app, _ in
            require(app.buttons["Avaa asetukset"], "the way into settings")
        }
    }

    /// And a device that has no camera at all, which on this project is not a
    /// hypothetical: it is every simulator, and it is what a screenshot run
    /// meets by default.
    func testCameraUnavailable() throws {
        try sweep(
            "Ei kameraa",
            arguments: ["-seed", "empty", "-tab", "memories", "-screen", "camera", "-camera", "unavailable"]
        ) { app, _ in
            require(app.buttons["Valitse kuvista"], "the way on")
        }
    }

    /// The way out of the single-device archive, which `testSettings` cannot
    /// reach: that run has no backend address, `isLocalByChoice` is false, and
    /// the row, its header and its footer are on no audited screen at all. The
    /// footer is the long one — it says what changes about the recording, on
    /// the screen where somebody decides whether to let it change.
    func testSettingsLocalArchive() throws {
        try sweep(
            "Asetukset, vain tämä puhelin",
            arguments: [
                "-seed", "archive", "-local_only", "YES", "-tab", "people", "-screen", "settings",
            ],
            api: "http://127.0.0.1:9"
        ) { app, _ in
            reach(app.buttons["Ota perhe käyttöön"], in: app, "the way into a family")
        }
    }

    /// What is on the other side of that row: three sentences about a change
    /// that cannot be undone, and the button that makes it. It is a screen
    /// rather than a `confirmationDialog` because the dialog's row would not
    /// pass this audit at all — see `EnableSharingScreen`.
    func testEnableSharing() throws {
        try sweep(
            "Ota perhe käyttöön",
            arguments: [
                "-seed", "archive", "-local_only", "YES", "-tab", "people", "-screen", "sharing",
            ],
            api: "http://127.0.0.1:9"
        ) { app, _ in
            require(app.buttons["Ota perhe käyttöön"], "the door itself")
        }
    }

    /// The invitation's first step, which did not exist until the invitation
    /// started carrying a name. It is a sheet with a text field and a long
    /// explanation in it — the shape that has failed this audit before, on a
    /// `Form` footer holding a stack.
    func testInviteNaming() throws {
        try sweep(
            "Kutsu, kenelle",
            arguments: ["-seed", "family", "-tab", "people", "-screen", "family"]
        ) { app, _ in
            reach(app.buttons["Kutsu perheenjäsen"], in: app, "the invite row").tap()
            require(app.staticTexts["Kenelle kutsu menee?"], "the naming step")
        }
    }

    /// The settings only a family can see. `testSettings` runs without a
    /// family, so the Perhe row, "Poistu perheestä" and the in-family wipe
    /// footer were on no audited screen at all — and the section's bare
    /// header was the same framework grey the family screen's top audit
    /// reported on "Käyttö" and "Jäsenet". The rows sit below the fold at
    /// the largest size and a List does not build what nobody can see, so
    /// this scrolls to them and audits there, the way testFamily reaches
    /// its invites.
    func testSettingsInFamily() throws {
        try sweep(
            "Asetukset perheessä",
            arguments: ["-seed", "family", "-tab", "people", "-screen", "settings"]
        ) { app, _ in
            let familyRow = reach(
                app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "label CONTAINS %@", "Perheen jäsenet ja kutsut"
                    ))
                    .firstMatch,
                in: app,
                "the family row in Settings"
            )
            reach(app.buttons["Tyhjennä ja aloita alusta"], in: app, "the wipe row")
            settle(familyRow)
            XCTAssertTrue(
                hasStoppedDrawing(app),
                "the in-family Settings screen was still being drawn when the audit ran"
            )
        }
    }

    /// Telling about a photo: the Tell screen as a sheet on top of the photo's
    /// card. Nothing had audited this presentation, and it is the one whose way
    /// out is a toolbar button — the shape this app has already had to abandon
    /// three times for barely growing with Dynamic Type. Measured here rather
    /// than assumed.
    func testTellAboutAPhoto() throws {
        try sweep("Kerro kuvasta", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Kerro tästä muisto"], in: app, "the photo's card").tap()
            require(app.staticTexts["Paina ja ala puhua"], "the telling sheet")
        }
    }

    /// The date sheet: a wheel, a graphical date picker and four choices, on the
    /// screen that asks how sure somebody is before it asks what they know.
    func testDateSheet() throws {
        try sweep("Ajankohta", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Lisää ajankohta"], in: app, "the date row").tap()
            require(app.staticTexts["Kuinka tarkkaan tiedät?"], "the date sheet")
        }
    }

    /// The question an import asks about a whole pile of photographs at once.
    /// `-import 3` stands in for the system photo picker, which a test run
    /// cannot drive — see `ImportTests`.
    func testImportedPhotosDate() throws {
        try sweep(
            "Tuonnin ajankohta",
            arguments: ["-seed", "empty", "-tab", "memories", "-import", "3"]
        ) { app, _ in
            require(app.staticTexts["Milloin nämä olivat?"], "the import's date sheet")
        }
    }

    /// The help page. Six sections of plain text and the only place in the app
    /// that says the recording leaves the phone — which makes it the one screen
    /// here whose whole content is text, and text at XXXL is what this sweep
    /// exists for.
    func testHelp() throws {
        try sweep(
            "Näin tämä toimii",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "settings"]
        ) { app, _ in
            reach(app.buttons["Näin tämä toimii"], in: app, "the help row").tap()
            require(app.navigationBars["Näin tämä toimii"], "the help page")
        }
    }

    /// The photo's own screen: the memory list, the recognition line and the
    /// two things you can do to a subject.
    func testPhotoDetail() throws {
        try sweep("Photo detail", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            require(app.buttons["Kerro tästä muisto"], "the photo's own screen")
        }
    }

    /// The way out of a misheard name. A sheet with a text field on it is the
    /// shape most likely to stop working at the largest size, and this one has
    /// to keep working: it is the only correction the archive offers once the
    /// telling is over.
    func testCorrectNameSheet() throws {
        try sweep("Korjaa nimi", arguments: ["-seed", "archive", "-tab", "people"]) { app, _ in
            require(app.cells.firstMatch, "a person in the list").tap()
            reach(app.buttons["Korjaa nimi"], in: app, "the correction button").tap()
            require(app.buttons["Tallenna"], "the correction sheet")
            // A sheet is presented with an animation, and this one failed inside
            // a full suite with two Dynamic Type findings and then passed three
            // times in isolation on the same build — the second test to show
            // that shape in a day. Under a suite's load the presentation takes
            // longer, and the audit read the sheet on its way in.
            //
            // Safe to wait for because this sheet does not focus its field: the
            // caret would blink for ever and the wait would time out. See
            // `hasStoppedDrawing(_:)`.
            XCTAssertTrue(
                hasStoppedDrawing(app),
                "the correction sheet was still being drawn when the audit ran"
            )
        }
    }

    /// Asking is the other half of the question loop, and it is a sheet with a
    /// text field — the one control type nothing else here covers.
    func testAskQuestionSheet() throws {
        try sweep("Kysy perheeltä", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
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

    /// The joiner's landing: straight onto Muistot, with a waiting state in
    /// place of an invitation that would be false. `-seed arrival` sets the
    /// same one-shot flag a real join sets, so the navigation bar reading
    /// "Muistot" — with no `-tab` argument anywhere — *is* the landing
    /// mechanism being exercised, not a simulation of its outcome. The waiting
    /// state itself exists only while the first pull is in flight, which no
    /// run can hold still, so the same seed forces it. See docs/UX.md §4.3.
    func testMemoriesArrival() throws {
        try sweep("Muistot, saapuminen", arguments: ["-seed", "arrival"]) { app, _ in
            require(app.navigationBars["Muistot"], "the landing on Muistot")
            require(
                app.staticTexts
                    .containing(NSPredicate(format: "label CONTAINS %@", "Haetaan perheen muistoja"))
                    .firstMatch,
                "the waiting state"
            )
        }
    }

    /// The offer slot while the family is one person: the invitation, not the
    /// paid archive — *"yksi maksaja avaa sen koko perheelle"* is a false
    /// sentence with nobody to open it for. `-tellings-since-upsell 2` puts
    /// the rhythm one telling from offering, and `-defer structure` keeps the
    /// result free of proposals, which is the slot's other gate. Nothing had
    /// ever audited a card in this slot: the paid one needs usage rows only a
    /// backend sends. See docs/UX.md §3.2.
    func testResultOffersTheFamily() throws {
        try sweep(
            "Tulos, kutsukortti",
            arguments: [
                "-seed", "alone", "-defer", "structure", "-screen", "interview",
                "-tellings-since-upsell", "2",
            ]
        ) { app, _ in
            require(app.staticTexts["Muisto tallennettu"], "the result screen")
            let invite = reach(
                app.buttons["Kutsu perheenjäsen"], in: app, "the invitation in the offer slot"
            )
            settle(invite)
        }
    }

    /// The reading half of the promise: what the family told while this phone
    /// was away, at the top of Muistot — and the landing that follows from it,
    /// with no `-tab` argument anywhere, which is the derivation being
    /// exercised. `-seed unseen` is the demo archive plus an empty
    /// seen-baseline, so Mummo's tellings are waiting; a real one needs a
    /// second device to have told something between visits. See docs/UX.md §6.
    func testMemoriesNewFromFamily() throws {
        try sweep("Muistot, uutta perheeltä", arguments: ["-seed", "unseen"]) { app, _ in
            require(app.navigationBars["Muistot"], "the landing on Muistot")
            require(app.staticTexts["Uutta perheeltä"], "the section heading")
            require(
                app.buttons
                    .matching(NSPredicate(format: "label CONTAINS %@", "Mummo kertoi"))
                    .firstMatch,
                "a telling by somebody else"
            )
        }
    }

    /// The note about photographs the free ceiling refused. Its real trigger
    /// needs a Worker and a family over its limit, which is why the refusal
    /// was swallowed unseen for as long as it was — nothing could ever look
    /// at it. `-photos-refused` holds the state still, the same shape of
    /// answer as `-mic denied`. See docs/UX.md §9.
    func testMemoriesPhotosOverQuota() throws {
        try sweep(
            "Muistot, kuvaraja",
            arguments: ["-seed", "archive", "-tab", "memories", "-photos-refused", "2"]
        ) { app, _ in
            require(
                app.staticTexts
                    .containing(NSPredicate(format: "label CONTAINS %@", "ei mahtunut ilmaiseen arkistoon"))
                    .firstMatch,
                "the photo-ceiling note"
            )
        }
    }

    /// The blind confirmation: the one card on this screen with no record
    /// button on it.
    ///
    /// Four answers stand where the 200 pt disc does, and a fifth way past
    /// below them — three more rows than the deck's card carries, on the screen
    /// this project has already measured to its limit twice. The first build
    /// drew *"En muista"* underneath the floating tab bar at the **ordinary**
    /// text size, which is what the spacing on `blindContent` is set to and
    /// says.
    func testBlindConfirmation() throws {
        try sweep("Sokkovahvistus", arguments: ["-seed", "blind"]) { app, _ in
            reach(
                app.buttons["En muista"], in: app,
                "the way past a face she cannot place"
            )
        }
    }

    /// And what the card says afterwards, which is a second shape on it: the
    /// answers go and one sentence takes their place.
    ///
    /// Audited on the branch that confirms nothing, because that is the
    /// sentence the app has to say without claiming anything — and because it
    /// is reachable without changing the archive, so the audit measures a card
    /// rather than a side effect.
    func testBlindConfirmationAfterAnswering() throws {
        try sweep("Sokkovahvistus, vastattu", arguments: ["-seed", "blind"]) { app, _ in
            reach(
                app.buttons["En muista"], in: app,
                "the way past a face she cannot place"
            ).tap()
            reach(app.buttons["Jatka"], in: app, "the way on from the answer")
        }
    }
}
