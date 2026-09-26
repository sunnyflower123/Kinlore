import XCTest

/// The facts on a person's card (docs/ARCHITECTURE.md §26), through the
/// sheet a person writes them with.
///
/// Every assertion reads the row by its spoken label — *"Syntynyt, 1930-luku,
/// Puumala"* — because that label is the fact: the decade stored as a decade
/// (rule 5), the place as the archive's own card, and the pauses VoiceOver
/// says it with. A row that showed the right words and spoke them run
/// together would fail here, and it should.
final class FactTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A birth in the thirties at Puumala, written by hand: the time through
    /// `DateSheet`'s own rows, the place chosen from the archive's.
    func testABirthWithADecadeAndAPlaceIsWrittenAndReadBack() {
        let app = launch(["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-eeva"])
        let add = app.buttons["Lisää tieto"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "never arrived: the row that adds a fact")
        add.tap()

        let birth = app.buttons["Syntymä"]
        XCTAssertTrue(birth.waitForExistence(timeout: 5), "never arrived: the kinds to choose from")
        birth.tap()

        let when = app.buttons["Lisää ajankohta"]
        XCTAssertTrue(when.waitForExistence(timeout: 5), "never arrived: a birth's parts")
        XCTAssertFalse(app.buttons["Tallenna"].isEnabled, "a birth with neither a time nor a place could be saved")
        when.tap()
        let decade = app.buttons["Vuosikymmen"]
        XCTAssertTrue(decade.waitForExistence(timeout: 5), "never arrived: the date sheet")
        decade.tap()
        let thirties = app.buttons["1930-luku"]
        for _ in 0 ..< 4 where !thirties.exists { app.swipeUp() }
        XCTAssertTrue(thirties.waitForExistence(timeout: 5), "never arrived: the decade to choose")
        thirties.tap()

        let where_ = app.buttons["Valitse paikka"]
        XCTAssertTrue(where_.waitForExistence(timeout: 5), "the date sheet did not hand the answer back")
        XCTAssertTrue(app.buttons["1930-luku"].exists, "the chosen decade is not on the sheet")
        where_.tap()
        let puumala = app.buttons["Puumala"]
        XCTAssertTrue(puumala.waitForExistence(timeout: 5), "never arrived: the archive's places")
        puumala.tap()

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the place sheet did not hand the answer back")
        XCTAssertTrue(save.isEnabled, "a birth with a time and a place cannot be saved")
        save.tap()

        XCTAssertTrue(
            app.buttons["Syntynyt, 1930-luku, Puumala"].waitForExistence(timeout: 5),
            "the fact is not on the card as a decade and the archive's place, spoken with its pauses"
        )
    }

    /// A place the archive does not have yet, made by name from the chooser:
    /// the fact points at the new card, and the card's name is what the row
    /// says.
    func testABirthplaceCanBeANewPlaceMadeByName() {
        let app = launch(["-seed", "archive", "-tab", "people", "-screen", "person", "-person", "demo-eeva"])
        let add = app.buttons["Lisää tieto"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "never arrived: the row that adds a fact")
        add.tap()
        let birth = app.buttons["Syntymä"]
        XCTAssertTrue(birth.waitForExistence(timeout: 5), "never arrived: the kinds to choose from")
        birth.tap()
        let where_ = app.buttons["Valitse paikka"]
        XCTAssertTrue(where_.waitForExistence(timeout: 5), "never arrived: a birth's parts")
        where_.tap()

        let name = app.textFields["Paikan nimi"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "never arrived: the field for a new place")
        let make = app.buttons["Lisää paikka"]
        XCTAssertFalse(make.isEnabled, "a place with no name could be added")
        name.tap()
        name.typeText("Viipuri")
        XCTAssertTrue(make.isEnabled, "a named place cannot be added")
        make.tap()

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the place sheet did not hand the new place back")
        XCTAssertTrue(app.buttons["Viipuri"].exists, "the new place's name is not on the sheet")
        XCTAssertTrue(save.isEnabled, "a birth with a place cannot be saved")
        save.tap()
        XCTAssertTrue(
            app.buttons["Syntynyt, Viipuri"].waitForExistence(timeout: 5),
            "the fact is not on the card with the new place's name"
        )
    }

    /// A fact taken off the card goes, and the others stay. The removal is a
    /// tombstone underneath (`PersonFact.deletedAt`), which is what keeps it
    /// from coming back from another phone; here it is enough that the row
    /// is gone and its neighbours are not.
    func testAFactIsTakenOffTheCardFromItsOwnSheet() {
        let app = launch(["-seed", "facts", "-tab", "people", "-screen", "person", "-person", "demo-eeva"])
        let trade = app.buttons["Ammatti, Kansakoulunopettaja, 1960-luku"]
        XCTAssertTrue(trade.waitForExistence(timeout: 10), "never arrived: the fixture's occupation")
        trade.tap()
        let remove = app.buttons["Poista tieto"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "never arrived: the sheet that changes a fact")
        remove.tap()
        let confirm = app.alerts.buttons["Poista"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "never arrived: the question before a removal")
        confirm.tap()

        XCTAssertTrue(trade.waitForNonExistence(timeout: 5), "the fact is still on the card")
        XCTAssertTrue(app.buttons["Syntynyt, 1930-luku, Puumala"].exists, "the birth went with it")
        XCTAssertTrue(app.buttons["Muu nimi, o.s. Virtanen"].exists, "the other name went with it")
        XCTAssertTrue(app.buttons["Kuollut, 4. helmikuuta 2001"].exists, "the death went with it")
    }

    /// The same rows on an English phone (26 Sep 2026): the kind's word from
    /// the English table, the decade through its key, and the day in the
    /// phone's own date format — so that a card filmed in English does not
    /// say *"Syntynyt"* or *"4. helmikuuta"* in the middle of it. The
    /// language and the locale are given after `launch`'s Finnish pair, and
    /// the later pair is the one the app reads.
    func testTheRowsSpeakEnglishOnAnEnglishPhone() {
        let app = launch([
            "-seed", "facts", "-tab", "people", "-screen", "person", "-person", "demo-eeva",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ])
        XCTAssertTrue(app.buttons["Born, 1930s, Puumala"].waitForExistence(timeout: 10), "never arrived: the birth in English")
        XCTAssertTrue(app.buttons["Died, February 4, 2001"].exists, "the death is not in the phone's own date format")
        XCTAssertTrue(app.buttons["Occupation, Kansakoulunopettaja, 1960s"].exists, "the trade's decade is not in English")
        XCTAssertTrue(app.buttons["Add a fact"].exists, "the row that adds a fact is not in English")
    }
}
