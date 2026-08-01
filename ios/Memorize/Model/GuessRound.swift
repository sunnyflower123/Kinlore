import Foundation

/// "Someone tells a story and the others guess who it was about."
///
/// The round is derived, never stored. Any memory that names exactly one person
/// is a round for every family member who did not tell it. Storing rounds would
/// mean deciding in advance which memories become questions, and that decision
/// goes stale the moment a misheard name is corrected or two people are merged.
///
/// What the round is *for* matters more than the game: a blind guess is the
/// strongest human confirmation this app can collect. A proposal card with the
/// answer already written on it gets tapped "yes" without being read. Someone
/// who was not shown the name and arrives at it anyway has actually recognised
/// the person — see rule 4 in CLAUDE.md.
struct GuessRound: Identifiable, Hashable {
    var id: String { memory.id }
    let memory: Memory
    /// Who the story was really about.
    let answer: Subject
    /// The answer and three others, in an order that is the same on every
    /// device and does not shuffle between redraws.
    let options: [Subject]
    /// The memory text with every inflected form of the answer's name removed.
    let maskedBody: String
}

// MARK: - Building

enum GuessRoundBuilder {
    /// What replaces a masked name. An em dash run rather than "[nimi]": it
    /// reads as a gap in the sentence instead of as a form field, and VoiceOver
    /// says nothing for it, which is exactly right — the gap is the question.
    static let mask = "———"

    /// Four options. Three is too easy in a family of four; five does not fit on
    /// one screen at the largest text size, and this screen has to.
    static let optionCount = 4

