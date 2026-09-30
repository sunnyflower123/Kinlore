import Foundation

/// How much a question asks of the person answering it.
///
/// The level is the shape of the answer, not the topic. "Kuka tässä on?" is
/// answered with a name in three seconds; "Mitä opit isältäsi?" needs a person
/// who is already used to being asked. Offering the second one first is how an
/// elderly teller decides this app is not for them.
///
/// See docs/ARCHITECTURE.md §12.
enum QuestionLevel: Int, Comparable, CaseIterable {
    /// One to three words. The smallest thing this app can ask of anybody.
    case naming = 1
    /// A single fact: a place, a year.
    case fact = 2
    /// A few sentences about a person or a place.
    case description = 3
    /// A story with a beginning and an end.
    case episode = 4
    /// Reflection — what it meant, what should be passed on.
    case meaning = 5

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The shortest answer that still counts as one at this level.
    ///
    /// Deliberately low. This is not a measure of a good answer — it separates
    /// "answered" from "could not answer", and one word genuinely is the whole
    /// answer to a naming question.
    var wordFloor: Int {
        switch self {
        case .naming: 1
        case .fact: 2
        case .description: 10
        case .episode, .meaning: 20
        }
    }
}

extension QuestionLevel {
    /// Reads the level off the question's own wording.
    ///
    /// A Finnish question word is the cheapest signal there is, and it needs no
    /// stored field, no migration and no model call — which is what keeps the
    /// first version of the ladder entirely on the client. When extraction
    /// starts labelling its own questions (ARCHITECTURE.md §12, step 2) this
    /// stays as the fallback for older rows and for questions a person asked.
    ///
    /// The needles are Finnish because the questions are: this is matching on
    /// user-visible text, not writing it.
    static func inferred(from text: String) -> QuestionLevel {
        let question = text.lowercased()
        for (needle, level) in needles where question.contains(needle) {
            return level
        }
        // Extraction aims at gaps, and a gap question is usually a description.
        // Guessing the middle is more honest than guessing easy.
        return .description
    }

    /// Scanned in order, so the more specific phrase wins: "mitä toivoisit" and
    /// "mitä tapahtui" are different levels and both begin with "mitä", and
    /// "Kerro millainen Aino oli" asks for a story rather than a description.
    private static let needles: [(String, QuestionLevel)] = [
        ("miltä tuntui", .meaning),
        ("miltä se tuntui", .meaning),
        ("mitä toivoisit", .meaning),
        ("mitä haluaisit", .meaning),
        ("mitä olisit", .meaning),
        ("mitä opit", .meaning),
        ("mitä jäi", .meaning),
        ("miksi", .meaning),

        ("kerro", .episode),
        ("muistatko", .episode),
        ("mitä tapahtui", .episode),
        ("mitä muistat", .episode),
        ("millainen päivä", .episode),

        ("millainen", .description),
        ("minkälainen", .description),
        ("kuvaile", .description),
        ("miten", .description),
        ("mitä teitte", .description),

        ("missä", .fact),
        ("mistä", .fact),
        ("mihin", .fact),
        ("milloin", .fact),
        ("minä vuonna", .fact),
        ("kuinka", .fact),
        ("montako", .fact),
        ("mikä", .fact),

        ("kuka", .naming),
        ("ketkä", .naming),
        ("keitä", .naming),
        ("kenen", .naming),
        ("kenet", .naming),
    ]
}

extension FollowUpQuestion {
    /// What this question asks of the teller.
    ///
    /// The label the extraction gave it wins, because the model knows what it
    /// meant by the question. Reading it off the wording is the fallback, and it
    /// covers everything the model never saw: rows written before the field
    /// existed, and the questions people ask each other.
    var level: QuestionLevel {
        storedLevel.flatMap(QuestionLevel.init(rawValue:)) ?? .inferred(from: text)
    }
}

/// Chooses which question to put in front of the person, and keeps track of how
/// much they are up to.
///
/// A transformed up/down staircase (Levitt 1971): two fluent answers move up
/// half a level, one strained answer drops a whole one. Two-down/one-up settles
/// at roughly a 70 % success rate, which is about where questions stay
/// answerable without being pointless — and the asymmetry is the product
/// decision: for this user one wall costs more than a run of easy questions.
///
/// Nothing here is synced. `comfort` describes the person holding the phone, and
/// a family has no business seeing a difficulty number attached to a relative.
enum QuestionLadder {
    enum Outcome {
        /// They answered, and the answer had something in it.
        case fluent
        /// They could not, or would not: an answer under the level's floor, a
        /// question skipped, a recording of silence.
        case strained
    }

