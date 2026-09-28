import Foundation

/// What the family's archive already holds, sent with a transcript so that a
/// follow-up question can aim at a hole rather than at the speech.
///
/// The questions used to be as personal as ninety seconds of talk allows, which
/// is not very. Rule 6 of the extraction prompt asks for a gap *in the speech*,
/// so the model converges on the three shapes that rule names — a person named
/// but not described, a place known only by its name, a smell or a sound — and
/// asks them again on the fourth telling as readily as on the first. Measured
/// 19 Sep 2026 against `google/gemini-3.6-flash` on one Puumala transcript, the
/// reply with no archive was *"Millainen se Puumalan mökki ja sen piha oli?"*,
/// which needed no archive to write and answers nothing the archive lacked.
///
/// Three things travel, and one of them is a photograph:
///
/// 1. **The subject** the telling was filed under, so a question can ask for the
///    year a photograph does not have.
/// 2. **What is missing** about the people and places already linked to it.
///    Names and holes only — no memory text leaves the phone for this. The
///    archive's contents stay where they are; only the shape of the gap is sent.
/// 3. **The questions already open** on that subject, so the model aims
///    elsewhere instead of being filtered down to fewer than three afterwards.
///
/// See docs/ARCHITECTURE.md §12.
struct ExtractionContext: Encodable, Equatable {
    struct SubjectBrief: Encodable, Equatable {
        let kind: String
        let title: String?
        /// Already rendered — "1950-luku", "kesäkuu 1957". `DateHint.displayText`
        /// owns this wording and the Worker has no business owning it twice.
        let date: String?
        let place: String?
        let memories: Int
    }

    /// The closed vocabulary of holes. The Worker turns each of these into a
    /// Finnish or English phrase, which is why it is a word from a list rather
    /// than a sentence: a gap the client could write freely would be a prompt
    /// the client could write freely.
    ///
    /// Every one of them is answerable by TALKING, which is the whole test for
    /// membership. A missing photograph is a real hole in an archive and it is
    /// not on this list: *"onko teillä valokuvaa Ainosta?"* is answered "kyllä
    /// on" and then nothing has been told. Worse, `QuestionLadder.outcome`
    /// measures an answer against the level's word floor, so the honest answer
    /// to a photograph question reads as strain and drops the teller a whole
    /// level — a question that punishes the person for answering it correctly.
    /// Photographs are asked for on Albumi, by a hand that can go and find one.
    enum Gap: String, Encodable, CaseIterable {
        case date, place
        case birthYear = "birth_year"
        case relation, description
    }

    struct KnownSubject: Encodable, Equatable {
        let name: String
        let kind: String
        let memories: Int
        let missing: [String]
    }

    var subject: SubjectBrief?
    var known: [KnownSubject] = []
    var asked: [String] = []

    var isEmpty: Bool { subject == nil && known.isEmpty && asked.isEmpty }
}

extension ExtractionContext {
    /// Builds the context for a telling about `target`.
    ///
    /// Pure, and over the model types rather than over `MemoryStore`, so that a
    /// check can run it on a laptop. The store's own `extractionContext(for:)`
    /// in `ExtractionContext+Store.swift` is the one line that hands it the
    /// four arrays. That is not tidiness: `MemoryStore` reaches `MediaStore`
    /// and so reaches UIKit, and a check that needs UIKit needs a booted
    /// simulator, which is what put `family_crypto` a week out of date once
    /// already. `verify.sh` runs this one for nothing.
    ///
    /// `target` is nil in free dictation, where there is no subject until after
    /// extraction. The context is then the open questions alone, which is still
    /// worth sending: repeating a question does not need a subject to happen.
    static func build(
        target: Subject?,
        subjects: [Subject],
        memories: [Memory],
        relations: [Relation],
        questions: [FollowUpQuestion]
    ) -> ExtractionContext {
        var context = ExtractionContext()
        let live = memories.filter { $0.deletedAt == nil }

        if let target {
            let own = live.filter { $0.subjectID == target.id }
            context.subject = SubjectBrief(
                kind: target.kind.rawValue,
                // `displayTitle` is deliberately not used: it falls back to
                // *"Valokuva"*, and a fallback sent as a title tells the model
                // the photograph is called Valokuva. An untitled subject has no
                // title, and that absence is the useful fact.
                title: target.title.isEmpty ? nil : target.title,
                date: target.dateHint.map(\.displayText),
                place: target.place == nil ? nil : target.title,
                memories: own.count
            )
            let named = Set(own.flatMap(\.mentionedSubjectIDs))
            context.known = subjects
                .filter { named.contains($0.id) && $0.deletedAt == nil && $0.mergedInto == nil }
                .compactMap { brief(for: $0, memories: live, relations: relations) }
        }

        // Every open question on the subject, not the three the ladder would
        // pick. The ladder chooses what to SHOW; this list is what not to write
        // again, and a question left out of it is one the model is free to
        // produce for the second time.
        context.asked = questions
            .filter { question in
                guard !question.answered else { return false }
                guard let target else { return question.subjectID == nil }
                return question.subjectID == target.id
            }
            .map(\.text)

        return context
    }

