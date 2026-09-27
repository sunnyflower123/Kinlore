import UIKit
import XCTest

/// Three layouts the English read-through of 27 Sep 2026 found wrong at the
/// largest text size, each measured from the frames on screen rather than
/// judged from a screenshot, so that the fix can be told from the finding.
///
/// Two of them are English-only: a Finnish phone fitted the same words. The
/// app is filmed and judged in English, so those two launch in it — the
/// language pair given after `launch`'s Finnish one is the one the app reads
/// (`FactTests.testTheRowsSpeakEnglishOnAnEnglishPhone`).
final class LayoutAtSizeTests: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let english = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]

    override func setUp() {
        continueAfterFailure = false
    }

    /// *Choose a face* beside the card's disc, at the largest size. The disc
    /// grows with the text, to 175 points, and left the words a column
    /// narrower than "Choose", which broke in the middle: *Choos / e a /
    /// face*. A row is as tall as its words are when they wrap at the row's
    /// own width only when no word is broken — a broken word costs a line,
    /// and a line at this size is 64 points, so half of one is the tolerance.
    func testTheFaceRowBreaksNoWordAtTheLargestSizeInEnglish() {
        let app = launch(
            ["-seed", "faces", "-tab", "people", "-screen", "person", "-person", "demo-eeva"] + Self.english,
            textSize: Self.largest
        )
        let row = app.buttons["Choose a face"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "never arrived: the row that chooses a face, in English")
        let frame = row.frame
        let font = Self.font(.body)
        let wrapped = ("Choose a face" as NSString).boundingRect(
            with: CGSize(width: frame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil
        ).height
        XCTAssertLessThanOrEqual(
            frame.height, wrapped + font.lineHeight / 2,
            "the row is \(Int(frame.height)) points tall where its words wrapped at its own width of \(Int(frame.width)) take \(Int(wrapped)): a word is broken"
        )
    }

    /// *Whole family* over the drawing, at the largest size. The buttons
    /// floated over the canvas in its bottom corner, and the drawing went on
    /// under them: a family that does not fit the window opens at its own
    /// size, so whatever card the layout put there stood under the button —
    /// Sanni's disc, in the seeded family. What is measured is the part of
    /// each card the canvas shows, against the button's frame; a card
    /// scrolled clean out of the canvas is nobody's business.
    func testTheWholeFamilyButtonCoversNoCardAtTheLargestSizeInEnglish() {
        let app = launch(
            ["-seed", "related", "-tab", "people", "-screen", "tree"] + Self.english,
            textSize: Self.largest
        )
        let fit = app.buttons["Whole family"]
        XCTAssertTrue(fit.waitForExistence(timeout: 10), "never arrived: the button that fits the whole family, in English")
        let canvas = app.scrollViews.firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "never arrived: the drawing")
        let cards = canvas.buttons.allElementsBoundByIndex
        XCTAssertFalse(cards.isEmpty, "no card in the drawing")
        let button = fit.frame
        let shown = canvas.frame
        for card in cards {
            let visible = card.frame.intersection(shown)
            XCTAssertFalse(
                visible.intersects(button),
                "\(card.label)'s card is under the Whole family button: card \(card.frame), canvas \(shown), button \(button)"
            )
        }
    }

    /// The listen button beside the byline (H49 L6). In one row with the
    /// teller and the day, the button was left a column five characters
    /// wide, and *Kuuntele omalla äänellä · 42 s* stood in it seven lines
    /// tall at the default size, on every card with a voice on it. At the
    /// default size the button is one line, which is its tap target's height
    /// and no more; at the largest size the two share no line, and the
    /// button sits under the byline.
    func testTheListenButtonIsNotSqueezedBesideTheByline() {
        for textSize in [nil, Self.largest] {
            let size = textSize == nil ? "default" : "largest"
            let app = launch(["-seed", "archive", "-tab", "memories"], textSize: textSize)
            let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 15), "never arrived: the photograph in the album (\(size))")
            for _ in 0 ..< 4 where !tile.isHittable { app.swipeUp() }
            tile.tap()

            let listen = app.buttons["Kuuntele omalla äänellä"]
            let byline = app.staticTexts.matching(identifier: "memory.byline").firstMatch
            for _ in 0 ..< 10 where !(listen.exists && byline.exists) { app.swipeUp() }
            XCTAssertTrue(listen.waitForExistence(timeout: 10), "never arrived: the listen button (\(size))")
            XCTAssertTrue(byline.exists, "never arrived: the byline (\(size))")

            if textSize == nil {
                XCTAssertLessThanOrEqual(
                    listen.frame.height, 60,
                    "the listen button is \(Int(listen.frame.height)) points tall at the default size: its words are wrapped into a column"
                )
            } else {
                XCTAssertGreaterThanOrEqual(
                    listen.frame.minY, byline.frame.maxY - 1,
                    "the listen button shares a line with the byline at the largest size: button \(listen.frame), byline \(byline.frame)"
                )
            }
            app.terminate()
        }
    }

    /// The teller's disc beside the byline, at the largest size. The disc
    /// grew with the body, to 100 points, and left *Mummo · 9/27/2026* a
    /// column narrower than the date, which broke in the middle: *9/27/202 /
    /// 6*. No word of the line may be wider than the column it is drawn in:
    /// each is measured on one line in the byline's own font, against the
    /// frame the byline reports, which is as wide as its widest line.
    func testTheBylineBreaksNoWordAtTheLargestSizeInEnglish() {
        let app = launch(
            ["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-photo"] + Self.english,
            textSize: Self.largest
        )
        XCTAssertTrue(app.staticTexts["Photograph"].firstMatch.waitForExistence(timeout: 20), "never arrived: the photograph's card, in English")
        // The bubble is pages down at this size, and a row of a `List` is in
        // the tree only once it has been drawn — the ask button under the
        // placeholder is not there yet either, which is why the title is
        // what arriving means here.
        let byline = app.staticTexts.matching(identifier: "memory.byline").firstMatch
        for _ in 0 ..< 14 where !byline.exists { app.swipeUp() }
        XCTAssertTrue(byline.waitForExistence(timeout: 10), "never arrived: the byline of the photograph's memory, in English")
        let width = byline.frame.width
        let font = Self.font(.subheadline)
        for word in byline.label.split(separator: " ") {
            let wide = (String(word) as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(
                wide, width + 1,
                "\"\(word)\" is \(Int(wide)) points wide on one line and its column \(Int(width)): the word is broken"
            )
        }
    }

    /// The font the app draws a text button in at the largest size: rounded
    /// since 26 Sep 2026 (`.fontDesign(.rounded)` at the root), which is a
    /// little wider than SF Pro, and medium, which is a little wider again —
    /// and the width is what decides where a line breaks.
    private static func font(_ style: UIFont.TextStyle) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let plain = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        let rounded = plain.fontDescriptor.withDesign(.rounded) ?? plain.fontDescriptor
        let medium = rounded.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]])
        return UIFont(descriptor: medium, size: plain.pointSize)
    }
}
