import XCTest

/// A photograph opened to the whole screen, brought closer, and closed back
/// to where it was opened.
///
/// The app draws a photograph a phone's width across at most, and a face in a
/// group picture is a few points wide there. Nothing let anybody look closer
/// until 28 Sep 2026: a tap on a picture did nothing at all, on its card or
/// anywhere else.
///
/// `-seed blind` is the fixture whose photograph has a file behind it
/// (`demoPhotoFile`), and it is untitled, so the picture is `displayTitle`'s
/// *"Valokuva"* on the card and must be the same in the viewer. `-seed deck`
/// deals the Kerro tab a card of a photograph with a file. The blind card's
/// photograph opens the same way, and is `BlindConfirmationTests`' to check,
/// because what may not be said over it is rule 4's.
final class PhotoViewerTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The card with the photograph on it, opened out of its tile.
    private func openCard(_ app: XCUIApplication) {
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch
        for _ in 0 ..< 4 where !tile.exists { app.swipeUp() }
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "never arrived: the photo tile")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Valokuva"].waitForExistence(timeout: 10), "the photograph's card did not open")
    }

    /// The picture VoiceOver calls `label`, as whichever element it is drawn
    /// as: an image while it opened nothing, a button once it does. Either,
    /// so that before the change a test fails where the viewer should have
    /// opened and not at a query for the button.
    private func picture(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %d OR elementType == %d)",
            label,
            XCUIElement.ElementType.image.rawValue,
            XCUIElement.ElementType.button.rawValue
        )).firstMatch
    }

    /// The viewer, opened by a tap on the picture VoiceOver calls `label`.
    private func openViewer(from label: String, in app: XCUIApplication) -> (photo: XCUIElement, close: XCUIElement) {
        let picture = picture(label, in: app)
        XCTAssertTrue(picture.waitForExistence(timeout: 10), "never arrived: \"\(label)\"")
        picture.tap()
        let close = app.buttons["photoViewer.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "a tap on \"\(label)\" opened nothing")
        let photo = app.images["photoViewer.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "the photograph is not on the screen it opened")
        return (photo, close)
    }

    /// Opens the picture VoiceOver calls `label`, hears the same words for it
    /// on the whole screen, and closes it with Sulje back to where it was.
    private func opensAndCloses(_ label: String, in app: XCUIApplication) {
        let (photo, close) = openViewer(from: label, in: app)
        XCTAssertEqual(photo.label, label, "the photograph is named otherwise than where it was opened")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "Sulje did not close \"\(label)\"")
        XCTAssertTrue(picture(label, in: app).waitForExistence(timeout: 5), "closing did not come back to \"\(label)\"")
    }

    /// What the seeded photograph shows of its dark shape, read from the
    /// pixels on the screen: the photograph's element keeps the frame of its
    /// room however close the picture is (measured 28 Sep 2026), so its
    /// frame cannot say whether a pinch did anything.
    ///
    /// The picture is `MemoryStore.demoPhotoData`'s, a dark upright
    /// rectangle in the middle of a pale ground. `share` is how much of the
    /// room the rectangle covers, about a twentieth when the whole picture is
    /// on screen and more the closer it is; `middle` is where its middle is
    /// across the room, from 0 at the left edge to 1 at the right.
    private struct Shape: CustomStringConvertible {
        var share: Double
        var middle: Double
        var description: String { String(format: "share %.3f, middle %.3f", share, middle) }
    }

    private func shape(of element: XCUIElement) -> Shape {
        guard let picture = element.screenshot().image.cgImage else { return Shape(share: 0, middle: 0) }
        let width = picture.width
        let height = picture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                  )
            else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return Shape(share: 0, middle: 0) }
        var seen = 0
        var inside = 0
        var across = 0
        for y in stride(from: 0, to: height, by: 3) {
            for x in stride(from: 0, to: width, by: 3) {
                let i = (y * width + x) * 4
                seen += 1
                // The rectangle's colour, (92, 79, 66): not the ink around
                // the picture and not the pale ground around the rectangle.
                if abs(Int(pixels[i]) - 92) < 30, abs(Int(pixels[i + 1]) - 79) < 30, abs(Int(pixels[i + 2]) - 66) < 30 {
                    inside += 1
                    across += x
                }
            }
        }
        return Shape(
            share: Double(inside) / Double(max(seen, 1)),
            middle: inside > 0 ? Double(across) / Double(inside) / Double(width) : 0
        )
    }

    /// The shape once it has stopped changing: the photograph comes the last
    /// four per cent of its way after it has opened, and a zoom eases in.
    private func settledShape(of element: XCUIElement) -> Shape {
        var previous = shape(of: element)
        for _ in 0 ..< 20 {
            Thread.sleep(forTimeInterval: 0.25)
            let now = shape(of: element)
            if abs(now.share - previous.share) < 0.002, abs(now.middle - previous.middle) < 0.002 { return now }
            previous = now
        }
        return previous
    }

    func testThePhotographOpensComesCloserAndClosesBackToItsCard() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        openCard(app)
        let (photo, close) = openViewer(from: "Valokuva", in: app)

        // The same words as on the card (a VoiceOver user hears one
        // photograph on both sides of the tap), a close control the size
        // rule 1 asks of every control, and that control first.
        XCTAssertEqual(photo.label, "Valokuva", "the photograph is named otherwise than on its card")
        XCTAssertEqual(close.label, "Sulje", "the close control does not say what it does")
        XCTAssertGreaterThanOrEqual(close.frame.height, 60, "the close control is shorter than 60 pt")
        XCTAssertGreaterThanOrEqual(close.frame.width, 60, "the close control is narrower than 60 pt")
        let order = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["photoViewer.close", "photoViewer.photo"]))
            .allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(order, ["photoViewer.close", "photoViewer.photo"], "the close control does not come first")

        let whole = settledShape(of: photo)
        XCTAssertGreaterThan(whole.share, 0.02, "the whole photograph does not show its shape: \(whole)")

        // A pinch brings it closer, and a double tap takes it back.
        photo.pinch(withScale: 3, velocity: 2)
        let pinched = settledShape(of: photo)
        XCTAssertGreaterThan(pinched.share, whole.share * 2, "a pinch did not bring the photograph closer: \(whole), then \(pinched)")
        photo.doubleTap()
        let back = settledShape(of: photo)
        XCTAssertEqual(back.share, whole.share, accuracy: 0.01, "a double tap did not take the photograph back: \(whole), then \(back)")

        // A double tap brings it closer too, and a finger then moves around
        // it without closing it.
        photo.doubleTap()
        let closer = settledShape(of: photo)
        XCTAssertGreaterThan(closer.share, whole.share * 2, "a double tap did not bring the photograph closer: \(whole), then \(closer)")
        // Down and to the side: down is the way a pull closes the photograph
        // when it is whole, and closer it must not.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 120, dy: 160)))
        XCTAssertFalse(close.waitForNonExistence(timeout: 2), "a drag across a photograph brought closer closed it")
        let moved = settledShape(of: photo)
        XCTAssertGreaterThan(moved.middle, closer.middle + 0.05, "a drag to the right did not move the photograph brought closer: \(closer), then \(moved)")

        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "Sulje did not close the photograph")
        XCTAssertTrue(app.navigationBars["Valokuva"].exists, "closing the photograph did not come back to its card")
        XCTAssertTrue(picture("Valokuva", in: app).waitForExistence(timeout: 5), "the card has lost its photograph")
    }

    /// A pull down closes the photograph into its card, as a pull down at the
    /// top of the card closes the card into the album — and closes only the
    /// photograph: the card is still open under it.
    func testAPullDownClosesThePhotographIntoItsCard() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        openCard(app)
        let (_, close) = openViewer(from: "Valokuva", in: app)

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 320)))

        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "a pull down did not close the photograph")
        XCTAssertTrue(app.navigationBars["Valokuva"].waitForExistence(timeout: 5), "the pull closed the card as well")
        XCTAssertTrue(picture("Valokuva", in: app).waitForExistence(timeout: 5), "the card has lost its photograph")
    }

    /// The Kerro tab's card opens its photograph too, where the question under
    /// it is often who is in it, and closing it leaves the card as it was:
    /// the question and the way past it, not the next card.
    func testTheKerroTabsCardOpensItsPhotograph() {
        let app = launch(["-seed", "deck"])
        XCTAssertTrue(app.staticTexts["Kuka tässä kuvassa on?"].waitForExistence(timeout: 15), "never arrived: the card")

        opensAndCloses("Valokuva, josta ei ole vielä kerrottu", in: app)
        XCTAssertTrue(app.staticTexts["Kuka tässä kuvassa on?"].exists, "closing the photograph took the card's question with it")
        XCTAssertTrue(app.buttons["En muista tätä"].exists, "closing the photograph took the way past the card with it")
    }

    /// The colours open too: the proposal the question is asked over, and the
    /// colours kept on the card. Looking at the proposal answers nothing, so
    /// the question is still there once it closes. The model is the stub
    /// (`-api ""`), as in `ColourTests`.
    func testTheColoursOpenAsTheProposalAndOnceKept() {
        let app = launch(["-seed", "blind", "-tab", "memories"])
        openCard(app)
        let colour = app.buttons["Väritä kerronnan mukaan"]
        for _ in 0 ..< 6 where !colour.exists { app.swipeUp() }
        XCTAssertTrue(colour.waitForExistence(timeout: 10), "the card offers no colouring")
        colour.tap()
        XCTAssertTrue(app.staticTexts["Näyttääkö tältä?"].waitForExistence(timeout: 20), "never arrived: the question over the colouring")

        opensAndCloses("Väritetty ehdotus. Värit ovat tekoälyn arvaus siitä, mitä kuvasta on kerrottu.", in: app)
        XCTAssertTrue(app.staticTexts["Näyttääkö tältä?"].exists, "closing the proposal took its question with it")
        XCTAssertTrue(app.buttons["Kyllä, tallenna värit"].exists, "closing the proposal took its answers with it")

        app.buttons["Kyllä, tallenna värit"].tap()
        // Under the photograph, which the card may have scrolled past on the
        // way down to the button: back up to the photograph, as far as it
        // and no further (`ColourTests.backToThePhotograph`), then down
        // until the colours' middle is above the tab bar, where a tap lands.
        let kept = "Väritetty kuva. Värit ovat tekoälyn arvaus kerrotun mukaan."
        let photograph = app.buttons["Valokuva"]
        let title = app.navigationBars["Valokuva"]
        for _ in 0 ..< 6 where !(photograph.exists && title.exists && photograph.frame.minY >= title.frame.maxY - 1) {
            app.swipeDown()
        }
        XCTAssertTrue(title.exists, "the card closed on the way back up to its photograph")
        let colours = picture(kept, in: app)
        XCTAssertTrue(colours.waitForExistence(timeout: 10), "the kept colouring is not on the card")
        let bar = app.tabBars.firstMatch
        for _ in 0 ..< 6 where bar.exists && colours.frame.midY > bar.frame.minY - 20 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -150)))
        }
        opensAndCloses(kept, in: app)
    }
}
