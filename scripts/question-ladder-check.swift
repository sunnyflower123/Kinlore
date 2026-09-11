// What the app decides to ask an 80-year-old next.
//
// `QuestionLadder` is a transformed up/down staircase over three UserDefaults
// keys, and it had no check at all — 380 lines of arithmetic against
// `UpsellRhythm`'s four, which has had one in `verify.sh` for weeks. The
// asymmetry was not a judgement about risk; the small file simply got looked
// at. Both hits for "ladder" in the test suite are comments.
//
// Every way this goes wrong is silent, and the two directions are not
// symmetric:
//
//   * Too eager, and somebody who has answered two naming questions is asked
//     "mitä toivoisit lastenlastesi tietävän" — the wall the whole file exists
//     to prevent, and the moment an elderly teller concludes the app is not
//     for them. Nothing on screen says a level was chosen.
//   * Too shy, and a person who has been telling stories for a month is still
//     being asked who is in the photograph. That one never even looks wrong.
//
// Neither fails a build, neither shows in a screenshot, and neither is visible
// to the accessibility suite, which reads what is on screen and not why that
// question is the one on it.
//
//   swiftc -parse-as-library -o /tmp/question-ladder-check \
//     scripts/question-ladder-check.swift \
//     ios/Kinlore/Services/QuestionLadder.swift ios/Kinlore/Model/Models.swift
//
// Costs nothing: no simulator, no network, no key. Run it after touching
// QuestionLadder.swift.
//
// NOTE ON `#if DEBUG`. This harness is built without it, so `comfort`'s
// `-comfort <n>` override is compiled out and what runs here is the shipping
// path. That is the right way round — the override exists for filming and for
// the audit, and a check that measured it would be measuring the affordance
// rather than the ladder.

import Foundation

@main
enum QuestionLadderCheck {
    /// The storage keys, mirrored from the private constants in
    /// `QuestionLadder`. Only dormancy needs them: it is a fact about a date
    /// in the past, and there is no other way to be three weeks away.
    ///
    /// Mirroring is safe here in the one way that matters — a rename breaks
    /// the dormancy cases loudly rather than quietly passing them, because the
    /// stamp then lands on a key nothing reads and no decay happens at all.
    private static let answeredKey = "ladder.answeredAt"

    @MainActor
    static func main() {
        var failures = 0

        func check(_ label: String, _ actual: some Equatable, _ expected: some Equatable) {
            if String(describing: actual) == String(describing: expected) {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label): got \(actual), expected \(expected)")
            }
        }

        /// A phone nobody has answered anything on.
        func fresh() { QuestionLadder.reset() }

        /// Puts the last answer this far in the past.
        func lastAnswered(daysAgo: Double) {
            UserDefaults.standard.set(
                Date.now.addingTimeInterval(-daysAgo * 86_400).timeIntervalSince1970,
                forKey: answeredKey
            )
        }

        func question(
            _ text: String,
            level: Int? = nil,
            asker: String? = nil,
            age: TimeInterval = 0
        ) -> FollowUpQuestion {
            FollowUpQuestion(
                subjectID: nil,
                text: text,
                storedLevel: level,
                createdAt: Date(timeIntervalSince1970: 1_000_000 + age),
                authorName: asker
            )
        }

        // ------------------------------------------------ where the person is

        print("— everybody starts at the bottom —")
        fresh()
        // The first question this app ever asks is a naming question. If this
        // is ever anything but 1, the opening move of the product has changed
        // and nothing else would say so.
        check("a phone nobody has answered on is at the bottom", QuestionLadder.comfort, 1.0)

        print("— two fluent answers to move up, one strained to fall —")
        fresh()
        QuestionLadder.record(.fluent, at: .naming)
        check("one fluent answer moves nothing", QuestionLadder.comfort, 1.0)
        QuestionLadder.record(.fluent, at: .naming)
        check("the second moves half a level", QuestionLadder.comfort, 1.5)
        QuestionLadder.record(.fluent, at: .fact)
        check("and the streak starts again, so the third moves nothing", QuestionLadder.comfort, 1.5)
        QuestionLadder.record(.fluent, at: .fact)
        check("the fourth moves half a level again", QuestionLadder.comfort, 2.0)

