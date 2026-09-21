import XCTest

/// The face on a person's card (21 Sep 2026, ARCHITECTURE §25): chosen from a
/// photograph of the archive by tapping the face in it, drawn as a disc on
/// the card, the list and the tree, and taken off again from the same place.
///
/// The disc itself is hidden from the accessibility tree — `SubjectAvatar`
/// hides every avatar, because the name is in the row beside it — so these
/// read the card's own words: the row offers to choose a face until there is
/// one and to change it after, and that flip is the only thing on screen
/// that says which state the card is in.
final class FaceTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// From Eeva's card: Valitse kasvot, the archive's one photograph, a tap
    /// on the face in it, Tallenna — and the card offers to change the face
    /// rather than to choose one.
    func testAFaceIsChosenFromAPhotographByTappingIt() {
        let app = launch(["-seed", "faces", "-tab", "people", "-screen", "person", "-person", "demo-eeva"])
        let choose = app.buttons["Valitse kasvot"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "the row that chooses a face")
        choose.tap()

        let tile = app.buttons["Valokuva"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "the photograph is not offered")
        tile.tap()

        let picture = app.images.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva. Kasvot")
        ).firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 10), "the photograph to tap the face in")
        // The dark shape `demoPhotoFile` draws, a little above its middle.
        picture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()

        let save = app.buttons["Tallenna"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no way to save the face")
        XCTAssertTrue(save.isEnabled, "the save button is disabled after a tap on the picture")
        save.tap()

        XCTAssertTrue(app.buttons["Vaihda kasvot"].waitForExistence(timeout: 10), "the card does not say it has a face")
        XCTAssertFalse(app.buttons["Valitse kasvot"].exists, "the card still offers to choose a face it has")
    }

    /// Kalle's card, which the fixture gives a face: Vaihda kasvot, Poista
    /// kasvot — and the row offers to choose one again. Nothing else is
    /// asked, because nothing is deleted: the photograph stays.
    func testAFaceIsTakenOffTheCardFromTheSameRow() {
        let app = launch(["-seed", "faces", "-tab", "people", "-screen", "person", "-person", "demo-kalle"])
        let change = app.buttons["Vaihda kasvot"]
        XCTAssertTrue(change.waitForExistence(timeout: 10), "Kalle's card does not say it has a face")
        change.tap()

        let remove = app.buttons["Poista kasvot"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "no way to take the face off")
        remove.tap()

        XCTAssertTrue(app.buttons["Valitse kasvot"].waitForExistence(timeout: 10), "the card still says it has a face")
        XCTAssertFalse(app.buttons["Vaihda kasvot"].exists, "the row still offers to change a face that is gone")
    }
}