    /// What the archive still does not know about one person or place.
    ///
    /// Unconfirmed proposals are included deliberately. Somebody the AI
    /// proposed and nobody has confirmed is exactly who most needs asking
    /// about — rule 4 says a human confirms, and a question is how the asking
    /// happens. What must not follow is the model asserting they are real, and
    /// that is the prompt's half of the rule rather than this one's.
    private static func brief(
        for subject: Subject,
        memories: [Memory],
        relations: [Relation]
    ) -> KnownSubject? {
        guard subject.kind == .person || subject.kind == .place else { return nil }
        guard !subject.title.isEmpty else { return nil }

        var missing: [Gap] = []
        let about = memories.filter { $0.subjectID == subject.id }
        let mentioning = memories.filter { $0.mentionedSubjectIDs.contains(subject.id) }

        if subject.dateHint == nil {
            missing.append(subject.kind == .person ? .birthYear : .date)
        }
        if subject.kind == .place, subject.place == nil { missing.append(.place) }
        // Named but never described: every appearance is inside somebody else's
        // story and nothing has ever been told about them. This is the hole the
        // old prompt aimed at by guessing; here it is a fact.
        if about.isEmpty { missing.append(.description) }
        if subject.kind == .person, !relations.contains(where: {
            $0.deletedAt == nil && ($0.fromSubjectID == subject.id || $0.toSubjectID == subject.id)
        }) {
            missing.append(.relation)
        }

        return KnownSubject(
            name: subject.title,
            kind: subject.kind.rawValue,
            memories: about.count + mentioning.count,
            missing: missing.map(\.rawValue)
        )
    }
}

// MARK: - Not asking the same thing twice

extension ExtractionContext {
    /// Drops a fresh question that repeats one already open.
    ///
    /// The list of already-asked questions goes to the model and the model is
    /// told not to repeat them, and that is the half that produces a better
    /// question rather than merely fewer. This is the other half: the model is
    /// asked, not obeyed, and `MemoryStore.add(questions:)` appends whatever it
    /// is handed. Three questions per telling for ever, with nothing between
    /// them and the archive, is why the fourth telling about one photograph used
    /// to produce the first telling's questions again.
    ///
    /// The comparison is deliberately crude — case and punctuation folded away,
    /// then a shared-word ratio. A near-miss left in is one repeated question; a
    /// good question thrown out is a hole nobody ever hears about, so the
    /// threshold sits high enough that only a restatement trips it.
    ///
    /// Except between people, where no threshold can tell. *"Millainen
    /// ihminen Kalle oli?"* shares three of its four words with Aino's
    /// question, and until 28 Sep 2026 it was dropped as its repeat, in
    /// either language: the question the archive asked about one person it
    /// never asked about the next. So two questions that each name somebody
    /// the other does not are two questions, however many words they share
    /// (`names(in:)`).
    static func deduplicated(_ incoming: [String], against existing: [String]) -> [String] {
        var kept: [String] = []
        var seen = existing.map { (words: words(of: $0), names: names(in: $0)) }
        for question in incoming {
            let candidate = (words: words(of: question), names: names(in: question))
            guard !candidate.words.isEmpty else { continue }
            let repeats = seen.contains {
                !differentPeople(candidate.names, $0.names) && overlap(candidate.words, $0.words) >= 0.7
            }
            if repeats { continue }
            kept.append(question)
            seen.append(candidate)
        }
        return kept
    }