        fresh()
        QuestionLadder.record(.fluent, at: .naming)
        QuestionLadder.record(.fluent, at: .naming)
        QuestionLadder.record(.strained, at: .fact)
        // The asymmetry is the product decision, not an oversight: one wall
        // costs this user more than a run of questions that were too easy.
        check("one strained answer drops a whole level", QuestionLadder.comfort, 1.0)

        fresh()
        QuestionLadder.record(.fluent, at: .naming)
        QuestionLadder.record(.strained, at: .naming)
        QuestionLadder.record(.fluent, at: .naming)
        check("and it resets the streak, so a single fluent answer after it moves nothing",
              QuestionLadder.comfort, 1.0)

        print("— an easy question answered easily is no evidence —")
        fresh()
        for _ in 0 ..< 6 { QuestionLadder.record(.fluent, at: .naming) }
        // Six naming questions answered in a row. Without the guard this is a
        // walk to the top: a person who can say "Aino" six times would be
        // asked what she hopes her grandchildren will know. The starters on an
        // archive of thirty imported photographs are exactly such a run.
        check("a run of starters cannot climb the ladder", QuestionLadder.comfort, 1.5)

        print("— and the ends hold —")
        fresh()
        for _ in 0 ..< 4 { QuestionLadder.record(.strained, at: .naming) }
        // Below 1 there is no question to ask: `select` aims at
        // `Int(comfort.rounded())` and level 0 does not exist.
        check("strain at the bottom cannot go under it", QuestionLadder.comfort, 1.0)

        fresh()
        for _ in 0 ..< 40 { QuestionLadder.record(.fluent, at: .meaning) }
        check("fluency at the top cannot run past it", QuestionLadder.comfort, 5.0)

        print("— three weeks away makes the way back EASIER, never harder —")
        fresh()
        for _ in 0 ..< 12 { QuestionLadder.record(.fluent, at: .meaning) }
        check("somebody who was telling stories is well up the ladder", QuestionLadder.comfort, 4.0)
        lastAnswered(daysAgo: 20)
        check("and comes back one level lower", QuestionLadder.comfort, 3.0)

        fresh()
        lastAnswered(daysAgo: 1)
        check("a day away changes nothing", QuestionLadder.comfort, 1.0)

        // The direction is the whole of it. The step back exists because being
        // asked something hard on the way back is how a returning user stops
        // returning — so for the person at the very bottom, who is the one
        // most at risk of not returning, it must not become a step UP.
        fresh()
        lastAnswered(daysAgo: 20)
        check("a beginner who was away is not promoted for it", QuestionLadder.comfort, 1.0)

        fresh()
        QuestionLadder.record(.fluent, at: .naming)
        QuestionLadder.record(.fluent, at: .naming)
        lastAnswered(daysAgo: 20)
        check("and nobody is ever raised by staying away", QuestionLadder.comfort, 1.5)

        // Answering is what says somebody is not dormant, including an answer
        // that moved nothing.
        fresh()
        lastAnswered(daysAgo: 20)
        QuestionLadder.record(.fluent, at: .naming)
        check("one answer ends the dormancy", QuestionLadder.comfort, 1.0)

        // --------------------------------------------- which question is put

        print("— too hard costs double too easy —")
        let aimIsThree = 3.0
        let easier = question("Missä tämä on otettu?", level: 2)
        let harder = question("Mitä toivoisit lastenlastesi tietävän?", level: 4)
        check(
            "offered a question above and one below, the easier one is chosen",
            QuestionLadder.select([harder, easier], comfort: aimIsThree, limit: 1)
                .map(\.text) == [easier.text],
            true
        )
        check(
            "and a question at the aim beats both",
            QuestionLadder.select(
                [harder, easier, question("Millainen ihminen Aino oli?", level: 3)],
                comfort: aimIsThree, limit: 1
            ).map(\.storedLevel) == [3],
            true
        )

        print("— and nothing waits forever —")
        let old = question("Kuka tässä on?", level: 1, age: 0)
        let recent = question("Ketkä siinä olivat?", level: 1, age: 10_000)
        check(
            "among equals the oldest is offered first",
            QuestionLadder.select([recent, old], comfort: 1.0, limit: 1).map(\.id) == [old.id],
            true
        )

