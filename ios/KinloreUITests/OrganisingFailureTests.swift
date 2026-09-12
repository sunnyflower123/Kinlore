import XCTest

/// What is left when the organising fails.
///
/// By the time extraction is asked for, the expensive half of the pipeline has
/// already run and been paid for. This branch used to answer a failure by ending
/// the telling: neither `save` nor `saveAudioOnly` ran, the recording was left in
/// the temporary directory, and "Voit yrittää uudelleen" meant saying the whole
/// memory over again. Rule 3 says the original is always kept, and this was the
/// one branch that did not keep it.
///
/// So what is checked is the archive, not a screen: after a failed organising the
/// telling has to be in it. `-defer structure` is what makes the situation
/// reachable at all — it needs transcription to succeed and extraction to fail at
/// the same moment, which cannot be arranged by hand.
final class OrganisingFailureTests: XCTestCase {
    func testAFailedOrganisingStillKeepsTheTelling() {
        // `-screen interview` runs a canned telling through the pipeline by
        // itself. Used here for the hands, not for the interview: with the
        // organising failing there are no follow-up questions, so the loop ends
        // where the telling is saved — which is the part being checked. Typing
        // it by hand would only add a keyboard to the things that can flake.
        let app = launch(["-seed", "empty", "-defer", "structure", "-screen", "interview"])

        XCTAssertTrue(
            app.staticTexts["Muisto tallennettu"].waitForExistence(timeout: 30),
            "the telling was lost when the organising failed"
        )

        // The screen admits what did not happen. Without this an unorganised
        // result reads as "the AI read it and found nobody in it", which is a
        // different and untrue thing.
        XCTAssertTrue(
            app.staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@", "En saanut järjesteltyä"))
                .firstMatch
                .exists,
            "the result screen did not say that the organising failed"
        )

        // The words themselves, in the teller's own order. "Kuopiossa" is from
        // the sample `-screen interview` types as its opening telling — the
        // last one, since the recorded rounds rotate from the first.
        XCTAssertTrue(
            app.staticTexts
                .containing(NSPredicate(format: "label CONTAINS %@", "Kuopiossa"))
                .firstMatch
                .exists,
            "the telling is not on the result screen"
        )

        // And in the archive rather than only on the screen that just made it.
        // An untitled home subject is what an unorganised memory gets — there is
        // no place and no year to name it after — and it is listed as such.
        app.tabBars.buttons["Muistot"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Kerrottu ")).firstMatch.waitForExistence(timeout: 10),
            "the memory is not in the archive"
        )
    }
}
