import XCTest

/// The chosen local mode of a build that has a real backend (finding B4).
///
/// That mode never creates a member the server knows, so transcription can
/// only ever answer 401 — and until this was fixed, the app recorded, promised
/// "teksti valmistuu myöhemmin", and kept the promise-shaped request alive on
/// every launch, forever. The honest behaviour is the one checked here: both
/// the result screen and the memory row say the text is not coming instead of
/// promising it.
///
/// Said precisely, because the audit refuted a bigger claim this comment used
/// to make: what these assertions pin is the sentences and their gating —
/// `canTranscribe` reaching the result screen, `isLocalByChoice` reaching the
/// row. The skip-guard in `TellViewModel.stopAndProcess` is NOT pinned:
/// against this dead loopback port a reverted guard fails fast into the same
/// phase and the same sentences, and nothing here observes whether a request
/// left. That residual is named in docs/UX.md §7 rather than papered over
/// with a timing assertion that would flake.
final class LocalModeTests: XCTestCase {
    func testLocalModeSaysTheTextIsNotComing() {
        // `-local_only YES` is the same UserDefaults key the onboarding form's
        // "Vain minulle, tälle puhelimelle" writes, so this exercises the real
        // mode decision rather than simulating its outcome.
        let app = launch(
            ["-seed", "empty", "-local_only", "YES"],
            api: "http://127.0.0.1:9"
        )

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()

        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )
        // Anything under a second is discarded as an accident, so the telling
        // has to be old enough to be a memory before it is stopped.
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()

        // The audio-saved screen — and fast, because nothing was uploaded to a
        // server that would only have said 401.
        XCTAssertTrue(
            app.staticTexts["Äänesi on tallessa"].waitForExistence(timeout: 15),
            "never arrived: the audio-saved screen"
        )
        XCTAssertTrue(
            app.staticTexts[
                "Kun arkisto on vain tällä puhelimella, puhetta ei muuteta tekstiksi. "
                    + "Äänesi säilyy — voit kirjoittaa muiston itse."
            ].exists,
            "the honest sentence is missing from the result screen"
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "valmistuu myöhemmin")
            ).firstMatch.exists,
            "the result screen still promises text that is never coming"
        )

        // The memory row makes the same promise in the archive, and it has its
        // own sentence to get right.
        app.buttons["Selvä"].tap()
        app.tabBars.buttons["Muistot"].tap()
        let card = app.staticTexts["Kerrottu muisto"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "never arrived: the telling's card")
        card.tap()
        let row = app.staticTexts["Ääni tallessa — voit kirjoittaa tekstin itse"]
        for _ in 0 ..< 4 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the row does not say the honest sentence")
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "valmistuu myöhemmin")
            ).firstMatch.exists,
            "the memory row still promises text that is never coming"
        )
    }

    /// Answers the microphone prompt if it is showing, by position rather than
    /// label — permission alerts put the allowing answer last, whatever the
    /// simulator's language. Same helper as TakingBackTests.
    private func allowTheMicrophone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        let buttons = alert.buttons
        guard buttons.count > 0 else { return }
        buttons.element(boundBy: buttons.count - 1).tap()
    }
}
