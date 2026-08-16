import XCTest

/// Whether what she told has reached the family.
///
/// `SyncEngine` has carried `state` and `lastSyncedAt` since it was written, the
/// engine was never put in the environment, and no view ever asked. So a memory
/// told at a cottage with no signal looked exactly like one the whole family had
/// already read — and that difference is the app's entire promise.
///
/// The situation is built out of launch arguments rather than a backend: an
/// address with nothing behind it and a family id in `UserDefaults` put the app
/// in the state it is in on a phone with no signal, which is the state worth
/// looking at.
final class SyncVisibilityTests: XCTestCase {
    func testATellingThatHasNotLeftTheDeviceSaysSo() {
        let app = launch(
            ["-seed", "empty", "-defer", "structure", "-screen", "interview", "-family_id", "demo"],
            api: "http://127.0.0.1:9"
        )

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: a telling to be waiting for"
        )

        app.tabBars.buttons["Muistot"].tap()
        let note = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS %@", "vain tässä puhelimessa"))
            .firstMatch
        XCTAssertTrue(
            note.waitForExistence(timeout: 10),
            "the gallery did not say that the telling is still only on this phone"
        )
    }

    /// And says nothing at all when there is nothing to say. A permanent status
    /// bar about the network would be furniture on the screen of somebody who
    /// has no use for it — the note is a waiting state, not a decoration.
    func testAnArchiveThatIsThroughSaysNothing() {
        let app = launch(["-seed", "archive", "-tab", "memories", "-family_id", "demo"], api: "http://127.0.0.1:9")

        XCTAssertTrue(app.navigationBars["Muistot"].waitForExistence(timeout: 10), "never arrived: the gallery")
        XCTAssertFalse(
            app.staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@", "tässä puhelimessa"))
                .firstMatch
                .exists,
            "the gallery worried about a sync that had nothing to send"
        )
    }
}
