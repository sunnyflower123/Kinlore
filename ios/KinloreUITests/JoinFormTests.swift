import UIKit
import XCTest

/// The screen an 80-year-old reaches on her own, from a link, with nobody
/// beside her — and the two things that used to stand between her and the
/// family: a paste gesture and a keyboard.
///
/// Both are the same argument. The invitation arrives inside a message; getting
/// the code out of it and a name into the form were the only two acts on this
/// path that needed hands this audience does not have. Neither failure is loud:
/// a code that never got pasted looks like an empty field, and a name field that
/// blocks the button looks like an app that will not let you in.
final class JoinFormTests: XCTestCase {
    /// Pasting the whole invitation, which is what a paste button will be given.
    ///
    /// Selecting one line out of a message is a finer gesture than selecting the
    /// message, so the message is what arrives — and the field has to find the
    /// code in it rather than answering the easy gesture with "invalid_invite".
    /// The text here is the app's own `InviteShareButton.inviteText`, extra line
    /// and all, because that is the string being pasted in real life.
    func testPastingTheWholeInvitationFindsTheCode() {
        let code = "AbCdEf1234567890123456#a2V5LWZvci10ZXN0aW5n"
        UIPasteboard.general.string = """
        Liity perheen muistoarkistoon:
        kinlore://join?code=\(code)

        Tarvitset iPhonen ja Kinloren. Puhelin voi kysyä englanniksi luvan avata Kinlore — vastaa "Open".

        Tai avaa sovellus ja liitä tämä koodi:
        \(code)
        """

        let app = launch([], api: "http://127.0.0.1:9")
        let join = app.buttons["Liity kutsulinkillä"]
        XCTAssertTrue(join.waitForExistence(timeout: 10), "never arrived: the way into joining")
        join.tap()

        // By identifier, because the label is iOS's own and follows the
        // simulator's language rather than the app's.
        let paste = app.buttons["invite-code-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10), "never arrived: the paste button")
        paste.tap()

        let field = app.textFields["Kutsukoodi"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the code field")
        XCTAssertEqual(
            field.value as? String,
            code,
            "the paste put the whole message in the field instead of the code"
        )
    }

    /// The name stopped being required, and this is the assertion that keeps it
    /// that way: the invitation carries a name (`invite.display_name`), so
    /// demanding one here is the app insisting she type something it has already
    /// been told.
    ///
    /// What is checked is that the form stops asking, not that the join
    /// succeeds — there is no Worker on this port and there must not be.
    func testJoiningDoesNotDemandAName() {
        let app = launch([], api: "http://127.0.0.1:9")
        let join = app.buttons["Liity kutsulinkillä"]
        XCTAssertTrue(join.waitForExistence(timeout: 10), "never arrived: the way into joining")
        join.tap()

        let field = app.textFields["Kutsukoodi"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the code field")
        field.tap()
        field.typeText("AbCdEf1234567890123456")

        app.buttons["Liity perheeseen"].tap()

        XCTAssertFalse(
            app.staticTexts["Kirjoita ensin nimesi."].waitForExistence(timeout: 3),
            "the join form still demands a name it does not need"
        )
    }

    /// And the code still is required, because nothing but her can supply it.
    /// A form that asks for nothing would let somebody press the one button on
    /// the screen and be told only that the network failed.
    func testJoiningStillAsksForTheCode() {
        let app = launch([], api: "http://127.0.0.1:9")
        let join = app.buttons["Liity kutsulinkillä"]
        XCTAssertTrue(join.waitForExistence(timeout: 10), "never arrived: the way into joining")
        join.tap()

        let button = app.buttons["Liity perheeseen"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "never arrived: the join button")
        button.tap()

        XCTAssertTrue(
            app.staticTexts["Liitä vielä saamasi kutsukoodi."].waitForExistence(timeout: 5),
            "an empty form said nothing about what is missing"
        )
    }
}
