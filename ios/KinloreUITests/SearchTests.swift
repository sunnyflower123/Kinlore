import XCTest

/// Finding one memory in an archive that has worked.
///
/// The search looks in what was *told*, not only in titles. A photograph has no
/// title until somebody says something about it, so a search over titles would
/// find least on exactly the archive that most needs finding — and what a person
/// remembers is "the one about the cottage", never a name nobody gave it.
final class SearchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The field sits above the list until somebody pulls down, which is the
    /// bargain: the grandchild finds it, grandmother never meets it.
    private func search(_ text: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        for _ in 0 ..< 3 where !field.exists { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 10), "never arrived: the search field")
        field.tap()
        field.typeText(text)
    }

    func testAPersonIsFoundByWhatWasToldAboutThem() {
        let app = launch(["-seed", "archive", "-tab", "people"])
        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 10), "the people list")

        // A word from Eeva's memory and from nobody else's. Her name is not in
        // it, which is the whole point of the test.
        search("naapurissa", in: app)

        XCTAssertTrue(app.staticTexts["Eeva"].waitForExistence(timeout: 5), "the search lost the person it should find")
        XCTAssertFalse(app.staticTexts["Kalle"].exists, "the search kept somebody it should not")
    }

    func testTheGalleryFindsAPhotoByItsStory() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        XCTAssertTrue(app.navigationBars["Muistot"].waitForExistence(timeout: 10), "the gallery")

        search("soudettiin", in: app)

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        XCTAssertTrue(
            photo.waitForExistence(timeout: 5),
            "the photo whose story contains the word was not found"
        )
    }

    /// A search that finds nothing is a different emptiness from an archive
    /// nobody has filled, and it must not offer the invitation meant for the
    /// second one.
    func testNothingFoundSaysSoInItsOwnWords() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        XCTAssertTrue(app.navigationBars["Muistot"].waitForExistence(timeout: 10), "the gallery")

        search("traktori", in: app)

        XCTAssertTrue(
            app.staticTexts["Ei osumia"].waitForExistence(timeout: 5),
            "a fruitless search did not say so"
        )
        XCTAssertFalse(
            app.staticTexts["Ei vielä kuvia"].exists,
            "a fruitless search offered the empty archive's invitation"
        )
    }
}
