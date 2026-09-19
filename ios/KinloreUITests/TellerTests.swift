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