        print("— a question a person asked is pinned, but never last —")
        let asked = question("Kerro siitä päivästä.", level: 4, asker: "Ville")
        let easy = question("Kuka tässä on?", level: 1)
        let alsoEasy = question("Missä tämä on?", level: 2)
        let two = QuestionLadder.select([easy, alsoEasy, asked], comfort: 1.0, limit: 2)
        check("an asked question is carried past the ladder's own ranking",
              two.contains { $0.id == asked.id }, true)
        check("and it arrives beside an easy way out", two.count, 2)
        check("offered in the order the ladder would climb them",
              two.map(\.level.rawValue) == two.map(\.level.rawValue).sorted(), true)
        // One slot is the last slot. Pinning there would put a level-5
        // question in front of somebody with nothing else to choose.
        let one = QuestionLadder.select([easy, asked], comfort: 1.0, limit: 1)
        check("with one slot, nothing is pinned", one.map(\.id) == [easy.id], true)

        let bothAsked = [
            question("Kerro siitä päivästä.", level: 4, asker: "Ville"),
            question("Mitä opit isältäsi?", level: 5, asker: "Sanna"),
        ]
        let picked = QuestionLadder.select(bothAsked + [easy], comfort: 1.0, limit: 2)
        check("never more than one asked question at a time",
              picked.filter { $0.authorName != nil }.count, 1)

        check("no slots, nothing offered", QuestionLadder.select([easy], comfort: 1.0, limit: 0).count, 0)
        check("and nothing is offered twice",
              Set(QuestionLadder.select([easy, alsoEasy], comfort: 1.0, limit: 5).map(\.id)).count, 2)

        // ------------------------------------------- reading it off the words

        print("— the wording says how much is being asked —")
        // Scanned in order, so the specific phrase wins. Both of these begin
        // with "mitä" and they are two levels apart; getting the order wrong
        // makes every reflective question read as an episode.
        check("\"mitä toivoisit\" is a reflection",
              QuestionLevel.inferred(from: "Mitä toivoisit lastenlastesi tietävän?"), QuestionLevel.meaning)
        check("\"mitä tapahtui\" is a story",
              QuestionLevel.inferred(from: "Mitä tapahtui sinä kesänä?"), QuestionLevel.episode)
        check("\"kerro millainen\" is a story, not a description",
              QuestionLevel.inferred(from: "Kerro millainen Aino oli."), QuestionLevel.episode)
        check("\"kuka\" is a name", QuestionLevel.inferred(from: "Kuka tässä kuvassa on?"), QuestionLevel.naming)
        check("\"missä\" is one fact", QuestionLevel.inferred(from: "Missä tämä on otettu?"), QuestionLevel.fact)
        // Guessing the middle is more honest than guessing easy: extraction
        // aims at gaps, and a gap question is usually a description.
        check("a question it cannot read guesses the middle, not the easiest",
              QuestionLevel.inferred(from: "Tämä on outo kysymys."), QuestionLevel.description)

        check("the extraction's own label beats the wording",
              question("Kuka tässä on?", level: 5).level, QuestionLevel.meaning)
        check("and a question nobody labelled falls back to it",
              question("Kuka tässä on?").level, QuestionLevel.naming)
        // Out of range is not a level. It arrives from the server, which
        // stores 1–5 and nothing else, but the field is an Int and the client
        // reads what it is given.
        check("an impossible label falls back to the wording too",
              question("Kuka tässä on?", level: 9).level, QuestionLevel.naming)

        // ------------------------------------------------- how it went

        print("— whether they could answer at all —")
        // Not whether the answer was good. There is no right answer to
        // "millainen isäsi oli".
        check("a short answer that named somebody did the job",
              QuestionLadder.outcome(forAnswer: "Aino.", at: .meaning, yieldedStructure: true),
              QuestionLadder.Outcome.fluent)
        check("one word genuinely answers a naming question",
              QuestionLadder.outcome(forAnswer: "Aino", at: .naming, yieldedStructure: false),
              QuestionLadder.Outcome.fluent)
        check("one word does not answer a reflection",
              QuestionLadder.outcome(forAnswer: "Aino", at: .meaning, yieldedStructure: false),
              QuestionLadder.Outcome.strained)
        check("and silence is strain wherever it happens",
              QuestionLadder.outcome(forAnswer: "", at: .naming, yieldedStructure: false),
              QuestionLadder.Outcome.strained)

        print("— emptying the device forgets where she had got to —")
        fresh()
        for _ in 0 ..< 6 { QuestionLadder.record(.fluent, at: .meaning) }
        QuestionLadder.reset()
        check("the ladder is back at the bottom, not merely paused",
              QuestionLadder.comfort, 1.0)

        QuestionLadder.reset()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
