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
///
/// **`testMemoriesNewFromFamily` is a third, and it breaks the pattern the
/// other two set.** Measured 12 Sep 2026: four consecutive runs of that test
/// *alone*, same binary, same private simulator, no other test in the run —
/// **passed, passed, failed, failed**. So "green alone and red in company" is
/// not the shape here. It flips alone, and its finding names an element and a
/// frame (`Contrast failed — "K"`, the avatar) where the other two named
/// nothing.
///
/// One honest difference from the 16 Aug measurement, which was taken on a
/// quiet machine: this one was not. The simulator was private but the host was
/// carrying four or five other booted devices and sat at 18–40 % idle
/// throughout. That does not explain a *pass* — starvation invents failures,
/// not passes — so the two greens are real and the flakiness is real, but
/// whether a quiet host would show the same ratio is untested.
///
/// **The cost of this one was paid before it was measured.** It was used twice
/// as evidence about a change to `SubjectAvatar` — once to conclude a fix had
/// worked, once to conclude a different fix had broken something — and both
/// readings were noise. `testPeople` covers the same component and did
/// discriminate cleanly, four runs to four. Until somebody re-measures this
/// test on a quiet host, do not let it arbitrate a change on its own.
/// **`testNamePhotoSheet` is a fourth, and it failed in a way none of the
/// others did.** Measured 12 Sep 2026: in a 138-test run it reported no
/// finding at all — the audit itself gave up, `Code=-56 "Audit failed to
/// complete in time"`, after 194 seconds. Alone, on a private simulator and
/// pinned to the same commit in a worktree of its own, it passed three times:
/// 44.4 s, 41.6 s, 54.7 s.
///
/// The shape is the first two tests' rather than the third's — green alone, red
/// in company, the finding naming nothing. What is new is the failure mode. A
/// timeout is the one red the pixel method in CLAUDE.md cannot answer, because
/// a busy machine can make the audit report a colour that is not there but the
/// colour it reports is still measurable; here there is no colour at all.
///
/// And the host was not starved. Four devices booted throughout, 34 s per test
/// against the 25 s this suite has run at, and the tree clean before the build
/// and after it. So an audit can run out of time under ordinary load, which is
/// worth knowing separately from what eight booted devices do.
///
/// Three greens are not proof the test is sound: the third test above gave two
/// greens before two reds. They are enough to say this red was not a
/// measurement of the screen.
///
/// **One timeout has a measured cause now, and it is not load.** On 25 Sep
/// 2026 `testFamilyTreeAtSize` gave up at the largest text size on every
/// run — alone, on a private simulator, at a load of 20 and of 700 alike —
/// and the contrast check did it by itself: 15.0 s with a handler that only
/// counted, while each of the other six checks finished in under four. A
/// `sample` of that simulator's testmanagerd named the work: twenty leaked
/// `com.apple.axAudit.automation` queues, one per audit that had given up,
/// every one still inside `-[AXAuditContrastDetectionManager
/// _topColorsForImageData:optimized:]` walking `-[UIDeviceRGBColor
/// isEqual:]` chains. The check reads a text element's pixels into a set of
/// colours one by one, and a region with thousands of distinct colours is
/// one it does not finish. Glass is such a region: the tree's two
/// `.bordered` capsules were text on it and its tab bar was glass over the
/// row beneath, and at the largest size those regions run to hundreds of
/// thousands of pixels. The same check over main's tree, on the same
/// simulator two minutes apart, took 0.8 s — its buttons were images and
/// its opening kept the names out of the strip. With the capsules paper and
/// the drawing inside the tab bar: 0.3 s.
///
/// Two things follow that are worth more than the finding. **An audit that
/// gives up does not stop.** Its thread runs on, each timeout slows every
/// audit after it on that simulator, and after enough of them the runner
/// cannot start at all — "Timed out waiting for AX loaded notification",
/// testmanagerd at 800 % of a core, the machine's load in the hundreds for
/// every session on it. That is what the evening's two "runaway
/// testmanagerd"s were, and only `kill -9` ends one. And **a red that
/// reproduces alone at any load is a finding**, whatever the paragraphs
/// above say about company: the pixel method in CLAUDE.md answers a colour
/// the audit reported, and this audit reported nothing — which the lines
/// above already say to reproduce before believing, and which, reproduced,
/// still took a sample of the daemon to explain.
///
/// **Six reds in one suite run on `main`, 26 Sep 2026, each run alone twice
/// on a private simulator in Finnish before anything was touched.** Four
/// were the company shape — `testCreateFamilyForm` (180 s, 166 s),
/// `testFamily` (352 s, 329 s: some 2 500 activities and no gap above eight
/// seconds, so not the glass timeout above), `testMemoriesNewFromFamily`
/// (27 s, 22 s) and `testMemoriesWithContent` (26 s, 21 s) — green both
/// times with three to five other sessions' devices booted throughout, and
/// nothing was changed for them. `testSettingsInFamily` took the same shape
/// in the full run after the fix: red at `scrollToTop`'s tenth flick ("never
/// reached the top of the list", 95 s, load 25 to 110), then alone green
/// three times out of four (214 s, 209 s, 158 s), the one red at load 60
/// while another session's device was booting. Nothing was changed for it
/// either. The other two, `testPersonCardWithoutAStory`
/// and `testPersonCardWithAFriend`, reproduced alone with frames identical
/// to the decimal, and were the audit's default-size simulation rather than
/// the screen: the measurement is beside
/// `AccessibilityPolicy.isDefaultSizeSimulationArtefact`.
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
    ///
    /// Four swipes unless told otherwise, which is what every screen here
    /// needed until `-seed aimed` put two questions between the photograph's
    /// memories and its ask button.
    @discardableResult
    private func reach(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ what: String,
        swipes: Int = 4
    ) -> XCUIElement {
        for _ in 0 ..< swipes where !element.exists {
            app.swipeUp()
        }
        return require(element, what)
    }

    /// A spoken telling through the stub pipeline, up to the question the app
    /// asks back: the button, two seconds, the stop — under a second is thrown
    /// away as an accident. Since 26 Sep 2026 a spoken telling goes straight
    /// on to its first question, and `-voice stub` keeps that question on the
    /// screen, "read" until something stops it, so nothing arms the
    /// microphone while a test is looking.
    private func tellAloud(_ app: XCUIApplication) {
        require(app.buttons["Aloita kertominen"], "the record button").tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        require(app.staticTexts["Kuuntelen"], "the recording screen")
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()
        XCTAssertTrue(
            app.buttons["Riittää tältä erää"].waitForExistence(timeout: 30),
            "never arrived: the question a spoken telling goes on to"
        )
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

    /// Brings an element's top edge to `y` and leaves it there, for a sweep
    /// whose audit depends on where one row sits. A swipe coasts on past its
    /// finger and `auditPageByPage`'s half-screen steps end wherever a page
    /// ends, so this drags slowly, with no momentum, measures the frame again
    /// and drags the difference, at most 330 pt at a time — the room between
    /// the two bars on either side of where each drag starts. It stops when
    /// the list stops moving the element, which is where the list ends.
    ///
    /// **Each drag is 10 pt longer than the distance**, because the list does
    /// not move for the first 10 pt of a finger: a 165.67 pt drag moved the
    /// photo card's heading 155.67 pt, twice (26 Sep 2026), and a correction
    /// of the 10 pt left over then moved nothing, which read as the list's end.
    ///
    /// It asserts nothing about where the element came to rest. The caller
    /// does, because only the caller knows which edge of it matters.
    private func drag(_ element: XCUIElement, toMinY y: CGFloat, in app: XCUIApplication) {
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        var last = CGFloat.nan
        for _ in 1 ... 12 {
            settle(element)
            let top = element.frame.minY
            if abs(top - y) < 3 || abs(top - last) < 0.5 { return }
            last = top
            let move = max(-330, min(330, top - y + (top > y ? 10 : -10)))
            let start = origin.withOffset(CGVector(dx: 200, dy: move > 0 ? 600 : 260))
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -move)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
    }

    /// The last thing on the Settings screen of a phone that can leave its
    /// family: the footer under the wipe row, which tells leaving from
    /// emptying. The other two states have one row and nothing to tell it
    /// from, so since 26 Sep 2026 they have no footer there, and their sweeps
    /// end at the wipe row itself.
    private func settingsFooter(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Perheestä poistuminen"
        )).firstMatch
    }

    /// What audits inside a `sweep` closure have already judged, so that the
    /// loss check below counts a screen measured page by page as measured.
    private var judgedAbove: Set<String> = []

    /// The labels in the tree right now. Read **before** an audit, never
    /// after: the audit changes the tree it judged — see the loss check.
    private func labelsInTree(_ app: XCUIApplication) -> Set<String> {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let buttons = app.buttons.allElementsBoundByIndex.map(\.label)
        return Set((texts + buttons).filter { !$0.isEmpty })
    }

    /// Scrolls a list back to its top: flicks down until one more changes
    /// nothing. Not a tap on the status bar, which was the first version and
    /// works on the setup forms and not under a tab bar — on Asetukset it
    /// left the list at its bottom, measured 21 Sep 2026, so every "page 1"
    /// there was the last page.
    private func scrollToTop(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var previous: [String: CGRect] = [:]
        for _ in 0 ..< 10 {
            app.swipeDown(velocity: .fast)
            _ = hasStoppedDrawing(app)
            let words = app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex
            let now = Dictionary(words.map { ($0.label, $0.frame) }, uniquingKeysWith: { first, _ in first })
            if now == previous { return }
            previous = now
        }
        XCTFail("never reached the top of the list", file: file, line: line)
    }

    /// Whether a line of text sits across the navigation bar's lower edge,
    /// where iOS 26 blurs and fades it. The audit reports that line as a
    /// contrast failure with no element, so there is no frame to measure; it
    /// is forgiven on exactly this condition, and a finding with an element
    /// is judged as before. Measured 21 Sep 2026 on the setup form's second
    /// page, three runs out of three, the last at load 10: the audit's own
    /// picture shows *"Vain minulle,"* blurred under *"Uusi arkisto"* and
    /// nothing else on the page below the minimum.
    ///
    /// A button counts as a word: the line on that page is a row of the inline
    /// picker, which the tree holds as one. So does a text field with words in
    /// it, since 26 Sep 2026: the join form's code field, across the edge at
    /// 111–133 pt under a bar ending at 116, was the finding on eleven pages
    /// out of eleven and on none where it was clear of the edge.
    ///
    /// A screen with no bar has no edge to cross, and `frame` on a bar that is
    /// not there throws rather than answering. Both callers run this on a
    /// form today — the page loop, and `sweep`'s own audit where a sweep asks
    /// for the allowance — and the guard stays because for one build it ran
    /// under every sweep and the welcome screen failed at once (26 Sep 2026,
    /// `testOnboarding`, 7 s).
    private func wordCrossesTheBarEdge(_ app: XCUIApplication) -> Bool {
        let bar = app.navigationBars.firstMatch
        guard bar.exists else { return false }
        let barEdge = bar.frame.maxY
        let words = app.staticTexts.allElementsBoundByIndex
            + app.buttons.allElementsBoundByIndex
            + app.textFields.allElementsBoundByIndex
        return words.contains { $0.frame.minY < barEdge && $0.frame.maxY > barEdge }
    }

    /// Audits a screen that is taller than the phone one page at a time, down
    /// to `bottom`, and leaves the last page to `sweep`'s own audit.
    ///
    /// One audit cannot judge such a screen: a `Form` holds only the rows near
    /// the screen, so at the largest text size the rest is not in the tree the
    /// audit reads. Measured with `KINLORE_XXXL_LOSS` on 21 Sep 2026: the
    /// setup form is several screenfuls tall there, and the audit had judged the
    /// first — *"Kuka sinä olet"*, the phone question, the consent notice and
    /// *"Luo arkisto"* were never in front of it. Top and bottom alone are not
    /// enough either; the questions are in the middle.
    ///
    /// Scrolling before an audit is what `reach` warns against, and the answer
    /// is the one it gives: every page is waited out before it is judged. The
    /// step is a slow drag of half the screen, not a swipe, so that it carries
    /// no momentum past a row and every page overlaps the one before it.
    ///
    /// **Each page is found from the top, not from the page before it**,
    /// because the audit moves the list. Measured 21 Sep 2026 on this form:
    /// with an audit between the drags the pages ran 1 to 5, back to 2, on to
    /// 5 and back to the top, twelve pages without reaching the button; the
    /// same drags with no audit between them ran 1 to 6 and reached it on the
    /// seventh. The audit simulates other text sizes on the live screen, and
    /// the list does not come back to where it was — nor, straight after an
    /// audit, with the rows it had, which is why the loss check reads the tree
    /// before one.
    private func auditPageByPage(
        _ app: XCUIApplication,
        _ context: String,
        to bottom: XCUIElement,
        _ what: String
    ) throws {
        let window = app.windows.firstMatch
        // On screen means above the tab bar where there is one: the tree holds
        // a row under the translucent bar as hittable, and the audit forgives
        // contrast there by geometry, so a last row that stopped under the bar
        // would be judged by nobody. A point of slack, because a list at its
        // end rests its last footer on the bar's edge and not a hair above
        // it: 791.33 against a bar at 791 on Asetukset, measured 21 Sep 2026.
        let bar = app.tabBars.firstMatch
        let floor = bar.exists ? bar.frame.minY : window.frame.maxY
        let onScreen = { bottom.exists && bottom.isHittable && bottom.frame.maxY <= floor + 1 }
        for page in 1 ... 12 {
            // From the top every time — the first page too, since a caller
            // may have scrolled on its way here.
            scrollToTop(app)
            for _ in 1 ..< page {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                    .press(forDuration: 0.1, thenDragTo:
                        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
            }
            if page > 1, onScreen() { break }
            XCTAssertTrue(hasStoppedDrawing(app), "\(context), page \(page), was still being drawn")
            judgedAbove.formUnion(labelsInTree(app))
            // **A word half under the navigation bar.** A page reached by
            // dragging rarely starts on a row's edge, so a line of text sits
            // across the bar's lower edge, where iOS 26 blurs and fades it —
            // the tab bar's fade, at the other end of the screen, which a
            // sweep audited from the top had never met. What is forgiven for
            // it, on exactly that condition, and the measurement behind it
            // are on `wordCrossesTheBarEdge`.
            let underTheBar = wordCrossesTheBarEdge(app)
            // Every page is reported, for the reason `sweep` gives about both
            // sizes: a finding on one page says nothing about the next.
            do {
                let abortAfterAudit = continueAfterFailure
                continueAfterFailure = true
                defer { continueAfterFailure = abortAfterAudit }
                try audit(app, "\(context), page \(page)", alsoAllowing: { issue in
                    underTheBar && issue.auditType == .contrast && issue.element == nil
                })
            }
        }
        require(bottom, what)
        XCTAssertTrue(onScreen(), "\(what) was never scrolled onto the screen")
        XCTAssertTrue(hasStoppedDrawing(app), "\(what) was still moving when the audit ran")
    }

    /// Audits a screen at both sizes in one test, so a failure names the screen
    /// rather than an index into a list.
    ///
    /// `forgivingTheBarEdge` extends the page loop's one allowance — a word
    /// across the navigation bar's lower edge, `wordCrossesTheBarEdge` — to
    /// the screen the closure ends on. Asked for by the sweeps that measured
    /// it and by no other: the two error-note sweeps of the welcome forms,
    /// where the join form's code field sits across that edge on the last
    /// page (26 Sep 2026). For one build it ran under every sweep, which was
    /// wrong twice over — an allowance measured on two forms would have
    /// covered eighty-nine screens it was never measured on, and reading
    /// every word's frame before each audit is hundreds of queries on the
    /// album or the tree. Every other sweep judges its last screen as before.
    private func sweep(
        _ name: String,
        arguments: [String],
        api: String = "",
        forgivingTheBarEdge: Bool = false,
        settle: (XCUIApplication, Bool) throws -> Void = { _, _ in }
    ) throws {
        // What each size put in the accessibility tree, collected only when
        // `KINLORE_XXXL_LOSS` asks for it. See the comparison below.
        var seen: [Bool: Set<String>] = [:]
        let wantsLossCheck = ProcessInfo.processInfo.environment["KINLORE_XXXL_LOSS"] != nil
        for size in [nil, Self.largest] {
            judgedAbove = []
            let app = launch(arguments, api: api, textSize: size)
            // The closure is told which size it is in, because a screen does not
            // hold the same things at both: at the largest size a list that fits
            // in one screenful no longer does, and what is worth waiting for
            // changes with it. It may also audit on its own — a screen whose
            // top and bottom cannot be on screen together has to be measured
            // twice, and only the closure knows where its landmarks are.
            try settle(app, size != nil)
            let at = size == nil ? "default text size" : "largest text size"
            // Both sizes are reported, even when the first one fails.
            //
            // `continueAfterFailure` is false for this class, and for the
            // settle step above it must stay false: `require` asserts and
            // returns rather than throwing, so a screen that never arrived
            // would otherwise be audited under the name of the screen the test
            // failed to reach — which is what `testAskQuestionSheet` did.
            //
            // The audit is the opposite case. The two rounds of this loop are
            // independent launches, so a failure in the first says nothing
            // about the second, and aborting hides half of every red sweep.
            // Measured 19 Sep 2026: testFamilyTree opened the app once and
            // reported five findings at the default size, and the six it also
            // had at the largest size — where the names are drawn SMALLER than
            // at the default size, which is the defect — were invisible until
            // the flag was flipped by hand in a worktree. Two sessions read
            // that silence as a clean largest size on the same day. With this
            // in place the same test opens the app twice and reports both.
            let abortAfterAudit = continueAfterFailure
            continueAfterFailure = true
            defer { continueAfterFailure = abortAfterAudit }
            if wantsLossCheck {
                seen[size != nil] = labelsInTree(app).union(judgedAbove)
            }
            // The first launch is where the audit simulates the scaling, and
            // the simulation's artefact lives there only, as does the join
            // form's filled code field's; the second launch is the real
            // layout, with nothing forgiven. The policy says why.
            // And the page loop's one allowance, for the screen a closure ends
            // on, where the sweep has asked for it: a word across the bar's
            // lower edge. The join form's error note is at the bottom of a
            // form whose code field then sits across that edge — reported on
            // eleven pages out of eleven on 26 Sep 2026 and on none where the
            // field was clear of it. Not computed otherwise: it reads every
            // word's frame, and a sweep that has not asked forgives nothing.
            let underTheBar = forgivingTheBarEdge && wordCrossesTheBarEdge(app)
            try audit(app, "\(name), \(at)", alsoAllowing: { issue in
                size == nil && AccessibilityPolicy.isDefaultSizeSimulationArtefact(issue)
                    || size == nil && AccessibilityPolicy.isInviteCodeSimulationArtefact(issue)
                    || underTheBar && issue.auditType == .contrast && issue.element == nil
            })
            app.terminate()
        }
        // **What the audit at the largest size could not see.**
        //
        // A sweep that reports nothing at the largest text size reads as a
        // clean screen, and it is not the same claim: an element the tree no
        // longer holds is an element the audit did not judge. SwiftUI builds
        // a list's rows lazily — the note above `testCreateFamilyForm` is the
        // same fact from the other end — so a screen that grows one row can
        // push its lower half past whatever has been built, silently, in the
        // direction that looks like success.
        //
        // Measured 19 Sep 2026. On a build carrying an extra row under the
        // place card's map, that screen held 19 labels at the default size
        // and 9 at the largest: ten gone, including both sentences the audit
        // had reported, *"Kuuntele omalla äänellä"* and a person's name. In
        // the same run Albumi, Ihmiset as a list, Kerro and the drawn family
        // tree at `-seed clan` lost none — 11, 17, 8 and 83 labels, identical
        // at both sizes. So the loss is not a property of the largest size;
        // it is what a particular screen does there, and nothing reports it.
        //
        // **Behind a variable rather than on by default, and now measured.**
        // The labels are read *before* the audit, and until 21 Sep 2026 they
        // were read after it — which is not the same tree. The audit simulates
        // other text sizes on the live screen and leaves a list scrolled and
        // half rebuilt: on the setup form the tree held the consent notice
        // and *"Luo arkisto"* just before the audit and only the navigation
        // bar just after. The first full run was taken that way and said 29
        // of 69; read before the audit, the same class at `e59846f` plus this
        // change says 26, and `testFamily` falls from 22 of 27 to 14.
        //
        // On by default it would be red on over a third of the suite, and
        // much of that red is not a gap in the audit — the screen behind a
        // sheet, which that screen's own sweep judges, and a wheel picker
        // showing fewer years. The rest is: Näin tämä toimii and the album
        // by decade are judged at the largest size only as far as the first
        // screen reaches. The two setup forms, Perhe and all three states of
        // Asetukset were on that list and are not any more — they are
        // audited page by page (`auditPageByPage`), and each one's loss
        // check is green, measured one at a time on 21 Sep 2026.
        if let atDefault = seen[false], let atLargest = seen[true] {
            let lost = atDefault.subtracting(atLargest).sorted()
            XCTAssertTrue(
                lost.isEmpty,
                "\(name): \(lost.count) of \(atDefault.count) labels are in the tree at the"
                    + " default text size and gone at the largest, so the audit there judged"
                    + " less than the screen: "
                    + lost.prefix(10).map { String($0.prefix(60)) }.joined(separator: " | ")
            )
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

    /// What a phone the server knows as a member meets instead of the fork,
    /// after the app was deleted or on a new phone on the same Apple account
    /// (`ReturningPhoneTests`, docs/UX.md §4.5). The family's name is the
    /// founder's, at a size of its own.
    func testReturningPhone() throws {
        try sweep("Paluu perheeseen", arguments: ["-seed", "returning"], api: "http://127.0.0.1:9") { app, isLargest in
            require(app.buttons["Avaa perheen arkisto"], "the page that offers the family back")
            // What the page says, with its button still on screen. At the
            // largest size the sentence used to be dropped for the button's
            // sake, and the page read as a title and a button (the English
            // read-through of 26 Sep 2026, 801); a shorter one fits.
            let sentence = isLargest
                ? app.staticTexts["Muistot haetaan tähän puhelimeen."]
                : app.staticTexts["Olet tämän perheen jäsen, ja sen muistot haetaan tähän puhelimeen."]
            XCTAssertTrue(sentence.exists, "the page does not say what it does")
            let button = app.buttons["Avaa perheen arkisto"]
            XCTAssertTrue(
                app.windows.firstMatch.frame.contains(button.frame),
                "the button is not on screen beside the sentence: \(button.frame)"
            )
        }
    }

    /// The notice a join leaves when it made this phone another member — a
    /// second phone on the same Apple ID (`SharedAppleIDTests`). The alert is
    /// iOS's own and is read rather than audited, as the removal's is in
    /// `testFamily`, where the reason is measured; what is audited is the
    /// archive it leaves once "Selvä" has been pressed, at both sizes.
    func testSharedAppleIDNotice() throws {
        try sweep(
            "Sama Apple ID",
            arguments: ["-seed", "joined", "-joinedAs", "Aino", "-joinTyped", "Eino"]
        ) { app, _ in
            let notice = app.alerts["Tällä puhelimella olet Kinloressa Aino"]
            require(notice, "the notice a join as somebody else leaves")
            require(
                notice.staticTexts.matching(NSPredicate(
                    format: "label BEGINSWITH %@", "Tämä puhelin käyttää samaa Apple ID:tä kuin Aino"
                )).firstMatch,
                "the notice's message, with the name in it"
            )
            notice.buttons["Selvä"].tap()
            XCTAssertTrue(notice.waitForNonExistence(timeout: 10), "the notice did not close on Selvä")
        }
    }

    /// The same phone when nothing answered — the page it can be left on,
    /// with the button that asks again.
    func testReturningPhoneUnanswered() throws {
        // The question is asked only of an identity that was already here.
        launch([], api: "http://127.0.0.1:9").terminate()
        try sweep("Odotetaan yhteyttä", arguments: ["-homecoming", "ask"], api: "http://127.0.0.1:9") { app, isLargest in
            require(app.buttons["Yritä uudelleen"], "the page that waits for the server")
            // Why the page waits, at both sizes. At the largest size it kept
            // only the half that says the app tries again by itself (the
            // English read-through of 26 Sep 2026, 802); there is room for
            // the half that says what did not answer.
            let sentence = isLargest
                ? app.staticTexts["Perheen palvelu ei vastannut. Sovellus yrittää itse uudelleen."]
                : app.staticTexts["Perheen palvelu ei vastannut. Sovellus yrittää itse uudelleen, kun yhteys palaa."]
            XCTAssertTrue(sentence.exists, "the page does not say what it waits for")
            let button = app.buttons["Yritä uudelleen"]
            XCTAssertTrue(
                app.windows.firstMatch.frame.contains(button.frame),
                "the button is not on screen beside the sentence: \(button.frame)"
            )
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
        try sweep("Uusi arkisto", arguments: [], api: "http://127.0.0.1:9") { app, isLargest in
            require(app.buttons["Aloita perheen arkisto"], "the way into setup").tap()
            // The form's first section, because a `Form` does not build rows
            // nobody can see: at the largest text size a landmark further down
            // has not been made yet, and waiting for it reads as "the form never
            // arrived". That is what happened when §10 lever 2 put a section
            // above the one this used to watch for.
            require(app.staticTexts["Keiden kesken"], "the setup form")
            // At the largest size the form is several screenfuls tall, and a
            // row is not in the tree until it is near the screen.
            if isLargest {
                try auditPageByPage(
                    app, "Uusi arkisto, largest text size",
                    to: app.buttons["Luo arkisto"], "the setup form's button"
                )
            }
        }
    }

    /// The one an 80-year-old reaches on her own, from a link, with nobody
    /// beside her.
    func testJoinFamilyForm() throws {
        try sweep("Liity perheeseen", arguments: [], api: "http://127.0.0.1:9") { app, isLargest in
            require(app.buttons["Liity kutsulinkillä"], "the way into joining").tap()
            require(app.staticTexts["Kutsu"], "the join form")
            if isLargest {
                try auditPageByPage(
                    app, "Liity perheeseen, largest text size",
                    to: app.buttons["Liity perheeseen"], "the join form's button"
                )
            }
        }
    }

    /// The same two forms once the server has said no, which is the one state
    /// of them no sweep had reached: the two above audit the forms blank, and
    /// the note under the button — `ErrorNote`, a `Label` in `.elderBody()` —
    /// is drawn only after a request has failed. That was the shape the map's
    /// search sheet drew until 25 Sep 2026, when its audit called the sentence
    /// clipped at both sizes; and these are the first screens a relative or a
    /// grandparent meets, where rule 1 weighs most.
    ///
    /// No stub. The dead loopback address every sweep here launches with is
    /// refused by the kernel at once, so the form meets the real failure and
    /// the real sentence — the system's own words for a connection that could
    /// not be made, in the app's language — rather than one written for a
    /// test.
    ///
    /// Not page by page. The rows above the note are the blank form, which the
    /// two sweeps above already page through at the largest size; what is new
    /// is the last row, so `showErrorNote` brings it on and the sweep's own
    /// audit judges the screen it ends on, at both sizes.
    ///
    /// The newline typed after the name is the return key, which puts the
    /// keyboard away: the button is under it otherwise.
    func testCreateFamilyFormError() throws {
        try sweep("Uusi arkisto, virhe", arguments: [], api: "http://127.0.0.1:9", forgivingTheBarEdge: true) { app, _ in
            require(app.buttons["Aloita perheen arkisto"], "the way into setup").tap()
            require(app.staticTexts["Keiden kesken"], "the setup form")
            let name = reach(app.textFields["Nimesi"], in: app, "the name field")
            name.tap()
            name.typeText("Testaaja\n")
            reach(app.buttons["Luo arkisto"], in: app, "the setup form's button", swipes: 8).tap()
            showErrorNote(in: app)
        }
    }

    /// The join form's half of the same measurement. The code is what nothing
    /// but the invitation can supply, so one of the right shape is typed —
    /// twenty-two characters of base64url, as `randomCode` in the Worker's
    /// `auth.ts` makes them, with the descenders a real one can carry. The
    /// name is left empty, which the form allows since 19 Sep 2026.
    func testJoinFamilyFormError() throws {
        try sweep("Liity perheeseen, virhe", arguments: [], api: "http://127.0.0.1:9", forgivingTheBarEdge: true) { app, _ in
            require(app.buttons["Liity kutsulinkillä"], "the way into joining").tap()
            require(app.staticTexts["Kutsu"], "the join form")
            let code = reach(app.textFields["Kutsukoodi"], in: app, "the code field")
            code.tap()
            code.typeText("gjpqyAbCdEf12345678901\n")
            reach(app.buttons["Liity perheeseen"], in: app, "the join form's button", swipes: 8).tap()
            showErrorNote(in: app)
        }
    }

    /// The note under a welcome form's button, on the screen and at rest, for
    /// the audit that follows.
    ///
    /// Reached rather than waited for: a `Form` does not build a row nobody
    /// can see, and this row is the one below a button whose frame the comment
    /// above it in `OnboardingScreen` measured running past the screen's edge
    /// at the default size already. Measured 26 Sep 2026: waited for, the note
    /// never arrived in ten seconds at either size, while the tree held the
    /// whole form above it.
    ///
    /// The static text, and not whatever carries the identifier first. A
    /// `Label` hands its identifier to each of its elements and the sign comes
    /// before the words, so `auditPageByPage` with the first match as its
    /// bottom paged twelve times over a note that was on the screen from the
    /// second page — its recording shows it — and called it never scrolled on
    /// (26 Sep 2026, both forms, 391 and 509 seconds).
    private func showErrorNote(in app: XCUIApplication) {
        let note = app.staticTexts.matching(identifier: "onboarding-error").firstMatch
        let window = app.windows.firstMatch.frame
        reach(note, in: app, "the note under the button", swipes: 3)
        // Built is not shown: a list makes its next row a little before that
        // row scrolls in. One more flick, which at the list's end is the end.
        if note.frame.maxY > window.maxY {
            app.swipeUp()
        }
        settle(note)
        // Asserted rather than assumed, because an audit of a screen the note
        // has left is green for the wrong reason: neither under the bar nor
        // past the bottom edge.
        let barEdge = app.navigationBars.firstMatch.frame.maxY
        XCTAssertGreaterThanOrEqual(note.frame.minY, barEdge, "the note under the button sits under the bar")
        XCTAssertLessThanOrEqual(note.frame.maxY, window.maxY + 1, "the note under the button runs past the screen")
    }

    /// Members, usage and the invite rows.
    ///
    /// Nothing had ever measured this screen, and nothing could: the rows come
    /// from what the Worker sends, so every run without a backend reached the
    /// offline note instead. `-seed family` is the missing half — the same hole
    /// `-mic denied` and `-screen result` were written to close, and this one had
    /// already let a button be renamed without being drawn.
    ///
    /// Both invite rows are asked for by name. They read *"Kutsu: Kaarina"* and
    /// *"Kutsu ilman nimeä"* beside the same button, which is the length that
    /// matters at the largest text size. Before that, the owner's *"Poista
    /// perheestä"* on a member's row and the dialog behind it — asked for by the
    /// label VoiceOver reads, because three rows may carry the same visible word
    /// and the owner's own must not be one of them.
    ///
    /// One allowance, measured on 5 Sep 2026 before it was made. The top audit
    /// reported *"Jäsen · 24.8.2026"* — Aino's caption, 14 pt tall at y 711,
    /// the last row fully above the tab bar since the member rows grew the
    /// owner's 60 pt "Poista perheestä" — as "Dynamic Type font sizes are
    /// partially unsupported": twice in seven runs, at the default size only,
    /// in the same frame to the point both times, on identical row code and a
    /// private simulator with nothing else booted. The default-size simulation
    /// grows every row above it and pushes that one under the bar, where a lazy
    /// `List` is free to drop and rebuild it mid-measurement; the real largest
    /// size drew the same caption in full on every run that reached it. So the
    /// top audit at the default size lets that one finding through, on member
    /// captions only, and the second launch — which measures the real layout —
    /// stays live for it. A caption that really stopped scaling would fail
    /// there.
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
            // `-copy waiting` holds the "Kopio tällä puhelimella" row in its
            // longest state — some fetched, the rest waiting for Wi-Fi.
            arguments: ["-seed", "family", "-tab", "people", "-screen", "family", "-copy", "waiting"]
        ) { app, isLargest in
            require(app.navigationBars["Perhe"], "the family screen")
            require(
                app.descendants(matching: .any)
                    .matching(NSPredicate(
                        format: "label CONTAINS %@ OR value CONTAINS %@",
                        "odottaa wifi-yhteyttä", "odottaa wifi-yhteyttä"
                    ))
                    .firstMatch,
                "the copy row, waiting for Wi-Fi"
            )
            // By label *or* value: `LabeledContent` folds the row into one
            // element, so `staticTexts["Virtaset"]` matches nothing — measured
            // here, the first time this landmark was asked for. On iOS 26.5
            // that element is a static text labelled "Nimi, Virtaset", with
            // no value at all (26 Sep 2026, `testFamilyWithTheArchive`).
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
            // At the largest size the top is page 1 of `auditPageByPage`
            // below, which measures every page between it and the invites.
            if !isLargest {
                try audit(
                    app,
                    "Perhe ylälaita, default text size",
                    alsoAllowing: { issue in
                        issue.auditType == .dynamicType
                            && (issue.element?.label ?? "").hasPrefix("Jäsen · ")
                    }
                )
            }
            let remove = reach(
                app.buttons["Poista Ville perheestä"], in: app, "the way to remove a member"
            )
            XCTAssertFalse(
                app.buttons["Poista Minä perheestä"].exists,
                "the owner was offered their own removal"
            )
            remove.tap()
            let confirm = app.buttons["Poista perheestä"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the removal asked nothing first")
            // The alert's words, with the name in them: the title and the
            // message are format keys, and a key that did not resolve would
            // read "%@" here and nowhere else.
            require(app.staticTexts["Poistetaanko Ville perheestä?"], "the alert's title, with the name in it")
            require(
                app.staticTexts.matching(NSPredicate(
                    format: "label BEGINSWITH %@", "Ville ei enää näe perheen muistoja"
                )).firstMatch,
                "the alert's message, with the name in it"
            )
            // The way out, by name. This line is what found that the app's
            // confirmation dialogs came up on iOS 26 as popovers with no
            // cancel action at all — see the alert in `FamilyScreen` for the
            // measurement, and why every confirmation is an alert now.
            //
            // The alert itself is not audited, and that was measured twice on
            // 5 Sep 2026 with the same four findings each time, all of them
            // iOS's own: "Dynamic Type font sizes are partially unsupported"
            // on the alert's title and message, whose scaling UIAlertController
            // caps, and two "Potentially inaccessible text" with no element —
            // the dimmed list still visible behind it. The app draws none of
            // that; the screen underneath is audited once the alert has gone.
            let cancel = app.buttons["Peruuta"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the alert has no way out")
            cancel.tap()
            XCTAssertTrue(confirm.waitForNonExistence(timeout: 10), "the alert did not close on Peruuta")

            // The top audit judged the top and the sweep's own audit judges the
            // invites, and at the largest size the members and the usage rows
            // between them were in front of neither: 14 of the screen's 27
            // labels, measured with `KINLORE_XXXL_LOSS` on 21 Sep 2026.
            if isLargest {
                try auditPageByPage(
                    app, "Perhe, largest text size",
                    to: app.staticTexts.matching(NSPredicate(
                        format: "label BEGINSWITH %@", "Kutsu on voimassa viikon"
                    )).firstMatch,
                    "the invites' footer"
                )
                // The landmarks below, read from the pages rather than reached
                // again: the invites' footer is 841 pt tall at this size, so
                // the last page has scrolled the named invite off the top and
                // `reach`, which only scrolls down, would never find it.
                for label in ["Kutsu: Kaarina", "Kutsu ilman nimeä", "Poista"] {
                    XCTAssertTrue(judgedAbove.contains(label), "no page held \(label)")
                }
                return
            }

            let open = reach(app.staticTexts["Kutsu: Kaarina"], in: app, "the invite made for somebody by name")
            reach(app.staticTexts["Kutsu ilman nimeä"], in: app, "the invite with no name on it")
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

    /// The Perhe screen as a paying family reads it, which nothing had drawn:
    /// the paid state was reachable only through RevenueCat's sheet, and
    /// `-entitlement archive` holds it at launch.
    ///
    /// Its usage rows said *"rajaton"* until 26 Sep 2026, a promise the plan
    /// does not make — the paid archive's ceiling is a sentence and not yet a
    /// number, and the app's other words say *more* time (PLAN.md §10,
    /// *Prices*). They now say what has been used and nothing about a limit:
    /// the fixture's seven minutes and twelve photographs.
    ///
    /// A store key is in place, so the only thing keeping *"Avaa koko
    /// arkisto"* off this screen is the tier.
    func testFamilyWithTheArchive() throws {
        try sweep(
            "Perhe, maksullinen",
            arguments: [
                "-seed", "family", "-entitlement", "archive", "-rcKey", "test_placeholder",
                "-tab", "people", "-screen", "family",
            ]
        ) { app, isLargest in
            require(app.navigationBars["Perhe"], "the family screen")
            // By the row's whole label, "Tila, Maksullinen": the shape a
            // `LabeledContent` row has on iOS 26.5 — see `testFamily`. The
            // tier first, so a red row below is about the row and not about
            // the seed.
            require(app.staticTexts["Tila, Maksullinen"], "the paid tier")
            let photos = reach(app.staticTexts["Kuvat, 12"], in: app, "the photographs used, and no limit")
            require(app.staticTexts["Litterointiaika tässä kuussa, 7 min"], "the minutes used, and no limit")
            // Asked of every element, label or value, because an absence
            // asked too narrowly is green for the wrong reason.
            XCTAssertFalse(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "rajaton", "rajaton"))
                    .firstMatch.exists,
                "a row still promised no limit"
            )
            XCTAssertFalse(app.buttons["Avaa koko arkisto"].exists, "a paying family was offered the archive")
            // **At the largest size the audit judges the top of the screen**,
            // and the usage rows below the fold are asserted there rather
            // than audited. Audited, they were red three runs out of three on
            // 26 Sep 2026 — reached by `reach` and page by page alike — on
            // "Käyttö", "Litterointiaika tässä kuussa" and "Kopio tällä
            // puhelimella", which the settled screen draws at 9.54:1, 20.63:1
            // and 20.63:1. The screen recording shows what the audit judged:
            // its own text-size simulation had drawn the list at the default
            // size, and the frames it reported held other words at that size
            // — "Jäsenet" where "Käyttö" had been — and under one per cent
            // ink: 1.17–1.23:1 and 2.24:1 by `ContrastMeter`'s arithmetic.
            // Page by page, two of the findings sat at the very frames
            // `testFamily` reported when it went red at b7b198e, before this
            // test existed. The rows' words are audited at the default size,
            // where they are on the first screen.
            if isLargest {
                scrollToTop(app)
            } else {
                settle(photos)
            }
            XCTAssertTrue(hasStoppedDrawing(app), "the paid Perhe screen was still being drawn when the audit ran")
        }
    }

    func testMemoriesWithContent() throws {
        try sweep("Muistot", arguments: ["-seed", "archive", "-tab", "memories"]) { app, isLargest in
            require(app.navigationBars["Albumi"], "the gallery")
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

    /// The sheet that corrects where a telling was filed: the family's people,
    /// places and events, from the result screen.
    func testMoveMemory() throws {
        try sweep("Siirrä toiselle kortille", arguments: ["-seed", "archive", "-tab", "tell", "-screen", "result"]) { app, _ in
            require(app.staticTexts["Muisto tallennettu"], "the result")
            let move = app.buttons["Siirrä toiselle kortille"]
            for _ in 0 ..< 3 where !move.exists { app.swipeUp() }
            require(move, "the way to move the telling").tap()
            require(app.navigationBars["Mihin muisto kuuluu?"], "the sheet")
        }
    }

    /// The recording that could not be kept, said on the screen that used to
    /// say the opposite. `-audio-lost` holds the failure still.
    func testTellRecordingLost() throws {
        try sweep(
            "Kerro, nauhoitus ei tallentunut",
            arguments: ["-seed", "empty", "-defer", "once", "-audio-lost", "YES"]
        ) { app, _ in
            require(app.staticTexts["Nauhoitusta ei saatu talteen"], "the lost recording, said")
        }
    }

    /// The note that says the server no longer knows this phone, with its way
    /// back. Held still by `-sync refused`; the real state needs a Worker that
    /// has forgotten the device.
    ///
    /// Twice: over an archive with photographs in it, and over an empty one —
    /// the reader's phone the server forgot before anything arrived, which is
    /// the case the note was written for and the branch that used to draw no
    /// notes at all.
    ///
    /// The empty one is also where the album's layout is held, because it is
    /// the tallest thing an empty album draws. Until 26 Sep 2026 it was a
    /// stack of text centred on the screen and not a scroll view, so at the
    /// largest size it ran off both ends at once: "Ei vielä kuvia" was drawn
    /// across the title, and the button under it could not be reached at all.
    /// Every audit passed, because nothing on it was clipped — it was on top
    /// of something else. So the note's first line has to start under the
    /// bar, and the heading has to come to rest between the two bars.
    func testMemoriesRefused() throws {
        try sweep(
            "Muistot, palvelin ei tunnista",
            arguments: ["-seed", "archive", "-tab", "memories", "-sync", "refused"]
        ) { app, _ in
            require(app.buttons["Liity uudella kutsulla"], "the way back for a refused device")
        }
        try sweep(
            "Muistot tyhjänä, palvelin ei tunnista",
            arguments: ["-seed", "empty", "-tab", "memories", "-sync", "refused"]
        ) { app, _ in
            require(app.buttons["Liity uudella kutsulla"], "the way back on an empty archive")
            let note = require(
                app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH %@", "Perheen palvelin ei enää tunnista")
                ).firstMatch,
                "the refused note's words"
            )
            XCTAssertGreaterThanOrEqual(
                note.frame.minY, app.navigationBars["Albumi"].frame.maxY - 1,
                "the note starts under the title: \(note.frame)"
            )
            let heading = require(app.staticTexts["Ei vielä kuvia"], "the empty album's heading")
            drag(heading, toMinY: app.navigationBars["Albumi"].frame.maxY + 4, in: app)
            XCTAssertGreaterThanOrEqual(
                heading.frame.minY, app.navigationBars["Albumi"].frame.maxY - 1,
                "the empty album's heading is drawn over the title: \(heading.frame)"
            )
            XCTAssertLessThanOrEqual(
                heading.frame.maxY, app.tabBars.firstMatch.frame.minY + 1,
                "the empty album's heading cannot be brought out from under the tab bar: \(heading.frame)"
            )
        }
    }

    /// The same note for a phone that has lost the family's key, which syncs
    /// nothing until an invitation brings it back. Held still by
    /// `-sync keyless`. Its own words, so its own sweep: the sentence is not
    /// the refused one, and neither is its symbol.
    func testMemoriesKeyMissing() throws {
        try sweep(
            "Muistot, perheen avain puuttuu",
            arguments: ["-seed", "archive", "-tab", "memories", "-sync", "keyless"]
        ) { app, _ in
            require(
                app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH %@", "Tästä puhelimesta puuttuu perheen avain")
                ).firstMatch,
                "the note that says the key is missing"
            )
            require(app.buttons["Liity uudella kutsulla"], "the way back for a phone without the key")
        }
    }

    /// The joiner's first pull, failed: the state between arriving and empty.
    /// Real failure, not a held one — see `SilentFailureTests`.
    func testMemoriesNotArrived() throws {
        try sweep(
            "Muistot, ensimmäinen haku epäonnistui",
            arguments: ["-seed", "empty", "-tab", "memories", "-family_id", "demo"],
            api: "http://127.0.0.1:9"
        ) { app, _ in
            require(app.buttons["Hae nyt uudelleen"], "the way to fetch again")
        }
    }

    /// The name sheet, opened from a photograph's card. Same shape as the
    /// correction sheet and the same care: the field is not focused, so the
    /// sheet can be waited for.
    func testNamePhotoSheet() throws {
        try sweep("Nimeä kuva", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            reach(photoTile(in: app), in: app, "the photo tile").tap()
            reach(app.buttons["Anna kuvalle nimi"], in: app, "the way to name the photograph").tap()
            require(app.buttons["Tallenna"], "the name sheet")
            XCTAssertTrue(hasStoppedDrawing(app), "the name sheet was still being drawn when the audit ran")
        }
    }

    /// The same sheet for one's own name, from the Perhe screen.
    func testRenameSelfSheet() throws {
        try sweep(
            "Perhe, oma nimi",
            arguments: ["-seed", "family", "-tab", "people", "-screen", "family"]
        ) { app, _ in
            reach(app.buttons["Vaihda nimi"], in: app, "the way to change one's own name").tap()
            require(app.buttons["Tallenna"], "the name sheet")
            XCTAssertTrue(hasStoppedDrawing(app), "the name sheet was still being drawn when the audit ran")
        }
    }

    /// The grid by decade: one dated photograph under "1950-luku", three
    /// undated under their own heading. `-seed dated` is the only archive
    /// with a date in it; the plain one has none on purpose, so DateTests can
    /// give one.
    func testMemoriesByDecade() throws {
        try sweep(
            "Muistot, vuosikymmenet",
            arguments: ["-seed", "dated", "-tab", "memories"]
        ) { app, _ in
            require(app.staticTexts["1950-luku"], "the decade heading")
            require(app.staticTexts["Ilman ajankohtaa"], "the heading over the undated")
            // The titled tile reads its name aloud, not "Valokuva".
            require(app.buttons["Mökin ranta, 1 muisto"], "the tile read by its own name")
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
            app.tabBars.buttons["Albumi"].tap()
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
            require(app.navigationBars["Albumi"], "the gallery")
            require(app.navigationBars.buttons["Etsi"], "the album's magnifier").tap()
            let field = app.searchFields.firstMatch
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
    /// The result screen with a familiar name on it: the `related` fixture
    /// knows Toivo, and the canned telling names him.
    /// **If this one is red, read this before touching it.** It went red
    /// inside a full class on 9–10 Sep 2026 and passed 5/5 on its own, and
    /// the cause is neither the wait nor the scroll — both were tried and
    /// measured, and both failed:
    ///
    ///   * `reach` at the default size too: still red, inside `reach`.
    ///   * A wait on every `reach` attempt, 18 s in all: still red.
    ///
    /// Screenshotted at the failure instead: **the app was on Muistot**,
    /// under "Uutta perheeltä", and the result screen had never opened.
    /// `-screen result` is read by `TellScreen` and by nothing else, so it
    /// only happens on a launch that lands on Kerro — and this fixture gives
    /// the app reasons not to. `-seed related` leaves tellings this phone has
    /// not seen, which opens Muistot on purpose (docs/UX.md §6), and the
    /// arrival flag does the same. Both live in `UserDefaults`, which
    /// survives between launches of one install, so what the class did before
    /// this test decides which screen it gets.
    ///
    /// **`-tab tell` is not the fix, and was measured before being rejected.**
    /// It makes this test deterministic and turns `testTell` red instead —
    /// twice in a row, where it had been green in four class runs. The state
    /// the class leaves behind is the defect; pinning one test's tab only
    /// moves which test inherits it.
    func testResultWithKnownNames() throws {
        try sweep(
            "Tulos, tutut nimet",
            arguments: ["-seed", "related", "-screen", "result"]
        ) { app, _ in
            // Scrolled to at both sizes since 19 Sep 2026. The row used to be
            // on screen without scrolling at the default size, and the teller
            // question now stands above everything on this screen
            // (`TellerCard`) — a heading, a sentence, three choices and a
            // quiet row, which is more than the fold had to spare. The
            // section is still audited; it is simply no longer the first
            // thing under the memory.
            reach(app.staticTexts["Tutut nimet"], in: app, "the familiar names")
            XCTAssertTrue(hasStoppedDrawing(app), "the result screen was still being drawn when the audit ran")
        }
    }

    /// The sheet behind *"Joku muu"*, which is a new screen and so is
    /// measured at both sizes before it is called done (rule 1). It is the
    /// same shape as the relative picker, and shares its one hard part: the
    /// way out is a row at the bottom rather than a toolbar button, because a
    /// toolbar button's text barely grows with Dynamic Type.
    func testTellerSheet() throws {
        try sweep("Muiston kertoja", arguments: ["-seed", "related", "-screen", "result"]) { app, _ in
            reach(app.buttons["Joku muu"], in: app, "the way to the whole family").tap()
            require(app.buttons["Joku uusi"], "the sheet")
        }
    }

    func testResultWithProposals() throws {
        try sweep(
            "Tulos, nimiehdotukset",
            arguments: ["-seed", "empty", "-screen", "result"]
        ) { app, _ in
            require(app.staticTexts["Kuulin nämä"], "the names heard")
        }
    }

    /// The same card as a spoken telling reaches it since 26 Sep 2026: through
    /// its first question and "Riittää tältä erää", with the names, the decade
    /// and "Kysyisin vielä" all waiting on it. `-screen result` above types
    /// its telling, which is no longer the way an 80-year-old arrives here.
    func testResultAfterTheQuestion() throws {
        try sweep(
            "Tulos, kysymyksen jälkeen",
            arguments: ["-seed", "empty", "-voice", "stub"]
        ) { app, _ in
            tellAloud(app)
            app.buttons["Riittää tältä erää"].tap()
            require(app.staticTexts["Kuulin nämä"], "the names heard")
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
    /// The listening screen inside the interview loop, which carries one
    /// button the plain one does not. Audited on the second round: the aid
    /// stops the first after three seconds, and the second stays.
    func testInterviewRecordingIsAudited() throws {
        for size in [nil, Self.largest] {
            let app = launch(["-seed", "empty", "-screen", "interview"], textSize: size)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }
            let listening = app.staticTexts["Paina kun olet valmis"]
            XCTAssertTrue(listening.waitForExistence(timeout: 60), "never arrived: the first round's listening screen")
            XCTAssertTrue(listening.waitForNonExistence(timeout: 30), "the aid did not finish the first round")
            XCTAssertTrue(listening.waitForExistence(timeout: 60), "never arrived: the second round's listening screen")
            reach(app.buttons["Riittää tältä erää"], in: app, "the way out that keeps the answer")
            let at = size == nil ? "default text size" : "largest text size"
            try audit(app, "Kuuntelen, haastattelu, \(at)", alsoAllowing: { issue in
                issue.auditType == .elementDetection
            })
            app.terminate()
        }
    }

    /// The question the app asks back after a spoken telling — where every
    /// spoken telling goes first since 26 Sep 2026, and a screen no audit had
    /// stopped on: `-screen interview` only passes through it on the way to
    /// the listening screen above. Outside `sweep(...)` for the same reason
    /// as that one: the speaker animates while the question is being read,
    /// so exactly element detection is forgiven and nothing else.
    func testInterviewQuestionIsAudited() throws {
        for size in [nil, Self.largest] {
            let app = launch(["-seed", "empty", "-voice", "stub"], textSize: size)
            tellAloud(app)
            require(app.images["Luen kysymyksen ääneen"], "the question being read aloud")
            let at = size == nil ? "default text size" : "largest text size"
            try audit(app, "Kysymys, haastattelu, \(at)", alsoAllowing: { issue in
                issue.auditType == .elementDetection
            })
            app.terminate()
        }
    }

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
            require(app.staticTexts["Eeva"], "a person in the demo archive")
            // And the door: the fixture's Aino is a name nobody has checked,
            // and since 12 Sep 2026 she waits behind this row, not on the list.
            require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "odottaa tarkistusta")).firstMatch, "the door to the names heard")
        }
    }

    /// The names heard and not yet checked, one screen behind the people
    /// list: each with the sentence it was heard in and its two answers. A
    /// new screen, so it is measured at both sizes before it is called done.
    func testHeardNames() throws {
        try sweep("Kuullut nimet", arguments: ["-seed", "archive", "-tab", "people"]) { app, _ in
            require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "odottaa tarkistusta")).firstMatch, "the door").tap()
            require(app.buttons["Vahvista Aino"], "the name heard, with its answer")
        }
    }

    func testPeopleEmpty() throws {
        try sweep("Ihmiset, empty", arguments: ["-seed", "empty", "-tab", "people"]) { app, _ in
            require(app.staticTexts.firstMatch, "the empty people state")
        }
    }

    /// The sheet a person is typed into, since 13 Sep 2026: a new way into a
    /// shared sheet, so it is measured at both sizes before it is called done.
    func testAddPersonSheet() throws {
        try sweep("Lisää henkilö", arguments: ["-seed", "archive", "-tab", "people"]) { app, _ in
            reach(app.buttons["Lisää henkilö"], in: app, "the way to add a person").tap()
            require(app.buttons["Tallenna"], "the sheet")
        }
    }

    /// The drawn family tree: since 13 Sep 2026, what Ihmiset opens on, on a
    /// family member's phone. `-seed related` is the one fixture with a
    /// confirmed couple in it, and Sanni, related to nobody, is drawn beneath.
    func testFamilyTree() throws {
        try sweep("Sukupuu", arguments: ["-seed", "related", "-tab", "people", "-screen", "tree"]) { app, _ in
            require(app.buttons["Eeva"], "a person in the tree")
            require(app.buttons["Valikko"], "the menu")
        }
    }

    /// The same tree at the size a family reaches: six generations and
    /// fifty-five people, with a kinship word under every card in Elina's
    /// family (`-seed clan`, `-you clan-elina`).
    ///
    /// The small fixture cannot answer what this one does. The shaded bands
    /// are ground under every name in the drawing, and the words under the
    /// names — *Isovanhempasi sisarus* is the widest — wrap inside a place
    /// at the largest size, which is the kind of thing that measures fine at
    /// the default size and clips at the largest.
    func testFamilyTreeAtSize() throws {
        try sweep("Sukupuu, iso suku", arguments: ["-seed", "clan", "-tab", "people", "-screen", "tree", "-you", "clan-elina"]) { app, _ in
            require(app.buttons["Aapo"], "the oldest generation")
            require(app.staticTexts.matching(identifier: "Vanhempasi").firstMatch, "the word under a parent's name")
        }
    }

    /// Everything that used to stand around the drawing, behind one button
    /// since 19 Sep 2026: the ways out of the screen, the key to the lines,
    /// and the bonds the rows cannot hold. `-seed clan` has two of those, so
    /// the sheet is measured with every section it can have.
    func testTreeMenu() throws {
        try sweep("Sukupuu, valikko", arguments: ["-seed", "clan", "-tab", "people", "-screen", "tree", "-you", "clan-elina"]) { app, _ in
            require(app.buttons["Valikko"], "the menu's button").tap()
            require(app.staticTexts["Nämä eivät mahdu kuvaan"], "the menu")
        }
    }

    /// What a person in the tree offers: their card, or a relative added on
    /// the spot. A new sheet since 13 Sep 2026.
    func testTreePersonSheet() throws {
        try sweep("Sukupuu, henkilö", arguments: ["-seed", "related", "-tab", "people", "-people", "tree"]) { app, _ in
            require(app.buttons["Eeva"], "a person in the tree").tap()
            require(app.buttons["Avaa kortti"], "the person's sheet")
        }
    }

    /// The first minute after an archive is created, both of its steps: new
    /// since 13 Sep 2026, and the first screen whoever sets the archive up sees.
    func testFirstMinute() throws {
        try sweep("Kenen muistot", arguments: ["-seed", "alone", "-first_minute_pending", "YES"]) { app, _ in
            require(app.staticTexts["Kenen muistot haluat tallentaa?"], "the first step")
        }
        try sweep("Kenen muistot, kutsu", arguments: ["-seed", "alone", "-first_minute_pending", "YES"]) { app, _ in
            let field = require(app.textFields.firstMatch, "the name field")
            field.tap()
            field.typeText("Mummo")
            require(app.buttons["Jatka"], "the way on").tap()
            require(app.buttons["Tällä puhelimella"], "the step that asks how she will tell")
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
            app.tabBars.buttons["Albumi"].tap()
            let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
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

    /// The sheet a teller corrects their own words in.
    func testMemoryTextSheet() throws {
        try sweep(
            "Memory text sheet",
            arguments: ["-seed", "empty", "-defer", "structure", "-screen", "interview"]
        ) { app, _ in
            require(app.staticTexts["Muisto tallennettu"], "the result screen")
            reach(app.buttons["Kerro toinen muisto"], in: app, "the way on").tap()
            app.tabBars.buttons["Albumi"].tap()
            require(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch, "the telling in the gallery").tap()
            reach(app.buttons["Muokkaa tekstiä"], in: app, "the way to correct the text").tap()
            require(app.buttons["Tallenna"], "the sheet")
        }
    }

    /// A person's card while nothing has been told about them, which is when
    /// the card can be deleted: the fixture's Aino.
    func testPersonCardWithoutAStory() throws {
        try sweep("Person card without a story", arguments: ["-seed", "archive", "-tab", "people"]) { app, isLargest in
            // Through the door: a name nobody has checked is not on the list.
            require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "odottaa tarkistusta")).firstMatch, "the door").tap()
            require(app.staticTexts["Aino"], "the name heard").tap()
            let removal = reach(app.buttons["Poista henkilö"], in: app, "the way to delete the person")
            // At the largest size the swipes stop with the button under the
            // tab bar and the row that mentions her under the navigation bar,
            // where its byline was reported partially unsupported once the
            // card above it grew (26 Sep 2026; the entry on `memory.byline`
            // in `AccessibilityPolicy`). The button is dragged clear of the
            // bar, as somebody about to press it would, and the card is
            // judged there.
            if isLargest { drag(removal, toMinY: 700, in: app) }
        }
    }

    /// The gallery with the month's minutes used up and tellings waiting on
    /// them: the third quiet note, held still by `-minutes-out`.
    func testMemoriesOutOfMinutes() throws {
        try sweep(
            "Memories, out of minutes",
            arguments: ["-seed", "archive", "-tab", "memories", "-minutes-out", "12"]
        ) { app, _ in
            require(
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "12 kertomusta odottaa tekstiä")).firstMatch,
                "the note about the month's minutes"
            )
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

    /// The card that offers *Tämä olen minä* (26 Sep 2026): the seeded
    /// family's phone linked to no card, on Eeva's. The row is a second one
    /// in the face's section and is there in this state only.
    func testPersonCardOfferedAsYou() throws {
        try sweep(
            "Person card, this is me",
            arguments: ["-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-eeva", "-you", "none"]
        ) { app, _ in
            require(app.buttons["Tämä olen minä"], "the row that says which card is this phone's")
        }
    }

    /// The same card once the row has been answered on a phone that cannot
    /// reach the server — the seeded family has none — so the row reads
    /// *Tämä olet sinä* over the sentence that says the mark is waiting.
    func testPersonCardWaitingToBeYou() throws {
        try sweep(
            "Person card, waiting to be you",
            arguments: ["-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-eeva", "-you", "none"]
        ) { app, _ in
            let offer = app.buttons["Tämä olen minä"]
            require(offer, "the row that says which card is this phone's")
            offer.tap()
            let question = app.alerts["Merkitäänkö tämä sinuksi?"]
            require(question, "the question the row asks first")
            question.buttons["Merkitse"].tap()
            require(app.staticTexts["Merkintä lähtee itsestään, kun yhteys palaa."], "the waiting sentence")
        }
    }

    /// A card with a friend on it (21 Sep 2026): the friend under a heading of
    /// his own, which is a second section the card did not have. `-seed clan`'s
    /// Jonne is Elina's friend and nobody's kin, so his card is that section
    /// and little else, and `-person` names it — Elina's own card holds the
    /// same heading under seven relatives, a screenful down at the largest
    /// size, and a sweep audits what is on screen. Reached and then settled:
    /// a short list scrolled past its end bounces back.
    func testPersonCardWithAFriend() throws {
        try sweep(
            "Person card, friend",
            arguments: ["-seed", "clan", "-tab", "people", "-screen", "person", "-person", "clan-jonne"]
        ) { app, _ in
            require(app.buttons["Kerro tästä muisto"], "the person card")
            // The row and not its heading since 26 Sep 2026. Reached by the
            // heading, the largest size arrived with *"Ystävät"* under the
            // tab bar and the row unbuilt below it, so the audit there judged
            // the card's top and called the section clean — the loss probe
            // (`KINLORE_XXXL_LOSS`) counted five of sixteen labels gone, the
            // friend's name among them. One element per relative (see
            // `RelativeRow`), so the row is found by its whole label.
            settle(reach(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "Elina, Ystävä"))
                    .firstMatch,
                in: app, "the friend's row"
            ))
        }
    }

    /// The sheet behind *Lisää sukulainen* (21 Sep 2026): a menu until the
    /// day the friend's item was added to it and never fired. The friend's
    /// button stands after a gap, so the sheet is measured with it.
    func testPersonCardRelativeKindSheet() throws {
        try sweep(
            "Person card, add a relative",
            arguments: ["-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            reach(app.buttons["Lisää sukulainen"], in: app, "the row that adds a relative").tap()
            require(app.buttons["Lisää ystävä"], "the sheet")
        }
    }

    /// The list with a face on one card: Kalle's disc is a photograph now,
    /// with the ink ring that gives it an edge on the paper (§25).
    func testPeopleWithAFace() throws {
        try sweep("Ihmiset, kasvot kortilla", arguments: ["-seed", "faces", "-tab", "people"]) { app, _ in
            require(app.staticTexts["Kalle"], "the person with a face")
        }
    }

    /// The person card with a face on it, and the row that changes it.
    func testPersonCardWithAFace() throws {
        try sweep(
            "Person card with a face",
            arguments: ["-seed", "faces", "-tab", "people", "-screen", "person", "-person", "demo-kalle"]
        ) { app, _ in
            require(app.buttons["Vaihda kasvot"], "the row that changes the face")
        }
    }

    /// The picker: the archive's photographs as tiles, and the way out.
    func testPersonCardFacePicker() throws {
        try sweep(
            "Person card, choose a face",
            arguments: ["-seed", "faces", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            reach(app.buttons["Valitse kasvot"], in: app, "the row that chooses a face").tap()
            require(app.buttons["Valokuva"], "the photograph offered")
        }
    }

    /// The picker with no photograph on this phone to offer: the sentence
    /// that says so, the way in from the phone's own photographs with its
    /// caption, and the way out (26 Sep 2026). `-seed archive` has the
    /// fixture's photograph as a row without a file, which is what a
    /// picture another phone added looks like before the full copy.
    func testPersonCardFacePickerWithoutPhotographs() throws {
        try sweep(
            "Person card, choose a face, no photographs on this phone",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            reach(app.buttons["Valitse kasvot"], in: app, "the row that chooses a face").tap()
            require(app.buttons["Valitse puhelimen kuvista"], "the way in from the phone's own photographs")
        }
    }

    // MARK: The facts on a person's card (§26)

    /// The Tiedot section with four facts on it: a birth with a decade and
    /// a place, a death on a day, a trade with a decade, a name — each row
    /// one sentence.
    func testPersonCardWithFacts() throws {
        try sweep(
            "Person card with facts",
            arguments: ["-seed", "facts", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, isLargest in
            require(app.buttons["Syntynyt, 1930-luku, Puumala"], "the birth on the card")
            // The section's last row, below the fold at the largest size: a
            // List realises only the rows on screen, so it is scrolled to,
            // not waited for. At the default size the row's words are the
            // audit's simulation artefact, measured and keyed as `fact.add`
            // in `AccessibilityPolicy`; nothing else here is forgiven.
            // At the largest size the row is then dragged to mid-screen, as
            // the photograph's memories heading is, and judged there.
            let add = reach(app.buttons["Lisää tieto"], in: app, "the row that adds a fact")
            if isLargest { drag(add, toMinY: 330, in: app) }
        }
    }

    /// The sheet's first step: the kinds of fact, as rows.
    func testPersonCardFactSheetKinds() throws {
        try sweep(
            "Person card, add a fact, the kinds",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            require(app.buttons["Lisää tieto"], "the row that adds a fact").tap()
            require(app.buttons["Syntymä"], "the kinds to choose from")
        }
    }

    /// The second step for a birth: the time row, the place row, the save
    /// that waits for one of them, and the way out.
    func testPersonCardFactSheetBirthParts() throws {
        try sweep(
            "Person card, add a fact, a birth's parts",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            require(app.buttons["Lisää tieto"], "the row that adds a fact").tap()
            require(app.buttons["Syntymä"], "the kinds to choose from").tap()
            require(app.buttons["Valitse paikka"], "the place row of a birth")
        }
    }

    /// The place chooser: a field for a new name, and the archive's places.
    func testPersonCardFactPlaceChooser() throws {
        try sweep(
            "Person card, add a fact, the place chooser",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            require(app.buttons["Lisää tieto"], "the row that adds a fact").tap()
            require(app.buttons["Syntymä"], "the kinds to choose from").tap()
            require(app.buttons["Valitse paikka"], "the place row of a birth").tap()
            require(app.buttons["Puumala"], "the archive's places")
            require(app.buttons["Lisää paikka"], "the button that makes a place by name")
        }
    }

    /// A fact opened to change: its parts filled in, and the removal in the
    /// colour eyes cannot check.
    func testPersonCardFactBeingChanged() throws {
        try sweep(
            "Person card, a fact being changed",
            arguments: ["-seed", "facts", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            require(app.buttons["Syntynyt, 1930-luku, Puumala"], "the birth on the card").tap()
            require(app.buttons["Poista tieto"], "the removal on the sheet")
        }
    }

    /// The spot: the photograph with the ring on it, the card's disc beside
    /// its sentence, and Tallenna.
    func testPersonCardFaceSpot() throws {
        try sweep(
            "Person card, the face's spot",
            arguments: ["-seed", "faces", "-tab", "people", "-screen", "person", "-person", "demo-eeva"]
        ) { app, _ in
            reach(app.buttons["Valitse kasvot"], in: app, "the row that chooses a face").tap()
            require(app.buttons["Valokuva"], "the photograph offered").tap()
            require(app.buttons["Tallenna"], "the save button")
        }
    }

    func testSettings() throws {
        try sweep(
            "Asetukset",
            arguments: ["-seed", "archive", "-tab", "people", "-screen", "settings"]
        ) { app, isLargest in
            require(app.buttons.firstMatch, "a row in Settings")
            // At the largest size the list is taller than the phone, and the
            // wipe row and its footer were never in front of the audit.
            if isLargest {
                try auditPageByPage(
                    app, "Asetukset, largest text size",
                    to: app.buttons["Tyhjennä ja aloita alusta"], "the wipe row, last on the screen"
                )
            }
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
            // The heading under the bar, at both sizes. The page was a centred
            // stack that could grow taller than the screen, and at the largest
            // text size it overflowed both ends: its heading ran up over the
            // bar's title (the English read-through of 26 Sep 2026, 071).
            let heading = app.staticTexts["Kamera ei ole käytössä"]
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(heading.exists, "the refused camera has no heading")
            XCTAssertTrue(bar.exists, "the refused camera has no bar")
            XCTAssertGreaterThanOrEqual(
                heading.frame.minY, bar.frame.maxY,
                "the heading runs up over the bar: \(heading.frame) against \(bar.frame)"
            )
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
        ) { app, isLargest in
            reach(app.buttons["Ota perhe käyttöön"], in: app, "the way into a family")
            if isLargest {
                try auditPageByPage(
                    app, "Asetukset, vain tämä puhelin, largest text size",
                    to: app.buttons["Tyhjennä ja aloita alusta"], "the wipe row, last on the screen"
                )
            }
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
        ) { app, isLargest in
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
            // At the largest size the two rows above are landmarks, and the
            // measurement is every page from the top to the last footer:
            // between them sat the export row and the text-size row, which no
            // audit had in front of it.
            if isLargest {
                return try auditPageByPage(
                    app, "Asetukset perheessä, largest text size",
                    to: settingsFooter(in: app), "the footer under the wipe row"
                )
            }
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

    /// The date sheet: four kinds of answer and a column of years, on the screen
    /// that asks how sure somebody is before it asks what they know. There is no
    /// wheel and no graphical calendar on it — this sweep is why, and the sweep
    /// below is why the finest answers could come back without one.
    ///
    /// Four and not five, and this sweep is why that too: the month and the day
    /// were a row each at first, and at the default text size the fifth row made
    /// the audit report "Dynamic Type font sizes are partially unsupported".
    /// Three rows passed and four passed, A/B'd in a worktree pinned to HEAD, so
    /// the finer answers live behind "Päivämäärä" instead of beside it.
    func testDateSheet() throws {
        try sweep("Ajankohta", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Lisää ajankohta"], in: app, "the date row").tap()
            require(app.staticTexts["Kuinka tarkkaan tiedät?"], "the date sheet")
        }
    }

    /// The deepest step of the same sheet: the days of a chosen month, under the
    /// month and the year already answered.
    ///
    /// It is audited separately because it is the state the exact day was
    /// dropped for in the first place. A wheel and a graphical calendar were
    /// measured here and neither one's text grew with Dynamic Type — three
    /// findings on that state alone — so the day came back on 19 Sep 2026 as
    /// rows instead, and rows are only an answer if they hold at the largest
    /// size. 1900 and January are chosen because they are the first row of each
    /// list: what is being measured is the day list, not the scrolling.
    func testDateSheetDay() throws {
        try sweep("Ajankohta, päivä", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Lisää ajankohta"], in: app, "the date row").tap()
            reach(app.buttons["Päivämäärä"], in: app, "the exact-date choice").tap()
            reach(app.buttons["1900"], in: app, "the years").tap()
            reach(app.buttons["tammikuu"], in: app, "the months of the chosen year").tap()
            require(
                app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "Vaihda kuukausi")
                ).firstMatch,
                "the days of the chosen month"
            )
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
        try sweep("Photo detail", arguments: ["-seed", "archive", "-tab", "memories"]) { app, isLargest in
            reachPhotoTile(in: app).tap()
            // The demo photograph has no file, and since 26 Sep 2026 its place
            // holds a sentence instead of a spinner. At the largest size that
            // sentence is the whole first screen, so it is what arriving means
            // there, and the rest of the card is judged page by page down to
            // the footer under the way to ask the family.
            //
            // **The memories' heading on the way down.** The audit reports
            // "1 muisto" at this size as "Dynamic Type font sizes are partially
            // unsupported" wherever a page leaves it above the tab bar with its
            // frame reaching below `tabBar.minY - AccessibilityPolicy.fadeReach`
            // — the band where `audit(_:_:)` holds `.contrast` back and counts
            // the pixels instead. `.dynamicType` has no such handling, so where
            // the page stops decides. Measured 26 Sep 2026 on a private
            // simulator, the heading dragged to a chosen height and audited
            // there, with the bar at y 791: red at 610 and 651, clean at 310,
            // 450 and 530. Screenshotted at 651, it is drawn whole and at full
            // size. The button above it, "Kerro tästä muisto", was never
            // reported at the same heights, and four versions of the view — the
            // count as a row instead of a header, an explicit
            // `.title3.weight(.semibold)`, `.headerProminence(.increased)`, a
            // hard bottom scroll edge — were each red at 610 and 651 and clean
            // at 530. The finding follows where the words sit and nothing about
            // them, the signature `photoCardEmptyStateText` records.
            //
            // Nothing is forgiven for it. The pages land the heading at
            // y 870.67 under the bar, then 443.67 and 16.67, 427 points apart.
            // **If this goes red on the heading**, read the frame in the
            // finding before touching the view: a bottom edge below
            // `tabBar.minY - fadeReach` means something above it has moved a
            // page into the band, and it is this finding again rather than a
            // regression.
            if isLargest {
                require(
                    app.staticTexts[
                        "Kuva on vielä puhelimessa, jolla se lisättiin. Se tulee perille, kun se lähetetään sieltä."
                    ],
                    "the photo's own screen"
                )
                try auditPageByPage(
                    app, "Photo detail, largest text size",
                    to: app.staticTexts["Kysymys näkyy perheelle Kerro-näytöllä, ja vastaus tallentuu tähän."],
                    "the footer under the way to ask the family"
                )
            } else {
                require(app.buttons["Kerro tästä muisto"], "the photo's own screen")
            }
        }
    }

    /// The same card with the picture on it, which the sweep above cannot
    /// reach: the demo archive's photograph has no file, and `-seed blind`'s
    /// has one. No sweep judged the photograph itself until 26 Sep 2026, and
    /// the first audit that did — a throwaway one measuring the colour
    /// footer further down — reported it as "Element has no description":
    /// VoiceOver said nothing about the card's main content.
    ///
    /// The photograph is required by its label before the audit, so losing
    /// the label fails here by name rather than only as the audit's finding.
    /// The seed's photograph is untitled, so the label is the word an
    /// untitled one is shown under, `displayTitle`'s *"Valokuva"*.
    ///
    /// At the default size the picture holds the memories' heading at
    /// y 756.33, where the audit's simulation reports it. That finding is
    /// older than the label — it is there with the label taken away — and the
    /// gate forgives it by identifier, `card.memoriesHeading`, on the
    /// default-size launch only; the measurement is on
    /// `AccessibilityPolicy.isDefaultSizeSimulationArtefact`. Contrast is
    /// forgiven on neither launch.
    func testPhotoDetailWithThePicture() throws {
        try sweep("Photo detail with the picture", arguments: ["-seed", "blind", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            require(app.images["Valokuva"], "the photograph, by its label")
            XCTAssertTrue(hasStoppedDrawing(app), "the photo card was still being drawn when the audit ran")
        }
    }

    /// The colouring's footer under its button: the one sentence on the card
    /// that says where the photograph and its memories go when somebody asks
    /// for colours. No sweep reached it until 26 Sep 2026 — the demo
    /// archive's photograph has no file, so its card has neither the button
    /// nor the footer, and `-seed blind`'s has both.
    ///
    /// At the largest size the footer is 666.67 pt of text in the 675 pt
    /// between the two bars, so no page of `auditPageByPage` holds it whole.
    /// So it is dragged slowly, at both sizes, until its top is 4 pt under the
    /// navigation bar or the list ends. Measured 26 Sep 2026: at the largest
    /// size that is y 120, the last line ending at 786.67 above a bar at 791;
    /// at the default size the list ends first, with the footer at y 576.33.
    /// That page is left to the sweep's own audit, and the two assertions
    /// before it say the whole footer is on it.
    func testPhotoDetailColourFooter() throws {
        try sweep("Photo detail, colour footer", arguments: ["-seed", "blind", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Väritä kerronnan mukaan"], in: app, "the colour button", swipes: 12)
            let footer = require(
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kuva ja siitä kerrotut")).firstMatch,
                "the colour footer"
            )
            let top = app.navigationBars.firstMatch.frame.maxY
            drag(footer, toMinY: top + 4, in: app)
            XCTAssertGreaterThanOrEqual(footer.frame.minY, top - 1, "the footer's top is under the navigation bar: \(footer.frame)")
            XCTAssertLessThanOrEqual(
                footer.frame.maxY, app.tabBars.firstMatch.frame.minY + 1,
                "the footer's last line is under the tab bar: \(footer.frame)"
            )
            XCTAssertTrue(hasStoppedDrawing(app), "the photo card was still being drawn when the audit ran")
        }
    }

    /// The same screen for a photograph whose file is not on this phone and
    /// cannot be: another member added it past the free ceiling, and the
    /// server kept its card and refused its file. A spinner stood where the
    /// picture goes until 26 Sep 2026; the sentence that replaced it is what
    /// this measures.
    func testPhotoDetailPastTheCeiling() throws {
        try sweep("Photo detail past the ceiling", arguments: ["-seed", "unarrived", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            require(
                app.staticTexts[
                    "Kuva on vielä puhelimessa, jolla se lisättiin. Se tulee perille, kun perheen ilmaisessa arkistossa on tilaa."
                ],
                "the sentence where the picture would be"
            )
        }
    }

    /// And for one whose file is on the server and did not come: the same
    /// place carries a sentence and a button to try again.
    func testPhotoDetailFetchFailed() throws {
        try sweep("Photo detail, fetch failed", arguments: ["-seed", "unarrived", "-tab", "memories"]) { app, _ in
            let tile = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Rantasauna"))
                .firstMatch
            reach(tile, in: app, "the fetched photograph's tile").tap()
            require(app.buttons["Yritä uudelleen"], "the way to try the fetch again")
        }
    }

    /// A place's own screen, which is the photo screen plus a map — for a
    /// confirmed place, which since 12 Sep 2026 is the only kind the lookup
    /// gives a coordinate to.
    ///
    /// `PlaceMapCard` shipped without one of these. The fixture was built for
    /// it — the demo archive gives Puumala a coordinate expressly so the card
    /// is reachable from a seeded launch — and the sweep that was supposed to
    /// use it was never written, so a new screen carrying a full-bleed map, a
    /// wax circle over it and a spoken label went out with nothing measuring
    /// any of them. The map left v1 for one day, 12 Sep, and came back on the
    /// 13th (ARCHITECTURE §18); this sweep asked for its absence for that day.
    ///
    /// The map's own label is what proves arrival, and it has to be the
    /// circle's rather than the pin's: Puumala is a municipality, so rule 5
    /// says the card draws an area. A run that found the pin's wording here
    /// would mean the precision had been rounded somewhere on the way.
    func testPlaceDetail() throws {
        try sweep("Paikan kartta", arguments: ["-seed", "archive", "-tab", "memories"]) { app, _ in
            let row = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala"))
                .firstMatch
            reach(row, in: app, "the place's row in Muistot").tap()
            // A control since 19 Sep 2026, and it was `otherElements` before:
            // the card's map opens a larger one — the screen its point was
            // moved on until 25 Sep, the family's map on this place since.
            let map = require(
                app.buttons["Suunnilleen tällä seudulla kartalla"],
                "the place card's map"
            )
            // A map draws itself over several frames, and the tiles arrive
            // from a cache rather than instantly. Auditing mid-draw is how the
            // gallery's tiles once reported colours nothing had drawn.
            settle(map)
        }
    }

    /// A place card with nothing on the map yet: a confirmed farm the
    /// gazetteer did not know, which is most of a family's places (§18).
    /// Where the map would be, the card says "Merkitse kartalle", in the
    /// date row's shape — a row whose words grow, because a toolbar
    /// button's barely do.
    func testPlaceDetailWithNoPoint() throws {
        try sweep("Paikka ilman karttaa", arguments: ["-seed", "unplaced", "-tab", "memories"]) { app, _ in
            let row = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Koivula"))
                .firstMatch
            reach(row, in: app, "the unplaced place's row in Muistot").tap()
            settle(require(app.buttons["Merkitse kartalle"], "the card's way onto the map"))
        }
    }

    /// Putting a place's point where the place actually is, on the family's
    /// map itself (25 Sep 2026). The panel under the map is the tallest
    /// shape this screen has — a sentence, the two rows of how sure,
    /// "Tallenna" and "Peruuta", and "Poista sijainti" — and at the default
    /// size it floats over a map that has to keep enough of itself to be
    /// tapped. At the largest size the map is 300 points of a page that
    /// scrolls, and the rows under it are what has to fit.
    ///
    /// Opened the way the card's "Merkitse kartalle" opens it, on Puumala,
    /// whose name is in the sentence that proves arrival.
    func testPlacesMapEditing() throws {
        try sweep("Kartta, merkintä", arguments: editingPuumala) { app, _ in
            settle(require(
                app.staticTexts["Napauta karttaa kohtaan, jossa Puumala on."],
                "the panel that asks for a tap"
            ))
        }
    }

    /// The same panel after a tap: the mark is down, the camera has moved in
    /// to it and "Tallenna" is live, which is the one prominent button this
    /// screen has. The mark is a graphic over ground nobody can predict —
    /// which is why it is wax on a cream ring — and this is the state in
    /// which it is drawn.
    func testPlacesMapEditingWithAMark() throws {
        try sweep("Kartta, merkki", arguments: editingPuumala) { app, _ in
            let map = require(app.otherElements["Kartta. Napautus merkitsee kohdan."], "the map a tap marks")
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
            // Waited for rather than read at once, for the reason
            // `PlacePinTests.tapTheMap(in:)` gives.
            let save = require(app.buttons["Tallenna"], "the editor's save")
            XCTAssertTrue(
                save.wait(for: \.isEnabled, toEqual: true, timeout: 10),
                "the tap put no mark down, so this would audit the untouched panel"
            )
            settle(save)
        }
    }

    /// Taking the point off the map, which asks in the panel rather than in
    /// an alert and says what stays.
    func testPlacesMapRemoval() throws {
        try sweep("Kartta, poisto", arguments: editingPuumala) { app, _ in
            require(app.buttons["Poista sijainti"], "the way to take the point off the map").tap()
            settle(require(
                app.staticTexts["Poistetaanko sijainti kartalta? Puumala ja sen muistot säilyvät."],
                "the question that asks first"
            ))
        }
    }

    /// The places the map cannot draw, opened from the count under it: a
    /// sheet of the album's own rows, each a way into placing its place.
    func testPlacesMapUnplacedList() throws {
        try sweep(
            "Ei vielä kartalla",
            arguments: ["-seed", "unplaced", "-tab", "memories", "-screen", "placesMap"]
        ) { app, _ in
            require(app.buttons["1 paikka ei vielä kartalla"], "the map's count of what it cannot draw").tap()
            require(app.navigationBars["Ei vielä kartalla"], "the sheet of places not on the map")
            settle(require(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Koivula")).firstMatch,
                "Koivula's row"
            ))
        }
    }

    /// "Etsi nimellä" with its answers in: a sheet of rows over the map, each
    /// a name in bold and the line under it that tells two of the same name
    /// apart, in the supporting colour. The search is stubbed
    /// (`-placeSearch stub`), because a real one needs a network and answers
    /// differently from one day to the next.
    func testPlaceSearch() throws {
        try sweep("Etsi nimellä", arguments: editingPuumala + ["-placeSearch", "stub"]) { app, _ in
            require(app.buttons["Etsi nimellä"], "the editor's way to search").tap()
            settle(require(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Koivulantie 12")).firstMatch,
                "the search's answers"
            ))
        }
    }

    /// The search that did not get through, which says so in the warning
    /// colour and says what is still possible.
    func testPlaceSearchFailing() throws {
        try sweep("Etsi nimellä, ei yhteyttä", arguments: editingPuumala + ["-placeSearch", "failing"]) { app, _ in
            require(app.buttons["Etsi nimellä"], "the editor's way to search").tap()
            settle(require(
                app.staticTexts["Haku ei onnistunut. Voit napauttaa kohdan kartalta."],
                "the failed search's sentence"
            ))
        }
    }

    /// The editor after an answer was chosen, which is the tallest its panel
    /// gets: the sentence, the answer named under it, the search, the two
    /// rows of how sure, and the buttons.
    func testPlacesMapEditingWithAnAnswer() throws {
        try sweep("Kartta, hakutulos", arguments: editingPuumala + ["-placeSearch", "stub"]) { app, _ in
            require(app.buttons["Etsi nimellä"], "the editor's way to search").tap()
            require(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Koivulantie 12")).firstMatch,
                "the search's answers"
            ).tap()
            settle(require(
                app.staticTexts["Hakutulos: Koivulantie 12, 52200 Puumala"],
                "the chosen answer, named under the map"
            ))
        }
    }

    /// The map over the aerial photograph, on the film-week archive's three
    /// places: the chips on ground nobody can predict, and the circles on
    /// the cream line that ground asks for. `-map.aerial YES` is the bar's
    /// toggle, set the way the phone keeps it.
    func testPlacesMapAerial() throws {
        try sweep(
            "Kartta, ilmakuva",
            arguments: ["-seed", "film-week", "-tab", "memories", "-screen", "placesMap", "-map.aerial", "YES"]
        ) { app, _ in
            let place = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala"))
                .firstMatch
            settle(require(place, "Puumala on the aerial map"))
        }
    }

    /// The editor on Puumala, opened as the card's "Merkitse kartalle" opens
    /// it — the launch hook's `-screen placesMapEditing`.
    private var editingPuumala: [String] {
        [
            "-seed", "archive", "-tab", "memories",
            "-screen", "placesMapEditing", "-place", "demo-puumala",
        ]
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

    /// The same sheet asked of somebody by name, since 25 Sep 2026: a menu of
    /// the family's other members, and a sentence that changes with the
    /// choice. Audited with the choice made, because that is the longer
    /// sentence and the only state in which the menu shows a name.
    func testAskQuestionSheetByName() throws {
        try sweep("Kysy nimeltä", arguments: ["-seed", "aimed", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            // The seed's two questions sit above the button, and at the
            // largest size four swipes stopped short of it (25 Sep 2026).
            reach(app.buttons["Kysy perheeltä"], in: app, "the ask button", swipes: 8).tap()
            let field = require(app.textFields.firstMatch, "the question field")
            field.tap()
            field.typeText("Kuka rakensi saunan?")
            // One button whose label is the picker's own and the choice it
            // shows, joined: "Kenelle?, Koko perhe" until somebody is chosen.
            require(
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kenelle?,")).firstMatch,
                "the Kenelle? menu"
            ).tap()
            require(app.buttons["Ville"], "Ville in the menu").tap()
            require(
                app.staticTexts.matching(NSPredicate(
                    format: "label BEGINSWITH %@", "Kysymys näkyy koko perheelle, mutta"
                )).firstMatch,
                "the sentence for a question asked by name"
            )
        }
    }

    /// Kerro with a question asked of this phone's member by name: offered
    /// first, under "Mummo kysyy sinulta" — the ordinary offer row with a
    /// longer heading, which is the part that grows at the largest size.
    func testTellAskedOfYou() throws {
        try sweep("Kerro, kysytty sinulta", arguments: ["-seed", "aimed", "-tab", "tell"]) { app, _ in
            reach(app.staticTexts["Mummo kysyy sinulta"], in: app, "the question asked of you")
        }
    }

    /// The photograph's card with one question asked of Aino by name and one
    /// asked of you. "Kenelle: Aino" is a line of its own under the question,
    /// and the one new thing on the card.
    ///
    /// Judged at the largest size, at the foot of the card, and not at the
    /// default size, where the questions are below the fold. Scrolled to
    /// there, the default size's audit reported three texts of the memory row
    /// above them — *"Kuulin nämä"*, *"Henkilö"* and the playback button, all
    /// text styles — as Dynamic Type partly unsupported, in two runs out of
    /// two, the second at a lower load (25 Sep 2026). That is the simulation
    /// artefact `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
    /// describes — and has listed those three texts since 26 Sep 2026,
    /// measured on the person card rather than here. The largest size is the
    /// real layout with nothing forgiven, the half that would show those
    /// words being lost.
    ///
    /// Not `auditPageByPage`, for a reason that ended on 26 Sep 2026: this
    /// photograph has no file in the seed, and its place held a
    /// `ProgressView` that never stopped drawing, so the first page could
    /// never be waited out (25 Sep 2026). It holds a sentence now. The foot of
    /// the card is still a fixed place to stop — the list ends there, with
    /// the ask button and its footer under the line.
    func testPhotoDetailAskedByName() throws {
        try sweep("Photo detail, kysytty nimeltä", arguments: ["-seed", "aimed", "-tab", "memories"]) { app, isLargest in
            reachPhotoTile(in: app).tap()
            // At the largest size the sentence in the photograph's place is
            // the whole first screen, as in `testPhotoDetail`.
            if isLargest {
                require(
                    app.staticTexts[
                        "Kuva on vielä puhelimessa, jolla se lisättiin. Se tulee perille, kun se lähetetään sieltä."
                    ],
                    "the photo's own screen"
                )
            } else {
                require(app.buttons["Kerro tästä muisto"], "the photo's own screen")
            }
            guard isLargest else { return }
            for _ in 0 ..< 10 {
                app.swipeUp()
            }
            let line = require(app.staticTexts["Kenelle: Aino"], "the line naming whom it was asked of")
            XCTAssertTrue(hasStoppedDrawing(app), "the foot of the card was still being drawn")
            // Judged means clear of both bars, whose findings the audit
            // forgives by geometry.
            XCTAssertGreaterThanOrEqual(
                line.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1,
                "the line stopped under the navigation bar: \(line.frame)"
            )
            XCTAssertLessThanOrEqual(
                line.frame.maxY, app.tabBars.firstMatch.frame.minY + 1,
                "the line stopped under the tab bar: \(line.frame)"
            )
        }
    }

    /// The same card on a grandparent's phone, and its row pressed: the Tell
    /// screen with the question as its title, at the largest text size.
    ///
    /// Her phone draws the card as a reader's does — nothing on it follows
    /// the text floor, and this is what says so rather than that sentence.
    /// A question asked by name is most often asked of the one who knows,
    /// and on her phone the reading loop is on Albumi, so the row has to
    /// work at her size as well as at a reader's.
    ///
    /// By hand rather than through `sweep`, for the reason
    /// `testMemoriesWithTheBlindCard` gives: with the floor on, the audit's
    /// Dynamic Type simulation cannot move the text, so that one check is
    /// allowed. Contrast, clipping, tap targets and labels are measured.
    func testTellFromACardQuestionOnAGrandparentsPhone() throws {
        let app = launch(
            ["-seed", "aimed", "-elder.largerText", "YES", "-tab", "memories"], textSize: Self.largest
        )
        reachPhotoTile(in: app).tap()
        let asked = "Mitä mökillä syötiin juhannuksena?"
        let row = reach(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", asked)).firstMatch,
            in: app, "the question asked of Aino, on the card", swipes: 10
        )
        // At this size the row is some 610 pt tall and the list builds it
        // with its middle under the tab bar or off the screen. XCUITest calls
        // it hittable all the same and taps its top-left corner — at (17, 749)
        // on 26 Sep 2026 — which opens nothing. Its top edge is brought under
        // the navigation bar first, so that the tap lands in its middle.
        drag(row, toMinY: app.navigationBars.firstMatch.frame.maxY + 12, in: app)
        XCTAssertLessThan(
            row.frame.midY, app.tabBars.firstMatch.frame.minY,
            "the row's middle is still under the tab bar: \(row.frame)"
        )
        row.tap()
        // By identifier: the question's words are on the card under the
        // sheet too, so a query by label finds two.
        let title = require(app.staticTexts["tell.title"], "the Tell screen's title")
        settle(title)
        XCTAssertEqual(title.label, asked, "the Tell screen's title is not the question")
        require(app.buttons["Aloita kertominen"], "the button that answers it")
        try audit(app, "Tell from a card question on a grandparent's phone, largest text size", alsoAllowing: { issue in
            issue.auditType == .dynamicType
        })
    }

    /// The question over a colouring: the picture, a heading in the display
    /// face, and three answers. `-seed blind` is the fixture whose photograph
    /// has both a picture and a telling, which is what the colour button waits
    /// for, and the stub answers with a tint that keeps every edge — so the
    /// sheet reaches its question rather than its refusal, and no credit is
    /// spent. Audited once the stub's answer is on screen: the progress view
    /// before it never stops drawing.
    func testColourSheet() throws {
        try sweep("Värit kerronnan mukaan", arguments: ["-seed", "blind", "-tab", "memories"]) { app, _ in
            reachPhotoTile(in: app).tap()
            reach(app.buttons["Väritä kerronnan mukaan"], in: app, "the way to colour the photograph").tap()
            require(app.staticTexts["Näyttääkö tältä?"], "the question over the colouring")
            XCTAssertTrue(hasStoppedDrawing(app), "the colour sheet was still being drawn when the audit ran")
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
            require(app.navigationBars["Albumi"], "the landing on Muistot")
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
    /// Muistot on a grandparent's phone with the blind card on it.
    ///
    /// By hand rather than through `sweep`, because the text floor is on — it
    /// is what puts the card here — and with the floor the audit's Dynamic
    /// Type simulation cannot move the text: not down at the default size, not
    /// down from the largest either, so it reports texts as "partially
    /// unsupported" at both. Measured 5 Sep 2026: the plain gallery with the
    /// floor and no card gives three such findings ("Puumala", "Kerro tästä",
    /// "Paikat") at the default size, and this screen gives one on the card's
    /// title at the largest. That one check is allowed here; contrast,
    /// clipping, tap targets and labels are measured at both sizes, and the
    /// card's own Dynamic Type behaviour is measured without the floor by
    /// testTellWithACard, on the same view.
    func testMemoriesWithTheBlindCard() throws {
        for size in [nil, Self.largest] {
            let app = launch(
                ["-seed", "blind", "-elder.largerText", "YES", "-tab", "memories"], textSize: size
            )
            require(app.staticTexts["Kuka tässä on?"], "the blind card on Muistot")
            XCTAssertTrue(hasStoppedDrawing(app), "Muistot was still being drawn when the audit ran")
            let at = size == nil ? "default text size" : "largest text size"
            // The title's contrast, at the largest size only. Measured 5 Sep
            // 2026, twice, settled: the audit holds the title's frame at
            // y 450–592 and the screenshot shows the text at 558–680 — the
            // expanded large title's height, and the frame it samples lies
            // over the card's photograph, so a black-on-white title reports
            // as failing contrast. Every other element on the screen is
            // measured for contrast as usual, and the same title is measured
            // without the large title above it by testTellWithACard.
            try audit(app, "Memories with the blind card, \(at)", alsoAllowing: { issue in
                issue.auditType == .dynamicType
                    || (size != nil && issue.auditType == .contrast
                        && issue.element?.label == "Kuka tässä on?")
            })
            app.terminate()
        }
    }

    func testMemoriesNewFromFamily() throws {
        try sweep("Muistot, uutta perheeltä", arguments: ["-seed", "unseen"]) { app, _ in
            require(app.navigationBars["Albumi"], "the landing on Muistot")
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

    /// The map of places, which ARCHITECTURE §18 said until 21 Sep 2026 did
    /// not exist on purpose. Opened from the album's Paikat section on the
    /// film-week archive, the one seeded launch with three places to draw —
    /// Puumala, Savonlinna and Sulkava, all municipalities — so that the
    /// chips are measured beside each other and not one alone: Savonlinna
    /// and Sulkava are 27 km apart, and at the largest text size that is
    /// where two chips would overlap.
    ///
    /// Puumala's chip is what proves arrival. A chip is a button whose label
    /// is the place's name, and the album's row of the same name is under the
    /// map by then.
    func testPlacesMap() throws {
        try sweep("Paikkojen kartta", arguments: ["-seed", "film-week", "-tab", "memories"]) { app, _ in
            // Below a week of tellings, which at the largest size is more
            // than `reach`'s four swipes.
            let button = app.buttons["Näytä kartalla"]
            for _ in 0 ..< 10 where !button.exists { app.swipeUp() }
            require(button, "the album's way to the map").tap()
            require(app.navigationBars["Kartta"], "the map of places")
            let chip = app.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Puumala"))
                .firstMatch
            // Tiles arrive over several frames; the chip's frame is what is
            // waited for, as the place card's map is.
            settle(require(chip, "Puumala's chip on the map"))
        }
    }

    /// The same map opened on one place, the way a place card's own map
    /// opens it: centred on Puumala with its neighbours in view, and a panel
    /// under it that names the place, says how sure the archive is of the
    /// point and offers two buttons. That panel is the new shape here. At
    /// the default size it floats over the map's lower edge, where the tab
    /// bar also is; at the largest it sits between the picture and the rows,
    /// and its two buttons stack when they no longer fit side by side.
    ///
    /// "Muuta sijaintia" is what proves arrival — it exists only while the
    /// map is about one place.
    func testPlacesMapOnOnePlace() throws {
        try sweep(
            "Kartta, yksi paikka",
            arguments: [
                "-seed", "film-week", "-tab", "memories",
                "-screen", "placesMap", "-place", "demo-puumala",
            ]
        ) { app, _ in
            settle(require(app.buttons["Muuta sijaintia"], "the panel of the map opened on Puumala"))
        }
    }

    /// And opened on nothing at all: an album with no places, whose bar has
    /// the door all the same. The map frames Finland and the panel says what
    /// will come; a blank sea with no sentence would read as a map that
    /// failed.
    func testPlacesMapEmpty() throws {
        try sweep(
            "Kartta, tyhjä",
            arguments: ["-seed", "empty", "-tab", "memories", "-screen", "placesMap"]
        ) { app, _ in
            settle(require(
                app.staticTexts["Kun kerrotte paikoista, ne tulevat tähän kartalle."],
                "the empty map's sentence"
            ))
        }
    }
}
