import XCTest

/// The family tree at the size a family actually reaches, drawn from
/// `-seed clan`: six generations, fifty-five confirmed people, a remarriage,
/// two cousin marriages, a childless couple, a marriage the generations cannot
/// hold, siblings with no parents entered, two families sharing nobody, a
/// friend who is nobody's kin, and seven people related to nobody yet.
///
/// `FamilyTreeTests` asks whether the screen works, over a family of three.
/// Everything here only happens at size: a generation wider than the screen,
/// a word on a card three generations from your own, a family that shares
/// nobody with yours drawn beside it, a drawing that has to be flown across
/// rather than seen at once. The first look at one (16 Sep 2026) is what the
/// oldest of these were written from; the rest came with the rebuild of
/// 25 Sep 2026, which put the words inside the drawing.
final class FamilyTreeCrowdTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The whole crowd is drawn, and rule 4 still holds at this size: the one
    /// person nobody has confirmed is not in the picture, however many are.
    func testTheWholeCrowdIsDrawn() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the oldest generation")
        XCTAssertTrue(app.buttons["Hilma"].exists, "his wife")
        XCTAssertTrue(app.buttons["Lyyli"].exists, "the second wife is not drawn")
        XCTAssertTrue(app.buttons["Kustaa"].exists, "somebody related to nobody is not in the picture")
        shot(app, "crowd-top")
        XCTAssertTrue(app.staticTexts["Ei vielä sukupuussa"].exists, "the people related to nobody have no caption")
        XCTAssertFalse(app.buttons["Eeva"].exists, "a person nobody has confirmed is drawn in the tree")
    }

    /// What each card says that person is to you, on Elina's phone. The
    /// words are `Kinship`'s and `scripts/kinship-check.swift` derives every
    /// one of them from the fixture; this asks that the screen shows what the
    /// check derived, counted, because the same word stands on more than one
    /// card and a query by name would not say on how many.
    func testEachCardSaysWhatThatPersonIsToYou() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Elina, sinä"].waitForExistence(timeout: 20), "your own card")
        XCTAssertTrue(app.buttons["Elina, sinä"].staticTexts["Sinä"].exists, "no word under your own name")
        let expected: [(word: String, cards: Int, who: String)] = [
            ("Vanhempasi", 2, "Matti and Ritva"),
            ("Isovanhempasi", 4, "Toivo, Anneli, Aune and Paavo"),
            ("Isoisovanhempasi", 4, "Väinö, Hilja, Kerttu and Oiva"),
            ("Puolisosi", 1, "Mikko"),
            ("Sisaruksesi", 1, "Jukka"),
            ("Lapsesi", 3, "Venla, Oskari and Aino"),
            ("Sisaruksesi puoliso", 1, "Petra"),
            ("Sisaruksesi lapsi", 1, "Elias"),
            ("Vanhempasi sisarus", 1, "Liisa"),
            ("Isovanhempasi sisarus", 5, "Martta, Eino, Reino, Sirkka and Helvi"),
            ("Vanhempasi serkku", 2, "Veikko and Kaarina"),
            ("Pikkuserkkusi", 2, "Sanni and Aleksi"),
            ("Ystäväsi", 1, "Jonne"),
        ]
        for (word, cards, who) in expected {
            XCTAssertEqual(app.staticTexts.matching(identifier: word).count, cards,
                           "\(word) should stand on \(cards) cards: \(who)")
        }
        // On the card it is about: Matti's own button carries his word.
        XCTAssertTrue(app.buttons["Matti"].staticTexts["Vanhempasi"].exists, "your parent's word is not on his card")
        XCTAssertTrue(app.buttons["Petra"].staticTexts["Sisaruksesi puoliso"].exists, "your brother's wife's word is not on her card")
        shot(app, "crowd-words")
    }

    /// And nobody gets a word that is not exact: your great-great-grandparents
    /// are four generations up and Finnish has no word anybody says for
    /// that; Sulo is your great-grandfather's brother, Tuula your parent's
    /// cousin's wife, Iiris your second cousin's daughter, Eemeli a
    /// great-grandparent's brother married into the wrong generation, and
    /// Otto's family shares nobody with yours. A near word would be a
    /// wrong relationship drawn as fact. A card with no word has one text
    /// fewer than a card with one, and Kustaa — related to nobody — is the
    /// measure of a card with none.
    func testNobodyGetsAWordThatIsNotExact() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Matti"].waitForExistence(timeout: 20), "the tree")
        let none = app.buttons["Kustaa"].staticTexts.count
        XCTAssertEqual(app.buttons["Matti"].staticTexts.count, none + 1, "a card with a word is not one text longer than one without")
        for name in ["Aapo", "Hilma", "Lyyli", "Impi", "Urho", "Sulo", "Onni", "Eemeli",
                     "Tuula", "Heikki", "Noora", "Iiris", "Otto", "Helmi", "Rauha", "Sisko", "Onerva"] {
            XCTAssertEqual(app.buttons[name].staticTexts.count, none, "\(name) was given a word that cannot be exact")
        }
    }

    /// A phone linked to no card has nobody to count from, and says nothing
    /// rather than something: no word on any card, no *Sinä*, and no button
    /// to fly home with.
    func testAPhoneLinkedToNoCardSaysNoWord() {
        let app = launch(["-seed", "clan", "-tab", "people", "-people", "tree"])
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the tree")
        let none = app.buttons["Kustaa"].staticTexts.count
        for name in ["Matti", "Elina", "Mikko", "Venla", "Jonne"] {
            XCTAssertEqual(app.buttons[name].staticTexts.count, none, "\(name) carries a word on a phone linked to no card")
        }
        XCTAssertFalse(app.staticTexts["Sinä"].exists, "somebody is called you on a phone linked to no card")
        XCTAssertFalse(app.buttons["Sinä"].exists, "a way home on a phone with no card to go to")
        XCTAssertTrue(app.buttons["Koko suku"].exists, "the way to fit the family is missing")
    }

    /// The words go with the drawing, because they are part of it. The shape
    /// before this one kept the generation words still while the drawing
    /// moved, and measured that as a feature; on a phone the words then stood
    /// over the names. Your own card is carried left by a flick, and the
    /// word under it goes exactly as far.
    func testTheWordsGoWithTheDrawing() {
        let app = crowd()
        let you = app.buttons["Elina, sinä"]
        XCTAssertTrue(you.waitForExistence(timeout: 20), "your own card")
        let word = you.staticTexts["Sinä"]
        let card = you.frame
        let before = word.frame
        app.swipeLeft()
        shot(app, "crowd-across")
        XCTAssertLessThan(you.frame.minX, card.minX - 100, "the drawing did not scroll sideways at all")
        XCTAssertEqual(word.frame.minX - before.minX, you.frame.minX - card.minX, accuracy: 1,
                       "the word did not move with the card it is under")
        XCTAssertTrue(you.frame.contains(word.frame), "the word left your card")
    }

    /// A family that shares nobody with yours is captioned and not counted.
    /// Otto and Helmi start at row 0 because nothing is known about their
    /// age either way, so any word on their cards would be a relationship
    /// nobody entered; *Toinen perhe* over them says why the words stop at
    /// their edge, and it is inside the drawing, where they are.
    func testAFamilyThatSharesNobodyIsCaptionedAndNotCounted() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Elina, sinä"].waitForExistence(timeout: 20), "your own card")
        // Sixteen places from where the drawing opens, which is several
        // screens of a picture this wide. The scroll view clamps at the far
        // end, so more swipes than the distance needs cost nothing — and
        // asking whether Otto can be reached before he is on screen costs a
        // test: `isHittable` on somebody outside the window fails outright
        // rather than answering no ("Activation point invalid", 19 Sep 2026).
        for _ in 0 ..< 8 { app.swipeLeft() }
        // And upwards: the drawing opens on your own row and this family
        // starts at row 0, four generations up.
        for _ in 0 ..< 4 { app.swipeDown() }
        shot(app, "crowd-other-family")
        let otto = app.buttons["Otto"]
        XCTAssertTrue(otto.isHittable, "the far family cannot be scrolled to")
        // Two families here share nobody with Elina's, Sisko's and Otto's,
        // so the caption is in the drawing twice, and a query resolved to
        // one element fails on the pair rather than answering — "Multiple
        // matching elements found", 25 Sep 2026. The caption over Otto's
        // family is the one whose band ends above him and begins nearest to
        // the left of him; and it is asked for by its frame, because
        // `isHittable` on the other one, off the screen, would fail outright.
        let window = app.windows.firstMatch.frame
        let caption = app.staticTexts.matching(identifier: "Toinen perhe").allElementsBoundByIndex
            .filter { $0.frame.maxY < otto.frame.minY && $0.frame.minX <= otto.frame.midX && window.intersects($0.frame) }
            .max { $0.frame.minX < $1.frame.minX }
        XCTAssertNotNil(caption, "nothing says this family shares nobody with yours")
        XCTAssertEqual(otto.staticTexts.count, app.buttons["Kustaa"].staticTexts.count,
                       "somebody who shares nobody with you was given a word")
    }

    /// The drawing opens on the part of the family whose phone this is: her
    /// own card in the window's middle across and a little under a third of
    /// the way down, with her parents above her and her children below. A
    /// family of 55 is seventeen places wide against a phone's three, so a
    /// picture that opened at its own corner opened on whoever happened to be
    /// oldest, with the person holding the phone four places across and four
    /// rows down and nothing to say which way to look.
    func testTheTreeOpensOnYourOwnLine() {
        let app = crowd()
        let you = app.buttons["Elina, sinä"]
        XCTAssertTrue(you.waitForExistence(timeout: 20), "your own card is not in the tree")
        shot(app, "crowd-opens")
        XCTAssertTrue(you.isHittable, "the tree does not open on you")
        XCTAssertTrue(you.staticTexts["Sinä"].isHittable, "the word under your name is not on the screen")
        let screen = app.windows.firstMatch.frame
        XCTAssertLessThan(you.frame.midY, screen.midY, "your own card opens in the lower half of the screen")
        XCTAssertTrue(app.buttons["Matti"].isHittable, "your parents' generation is not on the screen")
        XCTAssertTrue(app.buttons["Venla"].isHittable, "your children's generation is not on the screen")
        XCTAssertFalse(app.buttons["Aapo"].isHittable, "the tree still opens on your great-great-grandparents")
    }

    /// The opening leaves nobody under the three controls that float over
    /// the drawing: the two buttons in the lower corner and the menu's
    /// button in the bar.
    ///
    /// A name under a control stays in the accessibility tree while being
    /// painted nowhere: VoiceOver reads a name that no eye can find, and the
    /// audit measures it as paper on paper — which is what it said of Liisa
    /// and Veikko under the bar the zoom buttons used to sit in, on 16 Sep
    /// 2026. Opening on your own row makes a scrolled screen the first one
    /// anybody sees, so where it stops is measured rather than chosen.
    func testTheTreeOpensWithNothingUnderItsButtons() {
        for size in [nil, "UICTContentSizeCategoryAccessibilityXXXL"] {
            let extra = size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? []
            let app = launch(["-seed", "clan", "-tab", "people", "-people", "tree",
                              "-you", "clan-elina"] + extra)
            XCTAssertTrue(app.buttons["Elina, sinä"].waitForExistence(timeout: 30),
                          "your own card is not in the tree")
            let tabs = app.tabBars.firstMatch.frame
            let names = ["Koko suku", "Sinä", "Valikko"]
            let controls = names.map { app.buttons[$0].frame }
            for (name, control) in zip(names, controls) {
                XCTAssertGreaterThan(control.height, 0, "\(name) is not on the screen")
                XCTAssertGreaterThan(tabs.minY, control.maxY, "\(name) is not above the tabs")
            }
            // The words: the names, the kinship words and the captions,
            // which is what the audit reads and a reader looks for. A
            // disc's edge under a translucent control is the map's own
            // business and a finger moves it; a word under one is hidden.
            // The tabs live below the controls, and a name carried off the
            // sides is another test's business. A disc's initial is a text
            // to the runner as well, `accessibilityHidden` or not — "V" at
            // the largest size, 19 Sep 2026, where a row is taller than the
            // window and the next row's disc is under something whatever
            // the opening — so a word here is anything longer than a letter.
            let covered = app.staticTexts.allElementsBoundByIndex.filter { word in
                let f = word.frame
                return word.label.count > 1 && f.height > 0 && controls.contains { $0.intersects(f) }
            }
            XCTAssertEqual(covered.map(\.label), [],
                           "the opening puts these under the controls (\(size ?? "default"))")
        }
    }

    /// Zoomed out to see a family this size, the discs stay and the names go:
    /// *Koko suku* takes a family of fifty-five to the smallest zoom, where a
    /// name would be seven points of ink, and draws none. Every disc is still
    /// a tap target, and a tap on one flies to that person at the natural
    /// size with their name back and their sheet up — which is how a name is
    /// read at that zoom, and why the pinch is optional.
    func testZoomedOutTheDiscsStayAndATapBringsTheNameBack() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Elina, sinä"].waitForExistence(timeout: 20), "your own card")
        app.buttons["Koko suku"].tap()
        XCTAssertTrue(app.staticTexts["Elina"].waitForNonExistence(timeout: 10), "a name is still drawn at the smallest zoom")
        shot(app, "crowd-small")
        let aapo = app.buttons["Aapo"]
        XCTAssertTrue(aapo.isHittable, "the oldest generation is not on the screen when the family is fitted")
        XCTAssertGreaterThanOrEqual(aapo.frame.width, 44, "a place is too narrow to tap at the smallest zoom")
        XCTAssertGreaterThanOrEqual(aapo.frame.height, 44, "a place is too short to tap at the smallest zoom")
        aapo.tap()
        XCTAssertTrue(app.buttons["Avaa kortti"].waitForExistence(timeout: 10), "the tapped person's sheet did not come up")
        // Nobody in the fixture has a memory, and a sheet that said "0
        // muistoa" fifty-five times would be the drawing repeating itself.
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'muistoa'")).count, 0,
                       "the sheet counts memories the archive does not hold")
        XCTAssertTrue(app.staticTexts["Aapo"].exists, "the name did not come back for the person tapped")
        app.buttons["Sulje"].tap()
        XCTAssertTrue(app.buttons["Avaa kortti"].waitForNonExistence(timeout: 10), "the sheet did not close")
        XCTAssertTrue(app.staticTexts["Aapo"].isHittable, "the drawing did not fly to the person tapped")
    }

    /// *Sinä* flies home from the far end of the picture: your own card in
    /// the upper part of the window, at the natural size, wherever the reader
    /// had carried the drawing.
    func testSinaFliesHome() {
        let app = crowd()
        let you = app.buttons["Elina, sinä"]
        XCTAssertTrue(you.waitForExistence(timeout: 20), "your own card")
        for _ in 0 ..< 8 { app.swipeLeft() }
        for _ in 0 ..< 4 { app.swipeDown() }
        XCTAssertTrue(app.buttons["Otto"].isHittable, "the far family cannot be scrolled to")
        app.buttons["Sinä"].tap()
        XCTAssertTrue(you.waitForExistence(timeout: 10), "your own card is gone")
        // The flight is 420 milliseconds; the runner waits for the screen to
        // settle before it reads a frame.
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(you.isHittable, "the drawing did not fly home")
        XCTAssertLessThan(you.frame.midY, screen.midY, "home is in the lower half of the screen")
        XCTAssertTrue(you.staticTexts["Sinä"].isHittable, "the word under your name is not on the screen")
        shot(app, "crowd-home")
    }

    /// A tap on a person brings them into the upper part of the window and
    /// their sheet up under them, so the card the sheet is about stays in
    /// view over it. Matti is on the row above Elina and on the screen when
    /// the drawing opens.
    func testATapBringsThePersonIntoTheUpperWindowOverTheirSheet() {
        let app = crowd()
        let matti = app.buttons["Matti"]
        XCTAssertTrue(matti.waitForExistence(timeout: 20), "your parent's card")
        XCTAssertTrue(matti.isHittable, "your parents' row is not on the screen when the drawing opens")
        matti.tap()
        XCTAssertTrue(app.buttons["Avaa kortti"].waitForExistence(timeout: 10), "the person's sheet")
        XCTAssertTrue(app.staticTexts["Vanhempasi"].firstMatch.exists, "the sheet does not say what he is to you")
        let screen = app.windows.firstMatch.frame
        XCTAssertLessThan(matti.frame.midY, screen.midY, "the tapped card is under its own sheet")
        shot(app, "crowd-tapped")
    }

    /// What the lines mean, in the menu rather than on the drawing. Three
    /// kinds of line are drawn and they are not guessable: a couple is two
    /// lines, children hang from a bracket, siblings from a bar. The drawing
    /// is the screen and the key is one tap away.
    func testTheMenuSaysWhatTheLinesMean() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the tree")
        XCTAssertFalse(app.staticTexts["Pariskunta"].exists, "the key stands on the drawing rather than in the menu")
        app.buttons["Valikko"].tap()
        let heading = app.staticTexts["Mitä viivat tarkoittavat"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "the menu does not say what the lines mean")
        XCTAssertTrue(app.staticTexts["Pariskunta"].exists, "nothing says what a couple's line is")
        XCTAssertTrue(app.staticTexts["Sisarukset"].exists, "nothing says what a sibling bar is")
        app.buttons["Sulje"].tap()
        XCTAssertTrue(heading.waitForNonExistence(timeout: 10), "the menu did not close")
        for _ in 0 ..< 4 { app.swipeUp() }
        shot(app, "crowd-down")
        XCTAssertTrue(app.buttons["Venla"].exists, "the youngest generation cannot be scrolled to")
    }

    /// The people related to nobody follow the tree instead of a dead
    /// generation. The layout leaves an empty row for each caption and the
    /// screen draws that row a caption tall rather than a generation tall:
    /// before 16 Sep 2026 the gap under the last generation was a whole
    /// generation, 134 points of nothing at the default text size.
    ///
    /// Measured against the drawing's own generation height — the distance
    /// between two rows of it — so it holds at every text size. Two bands
    /// since 21 Sep 2026, and the air is taken out of both caption rows the
    /// same way: the friends follow the youngest generation, and the people
    /// related to nobody follow the friend. `-seed clan`'s Jonne is the
    /// friend, so this measures each caption against what stands above it.
    func testTheCaptionFollowsTheTreeInsteadOfADeadGeneration() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the tree")
        let generation = app.buttons["Väinö"].frame.minY - app.buttons["Aapo"].frame.minY
        XCTAssertGreaterThan(generation, 1, "two generations are drawn at the same height")
        let friends = app.staticTexts["Ystävät"].frame
        let youngest = app.buttons["Venla"].frame
        XCTAssertGreaterThan(friends.minY, youngest.maxY, "the friends' caption is above the last generation")
        XCTAssertLessThan(friends.minY - youngest.maxY, generation,
                          "a whole empty generation sits between the tree and the friends' caption")
        let friend = app.buttons["Jonne"].frame
        let caption = app.staticTexts["Ei vielä sukupuussa"].frame
        XCTAssertGreaterThan(friend.minY, friends.maxY, "the friend stands above his own caption")
        XCTAssertGreaterThan(caption.minY, friend.maxY, "the caption is above the friend")
        XCTAssertLessThan(caption.minY - friend.maxY, generation,
                          "a whole empty generation sits between the friend and the caption")
    }

    /// A relationship the rows cannot hold is named in the menu rather than
    /// dropped in silence. The fixture's family has exactly two, and both
    /// are there on purpose: Eemeli is Oiva's brother and Sirkka's husband
    /// with Sirkka a generation below Oiva, so one of those two bonds has
    /// nowhere to go; and Onni and Sulo were entered as each other's parent,
    /// which is what a proposal confirmed from both ends looks like in the
    /// archive.
    ///
    /// Until 19 Sep 2026 the line simply was not drawn, which from the picture
    /// is indistinguishable from a bond nobody has entered yet — the reading
    /// that sends somebody off to enter it a second time.
    func testARelationshipTheRowsCannotHoldIsNamedRatherThanDropped() {
        let app = crowd()
        XCTAssertTrue(app.buttons["Aapo"].waitForExistence(timeout: 20), "the tree")
        XCTAssertFalse(app.staticTexts["Nämä eivät mahdu kuvaan"].exists,
                       "the note stands on the drawing rather than in the menu")
        app.buttons["Valikko"].tap()
        XCTAssertTrue(app.staticTexts["Nämä eivät mahdu kuvaan"].waitForExistence(timeout: 10),
                      "nothing says a relationship was left out of the picture")
        let marriage = app.staticTexts["Eemeli ja Sirkka — aviopuolisot"]
        let parents = app.staticTexts["Onni ja Sulo — vanhempi ja lapsi"]
        XCTAssertTrue(marriage.exists, "the marriage the generations cannot hold is not named")
        XCTAssertTrue(parents.exists, "the pair each entered as the other's parent is not named")
        // And it can be read. The sheet scrolls, and a sentence under its
        // fold exists all the same, so existing is the weaker half.
        if !parents.isHittable { app.swipeUp() }
        shot(app, "crowd-undrawn")
        XCTAssertTrue(marriage.isHittable, "what will not fit is named where nobody can read it")
        XCTAssertTrue(parents.isHittable, "the second bond is named where nobody can read it")
    }

    /// A name in the drawing is drawn larger, not smaller, when the reader
    /// asks for larger text.
    ///
    /// The opposite shipped for six hours on 19 Sep 2026. A place and a
    /// generation are `@ScaledMetric` and the phone is not, so at the largest
    /// text size a column is three times what it is at the default and the
    /// window is left with two thirds of one place. The answer taken then was
    /// to open the drawing at whatever showed two places, which shrinks the
    /// picture by as much as the text grew: "Eeva" measured 37.33 x 20.33
    /// points at the default size and 22.95 x 13.05 at AccessibilityXXXL, on
    /// a screen where every other word had grown by three. The accessibility
    /// sweep called all four names clipped at both sizes; nothing was cut,
    /// and the size was the defect.
    ///
    /// So this asks the two things that were both true of the picture before
    /// that factor and neither of them after: the name grows with the reader's
    /// text, and it is whole on the screen when the drawing opens. The
    /// opening fits a family only when it fits at a size that still has
    /// names, and a family of fifty-five never does; it opens on your own
    /// card at the natural size instead.
    func testTheDrawingsNamesGrowWithTheReadersText() {
        let arguments = ["-seed", "clan", "-tab", "people", "-people", "tree", "-you", "clan-elina"]
        let ordinary = launch(arguments)
        XCTAssertTrue(ordinary.staticTexts["Elina"].waitForExistence(timeout: 30),
                      "your own name is not in the tree at the default text size")
        let ordinaryName = ordinary.staticTexts["Elina"].frame.height
        ordinary.terminate()

        let app = launch(arguments, textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(app.staticTexts["Elina"].waitForExistence(timeout: 30),
                      "your own name is not in the tree at the largest text size")
        shot(app, "crowd-largest")
        let name = app.staticTexts["Elina"].frame
        XCTAssertGreaterThan(name.height, ordinaryName,
                             "the drawing's names are smaller at the largest text size than at the default")
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(name.minX, 0, "your own name starts off the left edge")
        XCTAssertLessThan(name.maxX, screen.width, "your own name runs off the right edge")
        XCTAssertTrue(app.staticTexts["Elina"].isHittable,
                      "the drawing opens somewhere your own name cannot be seen, at \(name) of \(screen)")
    }

    /// Two people entered as each other's parent. The layout keeps the
    /// earlier bond and names the later one in the menu, so Onni is drawn as
    /// Sulo's child — and the word on his card has to say the same thing
    /// from Sulo's phone. Handed both bonds, the words did not: upward is
    /// matched before downward, and Sulo read his son as *Vanhempasi*. From
    /// Sulo's phone, because the contradiction is his, and he opens on his
    /// own card with Onni the row below.
    func testAContradictedBondReadsTheWayItIsDrawn() {
        let app = launch(["-seed", "clan", "-tab", "people", "-people", "tree", "-you", "clan-sulo"])
        let onni = app.buttons["Onni"]
        XCTAssertTrue(onni.waitForExistence(timeout: 30), "the tree from Sulo's phone")
        XCTAssertTrue(app.buttons["Sulo, sinä"].exists, "Sulo's own card")
        XCTAssertTrue(onni.staticTexts["Lapsesi"].exists,
                      "Onni is drawn as Sulo's child and his card should read as one")
        XCTAssertFalse(onni.staticTexts["Vanhempasi"].exists,
                       "the later, contradicting bond names Onni as Sulo's parent")
    }

    /// A picture of what a test was looking at, when
    /// `TEST_RUNNER_KINLORE_TREE_SHOT=/some/dir/prefix` is on the xcodebuild
    /// line, and nothing at all when it is not.
    ///
    /// The same affordance as the audit's shot, for the same reason: this
    /// machine has no simulator panel, so a screen nobody can tap is a screen
    /// nobody can look at. A drawing is the one thing here that has to be
    /// looked at — every defect the first look found was a matter of air,
    /// crossing lines and words too small, and no assertion in this file would
    /// have reported any of them.
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["KINLORE_TREE_SHOT"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory)-\(name).png"))
    }

    /// The fixture's family, on a phone whose card is Elina's — four
    /// generations down from the oldest and one up from the youngest.
    private func crowd() -> XCUIApplication {
        launch(["-seed", "clan", "-tab", "people", "-people", "tree", "-you", "clan-elina"])
    }
}
