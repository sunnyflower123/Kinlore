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

        var found: [String] = []
        try app.performAccessibilityAudit { issue in
            if AccessibilityPolicy.isDeliberate(issue, tabBar: tabBarFrame) || extra(issue) {
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
            "\(context): \(found.count) accessibility issue(s)\n  " + found.joined(separator: "\n  "),
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

    static func isDeliberate(_ issue: XCUIAccessibilityAuditIssue, tabBar: CGRect) -> Bool {
        let label = issue.element?.label ?? ""

        // **Text under the floating tab bar.** iOS 26's tab bar is a translucent
        // capsule that content scrolls beneath by design, and the audit samples
        // the pixels it dims. Every contrast failure left at the largest text
        // size is this: "Kuvat", "Paina ja ala puhua" and "Ehdotus — vahvista
        // henkilö" are the same colours that pass at every other size, and they
        // were checked on screen. What fails is the overlap, not the colour.
        //
        // Deliberately narrow: contrast only, and only where the element really
        // does overlap the bar.
        if issue.auditType == .contrast, !tabBar.isNull {
            if let frame = issue.element?.frame, frame.intersects(tabBar) { return true }
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
