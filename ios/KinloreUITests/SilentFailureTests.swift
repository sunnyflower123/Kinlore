import XCTest

/// The places where the app answered something with nothing at all.
///
/// None of them looked broken from the outside, which is the point: a refused
/// microphone gave a retry button that retried the refusal, the button that
/// plays a dead person's voice did nothing when the audio could not be fetched —
/// indistinguishable from a phone on silent or a finger that missed — and an
/// invite link tapped at the wrong time was parsed, stored and read by nothing.
final class SilentFailureTests: XCTestCase {
    /// `-mic denied` refuses the microphone without touching the device's own
    /// permission, which is otherwise a manual trip into iOS Settings and out of
    /// reach of any test run.
    /// A file written before the newer fields existed still loads. Swift's
    /// synthesized Codable does not use a default for a missing key, and until
    /// 4 Sep 2026 that meant an ordinary update could read a two-year-old
    /// archive as empty (CLAUDE.md rule 10). `-store outdated` writes such a
    /// file with the real encoder minus the later keys.
    func testAnArchiveWrittenBeforeNewerFieldsStillLoads() {
        let app = launch(["-store", "outdated", "-tab", "people"])
        XCTAssertTrue(
            app.staticTexts["Vanha Aino"].waitForExistence(timeout: 10),
            "the archive from an older file did not load"
        )
        XCTAssertFalse(
            app.staticTexts["Tallennettua arkistoa ei saatu luettua"].exists,
            "an old file that loads must not be reported as unreadable"
        )
    }

    /// A file this version cannot read is kept and said so — never an empty
    /// archive that the next save overwrites.
    func testAnUnreadableArchiveIsKeptAndSaidSo() {
        let app = launch(["-store", "unreadable"])
        XCTAssertTrue(
            app.staticTexts["Tallennettua arkistoa ei saatu luettua"].waitForExistence(timeout: 10),
            "an unreadable archive came up empty in silence"
        )
        app.buttons["Selvä"].tap()
        // And the app goes on: the person is not locked out of telling.
        XCTAssertTrue(app.tabBars.buttons["Kerro"].waitForExistence(timeout: 10), "the app did not go on")
    }

