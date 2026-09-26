import XCTest

/// *Tämä olen minä* on the person card (26 Sep 2026): the way a member linked
/// to no card says which card is theirs.
///
/// The founder's card is made and linked as the family is created, and an
/// invitation made for somebody links its joiner as they arrive — but an
/// invitation made for nobody in particular left its joiner with no card, no
/// word in the tree, and no way to get one: `Session.linkMe` had one caller,
/// and it was the sync engine. These tests press the row itself, on the seeded
/// family whose phone is nobody yet (`-you none`), which has no server behind
/// it — so a tap walks the waiting road for real, exactly as a phone with no
/// network does, and the card reads *Tämä olet sinä* over the sentence that
/// says the mark is on its way.
final class OwnCardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Eeva's card on a phone that is nobody yet, opened by its own door.
    private func eevasCard(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Eeva"].waitForExistence(timeout: 10), "Eeva's card did not open")
    }

    /// The row on a card that offers to be this phone's, marked, unmarked and
    /// marked again — and no row on the card that is then somebody else's.
    ///
    /// The unmarking here clears a card that is only waiting, which needs no
    /// server: the row goes back to the offer and no sentence is left under
    /// it. Marking it again puts the offer's answer back, so the road does
    /// not depend on the order it is walked in.
    func testTheRowMarksAndUnmarksThePhoneOwner() {
        let app = launch([
            "-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-eeva", "-you", "none",
        ])
        eevasCard(app)

        let offer = app.buttons["Tämä olen minä"]
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the card does not offer to be this phone's")
        XCTAssertFalse(app.buttons["Tämä olet sinä"].exists, "the card is already somebody's")
        offer.tap()

        // It asks first: nothing else changes the link, and a slip stayed for
        // good until this row existed.
        let question = app.alerts["Merkitäänkö tämä sinuksi?"]
        XCTAssertTrue(question.waitForExistence(timeout: 10), "the row did not ask before marking")
        question.buttons["Merkitse"].tap()

        let own = app.buttons["Tämä olet sinä"]
        XCTAssertTrue(own.waitForExistence(timeout: 10), "the card did not become this phone's")
        XCTAssertFalse(offer.exists, "the offer is still there on one's own card")
        // The seeded family has no server, so the mark is waiting — and the
        // card says so rather than reading as done.
        XCTAssertTrue(
            app.staticTexts["Merkintä lähtee itsestään, kun yhteys palaa."].waitForExistence(timeout: 10),
            "a mark that is only waiting reads as made"
        )

        // Taken back: a card only waiting is simply no longer waiting.
        own.tap()
        let undo = app.alerts["Poistetaanko merkintä?"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "the row did not ask before unmarking")
        undo.buttons["Poista merkintä"].tap()
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "the offer did not come back")
        XCTAssertFalse(own.exists, "the card is still this phone's after the mark was taken back")
        XCTAssertFalse(
            app.staticTexts["Merkintä lähtee itsestään, kun yhteys palaa."].exists,
            "the waiting sentence outlived the mark"
        )
        XCTAssertFalse(
            app.staticTexts["Merkintää ei voitu poistaa. Yritä uudelleen, kun yhteys on."].exists,
            "clearing a waiting mark claimed to need the server"
        )

        // And marked again, the same way.
        offer.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 10), "the row did not ask the second time")
        question.buttons["Merkitse"].tap()
        XCTAssertTrue(own.waitForExistence(timeout: 10), "the card did not become this phone's again")

        // Back on the list, Kalle's card: this phone is somebody now, so
        // nobody else's card offers.
        app.navigationBars["Eeva"].buttons.firstMatch.tap()
        let kalle = app.staticTexts["Kalle"].firstMatch
        XCTAssertTrue(kalle.waitForExistence(timeout: 10), "the people list did not come back")
        kalle.tap()
        XCTAssertTrue(app.navigationBars["Kalle"].waitForExistence(timeout: 10), "Kalle's card did not open")
        XCTAssertTrue(app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10), "Kalle's card")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "a second card was offered while one is waiting")
        XCTAssertFalse(app.buttons["Tämä olet sinä"].exists, "Kalle's card reads as this phone's")
    }

    /// Where the row is not offered: on a phone kept to itself, which has no
    /// server to tell; on a card another member already is; and on a name the
    /// recognition heard that nobody has checked (rule 4).
    func testTheRowIsNotOfferedWhereItCannotBeRight() {
        // No family at all: the archive is this phone's alone.
        var app = launch(["-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-eeva"])
        eevasCard(app)
        XCTAssertTrue(app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10), "Eeva's card")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "a phone with no family was offered a card")
        XCTAssertFalse(app.buttons["Tämä olet sinä"].exists, "a phone with no family reads as somebody")

        // Kalle's card is Ville's already.
        app = launch([
            "-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-kalle",
            "-you", "none", "-theirs", "demo-kalle",
        ])
        XCTAssertTrue(app.navigationBars["Kalle"].waitForExistence(timeout: 10), "Kalle's card did not open")
        XCTAssertTrue(app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10), "Kalle's card")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "another member's card was offered")
        XCTAssertFalse(app.buttons["Tämä olet sinä"].exists, "another member's card reads as this phone's")

        // Aino is a name heard and not checked.
        app = launch([
            "-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-aino", "-you", "none",
        ])
        XCTAssertTrue(app.navigationBars["Aino"].waitForExistence(timeout: 10), "Aino's card did not open")
        XCTAssertTrue(app.buttons["Kerro tästä muisto"].waitForExistence(timeout: 10), "Aino's card")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "a name nobody has checked was offered as one's own")
        XCTAssertFalse(app.buttons["Tämä olet sinä"].exists, "a name nobody has checked reads as this phone's")
    }

    /// A card the server holds as this phone's — the founder's, or the one
    /// an invitation named — reads *Tämä olet sinä* with no waiting sentence,
    /// and taking the mark back needs the server: the seeded family has none,
    /// so nothing changes and the card says so.
    func testAnOwnCardOnTheServerIsUnmarkedOnlyThroughTheServer() {
        let app = launch([
            "-seed", "related", "-tab", "people", "-screen", "person", "-person", "demo-eeva", "-you", "demo-eeva",
        ])
        eevasCard(app)

        let own = app.buttons["Tämä olet sinä"]
        XCTAssertTrue(own.waitForExistence(timeout: 10), "one's own card does not say so")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "one's own card was offered again")
        XCTAssertFalse(
            app.staticTexts["Merkintä lähtee itsestään, kun yhteys palaa."].exists,
            "a card the server holds reads as waiting"
        )

        own.tap()
        let undo = app.alerts["Poistetaanko merkintä?"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "the row did not ask before unmarking")
        undo.buttons["Poista merkintä"].tap()

        XCTAssertTrue(
            app.staticTexts["Merkintää ei voitu poistaa. Yritä uudelleen, kun yhteys on."].waitForExistence(timeout: 10),
            "a mark the server could not be asked to remove was reported gone"
        )
        XCTAssertTrue(own.exists, "the card stopped being this phone's without the server")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "the offer came back without the server")

        // Kalle's card on the same phone: somebody else's, so no row.
        app.navigationBars["Eeva"].buttons.firstMatch.tap()
        let kalle = app.staticTexts["Kalle"].firstMatch
        XCTAssertTrue(kalle.waitForExistence(timeout: 10), "the people list did not come back")
        kalle.tap()
        XCTAssertTrue(app.navigationBars["Kalle"].waitForExistence(timeout: 10), "Kalle's card did not open")
        XCTAssertFalse(app.buttons["Tämä olen minä"].exists, "a second card was offered to a phone that is somebody")
        XCTAssertFalse(app.buttons["Tämä olet sinä"].exists, "Kalle's card reads as this phone's")
    }
}
