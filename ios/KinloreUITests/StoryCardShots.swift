import XCTest

/// The card with its story, photographed page by page (28 Sep 2026, §27).
///
/// Not a sweep: nothing here fails on a finding, which is the sweeps' job
/// (`testStoryCard…`). A photograph's card, a person's and a place's are
/// opened on the `story` archive at the default text size and at the
/// largest, and photographed from the top down, the tellings unfolded when
/// their button comes on screen, until the ask button at the card's foot
/// has been in a picture. The screenshots go to `$KINLORE_STORY_SHOTS`;
/// without that variable the test skips, so the suite does not grow a slow
/// test that asserts nothing. `KINLORE_STORY_CARDS` (the jetty, Toivo and
/// Puumala) and `KINLORE_STORY_SIZES` ("default,largest") narrow the run.
///
/// It replaced phase A's harness, which photographed six layouts behind
/// `-storyCard N`; the one card has one.
final class StoryCardShots: XCTestCase {
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    func testStoryCardPages() throws {
        guard let dir = ProcessInfo.processInfo.environment["KINLORE_STORY_SHOTS"] else {
            throw XCTSkip("KINLORE_STORY_SHOTS names no folder; this run is for the story card's pictures")
        }
        let env = ProcessInfo.processInfo.environment
        let cards = (env["KINLORE_STORY_CARDS"] ?? "demo-story-jetty,demo-story-toivo,demo-story-puumala")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let sizes = (env["KINLORE_STORY_SIZES"] ?? "default,largest")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        for card in cards {
            for size in sizes {
                let app = launch(
                    ["-seed", "story", "-tab", "people", "-screen", "person", "-person", card, "-story", "stub"],
                    textSize: size == "largest" ? Self.largest : nil
                )
                let tag = "\(card.replacingOccurrences(of: "demo-story-", with: ""))-\(size)"
                guard app.buttons["subject.rename"].waitForExistence(timeout: 30) else {
                    app.terminate()
                    continue
                }
                // The photograph is read off the main thread.
                sleep(2)
                let bar = app.tabBars.firstMatch
                let logs = app.buttons["storyCard.logs"]
                let ask = app.buttons["Kysy perheeltä"]
                var unfolded = false
                for page in 1 ... 12 {
                    Self.save(app, "\(dir)/\(tag)-\(page).png")
                    if !unfolded, logs.exists, logs.isHittable, !bar.exists || logs.frame.maxY < bar.frame.minY {
                        logs.tap()
                        unfolded = true
                        sleep(1)
                        Self.save(app, "\(dir)/\(tag)-\(page)-unfolded.png")
                    }
                    if ask.exists, ask.isHittable { break }
                    app.swipeUp()
                    sleep(1)
                }
                app.terminate()
            }
        }
    }

    private static func save(_ app: XCUIApplication, _ path: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
    }
}
