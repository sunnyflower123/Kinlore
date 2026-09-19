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

    /// The bargain: the grandchild finds the field, grandmother never meets
    /// it. It used to rest on the field sitting above the list until somebody
    /// pulled down; iOS 26 draws it under the title on arrival, so since
    /// 19 Sep 2026 her half is kept by the album carrying no field at all on
    /// a phone with `elder.largerText` set. These tests run on a reader's.
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

    /// The photograph — and, since 19 Sep 2026, the telling itself, listed by
    /// its own words above the photographs. A photograph found by a word
    /// inside its story looked exactly like one found by its title, and the
    /// sentence that matched was on the card two taps away. Both text sizes
    /// and audited, because the row is new and the audit is what reads it.
    func testTheGalleryFindsAPhotoByItsStory() throws {
        for textSize in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = launch(["-seed", "archive", "-tab", "memories"], textSize: textSize)
            XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "the gallery")

            search("soudettiin", in: app)

            let telling = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "soudettiin")
            ).firstMatch
            XCTAssertTrue(
                telling.waitForExistence(timeout: 5),
                "the telling that contains the word was not listed by its words"
            )
            try audit(app, "Albumi, haku, muistot, \(textSize ?? "default")")

            // The photograph is still found — below the tellings, which at
            // XXXL is below the fold, and a grid does not build a tile that is
            // not on screen. Measured 19 Sep 2026: found without a scroll at
            // the default size, not found at XXXL until the screen was moved.
            let photo = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
            ).firstMatch
            for _ in 0 ..< 4 where !photo.exists { app.swipeUp() }
            XCTAssertTrue(
                photo.waitForExistence(timeout: 5),
                "the photo whose story contains the word was not found"
            )
        }

        // A telling about a PERSON lives on her card on the Ihmiset tab and,
        // until 19 Sep 2026, nowhere the album's search could reach. Eeva's
        // is one sentence, and her name is not the word searched for.
        let app = launch(["-seed", "archive", "-tab", "memories"])
        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "the gallery")

        search("naapurissa", in: app)

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "naapurissa")).firstMatch
                .waitForExistence(timeout: 5),
            "a telling about a person was not found from the album"
        )
        XCTAssertFalse(app.staticTexts["Ei osumia"].exists, "a found telling was called no match")
    }

    /// The photograph is found by who and where its story names, not only by
    /// the words. The fixture's telling mentions Puumala and never says the
    /// word: the mention is what the family made of the words — a name
    /// corrected, two cards merged — and until 6 Sep 2026 a photograph was
    /// found by the name that was heard and never by the one that was fixed.
    func testTheGalleryFindsAPhotoByWhoItMentions() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "the gallery")

        search("Puumala", in: app)

        let photo = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Valokuva")
        ).firstMatch
        XCTAssertTrue(
            photo.waitForExistence(timeout: 5),
            "the photo whose story names the place was not found by it"
        )
    }

    /// A search that finds nothing is a different emptiness from an archive
    /// nobody has filled, and it must not offer the invitation meant for the
    /// second one.
    func testNothingFoundSaysSoInItsOwnWords() {
        let app = launch(["-seed", "archive", "-tab", "memories"])
        XCTAssertTrue(app.navigationBars["Albumi"].waitForExistence(timeout: 10), "the gallery")

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
