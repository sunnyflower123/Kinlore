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

    /// The screenshot aid that quietly pointed at the wrong screen.
    ///
    /// `-screen` names a destination that lives inside one tab, and a TabView
    /// builds a tab's content only once that tab is shown. The task that reads
    /// it sits in PeopleScreen, so on a launch that opened Kerro — the default —
    /// it never ran, and `-screen person|family|settings|export|help|sharing`
    /// did nothing at all. The Kerro values (`starter`, `write`, `interview`,
    /// `interviewed`, `result`) worked throughout and hid it: the aid looked
    /// half-working rather than broken, and a screenshot run came back with a
    /// plausible wrong screen instead of an error. Fixed 12 Sep 2026 by opening
    /// the tab the destination lives in; this is what keeps it fixed.
    func testScreenOpensTheTabItsDestinationLivesIn() {
        let app = launch(["-seed", "archive", "-screen", "person"])
        XCTAssertTrue(
            app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 15),
            "-screen person did not reach a person's card"
        )
        XCTAssertTrue(
            app.tabBars.buttons["Ihmiset"].isSelected,
            "-screen person reached a card without selecting the tab it lives in"
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

    /// The other direction of the same rule: a file written by a *later*
    /// version, on a phone that then went back to this one, holding a
    /// relationship of a kind this version has never heard of. The relations
    /// list used to be decoded as a whole, so that one row failed the whole
    /// file and sent a readable archive down the moved-aside path above.
    /// Now the row is left out and counted, and the rest loads — including
    /// the relationship beside it. `-store unknownKind` writes such a file
    /// with the real encoder and one kind edited in.
    func testAnArchiveWithAnUnknownRelationKindStillLoads() {
        let app = launch(["-store", "unknownKind", "-tab", "people"])
        XCTAssertTrue(
            app.staticTexts["Vanha Aino"].waitForExistence(timeout: 10),
            "the archive with an unknown relationship kind did not load"
        )
        XCTAssertFalse(
            app.staticTexts["Tallennettua arkistoa ei saatu luettua"].exists,
            "a file with one unreadable row was reported as an unreadable file"
        )
        // The row this version can read is still there: her card names the
        // spouse the same file holds.
        app.staticTexts["Vanha Aino"].tap()
        XCTAssertTrue(
            app.staticTexts["Vanha Eino, Puoliso"].waitForExistence(timeout: 10),
            "the relationship this version can read was lost with the one it cannot"
        )
    }

    /// Another member's telling, filed under a card somebody merged away, is
    /// on the survivor's card. The server keeps the forwarding address and
    /// re-points a telling for nobody but its author, so until 21 Sep 2026
    /// every phone but the merging one kept it under the tombstone — on no
    /// card, in no count, and left out of the export's readable page.
    /// `-store mergedElsewhere` writes that phone's file.
    func testATellingFiledUnderAMergedCardIsOnTheSurvivorsCard() {
        let app = launch(["-store", "mergedElsewhere", "-screen", "person"])
        XCTAssertTrue(
            app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 15),
            "-screen person did not reach the survivor's card"
        )
        XCTAssertTrue(
            app.staticTexts["Hän leipoi pullaa joka lauantai."].waitForExistence(timeout: 10),
            "the telling filed under the merged card is not on the survivor's card"
        )
    }

    /// A build that has learnt a new relationship kind pulls the family once
    /// more from the start. The build before it applied every pull minus the
    /// rows of a kind it did not know, and the cursor moved past them all the
    /// same — so a relationship the family confirmed never came again, and
    /// nothing said so. `-store synced` writes an empty archive whose pulls
    /// have reached 412, and `-sync.kindsKnown` is what the previous build
    /// recorded. The reset shows exactly where a cursor at zero shows: a
    /// first pull that fails is said as the family's memories not arriving,
    /// while a later pull that fails leaves the ordinary empty archive.
    func testABuildThatLearntARelationKindPullsFromTheStart() {
        let learnt = launch(
            ["-store", "synced", "-tab", "memories", "-family_id", "demo", "-sync.kindsKnown", "3/4"],
            api: "http://127.0.0.1:9"
        )
        XCTAssertTrue(
            learnt.staticTexts["Perheen muistoja ei saatu haettua"].waitForExistence(timeout: 10),
            "a build that learnt a new relationship kind did not pull from the start"
        )
        learnt.terminate()

        // The same file under a build that recorded every kind it knows —
        // `MemoryStore.kindsKnown`, relationship kinds over subject kinds,
        // which `friendOf` moved from 3/4 to 4/4 on 21 Sep 2026; the next
        // kind of either moves it again, and this line with it. The cursor
        // stands, and the failed pull is not the first one.
        let same = launch(
            ["-store", "synced", "-tab", "memories", "-family_id", "demo", "-sync.kindsKnown", "4/4"],
            api: "http://127.0.0.1:9"
        )
        XCTAssertTrue(same.staticTexts["Ei vielä kuvia"].waitForExistence(timeout: 10), "never arrived: the empty archive")
        XCTAssertFalse(
            same.staticTexts["Perheen muistoja ei saatu haettua"].exists,
            "a build whose kinds have not changed pulled from the start"
        )
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
        let quota = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kuukauden ilmainen litterointiaika on käytetty")).firstMatch
        XCTAssertTrue(quota.waitForExistence(timeout: 10), "the screen did not say it was the month's minutes")

        let done = app.buttons["Selvä"]
        for _ in 0 ..< 4 where !done.exists { app.swipeUp() }
        XCTAssertTrue(done.waitForExistence(timeout: 10), "never arrived: the way on")
        done.tap()

        app.tabBars.buttons["Albumi"].tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yksi kertomus odottaa tekstiä")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "the gallery did not count the waiting telling")

        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the telling is not in the gallery")
        row.tap()
        XCTAssertTrue(
            app.staticTexts["Ääni tallessa — kuukauden litterointiaika käytetty"].waitForExistence(timeout: 10),
            "the row still promised the text for later"
        )
    }

    /// The same walls on a grandparent's phone, each with the way past it.
    /// The ceilings are the family's, and so is the purchase that lifts them
    /// (`UpsellRhythm.offersPurchaseAtCeiling`): the screen that says her
    /// voice is safe, the minutes note and the photographs note on Albumi all
    /// carry "Avaa koko arkisto" wherever there is a store. For part of
    /// 26 Sep 2026 all three were hidden there on the result card's reasoning
    /// — the card still never asks her after a telling
    /// (`ResultScreenTests.testTheArchiveIsOfferedOnlyOnAReadersPhoneWithAStore`)
    /// — and a wall with nothing beside it said only that there was no way up.
    ///
    /// The key is that test's placeholder, in a key's shape and never the
    /// Test Store's. The photographs get a launch of their own because the
    /// minutes note takes the offer whenever it shows, so the photo note is
    /// never asked beside it.
    func testTheCeilingsOfferTheArchiveOnAGrandparentsPhone() {
        let grandparentWithAStore = ["-rcKey", "test_placeholder", "-elder.largerText", "YES"]

        let app = launch(["-seed", "empty", "-defer", "once", "-minutes-out", "1"] + grandparentWithAStore)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        XCTAssertTrue(app.staticTexts["Äänesi on tallessa"].waitForExistence(timeout: 30), "never arrived: the audio-saved screen")
        let saved = app.buttons["Avaa koko arkisto"]
        for _ in 0 ..< 4 where !saved.exists { app.swipeUp() }
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "the audio-saved screen met the wall with no way past it")

        let done = app.buttons["Selvä"]
        for _ in 0 ..< 4 where !done.exists { app.swipeUp() }
        XCTAssertTrue(done.waitForExistence(timeout: 10), "never arrived: the way on")
        done.tap()

        app.tabBars.buttons["Albumi"].tap()
        let minutes = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yksi kertomus odottaa tekstiä")).firstMatch
        XCTAssertTrue(minutes.waitForExistence(timeout: 10), "never arrived: the note about the month's minutes")
        let beside = app.buttons["Avaa koko arkisto"]
        for _ in 0 ..< 4 where !beside.exists { app.swipeUp() }
        XCTAssertTrue(beside.waitForExistence(timeout: 10), "the minutes note met the wall with no way past it")
        app.terminate()

        let photos = launch(["-seed", "archive", "-tab", "memories", "-photos-refused", "2"] + grandparentWithAStore)
        let refused = photos.staticTexts
            .containing(NSPredicate(format: "label CONTAINS %@", "ei mahtunut ilmaiseen arkistoon"))
            .firstMatch
        XCTAssertTrue(refused.waitForExistence(timeout: 15), "never arrived: the photographs note")
        let lift = photos.buttons["Avaa koko arkisto"]
        for _ in 0 ..< 4 where !lift.exists { photos.swipeUp() }
        XCTAssertTrue(lift.waitForExistence(timeout: 10), "the photographs note met the wall with no way past it")
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

        // The loop arms the microphone by itself — and `-screen interview`
        // ends its FIRST spoken round by itself too, three seconds after the
        // microphone arms, so a way out found on that round can be gone by
        // the time it is tapped. On a loaded machine it was (26 Sep 2026).
        // The second round nothing ends but a tap. So let the first one go:
        // when the listening screen leaves within the timer's reach, wait
        // for it to come back; when it does not leave, the round in front of
        // the test is already the second, and there is nothing to wait for.
        let listening = app.staticTexts["Paina kun olet valmis"]
        XCTAssertTrue(listening.waitForExistence(timeout: 60), "never arrived: the listening screen")
        let firstRoundEnded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: listening
        )
        if XCTWaiter().wait(for: [firstRoundEnded], timeout: 15) == .completed {
            XCTAssertTrue(
                listening.waitForExistence(timeout: 60),
                "the loop did not reach its second question"
            )
        }
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

    /// The same way back for a phone that has lost the family's key, which
    /// syncs nothing until an invitation brings the key (`SyncSeal`). The form
    /// must say that, and not the refused sentence: the reason is kept from
    /// the tap (`SyncEngine.rejoinReason`), because a round passing through
    /// `.syncing` would otherwise swap it. `-sync keyless` holds the state.
    func testAPhoneWithoutTheKeyIsOfferedAWayBack() {
        let app = launch(["-seed", "family", "-tab", "memories", "-sync", "keyless"])
        let back = app.buttons["Liity uudella kutsulla"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "a phone without the key was met with silence on Muistot")
        back.tap()
        let why = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Tästä puhelimesta puuttuu perheen avain. Kun liityt")
        ).firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 10), "the join form did not say that the key is missing")
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Palvelin ei enää tunnista tätä puhelinta.")
            ).firstMatch.exists,
            "a phone without the key was told the server had forgotten it"
        )
        app.terminate()

        let linked = launch(["-seed", "family", "-tab", "memories", "-sync", "keyless", "-invite", "demo-code"])
        let field = linked.textFields["Kutsukoodi"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 10),
            "a link on a phone without the key was answered with the wrong-time alert"
        )
        XCTAssertEqual(field.value as? String, "demo-code", "the code did not travel into the form")
    }

    /// The rejoin sheet's title, drawn once. The form is the first screen of
    /// that sheet, pushed the moment the sheet appears, and its large title
    /// was drawn over the note that says why the form is there while the bar
    /// already showed the same title inline — on both phones, in both
    /// languages, at both sizes (the English read-through of 26 Sep 2026,
    /// pictures 084 and 086), and still six seconds after the sheet had
    /// settled. Starting the stack on the form instead of pushing it made no
    /// difference to any of those numbers; the title is inline now.
    func testTheRejoinFormDoesNotDrawItsTitleOverItsNote() {
        for size in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launch(
                ["-seed", "family", "-tab", "memories", "-sync", "keyless", "-invite", "demo-code"],
                textSize: size
            )
            let note = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Tästä puhelimesta puuttuu perheen avain.")
            ).firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 10), "the join form's note never arrived")
            // The drawn large title is not in the accessibility tree at all —
            // the tree holds the inline one — so what is measured is the bar's
            // frame, which reserves the large title's height and ran down over
            // the note: 78 to 184 pt against a note starting at 132, at the
            // default size, measured 26 Sep 2026.
            let bar = app.navigationBars["Liity perheeseen"]
            XCTAssertTrue(bar.exists, "the join form has no bar")
            XCTAssertGreaterThanOrEqual(
                note.frame.minY, bar.frame.maxY,
                "the bar is drawn over the note: \(bar.frame) against \(note.frame) at \(size ?? "the default size")"
            )
            app.terminate()
        }
    }

    /// The joiner whose first pull failed. The state after a failed round is
    /// `waitingForNetwork`, not `syncing`, so Muistot fell through to the empty
    /// archive's invitation and asked her to photograph an album — a second
    /// archive beside the family's (founder's-eye review, finding #63). Real
    /// failure rather than a held state: an address with nothing behind it
    /// refuses the connection at once, and the engine, the cursor and the
    /// screen do the rest.
    func testAFailedFirstPullIsSaidNotShownAsEmpty() {
        let app = launch(
            ["-seed", "empty", "-tab", "memories", "-family_id", "demo"],
            api: "http://127.0.0.1:9"
        )
        let said = app.staticTexts["Perheen muistoja ei saatu haettua"]
        XCTAssertTrue(said.waitForExistence(timeout: 10), "a failed first pull was not said")
        XCTAssertFalse(app.staticTexts["Ei vielä kuvia"].exists, "a failed first pull was shown as an empty archive")
        XCTAssertFalse(app.buttons["Kuvaa vanha valokuva"].exists, "the joiner was asked to photograph an album")
        let again = app.buttons["Hae nyt uudelleen"]
        XCTAssertTrue(again.exists, "no way to fetch again")
        again.tap()
        // The round fails again, and the sentence stays true rather than
        // turning into the invitation on the way.
        XCTAssertTrue(said.waitForExistence(timeout: 10), "the retry turned a failed pull into an empty archive")
        XCTAssertFalse(app.buttons["Kuvaa vanha valokuva"].exists, "the retry offered the album")
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

    /// The launch sweep never touches a recording this launch made.
    ///
    /// `RecordingRecovery.sweep` ran once the launch task's network calls had
    /// answered, and took whatever `memory-` file tmp held at that moment
    /// for one the app had been killed under. A telling started
    /// before it — `-defer once` starts one at launch, and so can anybody who
    /// opens the app and presses the button — was deleted mid-recording as
    /// unreadable, or adopted between its stop and its save, which
    /// `persistAudio` then cleared out of its own way. Either way the screen
    /// said *"Nauhoitusta ei saatu talteen"*, and `export-check.mjs` found no
    /// audio in the export (26 Sep 2026). `-recovery-sweep` runs the sweep at
    /// each of the two moments.
    func testTheLaunchSweepLeavesThisLaunchsRecordingAlone() {
        for moment in ["recording", "stopped"] {
            let app = launch(["-seed", "empty", "-defer", "once", "-recovery-sweep", moment])
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 5) { allow.tap() }

            XCTAssertTrue(
                app.staticTexts["Äänesi on tallessa"].waitForExistence(timeout: 30),
                "a sweep while \(moment) lost the recording"
            )
            XCTAssertFalse(
                app.staticTexts["Nauhoitusta ei saatu talteen"].exists,
                "a sweep while \(moment) lost the recording"
            )
            app.terminate()
        }
    }

    /// And the recording it exists for is still taken in. `-recovery orphan`
    /// leaves a finished two-second one in tmp before the app looks, as a
    /// launch killed between the stop and the save would have: it arrives on
    /// Albumi as the same audio-only row a quota outage leaves.
    func testARecordingAnEarlierLaunchLeftBehindIsTakenIn() {
        let app = launch(["-seed", "empty", "-tab", "memories", "-recovery", "orphan"])
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "a recording left in tmp was not taken in")
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