    /// The question reduced to the words that carry it. Finnish inflection is
    /// left alone: "Ainon" and "Aino" do not fold together, so two questions
    /// about the same person in different cases both survive. That is the
    /// direction to err in — this decides what to throw away.
    private static func words(of question: String) -> Set<String> {
        Set(
            question
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    /// The names in a question: every word with a capital that does not open
    /// a sentence, since the word that opens one has a capital whatever it is.
    /// Taken as they stand, inflection and all, for the reason `words(of:)`
    /// gives: *"Ainosta"* is not *"Aino"*, so the same person moved into
    /// another case reads as somebody else and both questions survive. A name
    /// that opens the question is not seen at all, which leaves the ratio to
    /// decide as before; the model's questions open with the question word.
    private static func names(in question: String) -> Set<String> {
        var names: Set<String> = []
        for sentence in question.components(separatedBy: CharacterSet(charactersIn: ".?!")) {
            let tokens = sentence.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            for token in tokens.dropFirst() where token.count > 1 && token.first?.isUppercase == true {
                names.insert(token.lowercased())
            }
        }
        return names
    }

    /// Whether each of two questions names somebody the other does not.
    ///
    /// Not merely different names: *"Millainen ihminen hän oli?"* names
    /// nobody, and a question that adds a second name on the end is the
    /// longer restatement `overlap` already folds. A question in capitals
    /// throughout has a capital on every word, so it names every word it has,
    /// and a question about the same person names nobody it lacks: the ratio
    /// decides, as before.
    private static func differentPeople(_ a: Set<String>, _ b: Set<String>) -> Bool {
        !a.isSubset(of: b) && !b.isSubset(of: a)
    }

    /// The most questions one subject carries open before a model's reply
    /// adds no more to it.
    ///
    /// De-duplication stops the list repeating itself; it does not stop it
    /// growing, because every telling brings three new questions and answers at
    /// most one. A photograph somebody has talked about eight times would have
    /// twenty questions waiting under it, and a pile that size gives the
    /// family nothing to act on. Five is enough for the ladder to choose from
    /// at every level. A question a person asked is never held back
    /// (`AskQuestionSheet`), but it does count towards the five.
    static let openQuestionCap = 5

    /// What the archive takes from a model's reply: the questions that are not
    /// a repeat, and only as many of them as fit under `openQuestionCap`.
    ///
    /// `answeringNow` is the question the telling was an answer to. It is
    /// still open when this runs, so it still counts as something already
    /// asked, but its slot is free: an answer should make room for the next
    /// question rather than be blocked by the question it just answered.
    ///
    /// When there is room for fewer than all of them, the first ones are kept
    /// in the model's order. When the teller's level is sent, the prompt asks
    /// for the easier question first (QUESTION DEMAND in `extract.ts`). The
    /// model is not bound by that, but it is the only ordering there is.
    static func admitted(_ incoming: [String], against open: [String], answeringNow: String? = nil) -> [String] {
        let freed = answeringNow.map { open.contains($0) ? 1 : 0 } ?? 0
        let room = max(0, openQuestionCap - (open.count - freed))
        return Array(deduplicated(incoming, against: open).prefix(room))
    }

    /// What a telling does to the questions open on its card: the fresh ones
    /// it lets in, and the ids of the machine's older ones they replace.
    struct Turnover: Equatable {
        var admitted: [String]
        var retired: [String]
    }

    /// The newest telling's questions replace the machine's older ones on the
    /// same card, since 28 Sep 2026.
    ///
    /// The cap alone froze a card's questions at whatever its first tellings
    /// raised. Two tellings fill five slots, and from then on a reply was
    /// admitted nothing: questions written from a transcript alone, before the
    /// extraction was shown the archive and the photograph (19 Sep), stayed
    /// on the card for good, and every later telling's questions about the
    /// photograph were dropped at the gate. It showed on an older card, whose
    /// open questions had nothing in particular to do with the photograph or
    /// with what had been told under it.
    ///
    /// So a reply that brings anything new retires every open question the
    /// extraction wrote on that card, and takes their place. The newest reply
    /// is the best-informed one there is: it saw the photograph, the
    /// archive's holes and every question still open, and was asked not to
    /// repeat any of them. Three things are never retired: a question a person
    /// asked (`FollowUpQuestion.isMachine`), which still counts towards the
    /// cap, so five of them leave no room and retire nothing; the question
    /// this telling answers, which is marked answered next, and answered
    /// history stays; and anything at all when nothing new came, because a
    /// failed or verbatim extraction, or a reply that only restated what is
    /// open, must not empty a card.
    ///
    /// A fresh question is compared only with what stays. One that restates a
    /// retiring question replaces it, rather than being dropped as a repeat of
    /// a question that is about to go.
    static func turnover(
        _ incoming: [String],
        on open: [FollowUpQuestion],
        answering questionID: String? = nil
    ) -> Turnover {
        let retiring = open.filter { $0.isMachine && $0.id != questionID }
        let staying = open.filter { question in !retiring.contains { $0.id == question.id } }
        let fresh = admitted(
            incoming,
            against: staying.map(\.text),
            answeringNow: staying.first { $0.id == questionID }?.text
        )
        return Turnover(admitted: fresh, retired: fresh.isEmpty ? [] : retiring.map(\.id))
    }

    /// How much of the shorter question is contained in the longer one.
    ///
    /// Not a symmetric measure on purpose: *"Millainen ihminen Aino oli?"* and
    /// *"Millainen ihminen Aino oli ja mitä hän teki työkseen?"* are the same
    /// question asked twice, and a symmetric ratio would score them apart
    /// because the second is longer.
    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        let smaller = a.count <= b.count ? a : b
        guard !smaller.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(smaller.count)
    }
}
