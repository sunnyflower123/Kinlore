import UIKit
import XCTest

/// Counts the pixels a contrast finding is actually made of.
///
/// The audit reports a colour it computed from the view tree; near the floating
/// tab bar it computes one nobody ever saw, because iOS 26 fades content into
/// the bar and the audit reads the fade as the text's own colour. That produced
/// a real afternoon's chase over "Kerro tästä" — which measures 5.40:1 on
/// screen, against a 4.5:1 minimum.
///
/// The obvious answer was to widen the band of forgiveness around the bar, and
/// it is the wrong one: a band excuses *everything* that lands in it, so the
/// next real failure 30 pt above the bar would be silent — and contrast is
/// precisely the thing rule 1 says eyes cannot check. So the strip is forgiven
/// by measurement rather than by distance. One screenshot per audit, cropped to
/// the element the audit is complaining about.
struct ContrastMeter {
    /// WCAG's minimum for body text. The same number the audit uses.
    static let minimum = 4.5

    private let image: CGImage
    private let pixelsPerPoint: CGFloat

    init?(app: XCUIApplication) {
        let bounds = app.frame
        guard bounds.width > 0, let cgImage = app.screenshot().image.cgImage else { return nil }
        image = cgImage
        pixelsPerPoint = CGFloat(cgImage.width) / bounds.width
    }

