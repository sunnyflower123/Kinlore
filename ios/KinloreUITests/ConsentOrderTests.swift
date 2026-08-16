import XCTest

/// The sentence saying where a recording goes has to be readable *before* the
/// button that sends one.
///
/// PLAN.md §10 lever 1 is about an order rather than a fact. The audio leaving
/// the phone was always going to be true; the barrier was that nobody was told
/// before deciding, and the microphone prompt arrives after the archive already
/// exists. `WhereMemoriesGo` answered that by saying it on the two setup forms.
///
/// But it sits in a section *below* the button on both of them, and at the
/// largest text size these forms run to two or three screenfuls. A consent
/// notice underneath the button somebody has already pressed is the same
/// failure again at a smaller scale, and it would look completely fine in a
/// screenshot taken at the ordinary size.
///
/// **The audit cannot express this.** `performAccessibilityAudit` measures
/// contrast, clipping and tap targets on whatever is drawn. It has nothing to
/// say about which of two things is met first, and a form where the sentence is
/// one swipe below the button passes it cleanly — which is why this is a test
/// of its own rather than another entry in the sweep.
final class ConsentOrderTests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    /// A non-empty address with nothing behind it. It matters: with an empty one
    /// the app opens as a single-device archive and there is no onboarding to
    /// walk through at all. Nothing here is fetched from it.
    private static let api = "http://127.0.0.1:9"

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - The two forms

    func testTheNoticeIsOnScreenWhenTheCreateButtonIs() {
        for size in [nil, Self.largest] {
            checkNoticeReachesTheButton(
                onboardingButton: "Aloita perheen arkisto",
                landmark: "Kenen puhelin tämä on",
                commit: "Luo arkisto",
                textSize: size
            )
        }
    }

    func testTheNoticeIsOnScreenWhenTheJoinButtonIs() {
        for size in [nil, Self.largest] {
            checkNoticeReachesTheButton(
                onboardingButton: "Liity kutsulinkillä",
                landmark: "Kutsu",
                commit: "Liity perheeseen",
                textSize: size
            )
        }
    }

    // MARK: - The check

    private func checkNoticeReachesTheButton(
        onboardingButton: String,
        landmark: String,
        commit: String,
        textSize: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let at = textSize == nil ? "default text size" : "largest text size"
        let app = launch([], api: Self.api, textSize: textSize)
        defer { app.terminate() }

        let way = app.buttons[onboardingButton]
        XCTAssertTrue(
            way.waitForExistence(timeout: 10),
            "never arrived at \(at): \(onboardingButton)",
            file: file,
            line: line
        )
        way.tap()
        XCTAssertTrue(
            app.staticTexts[landmark].waitForExistence(timeout: 10),
            "the form behind \(onboardingButton) never arrived at \(at)",
            file: file,
            line: line
        )

        let button = app.buttons[commit]
        stopWhereTheButtonBecomesPressable(button, named: commit, in: app, at: at, file: file, line: line)

        // Read after the scrolling has stopped. A frame sampled mid-swipe is a
        // position nothing ever held, and this test is entirely about positions.
        settle(button)

        let notice = notice(in: app)
        let screen = app.windows.firstMatch.frame

        // `exists` is the strongest form of the failure rather than a
        // precondition for the real one. A Form does not build a section nobody
        // can see, so a notice that is not there yet is a notice that is more
        // than a screenful below the button somebody is about to press.
        XCTAssertTrue(
            notice.exists,
            "At the \(at) the notice about where a recording goes had not been "
                + "built when \"\(commit)\" became pressable — it is more than a "
                + "screenful below the button. PLAN.md §10 lever 1.",
            file: file,
            line: line
        )

        // Where it starts, not where it ends. At the largest text size the
        // sentence alone is taller than the space left beside a button, so
        // demanding the whole of it would be demanding something no wording
        // could satisfy. Beginning on the same screenful is the honest bar:
        // enough to be seen and read on, rather than found afterwards.
        //
        // **It passes, and the margin is the reason this test exists.** Measured
        // 16 Aug 2026 on `Uusi arkisto`: 287 pt of room at the default size and
        // **74 pt at the largest** — about one line. So today the notice clears
        // the bottom edge by roughly its own first line, and anything added
        // between the button and it, or any growth in the sections above, spends
        // a margin nobody would think to check. That is the regression this is
        // here to catch, and it is invisible in a screenshot at the size the
        // screen is usually looked at.
        XCTAssertLessThan(
            notice.frame.minY,
            screen.maxY,
            "At the \(at) the notice starts \(Int(notice.frame.minY - screen.maxY)) pt "
                + "below the bottom of the screen while \"\(commit)\" is pressable, so "
                + "the button can be pressed without it having been on screen. "
                + "PLAN.md §10 lever 1 is about the order, not the wording.",
            file: file,
            line: line
        )
    }

    // MARK: - Helpers

    /// Part of `WhereMemoriesGo` and not all of it. Matching the whole sentence
    /// would turn every rewording into a red test, which is not what this is
    /// here to catch — the clause about the recording being sent is.
    private func notice(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Äänitys lähetetään"))
            .firstMatch
    }

    /// Scrolls the way somebody does who is looking for the button: one swipe at
    /// a time, stopping the moment it can be pressed.
    ///
    /// Scrolling to the bottom instead would put both things on screen and prove
    /// nothing at all. The question is what is visible at the moment the button
    /// first becomes pressable, because that is the moment somebody presses it.
    private func stopWhereTheButtonBecomesPressable(
        _ button: XCUIElement,
        named name: String,
        in app: XCUIApplication,
        at: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0 ..< 8 where !(button.exists && button.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(
            button.exists && button.isHittable,
            "never became pressable at \(at): \(name)",
            file: file,
            line: line
        )
    }

    /// Waits until an element has stopped moving, by reading its frame twice.
    ///
    /// The same reason the sweep has one: a swipe leaves a form gliding, and
    /// deciding this test on a frame from mid-glide would make it answer a
    /// different question every run. Polling is deterministic where a sleep is a
    /// guess.
    private func settle(_ element: XCUIElement) {
        var previous = element.frame
        for _ in 0 ..< 30 {
            Thread.sleep(forTimeInterval: 0.1)
            let current = element.frame
            if current == previous { return }
            previous = current
        }
    }
}