    /// Everybody starts at the bottom. The first question this app ever asks a
    /// person is a naming question — that is the entire point of the ladder.
    static let start = 1.0
    private static let bottom = 1.0
    private static let top = 5.0
    /// After this long away, the way back in is a smaller step. Three weeks
    /// later nobody remembers where they left off, and being asked something
    /// hard on the way back is how a returning user stops returning.
    private static let dormancy: TimeInterval = 14 * 24 * 60 * 60

    // MARK: - Where the person is

    /// The current level, with dormancy already taken off.
    static var comfort: Double {
        #if DEBUG
        // `-comfort 4` puts the ladder anywhere for filming or verification,
        // without answering six questions first.
        if UserDefaults.standard.object(forKey: "comfort") != nil {
            return clamp(UserDefaults.standard.double(forKey: "comfort"))
        }
        #endif
        let stored = defaults.object(forKey: comfortKey) as? Double ?? start
        return decayed(stored, lastAnswered: lastAnswered)
    }

    /// Records how an answer went and moves the ladder.
    static func record(_ outcome: Outcome, at level: QuestionLevel) {
        var value = comfort
        var streak = defaults.integer(forKey: streakKey)

        switch outcome {
        case .fluent where Double(level.rawValue) >= value.rounded():
            streak += 1
            if streak >= 2 {
                value += 0.5
                streak = 0
            }
        case .fluent:
            // Answered, but the question was below where they already are. An
            // easy question answered easily is no evidence that a harder one
            // would land, so a run of starters cannot push an uncertain teller
            // up the ladder.
            break
        case .strained:
            // Strain counts wherever it happens, and counts double: this is the
            // direction the ladder is allowed to move fast in.
            value -= 1
            streak = 0
        }

        defaults.set(clamp(value), forKey: comfortKey)
        defaults.set(streak, forKey: streakKey)
        // Written on every outcome, including the ones that moved nothing:
        // somebody who is answering is not dormant.
        defaults.set(Date.now.timeIntervalSince1970, forKey: answeredKey)
    }

    /// Reads the outcome off the answer itself. There is no right answer to
    /// "millainen isäsi oli", so what is measured is whether they could answer
    /// at all.
    static func outcome(
        forAnswer text: String,
        at level: QuestionLevel,
        yieldedStructure: Bool
    ) -> Outcome {
        // A short answer that still named a person or a year did the job the
        // question existed for.
        if yieldedStructure { return .fluent }
        let words = text.split(whereSeparator: \.isWhitespace).count
        return words >= level.wordFloor ? .fluent : .strained
    }

    // MARK: - Choosing

    /// Picks what to offer, easiest first.
    ///
    /// Selection is not compulsion: the Tell screen shows two of these, so the
    /// person still chooses — and which one they choose is free calibration.
    static func select(
        _ questions: [FollowUpQuestion],
        comfort: Double,
        limit: Int
    ) -> [FollowUpQuestion] {
        guard limit > 0 else { return [] }
        let aim = Int(comfort.rounded())
        let byFit = { (a: FollowUpQuestion, b: FollowUpQuestion) -> Bool in
            let costA = cost(a, aim: aim)
            let costB = cost(b, aim: aim)
            if costA != costB { return costA < costB }
            // Oldest first among equals, so no question waits forever.
            return a.createdAt < b.createdAt
        }

        // A question a person asked is pinned rather than ranked. "Ville kysyy"
        // is the strongest reason there is to press the button, and letting the
        // ladder bury it because it rates the wording hard would cost more than
        // it saves — a grandchild's question going unseen for a fortnight is the
        // failure, not a question one level too high.
        //
        // Never more than one, and never the last slot: an asked question that
        // is far above the teller always arrives beside an easy way out.
        var chosen = questions
            .filter { $0.authorName != nil }
            .sorted(by: byFit)
            .prefix(min(1, limit - 1))
            .map { $0 }

        for question in questions.sorted(by: byFit) where chosen.count < limit {
            guard !chosen.contains(where: { $0.id == question.id }) else { continue }
            chosen.append(question)
        }
        return chosen.sorted { $0.level < $1.level }
    }

    /// Distance from the aim, with **above costing double below**. Asking too
    /// much is the failure this whole file exists to prevent; asking too little
    /// only spends a question.
    private static func cost(_ question: FollowUpQuestion, aim: Int) -> Double {
        let distance = Double(question.level.rawValue - aim)
        return distance >= 0 ? distance * 2 : -distance
    }

    // MARK: - Starters