    /// Screenshot and demo aid, alongside `-tab` and `-screen`: `-guess demo`
    /// builds rounds from memories you told yourself. A round otherwise needs a
    /// second family member, and a screenshot run has only one device — which is
    /// also true of the phone the demo video is filmed on. DEBUG builds only.
    private static var allowsOwnMemories: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "guess") == "demo"
        #else
        return false
        #endif
    }

    /// The round waiting for one member, newest memory first, or nothing.
    ///
    /// Lazy on purpose. Most memories are not rounds, this runs on every redraw
    /// of the memories screen, and masking is the expensive part — so the answer
    /// is found by building one round rather than all of them.
    @MainActor
    static func nextRound(store: MemoryStore, memberID: String) -> GuessRound? {
        unanswered(store: store, memberID: memberID)
            .compactMap { round(for: $0, store: store, memberID: memberID) }
            .first
    }

    /// How many rounds are waiting, counted no higher than `limit`.
    ///
    /// The tab badge needs a number, and the honest number is not free: knowing
    /// whether a memory is a round means building it. So the count stops at the
    /// cap — a family with eleven rounds waiting and one with nine are the same
    /// thing to the person looking at the badge.
    @MainActor
    static func roundsWaiting(store: MemoryStore, memberID: String, limit: Int = 9) -> Int {
        var count = 0
        for memory in unanswered(store: store, memberID: memberID) {
            if round(for: memory, store: store, memberID: memberID) != nil {
                count += 1
                if count == limit { break }
            }
        }
        return count
    }

    /// The memories this member has not answered yet, newest first. Lazy, so a
    /// caller that only wants the first round does not mask all of them.
    @MainActor
    private static func unanswered(
        store: MemoryStore, memberID: String
    ) -> LazySequence<[Memory]> {
        let answered = Set(
            store.guesses.filter { $0.memberID == memberID }.map(\.memoryID)
        )
        return store.memories
            .filter { !answered.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .lazy
    }

    /// Builds the round for one memory, or nothing if it does not make one.
    ///
    /// Most memories do not. That is the point: a round has to be safe before it
    /// is fun, and a leaked answer or an ambiguous question is worse than no
    /// round at all.
    @MainActor
    static func round(for memory: Memory, store: MemoryStore, memberID: String) -> GuessRound? {
        guard !memory.isAwaitingTranscription, !memory.body.isEmpty else { return nil }

        // You cannot guess your own story. An unknown author means we wrote it
        // ourselves before the first sync — a single-device archive has nobody
        // to guess and therefore no rounds, which is correct rather than a gap.
        if !allowsOwnMemories {
            guard let authorID = memory.authorID, authorID != memberID else { return nil }
        }

        // Exactly one person. Two named people make the question ambiguous, and
        // an ambiguous question teaches the family the wrong answer.
        guard let answer = store.soleMentionedPerson(in: memory), !answer.title.isEmpty else {
            return nil
        }

        // A memory told *about* Aino answers itself: her card is the subject the
        // round would be reached from, and the title is on screen.
        guard memory.subjectID != answer.id else { return nil }

        guard let masked = maskName(answer.title, in: memory.body) else { return nil }
        // Enough story has to survive the masking to recognise anybody from.
        // Fifteen words is about a sentence and a half — below that the round is
        // not a question about a person, it is a coin toss between four names.
        guard masked.readableWords >= minimumReadableWords else { return nil }
        // And the text must not be mostly gaps. A name said six times in six
        // sentences is normal speech; six gaps in twelve words is damage.
        guard masked.maskedWords * 4 <= masked.totalWords else { return nil }

        let others = store.subjects(of: .person)
            .filter { $0.id != answer.id && !$0.title.isEmpty }
        // Fewer than three others is not a guess, it is a formality.
        guard others.count >= optionCount - 1 else { return nil }

        // Decoys are drawn from the people the family has actually talked about,
        // and only then from the rest. A round between one real relative and
        // three names nobody has ever said out loud is not a question — the
        // answer is whichever name you recognise. Within each group the order is
        // the stable hash, so the choice is still the same on every device.
        let decoys = others
            .sorted { first, second in
                let firstKnown = !store.isEmpty(first), secondKnown = !store.isEmpty(second)
                if firstKnown != secondKnown { return firstKnown }
                return stableHash(memory.id + ":" + first.id) < stableHash(memory.id + ":" + second.id)
            }
            .prefix(optionCount - 1)
        let options = ([answer] + decoys)
            .sorted { stableHash(memory.id + "#" + $0.id) < stableHash(memory.id + "#" + $1.id) }

        return GuessRound(
            memory: memory, answer: answer, options: options, maskedBody: masked.text
        )
    }

    // MARK: - Masking

    /// The shortest story worth guessing from, in words that are still readable
    /// after the name has been taken out.
    static let minimumReadableWords = 15

    struct MaskedText {
        let text: String
        let maskedWords: Int
        let totalWords: Int
        var readableWords: Int { totalWords - maskedWords }
    }

    /// Removes a name from a memory's text, in every form Finnish inflection
    /// gives it.
    ///
    /// A plain string replacement is useless here: it removes "Aino" and leaves
    /// "Ainolle" standing two words later. Matching is done on the stem instead —
    /// the beginning of the word that a case ending cannot eat — and guarded on
    /// two sides:
    ///
    /// - the word must be **capitalised in the text**, which is how an inflected
    ///   Finnish name is written and how "ainakin" stays out of it;
    /// - the word must not be much longer than the name, which keeps
    ///   "ainoastaan" from vanishing because it happens to start the same way.
    ///
    /// Returns nil when there is nothing to hide: the name does not appear in
    /// the text at all. Whether what is left is *enough* is a separate question
    /// and belongs with the other round rules, not here.
    static func maskName(_ name: String, in body: String) -> MaskedText? {
        let stems = name
            .split(whereSeparator: { !isNameCharacter($0) })
            .map(String.init)
            .filter { $0.count >= 3 && ($0.first?.isUppercase ?? false) }
            .map { (stem: stem(of: $0), limit: $0.count + 5) }
        guard !stems.isEmpty else { return nil }

        var output = ""
        var token = ""
        var tokenCount = 0
        var maskedCount = 0

        func flush() {
            guard !token.isEmpty else { return }
            tokenCount += 1
            if matches(token, stems: stems) {
                maskedCount += 1
                output += mask
            } else {
                output += token
            }
            token = ""
        }

        for character in body {
            if isNameCharacter(character) {
                token.append(character)
            } else {
                flush()
                output.append(character)
            }
        }
        flush()

        // Nothing was hidden, so nothing is being asked. This is the common
        // case for a memory that talks about someone without naming them, and
        // those memories are not rounds.
        guard maskedCount > 0 else { return nil }

        let collapsed = collapseAdjacentMasks(in: output)
        // Collapsing "Isoäiti Aino" into one gap merges two masked words into
        // one, and the counts have to follow: otherwise a two-word name looks
        // like twice as much damage as it does on screen.
        let remaining = collapsed.components(separatedBy: mask).count - 1
        let merged = maskedCount - remaining
        return MaskedText(
            text: collapsed,
            maskedWords: remaining,
            totalWords: tokenCount - merged
        )
    }

    /// The part of a word that survives inflection.
    ///
    /// Two characters of slack covers the ordinary cases ("Aino" → "Ainolle",
    /// "Puumala" → "Puumalassa", "Pekka" → "Pekan"). The `-nen` surnames get
    /// their own rule, because their stem changes further in than that:
    /// "Virtanen" → "Virtasen" already differs at the sixth character.
    private static func stem(of word: String) -> String {
        let lowered = word.lowercased()
        if lowered.hasSuffix("nen"), lowered.count > 4 {
            return String(lowered.dropLast(3))
        }
        return String(lowered.prefix(max(3, lowered.count - 2)))
    }

    private static func matches(_ token: String, stems: [(stem: String, limit: Int)]) -> Bool {
        // Capitalisation is half the guard. A Finnish name keeps its capital
        // when inflected ("Ainolle"), and an ordinary word only has one at the
        // start of a sentence — where it would still have to match a stem.
        guard token.first?.isUppercase == true else { return false }
        let lowered = token.lowercased()
        return stems.contains { token.count <= $0.limit && lowered.hasPrefix($0.stem) }
    }

    /// "Isoäiti Aino" masks to two gaps in a row. One gap is the question; two
    /// in a row just look like damage.
    private static func collapseAdjacentMasks(in text: String) -> String {
        var result = text
        for separator in [" ", "-", " - "] {
            while let range = result.range(of: mask + separator + mask) {
                result.replaceSubrange(range, with: mask)
            }
        }
        return result
    }

    /// Hyphens and apostrophes belong to the name: "Liisa-Maija" and "O'Brien"
    /// are one word, and splitting them would mask half a name.
    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "-" || character == "'" || character == "’"
    }

    // MARK: - Stable ordering

    /// FNV-1a. Swift's own `hashValue` is seeded per process, so it would put
    /// the answer in a different slot every launch and in a different slot on
    /// each family member's phone — and "which option moved" is itself a clue.
    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}