    /// The contrast between the darkest and the lightest thing inside a frame.
    ///
    /// Percentiles rather than the extremes: a glyph's edge pixels are
    /// anti-aliased into the background, and one stray pixel of either would
    /// decide the answer. The 95th is the paper of any label; the ink is the
    /// **1st** — the 5th until 6 Sep 2026, the 2nd until 10 Sep, and the
    /// measurement that moved it each time is beside the line itself below. A frame is often a tap
    /// target rather than a word: the invite row's *"Poista"* is a 60 × 60 pt
    /// target around a 15 pt word, some three per cent ink, and the 5th
    /// percentile landed past the ink on its anti-aliased fringe — 1.59:1 for
    /// a colour that is 6.4:1 on screen, reported as the tab bar's fade
    /// because it happened to sit near it. Measured on that frame and four
    /// text-sized ones in the same run: 5th / 2nd / 1st percentile gave
    /// 1.59 / 6.40 / 6.43 on the target and 17.4 / 17.8 / 18.1, 20.9 / 20.9 /
    /// 21.0, 9.3 / 9.4 / 9.6 and 14.95 / 15.3 / 15.3 on the words. The 2nd
    /// agrees with the 5th wherever the frame is a word and finds the ink
    /// where it is a target; the 1st is one stray pixel away on a small frame.
    ///
    /// **Nil is not a pass.** It means the frame could not be measured — off the
    /// screenshot, or too small to hold a glyph — and the caller reports the
    /// finding rather than forgiving it. Every uncertainty here has to fall on
    /// the side of somebody looking at it.
    func ratio(in frame: CGRect) -> Double? {
        let rect = CGRect(
            x: frame.minX * pixelsPerPoint,
            y: frame.minY * pixelsPerPoint,
            width: frame.width * pixelsPerPoint,
            height: frame.height * pixelsPerPoint
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 4, rect.height >= 4, let crop = image.cropping(to: rect) else { return nil }

        let width = crop.width
        let height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // `withUnsafeMutableBytes` rather than `&pixels`: a context built on the
        // second one outlives the pointer it was handed, and the test runner
        // exits without a message rather than failing — which reads exactly like
        // a flaky simulator and cost a run to tell apart.
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        var luminances: [Double] = []
        luminances.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            luminances.append(Self.luminance(
                red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2]
            ))
        }
        guard luminances.count >= 16 else { return nil }
        luminances.sort()
        // The **1st**, and it was the 2nd until 10 Sep 2026. The same failure
        // as the 5th before it, one size of frame further out: the blind
        // card's name buttons are 354 x 60 pt tap targets around a four-letter
        // word, so the ink is between one and two per cent of the frame and
        // the 2nd percentile landed just past it. "Eeva" was reported at
        // 1.53:1 against a 4.5:1 minimum, on a screen where it is black on a
        // pale pill. Measured on that card's own audit picture, 1062 x 180 px:
        //
        //   0.1st / 0.5th   18.22:1   the ink, which is what it really is
        //   1st              8.18:1   ink and fringe — a pass, and honest
        //   2nd              1.53:1   the pill
        //   3rd / 5th / 10th 1.52:1   the pill
        //
        // **0.5 would have found the true colour and is still not taken.** A
        // blank strip of parchment on the same picture — no ink at all, the
        // frame this meter must go on failing — measures 1.00:1 at the 10th,
        // 2.16 at the 2nd, 3.08 at the 1st, and **16.01:1 at the 0.5th**,
        // where a handful of stray dark pixels at the frame's edge would
        // become "readable text". The 1st is the last percentile that finds
        // the ink in a sparse target and still fails a frame with none.
        //
        // The change can only raise a ratio — a darker `dark` over the same
        // `light` — so it cannot invent a finding; it can only stop one. That
        // is the direction that needs the control above, not a test run.
        let dark = luminances[max(1, luminances.count / 100)]
        let light = luminances[luminances.count - 1 - luminances.count / 20]
        return (light + 0.05) / (dark + 0.05)
    }

    private static func luminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        func channel(_ value: UInt8) -> Double {
            let v = Double(value) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

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
        // Where the scrolling stops. A list builds its rows lazily, so what is
        // below the fold is not in the tree at all — but a drawing is one view
        // with everything in it, and the family tree renders every generation
        // whether or not it is on screen. The tallest scroll view, because a
        // screen can hold more than one: the tree's own drawing scrolls
        // sideways inside the page that scrolls down.
        let scrollers = app.scrollViews.allElementsBoundByIndex.map(\.frame)
        let contentFrame = scrollers.max { $0.height < $1.height } ?? .null

        var found: [String] = []
        // Contrast findings in the fade above the tab bar, held back until the
        // audit has finished so their pixels can be counted.
        //
        // **Not measured inside the handler.** A screenshot taken while
        // `performAccessibilityAudit` is running kills the runner outright —
        // signal kill, no assertion, no message, indistinguishable from a flaky
        // simulator. It cost two runs to find, so it is written down here: the
        // audit holds the accessibility channel, and asking the same channel for
        // a picture in the middle of it is not a thing to retry.
        var deferred: [(line: String, frame: CGRect)] = []

        try app.performAccessibilityAudit { issue in
            if AccessibilityPolicy.isDeliberate(
                issue, tabBar: tabBarFrame, keyboard: keyboardFrame, topChrome: topFrame,
                content: contentFrame, screen: app.frame
            ) || extra(issue) {
                return true
            }
            // Type and frame as well as the label: an issue whose label is empty
            // is exactly the one that needs identifying, and "no description" on
            // its own says nothing about which element.
            let element = issue.element
            let label = element?.label ?? "no element"
            let where_ = element.map { "\($0.elementType.rawValue)@\(NSCoder.string(for: $0.frame))\($0.identifier.isEmpty ? "" : " id=\($0.identifier)")" } ?? "-"
            let line = "\(issue.compactDescription) — \"\(label)\" [\(where_)]"

            // The fade above the tab bar is decided by counting pixels, once the
            // audit has let go of the channel.
            if issue.auditType == .contrast, !tabBarFrame.isNull, let frame = element?.frame,
               !frame.intersects(tabBarFrame),
               frame.maxY >= tabBarFrame.minY - AccessibilityPolicy.fadeReach {
                deferred.append((line, frame))
                return true
            }

            found.append(line)
            // Collected rather than thrown, so the run reaches the end.
            return true
        }

        // Now that the audit is finished, one screenshot answers all of them.
        //
        // The measured ratio travels with whatever is still reported, so the
        // next person does not crop a screenshot by hand to learn whether the
        // audit is describing a colour or a fade. A finding that cannot be
        // measured is reported rather than forgiven: the point of measuring is
        // to keep the net tight, and an uncertainty resolved in the app's favour
        // is the net with a hole in it.
        // A picture of the screen, kept when asked for:
        // `TEST_RUNNER_KINLORE_AUDIT_SHOT=/some/dir/prefix` on the xcodebuild
        // line writes one PNG per audit that reported anything. It is what
        // told a frame full of paper from a word in the fade on 6 Sep 2026,
        // and it costs nothing when the variable is not set.
        //
        // **And give it to xcodebuild's own environment, not as a build
        // setting.** `TEST_RUNNER_KINLORE_AUDIT_SHOT=… xcodebuild …` reaches
        // the runner; the same text written after `xcodebuild` as an argument
        // does not, and it fails the way everything else about this variable
        // fails — in silence, with the run otherwise identical. Measured 19
        // Sep 2026 on `KINLORE_XXXL_LOSS`, the sweep's own variable, which
        // this process reads through the same `ProcessInfo` call: as an
        // argument the lookup was nil, as an environment prefix it was not,
        // same command otherwise. The shot itself was measured the same day
        // on an audit that reported two issues: as an argument its directory
        // stayed empty, as an environment prefix it held one 540 940-byte PNG.
        //
        // **Give it a path under `/tmp`.** A prefix inside a session's own
        // scratchpad produces no file at all: the simulator cannot write into
        // `/private/tmp/claude-<uid>/…`, the write below is `try?`, and so the
        // run prints its findings and stays otherwise identical — nothing says
        // the picture is missing except the empty directory. Measured 19 Sep
        // 2026, when the same command with `/tmp/kinlore-shot/card` wrote the
        // PNG on the first attempt.
        //
        // **It is taken here, after the audit has finished**, so it is the
        // settled screen and not necessarily the one the audit judged. It
        // answers what colour was drawn; it cannot show what the audit saw on
        // a screen that was still drawing. This comment used to call it "the
        // picture the findings were made on", and on 12 Sep 2026 a red finding
        // was measured from one at 18.21:1 and called the audit's mistake —
        // when the cheaper answer, that the test passed on its own, had not
        // been asked yet (CLAUDE.md, beside the worktree rule).
        if let shot = ProcessInfo.processInfo.environment["KINLORE_AUDIT_SHOT"],
           !found.isEmpty || !deferred.isEmpty {
            let name = context.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(shot)-\(name).png"))
        }
        if !deferred.isEmpty {
            let meter = ContrastMeter(app: app)
            for (line, frame) in deferred {
                let ratio = meter?.ratio(in: frame)
                if let ratio, ratio >= ContrastMeter.minimum { continue }
                found.append(line + (ratio.map { String(format: " measured %.2f:1", $0) } ?? " unmeasurable"))
            }
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
    ///
    /// The language is pinned for the same kind of reason and it is newer. Every
    /// query in this suite names an element by its Finnish label — `buttons[
    /// "Aloita perheen arkisto"]`, `tabBars.buttons["Albumi"]` — which was safe
    /// while the app had exactly one language. It stopped being safe on
    /// 30 Aug 2026, when English was added: on a simulator set to English the
    /// app answers in English and every one of those queries finds nothing.
    /// The suite failed as "never arrived: the ask button", which reads like a
    /// broken screen and is a device set to the wrong language.
    func launch(
        _ arguments: [String] = [],
        api: String = "",
        textSize: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(fi)", "-AppleLocale", "fi_FI"]
        app.launchArguments += ["-api", api] + arguments
        // Ihmiset opens on the drawn tree on a family member's phone since
        // 13 Sep 2026. Every test written before that is about the list, so
        // the list is what a test gets unless it names `-people` itself.
        if !arguments.contains("-people") {
            app.launchArguments += ["-people", "list"]
        }
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        return app
    }
}

/// UIKit's own name for the clear button inside a `.searchable` field, in every
/// language this app ships. It is the system's string and not ours, so it cannot
/// be looked up in our table — and it changes with the app's language, which is
/// what broke the exemption below when English was added.
private let searchFieldClearButtonLabels: Set<String> = ["Clear text", "Poista teksti"]

/// MapKit's own name for the attribution link it draws at the bottom-left of
/// every `Map`, in every language this app ships. The system's string, like the
/// clear button's, and it changes with the app's language the same way: the
/// Finnish one is the label the audit printed on 21 Sep 2026.
private let mapLegalLinkLabels: Set<String> = ["Lakitiedot", "Legal"]

/// The findings that are decisions rather than defects.
///
/// Every one is listed with a reason. Narrowing the audit to a few types would
/// be shorter and would also switch off the checks that catch real regressions
/// in those same categories — which is how the contrast problem survived this
/// long in the first place.
enum AccessibilityPolicy {
    /// How far above the floating tab bar its scroll-edge effect still dims
    /// what is underneath it.
    ///
    /// Not a forgiveness margin any more — it is the strip where a contrast
    /// finding is answered by counting pixels rather than by trusting either
    /// side. 40 pt was the outer limit the earlier note here named as worth
    /// thinking about, and two samples sat inside it: `Elder.supporting` 9 pt
    /// above the bar, and the gallery's "Kerro tästä" at 24.37 pt, which
    /// measures 5.40:1 on screen against a 4.5:1 minimum and had been failing
    /// a test for it.
    ///
    /// 60 pt since 17 Aug 2026. The first audit ever to reach a row at the
    /// top of Muistot at the largest size reported primary body text —
    /// "Eeva", a `NewTellingRow` title, the strongest text colour in the app —
    /// at 52 pt above the bar, where the XXXL bar's taller capsule pushes its
    /// effect past the old band. Widening this strip widens the measurement
    /// and not the forgiveness: everything in it is still decided by
    /// `ContrastMeter`, so a genuinely faint label inside it goes on failing,
    /// now with its measured ratio printed beside it.
    ///
    /// 120 pt since 6 Sep 2026, measured before it was widened, as the note
    /// above asks. Two findings at the largest size sat outside the 60 pt
    /// strip and were reported as colours: the grid's *"Ilman ajankohtaa"*
    /// heading, `Elder.supporting`, ending 83 pt above the bar, and the blind
    /// card's *"Sanni"* name button, primary text, ending 104 pt above it —
    /// the second on a screen this session had not touched, failing at HEAD
    /// the same way on a quiet machine. With the strip at 120 the meter
    /// answered both from their pixels: 10.37:1 and 15.17:1 (and *"Aino"*
    /// beside it, 14.95:1), against a 4.5:1 minimum. So the XXXL bar's effect
    /// reaches further than 60 pt, and what fails there is the fade and not
    /// the text. 120 is the value that was run, not a rounder number nobody
    /// measured.
    static let fadeReach: CGFloat = 120

    /// `ContentUnavailableView` sizes its own title and description, and it caps
    /// their growth. These are its labels, not ours. The empty states matter in
    /// this app — they are invitations rather than blanks — so if the system
    /// view ever stops being good enough, the answer is to stop using it, not to
    /// widen this list.
    private static let systemEmptyStateText: Set<String> = [
        // Muistot' empty state left this list on 29 Aug 2026 rather than
        // growing it: it stopped being a `ContentUnavailableView` when it
        // needed two ways in with the camera first, so its words are ours and
        // are held to the same standard as every other sentence in the app.
        // See `GalleryScreen.emptyState`.
        "Ei vielä ihmisiä",
        // Copied from the screen, and it has to be: a `ContentUnavailableView`
        // caps its own description, and the exemption is matched on the label.
        // Change the sentence in RootView and this line changes with it or
        // `testPeopleEmpty` goes red — which is the coupling working, not
        // failing.
        "Ihmiset kertyvät tähän sitä mukaa kun heistä puhutaan. Jokaisesta kirjoitetaan yhdessä, millainen hän oli. Voit myös lisätä ihmisen itse yläreunan painikkeesta.",
    ]

    /// A `List` caps how far its own headers and footers grow, exactly as
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
    private static let listHeaderAndFooterText: Set<String> = [
        "Kysymys näkyy perheelle Kerro-näytöllä, ja vastaus tallentuu tähän.",
        // Reached from the other direction as well, and worth keeping: this one
        // began failing the moment a row was added *above* it, and giving it an
        // explicit Dynamic Type font changed the finding not at all. Both facts
        // say the same thing as the y-coordinate above — the metrics are the
        // List's, not our typography's.
        "Kertomasi muistot ovat vain tässä laitteessa.",
        // A header rather than a footer, which is why this set was renamed. The
        // cap is the same one: `Uusi arkisto` gained a section above this header
        // for PLAN.md §10 lever 2, and the header began failing at the *default*
        // size the moment it did.
        //
        // Matched against the signature above rather than assumed, over six
        // runs. It moved with the content above it and nothing else — y 416,
        // then 444, then 438.67, then 430 — while the finding itself stayed
        // identical. Changing the new picker's tags from `Bool` to a type of
        // their own did not touch it; nor did dropping the new section's own
        // header; nor did replacing the new picker with a `Toggle`. A defect in
        // a sentence does not depend on where the sentence sits, and three
        // attempts at the sentence's own neighbours moved nothing.
        //
        // At AccessibilityXXXL the same screen audits clean and reports no
        // `textClipped` on this header, which is the half that would say the
        // words were actually being lost.
        "Kenen puhelin tämä on",
    ]

    /// The photo card's empty state: the sentence, and the delete button that
    /// shares its `VStack`. The last two things in that `List`.
    ///
    /// Kept apart from the two sets above because the finding arrives from the
    /// other end. Those are reported by the audit's *default-size* simulation
    /// and audit clean at a real AccessibilityXXXL; these are reported at the
    /// real largest size, which is the half that would normally mean a defect.
    /// So they were measured harder rather than filed faster.
    private static let photoCardEmptyStateText: Set<String> = [
        "Kukaan ei ole vielä kertonut mitään. Paina yllä olevaa nappia ja ala puhua.",
        // Only the photograph's word. `removalButton` has three — "Poista
        // henkilö" and "Poista paikka" are the same construction on the same
        // screen and are very likely the same finding, and neither has been
        // measured, so neither is here. A red person card is a measurement to
        // make, not a line to add.
        "Poista kuva",
    ]

    static func isDeliberate(
        _ issue: XCUIAccessibilityAuditIssue,
        tabBar: CGRect,
        keyboard: CGRect,
        topChrome: CGRect = .null,
        content: CGRect = .null,
        screen: CGRect = .null
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

        // **The keyboard's own prediction strip.** The QuickType bar sits
        // flush ABOVE `app.keyboards`' frame — touching it, which `intersects`
        // does not count — and its three candidate cells arrive with no
        // description when there is nothing to predict. They are the system's
        // cells over the system's keys: nothing this app draws lives in that
        // band while the keyboard is up, and nothing this app could do would
        // label them. Found by `testMemoriesSearching` on a fresh simulator,
        // and reproduced identically on a commit from before the screen was
        // last touched — the strip is environment, not code. Narrow three
        // ways: only while a keyboard is up, only the strip's own height
        // flush above the keys, and only the descriptionless finding — a
        // contrast failure in the same band still counts.
        if !keyboard.isNull,
           let element = issue.element, element.label.isEmpty,
           issue.auditType != .contrast,
           element.frame.maxY <= keyboard.minY,
           element.frame.minY >= keyboard.minY - 48 {
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

        // **Below the screen, which is the same thing from the other end.**
        // The rule above was written for an element scrolled off the top; a
        // drawing puts them off the bottom instead. The family tree renders
        // every generation whether or not it is on screen, so at the largest
        // text size — where a row of `-seed clan` is 487 points and the phone
        // is 874 — there are always names below the fold. Measured 19 Sep
        // 2026, twice alone on a private simulator, identical both times:
        // "Matti" at y 1084.33 on an 874-point screen, and the meter would
        // not put a number on it because the crop is off the picture.
        //
        // `ContrastMeter` refusing to measure is what makes this safe to
        // accept rather than a hole: nil is not a pass anywhere else in this
        // file, and here it is the proof that there were no pixels to judge.
        // Narrow in the same two ways as the rule above: contrast only, and
        // only where the element is wholly past the bottom edge. A name half
        // on the screen still has pixels and is still judged.
        if issue.auditType == .contrast, !screen.isNull,
           let frame = issue.element?.frame, frame.minY >= screen.maxY {
            return true
        }

        // **Below the scrolling area, which is the same thing from the other
        // end.** The family tree draws every generation at once, so a family
        // of any size has names below the fold, clipped and not drawn — and
        // the pixels at their frames belong to whatever the app puts under the
        // scroll view. Measured 16 Sep 2026 with `-seed clan`: two names
        // reported at 1.04:1, which is paper on paper, 120 points below the
        // bottom of the drawing.
        //
        // As narrow as the rule above it: contrast only, and only where the
        // element is entirely past the end of the scrolling area. A name half
        // in and half out still has pixels and is still judged.
        if issue.auditType == .contrast, !content.isNull,
           let frame = issue.element?.frame, frame.minY >= content.maxY {
            return true
        }

        // **Text seen through the floating tab bar.** Element detection reads
        // the rendered picture and asks the tree for an element under each
        // word it finds; a word under the translucent bar is drawn and has
        // its element, and the bar is what the hit-test answers. The finding
        // arrives with no element at all, which is also why nothing could
        // ever be done about it. Measured 6 Sep 2026 on the Perhe screen's
        // audit picture: the two findings were the invite footer's lines
        // under the bar, and nothing else on the screen was unaccounted for.
        // Only with no element and only under a bar: a word with an element
        // is still judged, and a screen without a bar has nothing to see
        // through.
        if issue.auditType == .elementDetection, issue.element == nil, !tabBar.isNull {
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
            // **Underneath the bar: forgiven by geometry.** Content scrolls
            // beneath the capsule by design and nobody is expected to read it
            // there, so there is nothing to measure and nothing to fix.
            if let frame = issue.element?.frame, frame.intersects(tabBar) { return true }

            // **In the fade above it: not decided here at all.**
            //
            // This used to be a band — 24 pt, then briefly 32 — and a band is a
            // blanket: it excuses whatever lands in the strip, so a real failure
            // 30 pt above the bar would be silent, on the one property rule 1
            // says eyes cannot check. The fade is a tool artefact, and the
            // answer to an artefact is to measure the thing itself, so anything
            // within `fadeReach` of the bar is held back by `audit(_:_:)` and
            // answered by counting its pixels once the audit has finished.
            //
            // Nothing to do here: falling through reports it, which is what
            // happens to a finding that is neither under the bar nor close
            // enough for the fade to explain it.
            // The audit sometimes reports a contrast failure it cannot attribute
            // to any element at all. Every one of those seen here was on a
            // tab-bar screen at the largest text size, in the same band of
            // pixels, and the attributable ones beside it were checked on
            // screen. Accepting it is a concession to the tool: with no element
            // there is no frame to test and nothing to point a fix at.
            if issue.element == nil { return true }
        }

        // **Clipping it cannot attribute to any element either.** The same
        // concession as the line above, and it arrived the same way: Settings
        // began reporting one unattributable "Text clipped" at the ordinary size
        // when a row was added to the list, and none at the largest.
        //
        // Screenshotted before it was accepted. Every sentence on that screen is
        // drawn in full, the list does not even fill the phone, and the finding
        // has no element, no frame and no label — there is nothing to point a
        // fix at. An attributable clipping still fails, which is the part that
        // matters: this exempts the tool's shrug, not our text.
        if issue.auditType == .textClipped, issue.element == nil {
            return true
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
        //
        // Matched on the element rather than on its name since 30 Aug 2026.
        // The name was "Clear text", which is UIKit's ENGLISH label — and it
        // matched for two months only because the app had one language and the
        // simulator had another. Pinning the tests to Finnish renamed the same
        // button "Poista teksti", the exemption stopped matching, and the suite
        // reported a hit-area failure on a control this app does not own and
        // cannot resize. It read like a regression in the search screen. It was
        // an exemption written in a language the app had just stopped assuming.
        //
        // It is still a list of names, because XCUIElement offers no parent to
        // ask and the frame alone would exempt any small button anywhere. What
        // it is not any more is a list of ONE name that happened to be right.
        // Adding a third language means adding its label above — and forgetting
        // to is loud, not silent: the suite fails on this exact control, with
        // the untranslated name printed in the message.
        if issue.auditType == .hitRegion,
           let element = issue.element,
           element.elementType == .button,
           searchFieldClearButtonLabels.contains(label) {
            return true
        }

        // **MapKit's legal link.** Every `Map` draws Apple's attribution as a
        // link of about 50 × 11 pt in its bottom-left corner, and there is no
        // API to make it bigger or to move it — it belongs to MapKit the way
        // the clear button above belongs to UIKit's search field. The place
        // card never met this finding because its map is one element
        // (`.accessibilityElement()`), which hides the link along with
        // everything else on the tile. The map of places (`PlacesMapScreen`,
        // 21 Sep 2026) cannot do the same: its chips are the buttons that
        // make it a screen, and they have to stay in the tree.
        //
        // Accepted for the clear button's reason — nothing in this app
        // depends on hitting it. It opens Apple's notice about the map data,
        // which is Apple's to show and not a step in anything the family
        // does.
        //
        // Matched two ways, because the audit hands the finding over in two
        // shapes. Measured 21 Sep 2026 on the same screen and the same
        // 49.9 × 10.7 pt link: twelve launches of a probe reported it with
        // the element attached — a `.link` named "Lakitiedot" — and the next
        // seven, two runs of the sweep and five launches of a second probe on
        // the final build, with `element` nil and nothing left to match but
        // the audit's own sentence, which the probe printed: *"The size of
        // this MKAttributionLabel is too small for user to interact"*.
        // `MKAttributionLabel` is MapKit's class for this
        // one control, in every language, so the sentence is the more exact
        // of the two matches; the label set is kept for the shape that names
        // the element, as the clear button's is, and a third language adds
        // its word there. Neither condition reaches any button of ours: one
        // needs the link type and a system name, the other a class this app
        // does not contain.
        if issue.auditType == .hitRegion {
            if let element = issue.element,
               element.elementType == .link,
               mapLegalLinkLabels.contains(label) {
                return true
            }
            if issue.detailedDescription.contains("MKAttributionLabel") {
                return true
            }
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

        // **Both audit types, for the same reason as the precedent below.** The
        // simulation reports whichever the row's current shape produces, so a
        // sentence exempt as `.dynamicType` and reported as `.textClipped` is
        // one finding under two names — which is what the disjunction for
        // `"Perheen jäsenet ja kutsut"` already says a few clauses down.
        //
        // `.textClipped` arrived here on 19 Sep 2026, on this set's first
        // entry, after two wrong turns that each looked convincing.
        //
        // Typography was the first. `866ec51` gave that footer
        // `.fixedSize(horizontal: false, vertical: true)` to let a third line
        // through; the frame measured 370 x 45.667 with and without it, to the
        // byte, and a screenshot showed two complete lines of ink ending 5.7 pt
        // above the tab bar with no third line to make room for. Reverted in
        // `307c408`.
        //
        // Position was the second. Three findings on these screens end exactly
        // at the tab bar's top edge at y 791 under three different audit types,
        // which reads like one cause. An A/B settled it: with
        // `.contentMargins(.bottom, Elder.minTapTarget, for: .scrollContent)`
        // on `SubjectDetailScreen`'s List the frame moved from y 745.33 to
        // 685.33 — sixty points clear of the capsule, height unchanged to the
        // byte — and `testPersonCardWithoutAStory` reported the same clipping
        // 2/2 in both arms. Proximity is not the cause and those three findings
        // are not one thing. The finding travels with the sentence rather than
        // with where the sentence sits, which is the signature the doc comment
        // on this set describes.
        //
        // **One sentence in `307c408` is wrong, and is corrected here rather
        // than in history**, because it is why this exemption was refused once:
        // it says every exemption in this function gates on
        // `issue.element == nil`. Three of twenty-one do. The rest gate on a
        // label, an element type, a frame, an enabled state or a named set —
        // and forgiving a `.textClipped` finding by its label was not new
        // either: `"Lisää sukulainen"` above gates on the label alone, and
        // `"Nimi"` below on the label with an element type.
        //
        // **This rests on construction and not on a measurement of its own
        // narrowness, because a canary was tried and could not be built.**
        // Twice on 19 Sep 2026, in a worktree: a `Text` clipped to a 140 x 14
        // frame with a label outside this set, first beside the footer and then
        // as the list's first section where it is certainly drawn. Neither was
        // reported as `Text clipped`. SwiftUI truncates with an ellipsis rather
        // than drawing a string cut off, and a truncation is a handled state —
        // which is also why this exemption and the ones at `"Lisää sukulainen"`
        // and `"Nimi"` are for a framework cap rather than for a truncation. So
        // no run proves that clipping still goes red, and the footing is the
        // same as `"Kutsu perheenjäsen"` below: three sentences, each measured
        // when it was added, and everything else still reported.
        //
        // `scripts/audit-exemption-check.mjs` pins those three sentences and
        // this gate's two types, and runs in `verify.sh` at any load. This set
        // is the one exemption here that widens by a line in a literal rather
        // than by a new clause — and `.contrast` must never join the two types
        // above, because forgiven by label it would switch off rule 1 by name.
        if issue.auditType == .dynamicType || issue.auditType == .textClipped,
           listHeaderAndFooterText.contains(label) {
            return true
        }

        // **The photo card's empty state.** Measured 9 Sep 2026 per the
        // protocol above, on a private simulator, and measured again after the
        // parchment migration rewrote both this screen and `Elder.swift` under
        // it — the first numbers were taken on the old surface and are not
        // quoted here, because they are not the ones that are true now.
        //
        //   * In place: 5/5 red at the largest size, the two labels below.
        //   * Moved up, by hiding the "Kerro tästä muisto" section above them
        //     — their own code untouched, not a character: 3/3 clean.
        //   * Given 88 pt of clear space below instead: 3/3 red, and the
        //     reported frames identical to the point.
        //   * Their own typography replaced: a different and worse finding, at
        //     the default size.
        //
        // The finding follows where the words sit and nothing else, which is
        // the signature this file names above — and the padding run is the
        // sharpest form of it, since space below is exactly what an element
        // that could not grow would need.
        //
        // Screenshotted at AccessibilityXXXL before being listed: the sentence
        // wraps to six lines and ends in "puhua.", and "Poista kuva" is drawn
        // whole above the bar. Nothing is truncated — which is what the
        // protocol asks, and what would have made this a defect instead.
        //
        // Two labels and one audit type. Anything else on that screen still
        // fails, and words genuinely lost would still be caught as clipping,
        // which this same test checks on every run.
        if issue.auditType == .dynamicType, photoCardEmptyStateText.contains(label) {
            return true
        }

        // The in-family Settings row, reported by the audit's *default-size*
        // simulation and by nothing else. Measured 16 Aug 2026, per the
        // protocol above, before being listed:
        //
        // The finding survived two different row shapes unchanged — the 60 pt
        // frame on the Label (reported as dynamicType, element 60 pt tall),
        // and the frame moved to the NavigationLink with the text free to wrap
        // (reported as textClipped, element 21 pt tall). A defect that keeps
        // its coordinates while the code under it changes shape is the
        // listHeaderAndFooterText signature, third appearance.
        //
        // At a real AccessibilityXXXL the same screen audits clean — and the
        // family screen's "Kutsu perheenjäsen", the same construction at the
        // same length class, audits clean with clipping checks live on every
        // testFamily run. Both types are named here because the simulation
        // reports whichever the row's current shape produces; the label match
        // keeps it to this one row.
        if issue.auditType == .dynamicType || issue.auditType == .textClipped,
           label == "Perheen jäsenet ja kutsut" {
            return true
        }

        // The family screen's usage row, reported by the default-size
        // simulation and by nothing else. Measured 5 Sep 2026, per the
        // protocol above, on a private simulator created for the run and a
        // machine under a load of four:
        //
        // The label passed at y 438 on every run of the day until the "Kopio
        // tällä puhelimella" row was added above it; it failed at y 512.83
        // with that row, and at y 615.83 with the row and a sentence under
        // it, the finding identical to the point each time while the label's
        // own code never changed. The value beside it was rebuilt twice on
        // the way — a ternary, a `Group` holding two branches, one `Text`
        // from a helper — and moved nothing. A finding that keeps its shape
        // while the code under it changes and turns on how low the row sits
        // is the listHeaderAndFooterText signature, fifth appearance: the
        // simulation grows everything above, and the row lands where it
        // cannot be measured whole. The same row is measured live at the
        // real largest size on every testFamily run, where it audits clean.
        if issue.auditType == .dynamicType, label == "Kertominen tässä kuussa" {
            return true
        }

        // The result screen's name field, on any archive that already holds
        // memories: reported clipped by the default-size simulation, and by
        // nothing else. Measured 4 Sep 2026, per the protocol above:
        //
        // `-seed archive -screen result` and `-seed related -screen result`
        // both report the first proposal row's "Nimi" field, 132 × 22 pt at
        // y 516, as clipped at the default size. The field was given its
        // column's full width and the frame reported did not move by a
        // point — SwiftUI hands the audit the text's own rect, whatever the
        // field's frame — which is the signature: a defect that keeps its
        // coordinates while the code under it changes shape, fourth
        // appearance. The same screen audits clean at the real largest size
        // (a one-off test on the `related` fixture, 7.2 s), and on
        // `-seed empty` at both sizes on every testResultWithProposals run.
        // Narrowed to the one label and the one element type: a name field
        // that really clipped at the largest size would still be caught by
        // the sweep's second launch, which measures the real layout.
        if issue.auditType == .textClipped, label == "Nimi",
           issue.element?.elementType == .textField {
            return true
        }

        return false
    }

    /// The memory row's two texts — the story and its byline — reported by
    /// the audit's *default-size* simulation and by nothing else: the
    /// `listHeaderAndFooterText` signature, fifth appearance, and the first
    /// whose label cannot be listed. A story's words are the family's, and
    /// the byline carries the day it was told.
    ///
    /// Measured 21 Sep 2026 on a private simulator, per the protocol above:
    ///
    ///   * `testPersonCard` and `testPersonCardWithAFace` audited clean until
    ///     a row was added ABOVE the memories — §25's face row, one `Section`
    ///     of a 56 pt disc and four words. Then both reported the same two
    ///     texts at the default size, the story at y 595.67 and *"Mummo ·
    ///     21.9.2026"* at y 624, in the suite and again alone (23.8 s), the
    ///     frames identical to the point.
    ///   * `MemoryRow`'s own code untouched, not a character. The finding
    ///     moved in with the row above it, which is the signature.
    ///   * The same two screens audit clean at a real AccessibilityXXXL on
    ///     every one of those runs — the half that would say the words were
    ///     actually being lost.
    ///
    /// So the sweep passes this in on its FIRST launch only, where the audit
    /// simulates the scaling. The second launch measures the real layout at
    /// the largest size with nothing forgiven, and a story that really
    /// stopped growing would still be caught there, as clipping or as this.
    /// Keyed on the row's identifiers rather than its words — `memory.body`
    /// and `memory.byline`, set in `RootView.swift` for this purpose alone —
    /// and on the one audit type; `scripts/audit-exemption-check.mjs` pins
    /// both, and `.contrast` must never join it.
    ///
    /// **Widened on 26 Sep 2026 and renamed, measured the same way**, on the
    /// two person-card sweeps that were red on `main` alone —
    /// `testPersonCardWithoutAStory`, seven findings, and
    /// `testPersonCardWithAFriend`, one — on a private simulator in Finnish,
    /// each test alone twice with frames identical to the decimal, at the
    /// default size only, the real AccessibilityXXXL launch clean on every run,
    /// and no contrast, hit-region or timeout finding on either. (The four
    /// other sweeps red in the same suite runs were green alone twice: load.)
    ///
    ///   * The story-less card, scrolled to *"Poista henkilö"* by its sweep:
    ///     the same row's other texts — *"Kuulin nämä"* at y 217, the heard
    ///     name's kind at y 275.33, the listen button's words at y 382.67 —
    ///     reported partially unsupported, and the card's last section —
    ///     *"Tästä ei ole vielä omaa muistoa…"* at y 502.67 and *"Poista
    ///     henkilö"* at y 561.33 — reported unsupported AND clipped.
    ///   * Moved up, by hiding the mentions section above that last section,
    ///     its own code untouched: clean, 0 findings.
    ///   * The loss probe (`KINLORE_XXXL_LOSS`): all five are still in the tree
    ///     at the real largest size, where the audit judged them clean; what
    ///     that card loses there is four rows further down. Screenshotted at
    ///     AccessibilityXXXL: the sentence wraps to six lines and ends in
    ///     "puhua.", the button is drawn whole under it.
    ///   * The friend card: *"Ystävä"*, the relative row's caption, at
    ///     y 627.67 — with the name in the same `VStack` not reported. Moved
    ///     up by hiding the face row above it (§25), its own code untouched:
    ///     clean, 0 findings. At the largest size the row had never been in
    ///     the tree at all: the sweep reached the heading, the heading sat
    ///     under the tab bar with the row unbuilt below it, and the probe
    ///     counted five of sixteen labels gone, the friend's name among them.
    ///     So that sweep reaches the row now, and the second launch judges it.
    ///   * The rename row under a photograph that is not on this phone
    ///     (folded in the same day, from a gate of its own; keyed on an
    ///     identifier because the row has three wordings). Words took the
    ///     spinner's place on every photograph without a file that day
    ///     (ARCHITECTURE §5), and `testPhotoDetail`,
    ///     `testPhotoDetailPastTheCeiling` and `testPhotoDetailWithoutAStory`
    ///     then reported *"Anna kuvalle nimi"* at the default size, at y 605.5
    ///     and 132 × 20.33 pt in all three, three screens with different
    ///     things below the row. The words' card shortened to its text moved
    ///     the finding to y 428.83 and changed nothing else about it; the
    ///     spinner put back in the same 4:3 place, the row's code untouched:
    ///     green, on the same simulator minutes apart, at a load under
    ///     fifteen. Scrolled into view at a real AccessibilityXXXL, the same
    ///     row audits clean (`testPhotoDetail`, twice).
    ///   * The relatives' *"Lisää sukulainen"* button (the same day, from the
    ///     "Tämä olen minä" row: a second row in the face's section, above
    ///     it). `testPersonCardOfferedAsYou` and `testPersonCardWaitingToBeYou`
    ///     reported the button partially unsupported at the default size, at
    ///     y 630 on the card offered and y 642 on the card waiting — the
    ///     footer's sentence between them — 338 × 60 pt both, alone twice
    ///     each with the frames identical, the real AccessibilityXXXL launch
    ///     clean on every run, and one finding per run, no contrast, hit
    ///     region or timeout. The same card on the same seed with the row
    ///     absent — no family, so nothing offered — audited clean at both
    ///     sizes in the same run, the button's own code untouched.
    ///
    /// Clipping is forgiven for the two texts that reported it and for no
    /// other, and only on this launch: the second still measures the real
    /// layout with nothing forgiven, so a sentence that really lost its last
    /// line at the largest size is caught there. `.contrast` must never join
    /// either set.
    static func isDefaultSizeSimulationArtefact(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        switch issue.auditType {
        case .dynamicType:
            return simulationArtefactIdentifiers.contains(element.identifier)
        case .textClipped:
            return simulationArtefactClippedIdentifiers.contains(element.identifier)
        default:
            return false
        }
    }

    /// What the gate above reads. Every identifier here was measured before
    /// it was listed, and `scripts/audit-exemption-check.mjs` pins the list.
    private static let simulationArtefactIdentifiers: Set<String> = [
        // The memory row (21 Sep 2026): the story and its byline.
        "memory.body", "memory.byline",
        // The same row's other texts (26 Sep 2026): the "Kuulin nämä" heading,
        // the heard name's kind, and the listen button's words.
        "memory.heard", "heardName.kind", "memory.playback",
        // The card's last section (26 Sep 2026): the empty state's sentence
        // and the removal button beside it.
        "card.emptyState", "card.removal",
        // The relative row's caption — "Ystävä", "Vanhemmat" (26 Sep 2026).
        "relative.caption",
        // The rename row under a photograph with no file on this phone,
        // "Anna kuvalle nimi" and its two other wordings (26 Sep 2026).
        "subject.rename",
        // The relatives' "Lisää sukulainen" button, below the "Tämä olen
        // minä" row (26 Sep 2026). On the button's label: the audit reports
        // the label, and an identifier on the button matched nothing.
        "relative.add",
    ]

    /// The two that also reported `.textClipped` at the default size, and
    /// only those two; both are drawn whole at a real AccessibilityXXXL.
    private static let simulationArtefactClippedIdentifiers: Set<String> = [
        "card.emptyState", "card.removal",
    ]

    /// The join form's code field with a code in it, reported clipped by the
    /// audit's *default-size* simulation and by nothing else — *"Text of this
    /// UITextField may be clipped at larger Dynamic Type sizes"*, in the
    /// finding's own words. The result screen's *"Nimi"* field above is the
    /// same finding on the same element type; this field has no label to key
    /// on once it holds a code, so it is keyed on the identifier it sets for
    /// this purpose alone.
    ///
    /// Measured 26 Sep 2026 on a private simulator, per the protocol above:
    /// `testJoinFamilyFormError` reported the field, 338 × 22 pt with
    /// twenty-two characters of base64url in it, at y 309 on the unscrolled
    /// form and at y 111 with the form scrolled to its end — the finding
    /// travels with the field — and the same form with the same code audited
    /// clean at the real largest size in the same run, where the field is
    /// measured live and the descenders in *gjpqy* are drawn whole. Blank,
    /// the field audits clean at both sizes on every `testJoinFamilyForm`
    /// run. Passed in on the first launch only, as the memory row's is, and
    /// pinned the same way by `scripts/audit-exemption-check.mjs`.
    static func isInviteCodeSimulationArtefact(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        issue.auditType == .textClipped
            && issue.element?.elementType == .textField
            && issue.element?.identifier == "invite-code"
    }
}
