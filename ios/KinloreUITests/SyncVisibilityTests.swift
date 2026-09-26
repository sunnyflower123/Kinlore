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

    /// A photograph another member added past the free ceiling. The server
    /// refuses its file and keeps its card, so every phone but theirs holds a
    /// card with nothing to draw — and until 26 Sep 2026 that card's screen
    /// answered with a spinner that never stopped, on every one of those
    /// phones, while only the phone that added it said anything at all.
    func testAPhotographPastTheCeilingSaysWhatItWaitsFor() {
        let app = launch(["-seed", "unarrived", "-tab", "memories"])

        let tile = tile(beginning: "Valokuva", in: app)
        XCTAssertTrue(tile.exists, "never arrived: the photograph's tile")
        // Since 27 Sep 2026 the value begins with who told it — "kertojana
        // Mummo, …", which is the album's to say — and the sentence this test
        // is about is the last part of it.
        XCTAssertEqual(
            (tile.value as? String)?.components(separatedBy: ", ").last,
            "Kuva ei ole vielä tullut perille",
            "the tile did not say that its picture has not arrived"
        )
        tile.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Kuva on vielä puhelimessa, jolla se lisättiin. Se tulee perille, kun perheen ilmaisessa arkistossa on tilaa."
            ].waitForExistence(timeout: 10),
            "the photograph's screen did not say what it is waiting for"
        )
        XCTAssertTrue(stopsSpinning(app), "a spinner for a file that is not on its way")
    }

    /// The other way a photograph is on the grid and not on this phone: its
    /// file reached the server and the fetch did not bring it — no network,
    /// or a server that did not answer. That spinner never stopped either.
    func testAPhotographThatCouldNotBeFetchedSaysSoAndOffersAnotherTry() {
        let app = launch(["-seed", "unarrived", "-tab", "memories"])

        let tile = tile(beginning: "Rantasauna", in: app)
        XCTAssertTrue(tile.exists, "never arrived: the fetched photograph's tile")
        tile.tap()

        let failed = app.staticTexts["Kuvaa ei saatu haettua."]
        XCTAssertTrue(failed.waitForExistence(timeout: 10), "the failed fetch was not reported")
        XCTAssertTrue(stopsSpinning(app), "a spinner after the fetch had already failed")

        let again = app.buttons["Yritä uudelleen"]
        XCTAssertTrue(again.exists, "no way to try the fetch again")
        again.tap()
        // A seeded launch has no server, so the second try fails as the first
        // did, and has to end in the same sentence rather than in a spinner.
        XCTAssertTrue(stopsSpinning(app), "the second try never finished")
        XCTAssertTrue(failed.waitForExistence(timeout: 10), "the second failure was not reported")
    }

    /// A grid tile by the start of its label, scrolled to: the gallery puts
    /// the family's sections above its photographs.
    private func tile(beginning label: String, in app: XCUIApplication) -> XCUIElement {
        let tile = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", label))
            .firstMatch
        _ = tile.waitForExistence(timeout: 10)
        for _ in 0 ..< 4 where !tile.isHittable {
            app.swipeUp()
        }
        return tile
    }

    /// Whether the screen stops spinning within a few seconds. A fetch may
    /// still be running for a moment; a spinner that is still there after
    /// that is the one that never stops.
    private func stopsSpinning(_ app: XCUIApplication) -> Bool {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.activityIndicators.firstMatch
        )
        return XCTWaiter().wait(for: [gone], timeout: 5) == .completed
    }
}
