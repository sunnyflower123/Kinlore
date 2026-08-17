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
}
