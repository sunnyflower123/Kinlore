import XCTest

/// The card on the Kerro tab.
///
/// The screen it replaced said *"Kerro mitä muistat"* over a button, which is
/// a blank page — and a blank page is the most reliable way there is to get
/// nothing from somebody who does not believe they remember anything worth
/// saying. What the deck does is answer *which card*, out of state the app
/// already had; what it must never do is trap her on one she cannot answer.
final class DeckTests: XCTestCase {
    /// A photograph she does not recognise has to have a way past it, and the
    /// deck has to know when to stop offering them.
    ///
    /// **This is the failure mode the whole idea has to be designed against,
    /// and it is silent:** nothing crashes, she simply meets a run of pictures
    /// she cannot place and concludes that an app built to tell her she
    /// remembers a great deal has decided otherwise. `Deck.patience` is three
    /// per session — the ladder already holds the same opinion in numbers, one
    /// strained answer for a whole level, because for this user one wall costs
    /// more than a run of easy questions.
    ///
    /// Written this way rather than counting cards on purpose: what the
    /// archive holds is the fixture's business and may change, but three
    /// pushes ending it is the promise.
    func testTheDeckStopsOfferingAfterThreePushesAside() {
        let app = launch(["-seed", "deck"])

        XCTAssertTrue(
            app.staticTexts["Kuka tässä kuvassa on?"].waitForExistence(timeout: 15),
            "never arrived: the card"
        )

        // Three, which is `Deck.patience` — the app target's constant is not
        // visible from here, so the number is written out and this sentence is
        // what couples them.
        for push in 1 ... 3 {
            let skip = app.buttons["En muista tätä"]
            XCTAssertTrue(
                skip.waitForExistence(timeout: 10),
                "the deck stopped offering after \(push - 1) pushes, before its patience ran out"
            )
            skip.tap()
        }

        XCTAssertTrue(
            app.staticTexts["Kerro mitä muistat"].waitForExistence(timeout: 10),
            "the deck went on offering cards past its patience"
        )
        XCTAssertFalse(
            app.buttons["En muista tätä"].exists,
            "a way past a card that is no longer offered"
        )
    }

    /// A question somebody in the family asked outranks any card.
    ///
    /// *"Mummo kysyy"* turns a prompt into a request from a person, which is
    /// the strongest pull this app has — and the deck can hide it without
    /// breaking anything visible: giving the screen a subject makes it offer
    /// *that subject's* questions, and the family's question about something
    /// else quietly stops being on screen. It did, for one commit, and only
    /// `VideoSceneTests` noticed because the demo video's fourth scene is that
    /// question being answered aloud. This says it in its own words so the
    /// rule does not depend on a film.
    func testAFamilyQuestionOutranksTheDeck() {
        let app = launch(["-seed", "unseen"])

        app.tabBars.buttons["Kerro"].tap()

        XCTAssertTrue(
            app.staticTexts["Mummo kysyy"].waitForExistence(timeout: 15),
            "the family's question is not offered on the Tell screen"
        )
        XCTAssertFalse(
            app.buttons["En muista tätä"].exists,
            "the deck stepped over a question a person asked"
        )
    }

    /// And the blank button is still what an empty archive gets. The deck adds
    /// a card where there is something to ask about; where there is nothing it
    /// must add nothing at all — including its own way past.
    func testAnEmptyArchiveKeepsTheBlankButton() {
        let app = launch(["-seed", "empty"])

        XCTAssertTrue(
            app.staticTexts["Kerro mitä muistat"].waitForExistence(timeout: 15),
            "never arrived: the Tell screen"
        )
        XCTAssertFalse(
            app.buttons["En muista tätä"].exists,
            "an empty archive offered a way past a card it does not have"
        )
    }
}
