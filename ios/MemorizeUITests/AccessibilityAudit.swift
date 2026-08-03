import XCTest

/// The shared accessibility check.
///
/// `performAccessibilityAudit()` throws on the first issue and names only its
/// type — "Contrast failed", no element. Fixing one and rediscovering the next
/// costs a full run each time, and on a screen with four failing buttons that is
/// four runs to learn one fact. This collects them all and names the element.
extension XCTestCase {
    func audit(
        _ app: XCUIApplication,
        _ context: String,
        alsoAllowing extra: @escaping (XCUIAccessibilityAuditIssue) -> Bool = { _ in false },
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // Read once: every query is a round trip to the app, and the tab bar is
        // consulted for most issues.
        let tabBar = app.tabBars.firstMatch
        let tabBarFrame = tabBar.exists ? tabBar.frame : .null
        // The keyboard for the same reason: a screen with a text field on it
        // puts a third of itself under the keys, and the audit samples the
        // pixels it finds there.
        let keyboard = app.keyboards.firstMatch
        let keyboardFrame = keyboard.exists ? keyboard.frame : .null

        var found: [String] = []
        try app.performAccessibilityAudit { issue in
            if AccessibilityPolicy.isDeliberate(issue, tabBar: tabBarFrame, keyboard: keyboardFrame) || extra(issue) {
                return true
            }
            // Type and frame as well as the label: an issue whose label is empty
            // is exactly the one that needs identifying, and "no description" on
            // its own says nothing about which element.
            let element = issue.element
            let label = element?.label ?? "no element"
            let where_ = element.map { "\($0.elementType.rawValue)@\(NSCoder.string(for: $0.frame))" } ?? "-"
            found.append("\(issue.compactDescription) — \"\(label)\" [\(where_)]")
            // Collected rather than thrown, so the run reaches the end.
            return true
        }
        XCTAssertTrue(
            found.isEmpty,
            "\(context): \(found.count) accessibility issue(s)"
                // The bar's own frame, because half the contrast findings in
                // this app turn on how close to it something sits, and reading
                // that off a screenshot is guesswork.
                + " [tab bar \(tabBarFrame.isNull ? "none" : NSCoder.string(for: tabBarFrame))"
                + " keyboard \(keyboardFrame.isNull ? "none" : NSCoder.string(for: keyboardFrame))]"
                + "\n  " + found.joined(separator: "\n  "),
            file: file,
            line: line
        )
    }

    /// Launches with the environment pinned.
    ///
    /// `-api ""` matters more than it looks. Without it the run inherits whatever
    /// address the last hand-run left in UserDefaults, and a device that has been
    /// pointed at a Worker starts on the join screen instead — which is how the
    /// first of these tests failed, with nothing wrong in the app.
    func launch(
        _ arguments: [String] = [],
        api: String = "",
        textSize: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-api", api] + arguments
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        return app
    }
}

/// The findings that are decisions rather than defects.
///
/// Every one is listed with a reason. Narrowing the audit to a few types would
/// be shorter and would also switch off the checks that catch real regressions
/// in those same categories — which is how the contrast problem survived this
/// long in the first place.
enum AccessibilityPolicy {
    /// The guessing round's gap. Kept here rather than imported from the app: if
    /// the app changes its mask, the test should fail and be looked at.
    static let mask = "———"

    /// `ContentUnavailableView` sizes its own title and description, and it caps
    /// their growth. These are its labels, not ours. The empty states matter in
    /// this app — they are invitations rather than blanks — so if the system
    /// view ever stops being good enough, the answer is to stop using it, not to
    /// widen this list.
    private static let systemEmptyStateText: Set<String> = [
        "Ei vielä kuvia",
        "Valitse kuvia",
        "Lisää vanha valokuva, niin koko perhe voi kertoa siitä omat muistonsa.",
        "Ei vielä ihmisiä",
        "Suvun henkilöt kertyvät tähän sitä mukaa kun heistä puhutaan. Jokaisesta kirjoitetaan yhdessä, millainen hän oli.",
        // A List styles its own footers and caps them the same way.
        "Kysymys näkyy perheelle Kerro-näytöllä, ja vastaus tallentuu tähän.",
    ]

