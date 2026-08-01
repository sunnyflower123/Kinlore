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
        let stored = UserDefaults.standard.object(forKey: comfortKey) as? Double ?? start
        return decayed(stored, lastAnswered: lastAnswered)
    }

    /// Records how an answer went and moves the ladder.
    static func record(_ outcome: Outcome, at level: QuestionLevel) {
        var value = comfort
        var streak = UserDefaults.standard.integer(forKey: streakKey)

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

        let defaults = UserDefaults.standard
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
    static func starters(for subject: Subject) -> [FollowUpQuestion] {
        // The level is written out rather than inferred. These texts were chosen
        // for their level, and a reworded starter must not quietly become a
        // harder question than the one place in the app that promises an easy
        // one.
        let texts: [(String, QuestionLevel)]
        switch subject.kind {
        case .photo:
            texts = [
                ("Kuka tässä kuvassa on?", .naming),
                ("Missä tämä kuva on otettu?", .fact),
                ("Minä vuonna tämä suunnilleen otettiin?", .fact),
            ]
        case .person:
            // The name stays in the nominative in every one of these. Finnish
            // inflection cannot be done with string concatenation, and "Ainon"
            // built in code would be wrong exactly as often as it was right.
            let name = subject.displayTitle
            texts = [
                ("Kuka \(name) oli sinulle?", .naming),
                ("Missä \(name) asui?", .fact),
            ]
        case .place:
            texts = [
                ("Milloin olit siellä viimeksi?", .fact),
                ("Kuka siellä asui?", .naming),
            ]
        case .event:
            texts = [
                ("Ketkä siellä olivat?", .naming),
                ("Milloin tämä tapahtui?", .fact),
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

    // MARK: - Storage

    // UserDefaults rather than the store's JSON file: this is device state, not
    // family data, and it must never reach `pendingPayload`.
    private static let comfortKey = "ladder.comfort"
    private static let streakKey = "ladder.streak"
    private static let answeredKey = "ladder.answeredAt"

    private static var lastAnswered: Date? {
        let stamp = UserDefaults.standard.double(forKey: answeredKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    private static func decayed(_ value: Double, lastAnswered: Date?) -> Double {
        guard let lastAnswered,
              Date.now.timeIntervalSince(lastAnswered) > dormancy
        else { return value }
        return max(1.5, value - 1)
    }

    private static func clamp(_ value: Double) -> Double {
        min(top, max(bottom, value))
    }
}