    /// Questions for a subject nobody has said anything about yet.
    ///
    /// This is the blank-button gap: extraction only produces questions once
    /// there is a memory to produce them from, so the very first contact with a
    /// photo had nothing to answer. These need no model, no network and no AI
    /// minutes.
    ///
    /// They are **not stored and not synced**. Thirty imported photographs would
    /// otherwise put ninety rows into the family's open-question list and make
    /// the list worthless. A starter is a prompt, not a debt — which is also why
    /// its id is derived from the subject rather than random: the same starter
    /// has to keep its identity across a redraw.
    // The prompts are looked up here, at creation, with `String(localized:)`:
    // they travel as Strings and were shown verbatim — the opening move of the
    // product, Finnish on an English phone (founder's-eye review, 3 Sep 2026,
    // finding #93). A question the model generates follows the speaker's
    // language already; only these hand-written ones needed the lookup.
    static func starters(for subject: Subject) -> [FollowUpQuestion] {
        // The level is written out rather than inferred. These texts were chosen
        // for their level, and a reworded starter must not quietly become a
        // harder question than the one place in the app that promises an easy
        // one.
        let texts: [(String, QuestionLevel)]
        switch subject.kind {
        case .photo:
            // What is remembered first, and who is in it second (30 Sep 2026).
            // With the naming question first, the card read as face
            // identification rather than as an invitation to tell. A fact
            // question because a sentence answers it.
            texts = [
                (String(localized: "Mitä muistat tästä kuvasta?"), .fact),
                (String(localized: "Kuka tässä kuvassa on?"), .naming),
                (String(localized: "Missä tämä kuva on otettu?"), .fact),
                (String(localized: "Minä vuonna tämä suunnilleen otettiin?"), .fact),
            ]
        case .person:
            // The name stays in the nominative in every one of these. Finnish
            // inflection cannot be done with string concatenation, and "Ainon"
            // built in code would be wrong exactly as often as it was right.
            let name = subject.displayTitle
            texts = [
                (String(localized: "Kuka \(name) oli sinulle?"), .naming),
                (String(localized: "Missä \(name) asui?"), .fact),
            ]
        case .place:
            texts = [
                (String(localized: "Milloin olit siellä viimeksi?"), .fact),
                (String(localized: "Kuka siellä asui?"), .naming),
            ]
        case .event:
            texts = [
                (String(localized: "Ketkä siellä olivat?"), .naming),
                (String(localized: "Milloin tämä tapahtui?"), .fact),
            ]
        }
        return texts.enumerated().map { index, starter in
            FollowUpQuestion(
                id: "starter-\(subject.id)-\(index)",
                subjectID: subject.id,
                text: starter.0,
                storedLevel: starter.1.rawValue
            )
        }
    }

    /// What the app opens with when there is nothing in the archive at all.
    ///
    /// `starters(for:)` covers a subject nobody has spoken about yet; this covers
    /// the moment before there is a subject. Free dictation offers the family's
    /// open questions, and on the first day there are none — so the first Tell
    /// screen anybody ever sees was the big button and nothing beside it. That is
    /// the blank button this whole file exists to remove, left standing on the one
    /// screen where it costs most: the first one an 80-year-old is handed.
    ///
    /// No subject, because there is not one to name yet. The answer is filed by
    /// extraction out of the speech itself, exactly as any other free dictation
    /// is. Not stored and not synced, for the same reason as the subject
    /// starters — a prompt is not a debt.
    ///
    /// The first two are at the bottom of the ladder and the naming question
    /// comes first, because this is the first question the app ever asks
    /// anybody.
    ///
    /// **Not only on the first day, since 30 Sep 2026.** The two stood here
    /// while the archive was empty and went with the first telling, and the
    /// photograph deck runs out too — every photograph told about, or pushed
    /// aside with *"En muista tätä"*. With no family member's question either,
    /// the screen was back to the blank button, on a phone with an archive full
    /// of photographs (founder, 30 Sep 2026). So the pair is now the front of a
    /// longer list that moves on as each one is answered, and starts again once
    /// all of them have been.
    ///
    /// Every one of them can be answered by a ten-year-old and by somebody of
    /// eighty-five, in a few words, and leads somewhere: a food leads to the
    /// person who made it, an old object to whoever owned it. Nothing assumes a
    /// working life, a marriage or a grandchild. The ids are the list index, so
    /// a new question goes at the end.
    static let opening: [FollowUpQuestion] = [
        (String(localized: "Kuka on vanhin ihminen, jonka muistat?"), QuestionLevel.naming),
        (String(localized: "Missä asuit lapsena?"), QuestionLevel.fact),
        (String(localized: "Mikä ruoka tuo mieleesi jonkun ihmisen?"), QuestionLevel.naming),
        (String(localized: "Mikä on vanhin esine, joka sinulla on?"), QuestionLevel.naming),
        (String(localized: "Kenestä suvussa kerrotaan hauskoja juttuja?"), QuestionLevel.naming),
        (String(localized: "Kenen luona oli mukavinta käydä kylässä?"), QuestionLevel.naming),
        (String(localized: "Kuka opetti sinulle jotain, mitä osaat yhä?"), QuestionLevel.naming),
        (String(localized: "Mikä oli ensimmäinen eläin, jonka muistat?"), QuestionLevel.naming),
        (String(localized: "Mikä juhla on sinulle tärkein?"), QuestionLevel.fact),
        (String(localized: "Mikä on ensimmäinen asia, jonka muistat?"), QuestionLevel.description),
    ].enumerated().map { index, starter in
        FollowUpQuestion(
            id: "opening-\(index)",
            subjectID: nil,
            text: starter.0,
            storedLevel: starter.1.rawValue
        )
    }

