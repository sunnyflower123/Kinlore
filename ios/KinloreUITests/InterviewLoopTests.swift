import XCTest

/// What follows a spoken telling: the app's first question, asked aloud
/// without anybody pressing anything, and everything the telling named
/// waiting on the result card until the conversation is over.
///
/// Until 26 Sep 2026 the questions stood under "Kysyisin vielä" and only
/// "Jatketaan jutellen" turned them into a conversation. When the founder
/// told about a photograph on their own phone, nothing was asked — the loop
/// this app was built around sat behind a button they did not see. A written
/// telling keeps the button: somebody typing has chosen the keyboard, and a
/// voice starting up would be the app ignoring that choice.
///
/// `-voice stub` keeps the question "being read" until something stops it and
/// makes no sound. What is checked is the call, not the voice — the speaker on
/// the question screen is labelled only while `InterviewVoice.speak` is
/// running, so the label is the call made visible.
///
/// And how a conversation ends when nobody ends it: an answer that has gone
/// quiet ends it the way "Riittää tältä erää" does, and a first telling is
/// never cut (`AnswerWatch`). `-meter silent` is the silence. A simulator
/// records from the Mac's own microphone, and a test cannot count on the room
/// around it. A reply with no words in it is `-answer wordless`, and it is
/// not one the Worker sends today: the Worker answers a silence 502.
final class InterviewLoopTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testASpokenTellingGoesStraightOnToItsQuestion() {
        let app = launch(["-seed", "empty", "-voice", "stub"])

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 15), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )
        // Under a second is thrown away as an accident, not told.
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()

        // The telling ends on its first question, and nothing was tapped in
        // between. The canned telling (`StubTranscriptionService.samples[0]`)
        // names Puumala, Aino and Toivo, and the stub always has questions.
        let enough = app.buttons["Riittää tältä erää"]
        XCTAssertTrue(
            enough.waitForExistence(timeout: 30),
            "the telling ended somewhere other than its first question"
        )
        XCTAssertFalse(
            app.staticTexts["Muisto tallennettu"].exists,
            "the result card came before the question"
        )
        XCTAssertTrue(
            app.images["Luen kysymyksen ääneen"].exists,
            "the question is on the screen and nothing was asked to read it aloud"
        )

        // "Riittää tältä erää" ends it on everything that was collected: the
        // names to check (rule 4) and the decade, none of them lost to the
        // screen the conversation replaced.
        enough.tap()
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 15),
            "ending the conversation did not land on the result"
        )
        XCTAssertFalse(
            app.images["Luen kysymyksen ääneen"].exists,
            "the voice went on after the conversation ended"
        )
        reach(app.buttons["1950-luku"], in: app, "the decade the telling named")
        for name in ["Puumalassa", "Aino", "Toivo"] {
            reach(app.buttons["Vahvista \(name)"], in: app, "the name \(name), to confirm")
        }
    }

    /// The same telling written: the result card first, the questions under
    /// it and the conversation one tap away, as before.
    func testAWrittenTellingWaitsForTheButton() {
        let app = launch(["-seed", "empty", "-voice", "stub"])

        let typing = app.buttons["Kirjoita sen sijaan"]
        XCTAssertTrue(typing.waitForExistence(timeout: 15), "never arrived: the way to write")
        typing.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "never arrived: the page to write on")
        editor.tap()
        editor.typeText("Olimme Puumalassa mökillä. Aino oli siellä joskus 50-luvulla.")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "a written telling did not land on its result"
        )
        XCTAssertFalse(app.buttons["Riittää tältä erää"].exists, "a written telling started talking")
        XCTAssertFalse(app.images["Luen kysymyksen ääneen"].exists, "a written telling was read aloud")
        reach(app.buttons["Jatketaan jutellen"], in: app, "the button that starts the conversation")
    }

    /// An answer nobody ends. The loop opens the microphone after every
    /// question by itself, and until 27 Sep 2026 an answer that had gone quiet
    /// kept it open for as long as nobody touched the phone.
    func testASilentAnswerEndsTheConversation() {
        let app = launch(["-seed", "empty", "-voice", "stub", "-meter", "silent"])

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 15), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()

        // The question. Under `-voice stub` it is still being read, and the
        // record button answers it, as it does for somebody who answers
        // before the voice has finished.
        XCTAssertTrue(
            app.buttons["Riittää tältä erää"].waitForExistence(timeout: 30),
            "the telling ended somewhere other than its first question"
        )
        app.buttons["Aloita kertominen"].tap()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the answer never started recording"
        )

        // Well short of the limit it is still listening: a pause to remember
        // is not the end of an answer.
        Thread.sleep(forTimeInterval: 15)
        XCTAssertTrue(app.staticTexts["Kuuntelen"].exists, "a silent answer was ended long before its limit")

        // Then, with nothing pressed, the result — and no further question.
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 45),
            "a silent answer never ended: the microphone the loop opened is still open"
        )
        XCTAssertFalse(app.buttons["Riittää tältä erää"].exists, "the conversation went on to another question")
        XCTAssertFalse(app.images["Luen kysymyksen ääneen"].exists, "the voice went on after the conversation ended")

        // Kaarina is the answer's own name (`StubTranscriptionService.samples[1]`),
        // so the answer the silence ended was kept; Aino and Toivo are the
        // telling's. All of them wait to be confirmed (rule 4).
        for name in ["Kaarina", "Aino", "Toivo"] {
            reach(app.buttons["Vahvista \(name)"], in: app, "the name \(name), to confirm")
        }
    }

    /// The same silence as a reply with no words in it. Until 27 Sep 2026
    /// that ended the conversation on "Äänesi on tallessa", with none of the
    /// names the telling had heard on that screen. `-answer wordless` empties
    /// the answer and only the answer. The Worker does not send this reply
    /// today: it answers a silence 502 (`openrouter.ts`), which still ends
    /// the conversation on "Äänesi on tallessa".
    func testAWordlessAnswerLandsOnTheRoundsBeforeIt() {
        let app = launch(["-seed", "empty", "-voice", "stub", "-answer", "wordless"])

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 15), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()

        XCTAssertTrue(
            app.buttons["Riittää tältä erää"].waitForExistence(timeout: 30),
            "the telling ended somewhere other than its first question"
        )
        app.buttons["Aloita kertominen"].tap()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the answer never started recording"
        )
        Thread.sleep(forTimeInterval: 2)
        app.buttons["Lopeta kertominen"].tap()

        // The result the telling made, as "Riittää tältä erää" would have
        // left it, and not the screen for a recording whose text is waiting.
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "a wordless answer did not land on the result the telling made"
        )
        XCTAssertFalse(app.staticTexts["Äänesi on tallessa"].exists, "a wordless answer stood for the conversation")
        XCTAssertFalse(app.buttons["Riittää tältä erää"].exists, "the conversation went on to another question")
        reach(app.buttons["1950-luku"], in: app, "the decade the telling named")
        for name in ["Aino", "Toivo"] {
            reach(app.buttons["Vahvista \(name)"], in: app, "the name \(name), to confirm")
        }
    }

    /// The first telling is never cut, however quiet: whoever pressed record
    /// can press stop, and a long pause to remember is part of a story.
    func testASilentTellingIsNeverCut() {
        let app = launch(["-seed", "empty", "-voice", "stub", "-meter", "silent"])

        let record = app.buttons["Aloita kertominen"]
        XCTAssertTrue(record.waitForExistence(timeout: 15), "never arrived: the record button")
        record.tap()
        allowTheMicrophone()
        XCTAssertTrue(
            app.staticTexts["Kuuntelen"].waitForExistence(timeout: 15),
            "the recording never started — is the microphone denied on this simulator?"
        )

        // An answer in the conversation would have ended at 25 seconds.
        Thread.sleep(forTimeInterval: 35)
        XCTAssertTrue(app.staticTexts["Kuuntelen"].exists, "the first telling was ended by its silence")

        // Stopped by hand, it is a telling like any other: kept, and on to
        // its first question.
        app.buttons["Lopeta kertominen"].tap()
        XCTAssertTrue(
            app.buttons["Riittää tältä erää"].waitForExistence(timeout: 30),
            "the quiet telling did not go on to its question"
        )
    }

    /// Scrolls until the element is there, and then insists that it is. A
    /// result at this length is taller than the phone, and a lazy stack does
    /// not build what nobody can see.
    private func reach(_ element: XCUIElement, in app: XCUIApplication, _ what: String) {
        for _ in 0 ..< 6 where !element.exists { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "never arrived: \(what)")
    }

    /// Answers the microphone prompt if a fresh simulator raises one.
    private func allowTheMicrophone() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 3) else { return }
        let buttons = alert.buttons
        guard buttons.count > 0 else { return }
        buttons.element(boundBy: buttons.count - 1).tap()
    }
}