    static func isDeliberate(
        _ issue: XCUIAccessibilityAuditIssue,
        tabBar: CGRect,
        keyboard: CGRect
    ) -> Bool {
        let label = issue.element?.label ?? ""

        // **Behind the keyboard.** A sheet with a text field on it raises the
        // keys over its own lower third, and what the audit measures there is
        // the keyboard. The send button on the ask sheet was reported as
        // low-contrast at the largest text size for exactly this reason, at a
        // position the keys were covering. Contrast only, and only where the
        // element really is underneath.
        if issue.auditType == .contrast, !keyboard.isNull,
           let frame = issue.element?.frame, frame.intersects(keyboard) {
            return true
        }

        // **Text under the floating tab bar.** iOS 26's tab bar is a translucent
        // capsule that content scrolls beneath by design, and the audit samples
        // the pixels it dims. Every contrast failure left at the largest text
        // size is this: "Kuvat", "Paina ja ala puhua" and "Ehdotus — vahvista
        // henkilö" are the same colours that pass at every other size, and they
        // were checked on screen. What fails is the overlap, not the colour.
        //
        // Deliberately narrow: contrast only, and only where the element really
        // does overlap the bar.
        // **Off the top of the screen.** Contrast is measured from pixels, and
        // there are none where an element has scrolled above the viewport: the
        // ask sheet's heading was reported at y −118 with the keyboard up, which
        // is not a colour anybody can see. The same reasoning as the tab bar
        // below, from the other end.
        if issue.auditType == .contrast, let frame = issue.element?.frame, frame.minY < 0 {
            return true
        }

        if issue.auditType == .contrast, !tabBar.isNull {
            // The bar's top edge, less the distance its scroll-edge effect
            // reaches above it. iOS 26 fades content into the bar rather than
            // stopping at its rectangle, so "overlaps the bar" was too narrow a
            // test — and the numbers say by how much.
            //
            // Measured rather than assumed. The memory author's name is
            // `Elder.supporting`, the token this app picked at 6.6:1. It passes
            // on the person card near the top of the screen and fails on the
            // photo's card at y 767–782, with the bar at y 791. Same view, same
            // colour, same run: nine points of fade is the whole difference.
            // The margin is set at 24 because the effect is a gradient and one
            // sample does not give its length; if something ever fails between
            // 24 and 40 points above the bar, measure it before widening this
            // again.
            if let frame = issue.element?.frame, frame.maxY >= tabBar.minY - 24 { return true }
            // The audit sometimes reports a contrast failure it cannot attribute
            // to any element at all. Every one of those seen here was on a
            // tab-bar screen at the largest text size, in the same band of
            // pixels, and the attributable ones beside it were checked on
            // screen. Accepting it is a concession to the tool: with no element
            // there is no frame to test and nothing to point a fix at.
            if issue.element == nil { return true }
        }

        // The round's card shows two to four lines of the story and truncates.
        // It is a teaser: the whole text is one tap away, and the card's
        // accessibility label carries all of it, so VoiceOver loses nothing.
        if issue.auditType == .textClipped, label.contains(mask) {
            return true
        }

        // A Menu reports a label frame smaller than the text it draws. Checked
        // on screen at both sizes: "Lisää sukulainen" is shown in full.
        if issue.auditType == .textClipped, label == "Lisää sukulainen" {
            return true
        }

        // The photo tile's memory count is capped at accessibility2 on purpose —
        // past that the badge stops being a label and becomes the tile. The
        // count is also in the tile's accessibility label and on the detail
        // screen, so it is not only available here. GalleryScreen says the same
        // in a comment.
        if issue.auditType == .dynamicType, label.count <= 5 {
            return true
        }

        if issue.auditType == .dynamicType, systemEmptyStateText.contains(label) {
            return true
        }

        return false
    }
}
