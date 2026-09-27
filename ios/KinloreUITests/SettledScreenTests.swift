import UIKit
import XCTest

/// The settled-screen rule, held to its word.
///
/// `SettledScreen` (AccessibilityAudit.swift) is a rule that forgives: a
/// contrast finding at a frame the settled screen never had is measured where
/// that screen drew the element and let go at 4.5:1 or above. A rule that
/// forgives has to be seen to condemn, or nobody can tell it from one that
/// forgives everything — and it is checked here with fixed frames and drawn
/// pixels rather than a screen, because the case it exists for, a frame from
/// a layout the audit's own simulation moved, is the one case no test can
/// make happen on purpose.
///
/// One screen, 400 × 800 pt at one pixel per point: paper throughout, a faint
/// grey word at its own frame, an inked one at its, a faint caption fourteen
/// points tall — shorter than a line — a tab bar over the bottom eighty
/// points and a word whose only frame is under it. Half of each word's
/// frame is its colour and half is paper — more ink than any word has, which
/// puts the meter's percentiles beyond doubt: the 1st is the colour and the
/// 95th the paper. The numbers asserted are what WCAG's formula gives for these
/// greys on this paper: 1.64:1 for the faint word and 13.91:1 for the inked
/// one, against the meter's 4.5:1 — asserted as bands, because the picture
/// passes through two colour spaces on its way to the meter. Every colour is
/// sRGB, and every frame in an expected line is written by the same
/// `NSCoder.string(for:)` the rule writes it with.
final class SettledScreenTests: XCTestCase {
    private static let paper = UIColor(red: 0xFD / 255, green: 0xFD / 255, blue: 0xFC / 255, alpha: 1)
    private static let faintGrey = UIColor(red: 0xC8 / 255, green: 0xC8 / 255, blue: 0xC8 / 255, alpha: 1)
    private static let ink = UIColor(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255, alpha: 1)
    private static let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
    private static let tabBar = CGRect(x: 0, y: 720, width: 400, height: 80)
    private static let faintFrame = CGRect(x: 24, y: 300, width: 200, height: 40)
    private static let inkFrame = CGRect(x: 24, y: 400, width: 200, height: 40)
    private static let captionFrame = CGRect(x: 24, y: 200, width: 200, height: 14)
    private static let underTheBar = CGRect(x: 24, y: 740, width: 200, height: 40)
    /// Where the audit's simulation might report any of them: plain paper, at
    /// the frame the form's row was reported at on 27 Sep 2026.
    private static let elsewhere = CGRect(x: 24, y: 505.33, width: 200, height: 155.33)

    private static func screen() -> SettledScreen {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let picture = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            paper.setFill()
            context.fill(bounds)
            for (colour, frame) in [(faintGrey, faintFrame), (ink, inkFrame), (faintGrey, captionFrame), (ink, underTheBar)] {
                colour.setFill()
                context.fill(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height / 2))
            }
        }
        return SettledScreen(
            frames: ["Faint": [faintFrame], "Ink": [inkFrame], "Caption": [captionFrame], "Under the bar": [underTheBar]],
            bounds: bounds, tabBar: tabBar, keyboard: .null, topChrome: .null,
            meter: picture.cgImage.map { ContrastMeter(image: $0, pixelsPerPoint: 1) }
        )
    }

    /// At its own frame the faint word is judged exactly as before: the settled
    /// screen held that frame, so the finding is not diverted — and the reading
    /// the rule adds to its line says the same thing the audit did.
    func testAFaintWordAtItsOwnFrameStaysRed() {
        let screen = Self.screen()
        XCTAssertTrue(
            screen.held("Faint", at: Self.faintFrame),
            "the settled screen held the word where it is drawn, so the finding takes the road it always took"
        )
        guard case .measured(let ratio, let frame) = screen.verdict(for: "Faint") else {
            return XCTFail("the faint word is on the page and measurable")
        }
        XCTAssertEqual(frame, Self.faintFrame)
        XCTAssertLessThan(ratio, ContrastMeter.minimum)
        XCTAssertEqual(ratio, 1.64, accuracy: 0.05)
    }

    /// Reported at a frame the settled screen never had, the faint word is
    /// measured where the screen drew it and condemned there.
    func testAFaintWordReportedElsewhereIsCondemnedWhereItIsDrawn() {
        let screen = Self.screen()
        XCTAssertFalse(screen.held("Faint", at: Self.elsewhere), "a frame the settled screen never had")
        let decision = screen.decide("Insufficient contrast — \"Faint\"", label: "Faint", reported: Self.elsewhere, context: "check")
        guard case .condemned(let line) = decision else {
            return XCTFail("a faint word is not forgiven for being reported in the wrong place: \(decision)")
        }
        XCTAssertTrue(line.hasPrefix("Insufficient contrast — \"Faint\" drawn at \(NSCoder.string(for: Self.faintFrame)), measured "), line)
        XCTAssertTrue(line.hasSuffix(":1 there"), line)

        // And a caption shorter than a line, whole on the page: measured and
        // condemned like the word, not left to a page that would never judge
        // it — which is what the first version of the rule did with every
        // frame under sixteen points (27 Sep 2026).
        let caption = screen.decide("Insufficient contrast — \"Caption\"", label: "Caption", reported: Self.elsewhere, context: "check")
        guard case .condemned(let captionLine) = caption else {
            return XCTFail("a faint caption is condemned where it is drawn, not left: \(caption)")
        }
        XCTAssertTrue(
            captionLine.hasPrefix("Insufficient contrast — \"Caption\" drawn at \(NSCoder.string(for: Self.captionFrame)), measured "),
            captionLine
        )
    }

    /// The rule forgives only what measures fine where it is drawn, and a word
    /// the settled screen held nowhere a reader could see is left to the page
    /// that holds it.
    func testAnInkedWordReportedElsewhereIsForgivenAndOneUnderTheBarIsLeft() {
        let screen = Self.screen()
        let inked = screen.decide("Insufficient contrast — \"Ink\"", label: "Ink", reported: Self.elsewhere, context: "check")
        guard case .forgiven(let note) = inked else {
            return XCTFail("an inked word reported on plain paper is forgiven where it is drawn: \(inked)")
        }
        XCTAssertTrue(
            note.hasPrefix("[audit] check: \"Ink\" reported at \(NSCoder.string(for: Self.elsewhere)), drawn at \(NSCoder.string(for: Self.inkFrame)), "),
            note
        )
        XCTAssertTrue(note.hasSuffix(":1 there — the audit's frame, not the screen's"), note)
        guard case .measured(let ratio, _) = screen.verdict(for: "Ink") else { return XCTFail("the inked word is measurable") }
        XCTAssertEqual(ratio, 13.91, accuracy: 0.4)
        let under = screen.decide("Insufficient contrast — \"Under the bar\"", label: "Under the bar", reported: Self.elsewhere, context: "check")
        guard case .left(let where_) = under else {
            return XCTFail("a word under the bar is left to the page that holds it: \(under)")
        }
        XCTAssertEqual(
            where_,
            "[audit] check: \"Under the bar\" reported at \(NSCoder.string(for: Self.elsewhere)), "
                + "which the settled screen held at \(NSCoder.string(for: Self.underTheBar)) — not on this page"
        )
    }
}
