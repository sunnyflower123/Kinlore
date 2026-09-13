import XCTest

/// Whether what she told has reached the family — and, since 17 Aug 2026,
/// whether what the family told has reached her.
///
/// `SyncEngine` has carried `state` and `lastSyncedAt` since it was written, the
/// engine was never put in the environment, and no view ever asked. So a memory
/// told at a cottage with no signal looked exactly like one the whole family had
/// already read — and that difference is the app's entire promise. The reading
/// direction had the same hole from the other side: nothing marked what was
/// new, which PLAN §4.1 names as how family archives actually die.
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

        app.tabBars.buttons["Albumi"].tap()
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

        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "never arrived: the gallery")
        XCTAssertFalse(
            app.staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@", "tässä puhelimessa"))
                .firstMatch
                .exists,
            "the gallery worried about a sync that had nothing to send"
        )
    }

    /// Reading one of the new tellings must not erase the rest. The section is
    /// captured when the tab is arrived at, and a pop-back from a card is the
    /// same visit still going — it used to re-run the capture after everything
    /// was already marked seen, so the elder who opened the first of three new
    /// tellings came back to find the other two gone, with no badge, no count
    /// and no other trace anywhere to say they had existed.
    func testNewFromFamilySurvivesReadingOneTelling() {
        let app = launch(["-seed", "unseen"])

        XCTAssertTrue(
            app.staticTexts["Uutta perheeltä"].waitForExistence(timeout: 10),
            "never arrived: the new-from-family section"
        )

        let telling = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "kertoi")
        ).firstMatch
        XCTAssertTrue(telling.waitForExistence(timeout: 10), "never arrived: a new telling's row")
        telling.tap()

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "never arrived: the way back")
        back.tap()

        XCTAssertTrue(
            app.staticTexts["Uutta perheeltä"].waitForExistence(timeout: 10),
            "reading one telling erased the rest of the section"
        )
    }

    /// The mirror, facing in: the section is a waiting state like the note
    /// above, not furniture. Being on the tab is what marks its content seen,
    /// so returning to the tab must find it gone — a "new" that never clears
    /// is a badge with more words.
    func testNewFromFamilyClearsOnceSeen() {
        let app = launch(["-seed", "unseen"])

        // No `-tab` argument: the unseen tellings are themselves what opens
        // the app on Muistot.
        XCTAssertTrue(
            app.navigationBars["Albumi"].waitForExistence(timeout: 10),
            "unseen tellings did not open the app on Muistot"
        )
        XCTAssertTrue(
            app.staticTexts["Uutta perheeltä"].waitForExistence(timeout: 10),
            "never arrived: the new-from-family section"
        )

        app.tabBars.buttons["Kerro"].tap()
        app.tabBars.buttons["Albumi"].tap()

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the gallery did not come back")
        XCTAssertFalse(
            app.staticTexts["Uutta perheeltä"].exists,
            "the section stayed after its content had been seen"
        )
    }
}