    /// The month's minutes are a wall with a date, and the app says so where
    /// it happens and everywhere the wait shows: the screen after the telling,
    /// the note on Muistot and the row itself. `-defer once` fails the first
    /// transcription as the quota would; `-minutes-out 1` holds the meter
    /// there, as the server's would be.
    func testRunningOutOfMinutesIsSaidWithADate() {
        let app = launch(["-seed", "empty", "-defer", "once", "-minutes-out", "1"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        XCTAssertTrue(app.staticTexts["Äänesi on tallessa"].waitForExistence(timeout: 30), "never arrived: the audio-saved screen")
        let quota = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kuukauden ilmainen kertominen on täynnä")).firstMatch
        XCTAssertTrue(quota.waitForExistence(timeout: 10), "the screen did not say it was the month's minutes")

        let done = app.buttons["Selvä"]
        for _ in 0 ..< 4 where !done.exists { app.swipeUp() }
        XCTAssertTrue(done.waitForExistence(timeout: 10), "never arrived: the way on")
        done.tap()

        app.tabBars.buttons["Muistot"].tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yksi kertomus odottaa tekstiä")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "the gallery did not count the waiting telling")

        let row = app.staticTexts["Kerrottu muisto"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery")
        row.tap()
        XCTAssertTrue(
            app.staticTexts["Ääni tallessa — kuukauden kertominen täynnä"].waitForExistence(timeout: 10),
            "the row still promised the text for later"
        )
    }

    /// The conversation can be ended while answering, keeping the answer. The
    /// loop's exit used to stand only while a question was being spoken; once
    /// the microphone had armed itself, the big button asked the next question
    /// and the only other one threw the answer away.
    func testTheConversationCanBeEndedWhileAnswering() {
        let app = launch(["-seed", "empty", "-screen", "interview"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        // The loop arms the microphone by itself; whichever round this is,
        // the way out must be on the listening screen.
        XCTAssertTrue(
            app.staticTexts["Paina kun olet valmis"].waitForExistence(timeout: 60),
            "never arrived: the listening screen"
        )
        let enough = app.buttons["Riittää tältä erää"]
        XCTAssertTrue(enough.waitForExistence(timeout: 10), "the listening screen has no way out that keeps the answer")
        enough.tap()

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "ending the conversation did not land on the result"
        )
        XCTAssertFalse(app.staticTexts["Paina kun olet valmis"].exists, "the loop went on after being ended")
    }

    func testARefusedMicrophoneOffersAWayOn() {
        let app = launch(["-seed", "empty", "-mic", "denied"])

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "never arrived: the record button")
        record.tap()

        XCTAssertTrue(
            app.staticTexts["Mikrofoni ei ole käytössä"].waitForExistence(timeout: 10),
            "a refused microphone did not say so"
        )
        // The place the old message told her to go to, as a button rather than
        // as an instruction. Not tapped: it leaves the app for iOS Settings.
        XCTAssertTrue(app.buttons["Avaa asetukset"].exists, "no way to the permission itself")

        // And the way that needs no permission from anybody. Telling is never
        // blocked, so a refused microphone must not be the thing that blocks it.
        app.buttons["Kirjoita sen sijaan"].tap()
        XCTAssertTrue(
            app.textViews.firstMatch.waitForExistence(timeout: 10),
            "the keyboard route out of the refusal did not open"
        )
    }

    /// The demo archive's recording is a key with nothing behind it, so this is
    /// the real failing fetch rather than a simulated one.
    func testAnAudioThatCannotBeFetchedSaysSo() {
        let app = launch(["-seed", "archive", "-tab", "memories"])

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "never arrived: the photo tile")
        photo.tap()

        let listen = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Kuuntele omalla äänellä")
        ).firstMatch
        XCTAssertTrue(listen.waitForExistence(timeout: 10), "never arrived: the playback button")
        listen.tap()

        XCTAssertTrue(
            app.buttons["Ääntä ei saatu haettua — yritä uudelleen"].waitForExistence(timeout: 15),
            "the tap did nothing, and said nothing"
        )
    }

    /// An invite link that arrives on a device that cannot use it.
    ///
    /// The likeliest wrong time is the most human one: the app was opened and
    /// looked at first, an archive got created with the big blue button, and
    /// *then* the grandchild's link was tapped. The code was stored and nothing
    /// outside onboarding ever read it — silence, on a deliberate act.
    /// `-invite` feeds the same handler a real URL open reaches.
    func testAnInviteLinkAtTheWrongTimeGetsAnAnswer() {
        // A device that already belongs to a family.
        let inFamily = launch(["-seed", "family", "-invite", "demo-code"])
        XCTAssertTrue(
            inFamily.alerts["Tämä laite kuuluu jo perheeseen"].waitForExistence(timeout: 10),
            "a link into a family was answered with silence"
        )
        inFamily.terminate()

        // A device with a single-device archive: no backend, no family.
        let local = launch(["-seed", "empty", "-invite", "demo-code"])
        XCTAssertTrue(
            local.alerts["Tällä laitteella on jo oma arkisto"].waitForExistence(timeout: 10),
            "a link onto a local archive was answered with silence"
        )
        local.terminate()
    }

    /// A device the server has stopped knowing — a 401 on every round, most
    /// likely from "Tyhjennä tämä laite" on another phone of the same Apple ID
    /// renewing the shared Keychain identity. It used to be a row on the Perhe
    /// screen with no action, and the documented way back ran through "Poistu
    /// perheestä", which the same server refuses (founder's-eye review,
    /// finding #57). Now Muistot says so and offers the way back, and a fresh
    /// link tapped on that device opens the same form with the code in it
    /// instead of the wrong-time alert. `-sync refused` holds the state; the
    /// real one needs a Worker that has forgotten the device.
    func testARefusedDeviceIsOfferedAWayBack() {
        let app = launch(["-seed", "family", "-tab", "memories", "-sync", "refused"])
        let back = app.buttons["Liity uudella kutsulla"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "a refused device was met with silence on Muistot")
        back.tap()
        XCTAssertTrue(
            app.textFields["Kutsukoodi"].waitForExistence(timeout: 10),
            "the way back did not open the join form"
        )
        app.terminate()

        let linked = launch(["-seed", "family", "-tab", "memories", "-sync", "refused", "-invite", "demo-code"])
        let field = linked.textFields["Kutsukoodi"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 10),
            "a link on a refused device was answered with the wrong-time alert"
        )
        XCTAssertEqual(field.value as? String, "demo-code", "the code did not travel into the form")
        XCTAssertFalse(
            linked.alerts["Tämä laite kuuluu jo perheeseen"].exists,
            "the refused device was told it already belongs to a family"
        )
    }

