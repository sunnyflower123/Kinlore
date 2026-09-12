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
        let card = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
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

    /// The door out of the single-device archive.
    ///
    /// "Keiden kesken" is answered on the first form in the app, before anybody
    /// knows what the app does, and until this existed the only thing that
    /// unmade it was "Tyhjennä tämä laite" — an exit priced at every memory on
    /// the phone. The cost of the wrong answer was the whole product: this mode
    /// attempts no transcription at all.
    ///
    /// **What this pins, exactly.** The row exists only where the choice was
    /// made (`isLocalByChoice` needs both the flag and an address), the dialog
    /// says what travels before it happens, and the far side is the onboarding
    /// fork rather than a screen with nothing on it.
    ///
    /// **What it does not.** `store.markAllPending()` runs in the same handler,
    /// one line above the mode flip, and nothing on any screen shows an outbox
    /// on a device with no family — so a build that dropped that call would go
    /// green here and would send an archive that stayed behind. That residual
    /// is named rather than papered over with an assertion that cannot see it;
    /// see docs/UX.md §11.
    func testTheLocalArchiveOpensToAFamilyWithoutLosingIt() {
        let app = launch(
            ["-seed", "archive", "-local_only", "YES", "-tab", "people", "-screen", "settings"],
            api: "http://127.0.0.1:9"
        )

        let row = app.buttons["Ota perhe käyttöön"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "never arrived: the way into a family")
        row.tap()

        // A screen rather than a dialog, and the sentence that has to be on it
        // is the one nobody would expect: what is already on this phone goes
        // with it. Asked for by name, because a screen that opened without it
        // would be this app changing where the memories live without saying so.
        XCTAssertTrue(
            app.staticTexts[
                "Tämän puhelimen muistot lähtevät sille perheelle, "
                    + "jonka perustat tai johon liityt."
            ].waitForExistence(timeout: 10),
            "the door does not say what travels through it"
        )
        app.buttons["Ota perhe käyttöön"].firstMatch.tap()

        XCTAssertTrue(
            app.buttons["Aloita perheen arkisto"].waitForExistence(timeout: 15),
            "the far side of the door is not the onboarding fork"
        )
        XCTAssertTrue(
            app.buttons["Liity kutsulinkillä"].exists,
            "the fork arrived with only one way through it"
        )

        // The far side is a sheet over the archive, not a wall in front of
        // it. The backend here is a dead address, so the create fails the way
        // a cottage with no signal fails — and nothing must have moved: the
        // form stays, the fork can be left, and Settings is where it was,
        // still offering the door, with the archive behind it.
        app.buttons["Aloita perheen arkisto"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10), "never arrived: the create form")
        name.tap()
        name.typeText("Mummo")
        let create = app.buttons["Luo arkisto"]
        for _ in 0 ..< 4 where !create.exists { app.swipeUp() }
        XCTAssertTrue(create.waitForExistence(timeout: 10), "never arrived: the create button")
        create.tap()
        XCTAssertTrue(create.waitForExistence(timeout: 15), "the failed create took the form away")

        app.navigationBars.buttons.firstMatch.tap()
        let cancel = app.buttons["Peruuta"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the fork over an archive has no way out")
        cancel.tap()

        // The sheet is gone and the door's own screen is under it, still
        // offering the door: nothing changed. One step back is Settings.
        XCTAssertTrue(app.buttons["Ota perhe käyttöön"].waitForExistence(timeout: 10), "the phone stopped being local without a family")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Vie arkisto"].waitForExistence(timeout: 10), "Settings did not come back")
        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch.waitForExistence(timeout: 10),
            "the archive is no longer on screen"
        )
    }

    /// And it is not offered where the choice was never made: a build with no
    /// backend address is local because there is nowhere to sync to, not
    /// because anybody decided so, and a row promising a family it cannot
    /// reach would be an offer with nothing behind it.
    func testTheDoorIsNotOfferedWithoutABackend() {
        let app = launch(["-seed", "archive", "-tab", "people", "-screen", "settings"])

        XCTAssertTrue(
            app.buttons["Vie arkisto"].waitForExistence(timeout: 15),
            "never arrived: Settings"
        )
        XCTAssertFalse(
            app.buttons["Ota perhe käyttöön"].exists,
            "a build with no address offers a family it cannot reach"
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
