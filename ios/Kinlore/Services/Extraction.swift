import Foundation

/// Extracting structure out of raw speech.
///
/// The protocol is separate from the implementation so that the UI can be built
/// against a stub. Switching to the real implementation (Worker → LLM) is a
/// one-line change in `AppServices` and touches no view at all.

// MARK: - Result

/// Mirrors exactly what the LLM's structured output returns and what the schema
/// expects: `memory.body`, `mention`, `subject.date_*` and `prompt_question`.
struct ExtractionResult: Equatable {
    /// The cleaned text. Rambling removed, content intact.
    var body: String
    var mentions: [MentionedEntity]
    var dateHint: DateHint?
    /// Three questions. More overwhelms, fewer do not carry the story forward.
    var questions: [ExtractedQuestion]

    /// The transcript as its own result: the words, and no structure claimed
    /// around them.
    ///
    /// Used when a transcript exists but extraction could not be had — see
    /// `TranscriptionCatchUp`. It is not a lesser memory in the way that
    /// matters: what was said is all there, only unorganised.
    static func verbatim(_ transcript: String) -> ExtractionResult {
        ExtractionResult(body: transcript, mentions: [], dateHint: nil, questions: [])
    }

    /// A title from the place and the time: "Puumalassa, 1950-luku".
    ///
    /// Nil if the speech yielded neither, because leaving a subject unnamed is
    /// more honest than inventing a title out of nothing — and an untitled
    /// subject is filled in by the next thing said about it.
    ///
    /// It lives on the result rather than in the Tell screen because naming a
    /// subject after an extraction is the same rule wherever it happens: a
    /// memory told just now, and one whose text arrived a week late.
    func suggestedTitle(mentioned: [Subject]) -> String? {
        var parts: [String] = []
        if let place = mentioned.first(where: { $0.kind == .place }) {
            parts.append(place.title)
        }
        if let dateHint, dateHint.precision != .unknown {
            parts.append(dateHint.displayText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// A follow-up question and how much it asks of the teller, 1–5.
///
/// The level is the extraction's own label — it knows what it meant by the
/// question. Nil when it did not label one, and the level is then read off the
/// wording instead. See `QuestionLadder` and docs/ARCHITECTURE.md §12.
struct ExtractedQuestion: Equatable, Hashable {
    var text: String
    var level: Int?
}

struct MentionedEntity: Equatable, Hashable {
    var name: String
    var kind: SubjectKind
    /// The LLM's confidence that it parsed the name correctly — not that the
    /// person is right, which no model can know.
    ///
    /// **Nothing reads it.** The threshold this comment described until
    /// 9 Sep 2026 does not exist: `findOrCreateSubject` is called with
    /// `confirmed: false` unconditionally, so every mentioned person and place
    /// arrives as a proposal whatever the model claims. That is rule 4 enforced
    /// more strictly than the schema and the prompt describe, and it is the
    /// right way round — a model confident about a misheard name is exactly the
    /// case §17 exists for.
    var confidence: Double
}

/// A name correction made by the teller. Speech recognition gets roughly one
/// proper noun in three wrong, and a wrong name builds a wrong person into the
/// family tree.
struct NameCorrection: Equatable, Hashable {
    let from: String
    let to: String
}

protocol ExtractionService {
    /// `level` is where the teller currently is on the question ladder, 1–5. It
    /// aims the follow-up questions: without it they come out at level 3–4 every
    /// time, because a question aimed at a gap is naturally a "tell me about"
    /// question — a wall for somebody who has not answered anything yet.
    func extract(
        transcript: String,
        corrections: [NameCorrection],
        level: Int?
    ) async throws -> ExtractionResult
}

extension ExtractionService {
    func extract(transcript: String, level: Int?) async throws -> ExtractionResult {
        try await extract(transcript: transcript, corrections: [], level: level)
    }
}

// MARK: - Requirement on the real implementation
//
// **Names must be returned in base form.** Finnish inflection makes this
// essential: speech contains "Ainon", "Ainolle" and "Aino", and if the LLM
// returns the surface form, `MemoryStore.findOrCreateSubject` creates three
// different people from them. The family tree fills with duplicates that nobody
// can later merge, and that is precisely the error the principle "AI proposes, a
// human confirms" cannot catch — the user confirms three correct names without
// knowing they are the same person.
//
// The same applies to places: "Puumalassa" → "Puumala". Question texts may use
// an inflected form, but `subject.title` may not.
//
// The stub cannot do this, because it picks words as they appear. That is a
// known limitation rather than a bug to fix — base-form normalisation belongs to
// the language model.

// MARK: - Stub

/// The development implementation. It genuinely picks proper nouns and years out
/// of the text, so the UI can be developed against realistic data before an LLM
/// key exists. It does not try to be clever — the real implementation does that.
///
/// The Finnish string literals below are heuristics over Finnish text and text
/// shown in the Finnish UI, not documentation.
struct StubExtractionService: ExtractionService {
    /// Simulates network latency, so the loading animation is designed under
    /// real conditions rather than as a flash.
    var simulatedDelay: Duration = .milliseconds(2200)

    func extract(
        transcript: String,
        corrections: [NameCorrection],
        level: Int?
    ) async throws -> ExtractionResult {
        try await Task.sleep(for: simulatedDelay)
        if let film = Self.filmResult(for: transcript, corrections: corrections, level: level) {
            return film
        }

        // The stub cannot inflect, so it only replaces the base form. The real
        // implementation handles inflection — here it is enough that the
        // correction is visible.
        var text = transcript
        for correction in corrections {
            text = text.replacingOccurrences(of: correction.from, with: correction.to)
        }

        let names = Self.properNouns(in: text).map { name -> String in
            corrections.first { $0.from == name }?.to ?? name
        }
        let mentions = names.map {
            // A rough split: Finnish place names often carry the -ssa/-lla endings.
            MentionedEntity(
                name: $0,
                kind: Self.looksLikePlace($0, in: text) ? .place : .person,
                confidence: 0.7
            )
        }

        return ExtractionResult(
            body: Self.tidy(text),
            mentions: mentions,
            dateHint: Self.dateHint(in: text),
            questions: Self.questions(for: mentions, level: level)
        )
    }

    // MARK: The film's sample

    /// `-sample film`: what the pipeline made of the film's own telling,
    /// played back verbatim — so a take shows a real extraction without a
    /// network, and the same one on every attempt.
    ///
    /// The heuristics below cannot read that sentence, and it is worth
    /// knowing why: "Elli and Toivo." starts a sentence, so its first name is
    /// never a proper noun to them; "the thirties" is not a year; and "at the
    /// jetty" puts the place in front of the wrong word. Cheap and visible in
    /// development, and useless on camera, where the screen has to show what
    /// the app really made of these words. Until SHOOT-v16.md §1 has been
    /// done, the mentions and the decade here are the film's script rather
    /// than a measurement, like the names in `-seed film`.
    static func filmResult(for transcript: String, corrections: [NameCorrection], level: Int?) -> ExtractionResult? {
        guard UserDefaults.standard.string(forKey: "sample") == "film" else { return nil }
        let corrected = { (name: String) -> String in corrections.first { $0.from == name }?.to ?? name }
        let mentions = [
            MentionedEntity(name: corrected("Puumala"), kind: .place, confidence: 0.9),
            MentionedEntity(name: corrected("Elli"), kind: .person, confidence: 0.6),
            MentionedEntity(name: corrected("Toivo"), kind: .person, confidence: 0.8),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current
        let decade = DateHint(
            start: calendar.date(from: DateComponents(year: 1930, month: 1, day: 1)),
            end: calendar.date(from: DateComponents(year: 1939, month: 1, day: 1)),
            precision: .decade
        )
        return ExtractionResult(
            body: tidy(transcript),
            mentions: mentions,
            dateHint: decade,
            questions: questions(for: mentions, level: level)
        )
    }

    // MARK: Heuristics

    /// Capitalised words that do not start a sentence.
    static func properNouns(in text: String) -> [String] {
        var found: [String] = []
        for sentence in text.components(separatedBy: CharacterSet(charactersIn: ".!?")) {
            let words = sentence.split(separator: " ").map(String.init)
            for word in words.dropFirst() {
                let clean = word.trimmingCharacters(in: .punctuationCharacters)
                guard let first = clean.first, first.isUppercase, clean.count > 2 else { continue }
                if !found.contains(clean) { found.append(clean) }
            }
        }
        return found
    }

    /// Finnish tells you a place by its case ending. English does not tell you
    /// at all, so the stub reads the word in front of the name instead — the
    /// same signal a person uses, and the only one available without a model.
    ///
    /// This is the stub, so being wrong is cheap and being SILENTLY wrong is
    /// not: before this, every English place came back a person, and a demo
    /// filmed on the stub would have shown the family tree growing a row called
    /// Ambleside.
    static func looksLikePlace(_ name: String, in text: String = "") -> Bool {
        let suffixes = ["ssa", "ssä", "lla", "llä", "sta", "stä", "lta", "ltä"]
        if suffixes.contains(where: { name.lowercased().hasSuffix($0) }) { return true }
        for preposition in ["in ", "at ", "to ", "from ", "near "] {
            if text.lowercased().contains(preposition + name.lowercased()) { return true }
        }
        return false
    }

    /// Picks either a four-digit year or a decade of the "50-luvulla" form.
    static func dateHint(in text: String) -> DateHint? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current

        func date(year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        }

        if let match = text.firstMatch(of: /\b(1[89]\d{2}|20\d{2})\b/),
           let year = Int(match.1) {
            return DateHint(start: date(year: year), end: date(year: year), precision: .year)
        }

        if let match = text.firstMatch(of: /\b([2-9]0)-luvu/),
           let short = Int(match.1) {
            // 20–90 is read as the 1900s: talk about old photographs means the
            // last century in practice every time.
            let decade = 1900 + short
            return DateHint(start: date(year: decade), end: date(year: decade + 9), precision: .decade)
        }

        return nil
    }

    /// Removes filler words but does not condense the content. The length of a
    /// memory is part of the memory — the real implementation may reshape, not
    /// shorten.
    static func tidy(_ text: String) -> String {
        // Both languages' fillers in one list. They cannot collide — no Finnish
        // filler is an English word or the other way round — so the stub does
        // not need to be told which language it is imitating here.
        let fillers = [
            "niinku", "tota", "öö", "ää", "siis niinku",
            "um", "uh", "erm", "you know", "I mean", "sort of",
        ]
        var result = text
        for filler in fillers {
            result = result.replacingOccurrences(
                of: "\\b\(filler)\\b,?\\s*",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The questions target the gaps: a mentioned person nothing was said about,
    /// or a place only known by name.
    ///
    /// The type has to be taken into account. A bare list of names produces
    /// questions like "Millainen ihminen Puumalassa oli?" — that destroys the
    /// credibility of the whole magic moment, because the user sees immediately
    /// that the program understands nothing.
    /// The spread across levels mirrors what the real prompt asks for — one
    /// question below where the teller is, one at it, one above — so the ladder
    /// can be developed and filmed without a backend.
    static func questions(for mentions: [MentionedEntity], level: Int?) -> [ExtractedQuestion] {
        let people = mentions.filter { $0.kind == .person }.map(\.name)
        let places = mentions.filter { $0.kind == .place }.map(\.name)

        // The real questions come back from the model in the language that was
        // spoken. Until 30 Aug 2026 the stub answered Finnish whatever the app
        // was showing, so an English screen carried Finnish questions — visible
        // in the first English screenshot ever taken of this app, and it would
        // have been visible in the film.
        let english = SpokenLanguage.current == "en"

        var pool = english
            ? [
                ExtractedQuestion(text: "Who else was there?", level: 1),
                ExtractedQuestion(text: "Roughly what year was this?", level: 2),
                ExtractedQuestion(text: "Do you remember how it smelled, or sounded?", level: 4),
                ExtractedQuestion(text: "What would you want your grandchildren to know about this?", level: 5),
            ]
            : [
                ExtractedQuestion(text: "Kuka muu oli paikalla?", level: 1),
                ExtractedQuestion(text: "Minä vuonna tämä suunnilleen oli?", level: 2),
                ExtractedQuestion(text: "Muistatko miltä siellä tuoksui tai kuulosti?", level: 4),
                ExtractedQuestion(text: "Mitä toivoisit lastenlastesi tietävän tästä?", level: 5),
            ]
        if let first = people.first {
            pool.append(ExtractedQuestion(
                text: english ? "What sort of person was \(first)?" : "Millainen ihminen \(first) oli?",
                level: 3
            ))
        }
        if people.count > 1 {
            pool.append(ExtractedQuestion(
                text: english
                    ? "How did \(people[0]) and \(people[1]) know each other?"
                    : "Miten \(people[0]) ja \(people[1]) tunsivat toisensa?",
                level: 3
            ))
        }
        if let place = places.first {
            // In Finnish speech a place name arrives already inflected
            // ("Puumalassa"), so the question is built to avoid inflecting it
            // again. English needs no such care and reads better without it.
            pool.append(ExtractedQuestion(
                text: english
                    ? "What else happened at \(place)?"
                    : "\(place) — mitä muuta siellä tapahtui?",
                level: 4
            ))
        }

        let aim = level ?? 3
        var chosen: [ExtractedQuestion] = []
        for target in [aim - 1, aim, aim + 1] {
            let wanted = min(5, max(1, target))
            let remaining = pool.filter { candidate in
                !chosen.contains { $0.text == candidate.text }
            }
            guard let pick = remaining.min(by: {
                abs(($0.level ?? 3) - wanted) < abs(($1.level ?? 3) - wanted)
            }) else { break }
            chosen.append(pick)
        }
        return chosen
    }
}

#if DEBUG
/// Extraction that always fails, for `-defer structure`.
///
/// The transcription beside it is left working on purpose: the situation being
/// reproduced is the one where the words have already been paid for and only the
/// organising is gone. What the app must do then is keep the telling verbatim —
/// see `TellViewModel.process` and docs/ARCHITECTURE.md §16.
struct FailingExtractionService: ExtractionService {
    func extract(
        transcript: String,
        corrections: [NameCorrection],
        level: Int?
    ) async throws -> ExtractionResult {
        throw RemoteError.badStatus(503)
    }
}
#endif