    /// The recording that could not be kept. `persistAudio` swallowed the
    /// failure and returned nil: the memory was saved without its audio and the
    /// screen said *"Äänesi on tallessa"* over a file that was gone — rule 3
    /// broken in silence on the one input the app calls irreplaceable
    /// (founder's-eye review, finding #58). `-audio-lost` holds the failure
    /// still; the real one needs the system to empty tmp under a telling.
    func testALostRecordingIsSaidNotClaimedKept() {
        // No words either: nothing is saved, and the screen says so. `-defer
        // once` records two seconds by itself and defers the text.
        let deferred = launch(["-seed", "empty", "-defer", "once", "-audio-lost", "YES"])
        XCTAssertTrue(
            deferred.staticTexts["Nauhoitusta ei saatu talteen"].waitForExistence(timeout: 30),
            "a lost recording was not said"
        )
        XCTAssertFalse(deferred.staticTexts["Äänesi on tallessa"].exists, "a lost recording was called kept")
        XCTAssertFalse(deferred.buttons["Poista tämä muisto"].exists, "a memory that was never saved was offered for removal")
        deferred.terminate()

        // The words arrived, the recording did not: saved as text, and said.
        // A real telling through the stub — the button, two seconds, the stop.
        let transcribed = launch(["-seed", "empty", "-audio-lost", "YES"])
        let record = transcribed.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), "never arrived: the record button")
        record.tap()
        XCTAssertTrue(transcribed.staticTexts["Kuuntelen"].waitForExistence(timeout: 15), "the recording did not start")
        Thread.sleep(forTimeInterval: 2)
        transcribed.buttons["Lopeta kertominen"].tap()
        XCTAssertTrue(transcribed.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30), "the telling was not saved as text")
        XCTAssertTrue(
            transcribed.staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@", "Äänitystä ei saatu talteen"))
                .firstMatch.waitForExistence(timeout: 10),
            "the missing recording was not said on the result"
        )
    }

    /// The family key rides the invite link as its `#`-fragment (lever 3), and
    /// the parser used to read query items only — which a fragment never
    /// reaches. The one thing a *tapped* link delivered was membership in a
    /// family the phone could not read, while *pasting* the same text worked.
    /// Silent in the worst way: everything looks joined.
    ///
    /// `-invite` with a full URL drives the real parser; the assertion is that
    /// the join form receives the code with its key still attached.
    func testATappedLinkKeepsTheFamilyKey() {
        let app = launch(
            ["-invite", "kinlore://join?code=demo123#demokey"],
            api: "http://127.0.0.1:9"
        )

        let field = app.textFields["Kutsukoodi"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 10),
            "the join form did not open from the link"
        )
        XCTAssertEqual(
            field.value as? String,
            "demo123#demokey",
            "the code lost its key fragment between the link and the form"
        )
    }

    /// Creating an invite used to fail in total silence: a brief spinner, then
    /// the resting button, on the flow UX.md calls the path to the product's
    /// second user. The seeded family has no client at all, which is the same
    /// nil the real screen meets with no network — so it must say so.
    ///
    /// The refusal moved one step in, and the test with it: since the
    /// invitation started carrying a name, the row opens a sheet that asks who
    /// it is for, and the code is made when that is answered. What must not
    /// change is the ending — a deliberate act that fails says so, rather than
    /// returning to a resting button.
    func testCreatingAnInviteSaysWhenItCannot() {
        let app = launch(["-seed", "family", "-tab", "people", "-screen", "family"])

        // Below the fold since the member rows grew the owner's "Poista
        // perheestä" (5 Sep 2026), and a List builds no row nobody can see.
        let invite = app.buttons["Kutsu perheenjäsen"]
        for _ in 0 ..< 4 where !invite.exists { app.swipeUp() }
        XCTAssertTrue(invite.waitForExistence(timeout: 10), "never arrived: the family screen")
        invite.tap()

        let create = app.buttons["Luo kutsu"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "never arrived: the naming step")
        create.tap()

        XCTAssertTrue(
            app.staticTexts["Kutsua ei voitu luoda"].waitForExistence(timeout: 10),
            "a failed invite creation said nothing"
        )
    }

    /// A camera on a device that has none.
    ///
    /// The simulator has no camera, and so does an iPad somebody borrowed —
    /// and the shape a missing camera takes by default is a black rectangle
    /// with a shutter that does nothing, which is the silence this file is
    /// about. It is also the state every screenshot run meets, so it is the
    /// one camera state that can be checked without forcing anything: no
    /// `-camera` argument here on purpose.
    func testTheCameraSaysWhenThereIsNone() {
        let app = launch(["-seed", "empty", "-tab", "memories", "-screen", "camera"])

        XCTAssertTrue(
            app.staticTexts["Tässä laitteessa ei ole kameraa"].waitForExistence(timeout: 15),
            "a device with no camera showed no reason"
        )
        XCTAssertTrue(
            app.buttons["Valitse kuvista"].exists,
            "a device with no camera was left with no way on"
        )
    }

    /// The same shape on the boundary's one remedy: "Poista" on a leaked
    /// invite with no connectivity used to leave the row in place with no
    /// message, indistinguishable from a slow revoke that worked.
    func testRevokingAnInviteSaysWhenItCannot() {
        let app = launch(["-seed", "family", "-tab", "people", "-screen", "family"])

        let revoke = app.buttons["Poista"].firstMatch
        for _ in 0 ..< 4 where !revoke.exists { app.swipeUp() }
        XCTAssertTrue(revoke.waitForExistence(timeout: 10), "never arrived: an invite row")
        revoke.tap()

        XCTAssertTrue(
            app.staticTexts["Kutsua ei voitu perua"].waitForExistence(timeout: 10),
            "a failed revocation said nothing"
        )
    }
}
