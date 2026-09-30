import XCTest

/// Who the archive says told a memory.
///
/// The author is the phone and the teller is the voice. They are one person on
/// a sofa and two the moment a phone goes round a table — the room this app
/// came out of (PLAN.md §8) — and until 19 Sep 2026 every telling made on one
/// phone was filed under its owner with nothing anywhere to say otherwise.
///
/// Both ways of getting this wrong are silent. A question that never appears
/// leaves the old behaviour looking correct, because the owner's name is a
/// real name and reads like an answer. And a name withheld that still shows up
/// somewhere is worse than never having offered to withhold it: the promise is
/// made on the result screen and kept, or not, on a row three taps away that
/// nobody looks at again.
final class TellerTests: XCTestCase {
    /// A teller who is not the phone's owner, typed in because a person spoken
    /// of for the first time has no card yet — which is the usual case at a
    /// table.
    func testATypedTellerFollowsTheTellingToItsCard() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result"
        )
        XCTAssertTrue(
            app.staticTexts["Kuka kertoi tämän muiston?"].exists,
            "the result screen did not ask who told it"
        )

        app.buttons["Joku muu"].tap()
        let someoneNew = app.buttons["Joku uusi"]
        XCTAssertTrue(someoneNew.waitForExistence(timeout: 10), "never arrived: the family's people")
        someoneNew.tap()

        // Not `textFields.firstMatch`, which is what the add-a-person test
        // three files away can afford and this one cannot: the result screen
        // behind this sheet is *made* of text fields — every heard name sits
        // in one, and the tree under this app carried three of them, reading
        // *"Puumalassa"*, *"Aino"* and *"Toivo"*, above the sheet's own. All
        // four share the placeholder *"Nimi"*; only the empty one has no
        // value, which is what tells them apart.
        let field = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@ AND (value == %@ OR value == nil)", "Nimi", "")
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the name field")
        field.tap()
        field.typeText("Mummo")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.staticTexts["Tämän muiston kertoi Mummo"].waitForExistence(timeout: 10),
            "the result screen did not say who it now says told it"
        )

        // And on the card the day after, which is the only place it matters.
        openTheTelling(in: app)
        XCTAssertTrue(
            byline(in: app, beginningWith: "Mummo · ").waitForExistence(timeout: 10),
            "the telling is still filed under the phone's owner"
        )
    }

    /// A teller who would rather not be named. The day stands where the name
    /// would have been — and the owner's name must not quietly take its place,
    /// which is what a fallback to the author would do.
    func testAWithheldNameIsNowhereOnTheCard() {
        let app = launch(["-seed", "empty", "-screen", "result"])
        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result"
        )

        app.buttons["En halua nimeäni näkyviin"].tap()
        XCTAssertTrue(
            app.staticTexts["Nimeä ei näytetä tämän muiston vieressä."].waitForExistence(timeout: 10),
            "the screen did not say the name is withheld"
        )

        openTheTelling(in: app)
        XCTAssertFalse(
            byline(in: app, beginningWith: "Minä · ").exists,
            "the withheld name was replaced by the phone's owner"
        )
    }

    /// *"That's me"*: the teller of a photograph's telling put among its
    /// people by the one hand that knows. The words are not a name, so the
    /// telling never names them, and until 21 Sep 2026 nothing else did —
    /// the card said who told it and the photograph went on not knowing.
    ///
    /// Both halves of the promise, because each is silent when broken: the
    /// row that places them, and the teller's own card, which is where a
    /// family finds the photographs somebody is in.
    func testATellerWhoSaysTheyAreInThePhotoIsPlacedInIt() {
        let app = tellAboutAPhoto()

        app.buttons["Joku muu"].tap()
        addSomeoneNew(named: "Mummo", in: app)

        let place = app.buttons["Mummo on tässä kuvassa"]
        XCTAssertTrue(place.waitForExistence(timeout: 10), "the card did not offer to place the teller in the photo")
        place.tap()
        let placed = app.staticTexts["Mummo on merkitty tämän kuvan ihmisiin."]
        XCTAssertTrue(placed.waitForExistence(timeout: 10), "the card did not say the teller is in the photo")

        // Taken back, the offer returns: the row is an answer, and answers here
        // can be changed.
        app.buttons["Poista merkintä"].tap()
        XCTAssertTrue(place.waitForExistence(timeout: 10), "taking it back did not bring the offer back")
        place.tap()
        XCTAssertTrue(placed.waitForExistence(timeout: 10), "placing the teller a second time did nothing")

        // And on Mummo's own card, which is the only place it matters.
        app.buttons["Valmis"].tap()
        app.tabBars.buttons["Sukupuu"].tap()
        let mummo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mummo")).firstMatch
        XCTAssertTrue(mummo.waitForExistence(timeout: 10), "never arrived: Mummo in the family's people")
        mummo.tap()
        XCTAssertTrue(
            app.staticTexts["Mainittu muualla yhdessä muistossa"].waitForExistence(timeout: 10),
            "the teller's card does not know the photograph they are in"
        )
    }

    /// A withheld name is never offered for the photograph: placed in it, the
    /// name would stand on the photograph's tellings, which is exactly what
    /// the teller asked it not to do.
    func testAWithheldTellerIsNotOfferedForThePhoto() {
        let app = tellAboutAPhoto()

        app.buttons["En halua nimeäni näkyviin"].tap()
        XCTAssertTrue(
            app.staticTexts["Nimeä ei näytetä tämän muiston vieressä."].waitForExistence(timeout: 10),
            "the screen did not say the name is withheld"
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "tässä kuvassa")).firstMatch.exists,
            "a withheld teller was offered for the photograph"
        )
    }

    /// Both states of the new row audited at the largest text size, where a
    /// name as long as a Finnish one and the sentence after it are two lines
    /// each (rule 1). The default size is the two tests above, which read
    /// every word of it.
    func testThePhotoRowAtTheLargestSize() throws {
        let app = tellAboutAPhoto(textSize: "UICTContentSizeCategoryAccessibilityXXXL")

        scrollTo(app.buttons["Joku muu"], in: app).tap()
        addSomeoneNew(named: "Mummo", in: app)

        let place = scrollTo(app.buttons["Mummo on tässä kuvassa"], in: app)
        try audit(app, "the offer to place the teller, largest text size", alsoAllowing: Self.answeredLine)
        place.tap()
        scrollTo(app.buttons["Poista merkintä"], in: app)
        try audit(app, "the teller placed in the photo, largest text size", alsoAllowing: Self.answeredLine)
    }

    /// One finding this test did not bring and does not own. The card's
    /// answered line, *"Tämän muiston kertoi Mummo"*, reports "Contrast
    /// failed" at the largest size **at HEAD `746dd9c` too, without the row
    /// this test is about** — A/B'd 21 Sep 2026 in two worktrees on one
    /// private simulator, red 2/2 at HEAD and 4/5 with the row. Its pixels
    /// measure 20.18:1, black on the card's cream, so what the audit is
    /// judging is still open; it is exempted by its exact words and nothing
    /// wider, so the new row itself stays audited.
    private static let answeredLine: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
        issue.auditType == .contrast
            && (issue.element?.label.hasPrefix("Tämän muiston kertoi") ?? false)
    }

    /// A typed telling about the demo archive's first photograph, left on the
    /// result screen with the teller question unanswered.
    private func tellAboutAPhoto(textSize: String? = nil) -> XCUIApplication {
        let app = launch(["-seed", "archive", "-tab", "memories"], textSize: textSize)
        let tile = scrollTo(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Valokuva")).firstMatch,
            in: app
        )
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "never arrived: a photo in the gallery")
        tile.tap()

        let tell = scrollTo(app.buttons["Kerro tästä muisto"], in: app)
        XCTAssertTrue(tell.waitForExistence(timeout: 10), "never arrived: the photo's card")
        tell.tap()
        let write = app.buttons["Kirjoita sen sijaan"]
        XCTAssertTrue(write.waitForExistence(timeout: 10), "never arrived: the way to write it")
        write.tap()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "never arrived: the editor")
        editor.typeText("Tässä olen minä rannassa, kesällä.")
        app.buttons["Tallenna"].tap()

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "never arrived: the result"
        )
        return app
    }

    /// Scrolls until the element is there. At the largest text size a list
    /// does not build the rows nobody can see, so below the fold is not merely
    /// off screen — it does not exist to be waited for.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0 ..< 6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        // Still, before anything is audited: a list left mid-scroll is sampled
        // moving, and the audit then reports colours nothing drew. Two equal
        // frames a beat apart mean the scroll is over.
        var last = CGRect.null
        for _ in 0 ..< 20 where element.exists && element.frame != last {
            last = element.frame
            Thread.sleep(forTimeInterval: 0.3)
        }
        return element
    }

    /// *"Joku uusi"* behind *"Joku muu"*, with a name typed into it.
    private func addSomeoneNew(named name: String, in app: XCUIApplication) {
        let someoneNew = app.buttons["Joku uusi"]
        XCTAssertTrue(someoneNew.waitForExistence(timeout: 10), "never arrived: the family's people")
        someoneNew.tap()
        // The empty one: the result screen behind the sheet holds a text
        // field for every heard name, all with the same placeholder.
        let field = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@ AND (value == %@ OR value == nil)", "Nimi", "")
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the name field")
        field.tap()
        field.typeText(name)
        app.buttons["Tallenna"].tap()
    }

    /// From the result screen to the telling's own card: a free dictation is
    /// listed under the day it was told (`Subject.displayTitle`), and its card
    /// is where a memory's byline is read.
    private func openTheTelling(in app: XCUIApplication) {
        app.tabBars.buttons["Albumi"].tap()
        let row = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "never arrived: the telling in the gallery")
        row.tap()
    }

    private func byline(in app: XCUIApplication, beginningWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