    /// The next opening questions nobody on this phone has answered yet, in
    /// list order. When every one has been answered the list starts again:
    /// a question answered a month ago is a better thing to put beside the
    /// button than nothing, and the answer will not be the same one.
    static func nextOpening(limit: Int = 2) -> [FollowUpQuestion] {
        var answered = Set(defaults.stringArray(forKey: openingAnsweredKey) ?? [])
        if opening.allSatisfy({ answered.contains($0.id) }) {
            defaults.removeObject(forKey: openingAnsweredKey)
            answered = []
        }
        return Array(opening.filter { !answered.contains($0.id) }.prefix(limit))
    }

    /// Moves the opening list on past a question that has been answered. Any
    /// other id is ignored, so the caller need not know which questions are
    /// opening ones.
    static func recordOpeningAnswered(_ questionID: String) {
        guard opening.contains(where: { $0.id == questionID }) else { return }
        var answered = defaults.stringArray(forKey: openingAnsweredKey) ?? []
        guard !answered.contains(questionID) else { return }
        answered.append(questionID)
        defaults.set(answered, forKey: openingAnsweredKey)
    }

    /// Forgets where the person had got to. Part of "Tyhjennä tämä laite": the
    /// ladder describes whoever holds the phone, so it leaves with them.
    static func reset() {
        defaults.removeObject(forKey: comfortKey)
        defaults.removeObject(forKey: streakKey)
        defaults.removeObject(forKey: answeredKey)
        defaults.removeObject(forKey: openingAnsweredKey)
    }

    // MARK: - Storage

    // UserDefaults rather than the store's JSON file: this is device state, not
    // family data, and it must never reach `pendingPayload`.
    private static let comfortKey = "ladder.comfort"
    private static let streakKey = "ladder.streak"
    private static let answeredKey = "ladder.answeredAt"
    private static let openingAnsweredKey = "ladder.openingAnswered"

    /// Where the four keys live: `.standard`, and nothing in the app changes
    /// it. `scripts/question-ladder-check.swift` points it at a store of the
    /// run's own, because the standard defaults of a command-line tool are a
    /// domain named after its executable: two `verify.sh` runs at once shared
    /// one ladder and failed each other's checks, five rounds out of five. The
    /// `-comfort` override above stays on `.standard`, since it is a launch
    /// argument and not something the ladder stored.
    static var defaults = UserDefaults.standard

    private static var lastAnswered: Date? {
        let stamp = defaults.double(forKey: answeredKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// The step back after a long absence — and it is only ever a step BACK.
    ///
    /// `max(1.5, value - 1)` was the whole of this until 11 Sep 2026, and the
    /// floor it was reaching for turned into a promotion at the bottom of the
    /// ladder: a beginner sitting at 1.0 came back from three weeks away at
    /// **1.5**. That is dormancy's own reason inverted — "being asked
    /// something hard on the way back is how a returning user stops
    /// returning" — applied to the one person most likely not to return. And
    /// it stuck: the next `record` reads `comfort`, so the raised value is
    /// written back, and at 1.5 `rounded()` is 2, so her answers to the
    /// naming questions the app actually offers her stop counting toward the
    /// streak. She is asked harder questions and earns nothing for answering
    /// them.
    ///
    /// `min` over the top of it. The floor still does what it was for —
    /// somebody who was at 4 comes back at 3, not at the bottom — and nobody
    /// is moved up the ladder by staying away from it.
    /// `scripts/question-ladder-check.swift` holds both halves.
    private static func decayed(_ value: Double, lastAnswered: Date?) -> Double {
        guard let lastAnswered,
              Date.now.timeIntervalSince(lastAnswered) > dormancy
        else { return value }
        return min(value, max(1.5, value - 1))
    }

    private static func clamp(_ value: Double) -> Double {
        min(top, max(bottom, value))
    }
}
