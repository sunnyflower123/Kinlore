import XCTest

/// The demo video's one scene no other test pins.
///
/// docs/VIDEO.md maps every scene of the demo video (docs/UX.md §10) to launch
/// arguments, so that filming night is filming and not debugging. Scenes 1, 2,
/// 3 and 5 ride states other tests already cover — the fork, the result
/// screen, the offer slot, the arrival. What nothing covered is the fourth
/// scene's opening, the return: the app opening onto "Uutta perheeltä", and a
/// family member's question waiting on the Tell screen to be answered aloud.
/// The fixture question behind it exists for exactly that scene (MemoryStore,
/// the unseen branch) — this is the test that reddens if filming night would
/// have met an empty screen instead.
final class VideoSceneTests: XCTestCase {
    func testTheReturnSceneIsFilmable() {
        let app = launch(["-seed", "unseen"])

        // The return opens on Muistot by itself: an unseen telling is the
        // reason the first tab is not Kerro this once.
        XCTAssertTrue(
            app.staticTexts["Uutta perheeltä"].waitForExistence(timeout: 15),
            "the landing did not open on Uutta perheeltä"
        )

        // And the Tell screen holds Mummo's question, ready to be answered.
        app.tabBars.buttons["Kerro"].tap()
        let asker = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Mummo kysyy"))
            .firstMatch
        XCTAssertTrue(
            asker.waitForExistence(timeout: 10),
            "the family question is not offered on the Tell screen"
        )
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "Kuka souti veneen"))
                .firstMatch.exists,
            "the offer does not carry the question itself"
        )
    }
}
