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
        // The chrome at the top, which is the tab bar's problem from the other
        // end: content fades into it as it scrolls underneath. The search field
        // is part of it when it is showing and absent from the tree when it is
        // not, so the navigation bar is the anchor and the field only ever
        // extends it downwards.
        let navBar = app.navigationBars.firstMatch
        var topFrame = navBar.exists ? navBar.frame : .null
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            topFrame = topFrame.isNull ? searchField.frame : topFrame.union(searchField.frame)
        }

        var found: [String] = []
        try app.performAccessibilityAudit { issue in
            if AccessibilityPolicy.isDeliberate(
                issue, tabBar: tabBarFrame, keyboard: keyboardFrame, topChrome: topFrame
            ) || extra(issue) {
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
                + " keyboard \(keyboardFrame.isNull ? "none" : NSCoder.string(for: keyboardFrame))"
                // The top chrome for the same reason as the bar's own frame: a
                // finding a few points under it is a fade rather than a colour,
                // and reading that off a screenshot is guesswork.
                + " top \(topFrame.isNull ? "none" : NSCoder.string(for: topFrame))]"
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
    ]

    /// A `List` caps how far its own footers grow, exactly as
    /// `ContentUnavailableView` caps its description — same framework decision,
    /// different view, and it is worth keeping apart from the empty states
    /// because these are sentences we wrote.
    ///
    /// **Measured before being listed, both times.** The finding appears at the
    /// *default* size, where the audit simulates scaling; at a real
    /// AccessibilityXXXL the same screens audit clean and the sentences are
    /// drawn in full — the settings footer below moved from y 659 to y 587 when
    /// a section above it was shortened, which is how a framework cap gives
    /// itself away: a defect in a sentence does not depend on where the sentence
    /// sits.
    ///
    /// So: measure at XXXL before adding anything here. A footer that is
    /// genuinely truncated on screen is a defect, and no list makes it not one.
    private static let listFooterText: Set<String> = [
        "Kysymys näkyy perheelle Kerro-näytöllä, ja vastaus tallentuu tähän.",
        // Reached from the other direction as well, and worth keeping: this one
        // began failing the moment a row was added *above* it, and giving it an
        // explicit Dynamic Type font changed the finding not at all. Both facts
        // say the same thing as the y-coordinate above — the metrics are the
        // List's, not our typography's.
        "Kertomasi muistot ovat vain tässä laitteessa.",
    ]

    static func isDeliberate(
        _ issue: XCUIAccessibilityAuditIssue,
        tabBar: CGRect,
        keyboard: CGRect,
        topChrome: CGRect = .null
    ) -> Bool {
        let label = issue.element?.label ?? ""

        // **Just under the navigation bar.** The tab bar's case from the other
        // end: iOS 26 fades content into the bar and its search field as it
        // scrolls beneath, and the audit samples the dimmed pixels.
        //
        // Measured before it was written. "Muistatko kuka?" is the primary
        // colour at `.title3.weight(.semibold)` — the strongest text in the app
        // — and it began failing at the largest size the day a search field was
        // added above it, a few points below the chrome. Screenshotted at that
        // size: black on white, perfectly readable. The same 24 pt margin as
        // the tab bar, and the same warning with it: if something ever fails
        // further down than this, measure it before widening the band.
        if issue.auditType == .contrast, !topChrome.isNull,
           let frame = issue.element?.frame,
           frame.minY <= topChrome.maxY + 24 {
            return true
        }

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

        // **A control that is switched off.** iOS draws a disabled control dim
        // on purpose — that is what "not yet" looks like — and the contrast
        // minimum exempts inactive components for exactly that reason. The
        // correction sheet opens with the name already in the field, so
        // "Tallenna" is disabled until something changes, and the audit was
        // measuring the dimming rather than a colour anybody chose.
        //
        // Narrow on purpose: contrast only, and only where the element really
        // is disabled. What keeps the disabling itself honest is a functional
        // test rather than this exemption — `NameCorrectionTests` asserts that
        // Tallenna stays disabled while there is nothing to save.
        if issue.auditType == .contrast, issue.element?.isEnabled == false {
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

        // **The search field's own text.** iOS gives `.searchable` a fixed 44 pt
        // box with its own metrics, and the audit reads that as clipping. The
        // evidence that it is the box and not our words: shortening the prompt
        // from twenty-seven characters to four changed nothing at all. What is
        // ours on that screen grows — the empty state under it is `elderBody`
        // and wraps at every size.
        if issue.auditType == .textClipped, issue.element?.elementType == .searchField {
            return true
        }

        // **The search field's own clear button.** `.searchable` draws it at
        // 19 × 19 pt and there is no API to make it bigger — it belongs to
        // UIKit's search field, like `ContentUnavailableView`'s type sizes
        // belong to that view. Ours are 60 pt everywhere and stay so.
        //
        // Accepted rather than answered, and the reason it can be: nothing
        // depends on hitting it. The keyboard's delete key clears the field,
        // "Peruuta" beside it is a full-size target that clears it as well, and
        // search is the one part of this app aimed at the grandchild rather
        // than at the person whose hands shake. If that ever stops being true,
        // the answer is our own field rather than a wider exemption.
        if issue.auditType == .hitRegion, label == "Clear text" {
            return true
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

        if issue.auditType == .dynamicType, listFooterText.contains(label) {
            return true
        }

        return false
    }
}
