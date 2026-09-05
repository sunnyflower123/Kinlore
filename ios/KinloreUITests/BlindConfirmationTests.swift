import XCTest

/// Asking who is in a photograph without saying who the app thinks it is.
///
/// Rule 4 says the AI proposes and a human confirms. The instrument the app had
/// for the second half was a card with the name already written on it, and a
/// card like that gets tapped "yes" without being read — which is the whole
/// problem, because a wrong relationship is worse than a missing one precisely
/// because later nobody remembers it was a guess. Somebody who was never shown
/// the name and arrived at it anyway has genuinely recognised the person.
///
/// **The first test here is the feature.** Every other one checks what an
/// answer does; that one checks that the question was asked blind, and it is
/// the half that fails silently: a card that leaks its answer still looks
/// exactly like a card that works, and it would go on producing confirmations
/// that mean nothing. ARCHITECTURE §13 records the cut round paying for the
/// same lesson through its mask.
final class BlindConfirmationTests: XCTestCase {
    /// The fixture's proposal, its photograph and its decoys. `-seed blind` is
    /// the plain archive with a file on `demo-photo` — the picture is the whole
    /// difference and also the guard, because "who is this?" over a grey
    /// placeholder asks nothing.
    private func card(_ app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts["Kuka tässä on?"].waitForExistence(timeout: 15),
            "never arrived: the blind confirmation"
        )
    }

    /// The one that matters.
    ///
    /// Nothing on the screen may say which of the four names the extraction
    /// proposed — not in a label, not in a caption, and above all not in the
    /// photograph's accessibility label, which is where a leak would reach the
    /// person most likely to be listening rather than looking. That is the door
    /// the cut round's mask had to be a *word* rather than a gap to close.
    /// On a grandparent's phone the Kerro tab is the button and nothing else,
    /// and the card is on Muistot, where she reads. The launch argument is the
    /// answer to "kenen puhelin tämä on".
    func testAGrandparentsPhoneKeepsTheButtonAndReadsTheCardOnMuistot() {
        let app = launch(["-seed", "blind", "-elder.largerText", "YES"])
        XCTAssertTrue(app.buttons["Aloita kertominen"].waitForExistence(timeout: 15), "her Kerro tab did not open on the button")
        XCTAssertFalse(app.staticTexts["Kuka tässä on?"].exists, "the card took her button")
        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(app.staticTexts["Kuka tässä on?"].waitForExistence(timeout: 10), "the card is not on Muistot")
    }

    /// And the reader-flip is hers to be spared: with the family's tellings
    /// unread, her phone still opens on Kerro.
    func testAGrandparentsPhoneOpensOnKerroDespiteNewTellings() {
        let app = launch(["-seed", "unseen", "-elder.largerText", "YES"])
        XCTAssertTrue(app.buttons["Aloita kertominen"].waitForExistence(timeout: 15), "her phone opened somewhere other than the button")
        // Leave the reading debt paid. `-seed unseen` empties the seen list
        // and the list persists across launches, so a test that never opens
        // Muistot hands the next launch — the next test — a reader's phone
        // that opens on Muistot. Measured: the test after this one waited on
        // the Kerro tab's card that was never going to show.
        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(app.staticTexts["Uutta perheeltä"].waitForExistence(timeout: 10), "the reading list did not open")
    }

    func testTheCardNeverSaysWhichNameWasProposed() {
        let app = launch(["-seed", "blind"])
        card(app)

        // All four are offered, and the proposal is one of them.
        for name in ["Aino", "Eeva", "Kalle", "Sanni"] {
            XCTAssertTrue(
                app.buttons[name].exists,
                "the card did not offer \(name), so the choice is not what it claims"
            )
        }

        // The marker the people list uses for a proposal. Its presence here in
        // any form would name the answer.
        XCTAssertFalse(
            app.staticTexts["Ehdotus — vahvista henkilö"].exists,
            "the card marked the proposal"
        )
        for element in app.staticTexts.allElementsBoundByIndex
            + app.buttons.allElementsBoundByIndex
            + app.images.allElementsBoundByIndex
        {
            let label = element.label
            XCTAssertFalse(
                label.localizedCaseInsensitiveContains("ehdotus"),
                "something on the card called a name a proposal: \"\(label)\""
            )
            // The photograph describes what is known and nothing more. A label
            // naming anybody would hand VoiceOver the answer.
            guard label.hasPrefix("Valokuva") else { continue }
            for name in ["Aino", "Eeva", "Kalle", "Sanni"] {
                XCTAssertFalse(
                    label.contains(name),
                    "the photograph's description named \(name)"
                )
            }
        }
    }

    /// A name that matches confirms the person, which is the strongest
    /// confirmation this app can collect.
    func testTheRecognisedNameConfirmsThePerson() {
        let app = launch(["-seed", "blind"])
        card(app)

        // `demo-aino` is the fixture's unconfirmed proposal, and Mummo's is the
        // telling that named her — somebody else's story, because you cannot
        // recognise a face in your own.
        app.buttons["Aino"].tap()

        XCTAssertTrue(
            app.staticTexts["Kiitos. Nyt tiedämme, kuka hän on."].waitForExistence(timeout: 10),
            "a recognition said nothing back"
        )
        app.buttons["Jatka"].tap()

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(
            app.staticTexts["Aino"].waitForExistence(timeout: 10),
            "never arrived: the people list"
        )
        XCTAssertFalse(
            app.staticTexts["Ehdotus — vahvista henkilö"].exists,
            "the person was recognised and is still only a proposal"
        )
    }

    /// A different name confirms nothing — and the app does not call her wrong,
    /// because it does not know who is in the photograph either. Saying so
    /// would be the guess asserted as fact one screen after the entire point
    /// was not asserting it.
    func testAnotherNameConfirmsNothingAndClaimsNothing() {
        let app = launch(["-seed", "blind"])
        card(app)

        app.buttons["Eeva"].tap()

        XCTAssertTrue(
            app.staticTexts["Kiitos. Tämä jää toistaiseksi avoimeksi."]
                .waitForExistence(timeout: 10),
            "a different name got no answer at all"
        )
        // Nothing that ranks her answer, and nothing that names the proposal.
        XCTAssertFalse(app.staticTexts["Aino"].exists, "the app revealed the proposal")
        app.buttons["Jatka"].tap()

        app.tabBars.buttons["Ihmiset"].tap()
        XCTAssertTrue(
            app.staticTexts["Ehdotus — vahvista henkilö"].waitForExistence(timeout: 10),
            "a name that was not recognised confirmed the proposal anyway"
        )
    }

    /// *"En muista"* is an answer, not a refusal.
    ///
    /// It confirms nothing and un-confirms nothing, and it is what stops the
    /// card coming back for ever — which for this user matters more than the
    /// data does: a question that returns every time she cannot answer it is
    /// the app telling her so. §13 had to learn this the same way.
    func testNotRememberingIsAnAnswer() {
        let app = launch(["-seed", "blind"])
        card(app)

        app.buttons["En muista"].tap()

        XCTAssertTrue(
            app.staticTexts["Kiitos. Tämä jää toistaiseksi avoimeksi."]
                .waitForExistence(timeout: 10),
            "not remembering was treated as no answer at all"
        )
        app.buttons["Jatka"].tap()

        // And the card is gone rather than asked again.
        XCTAssertFalse(
            app.staticTexts["Kuka tässä on?"].waitForExistence(timeout: 3),
            "the card came back after she said she did not remember"
        )
    }

    /// And the archive every other test launches into is untouched.
    ///
    /// `demo-photo` carries no file under `-seed archive`, so no card can be
    /// built from it. This is the assertion that keeps a new feature from
    /// moving the furniture under thirty-nine accessibility sweeps — the deck
    /// needed the same one when it was added, for the same reason.
    func testThePlainArchiveOffersNoCard() {
        let app = launch(["-seed", "archive"])

        // The record button and not a title: the plain archive already offers
        // the deck a person card — `demo-aino` is mentioned in Mummo's telling
        // and has no memory of her own, so she is somebody nobody has spoken
        // about — and this test is about the *blind* card, not about which
        // ordinary one the deck deals. Asserting the title was this test
        // failing on a screen that was working, which is the shape of test
        // worth deleting rather than keeping.
        XCTAssertTrue(
            app.buttons["Aloita kertominen"].waitForExistence(timeout: 15),
            "never arrived: the Tell screen"
        )
        XCTAssertFalse(
            app.staticTexts["Kuka tässä on?"].exists,
            "the plain archive grew a card, and every sweep that uses it is now looking at something else"
        )
    }
}
