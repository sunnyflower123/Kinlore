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
    var questions: [String]
}

struct MentionedEntity: Equatable, Hashable {
    var name: String
    var kind: SubjectKind
    /// The LLM's confidence. Below 1.0 is created as an unconfirmed proposal.
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
    func extract(transcript: String, corrections: [NameCorrection]) async throws -> ExtractionResult
}

extension ExtractionService {
    func extract(transcript: String) async throws -> ExtractionResult {
        try await extract(transcript: transcript, corrections: [])
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

    func extract(transcript: String, corrections: [NameCorrection]) async throws -> ExtractionResult {
        try await Task.sleep(for: simulatedDelay)

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
                kind: Self.looksLikePlace($0) ? .place : .person,
                confidence: 0.7
            )
        }

        return ExtractionResult(
            body: Self.tidy(text),
            mentions: mentions,
            dateHint: Self.dateHint(in: text),
            questions: Self.questions(for: mentions)
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

    static func looksLikePlace(_ name: String) -> Bool {
        let suffixes = ["ssa", "ssä", "lla", "llä", "sta", "stä", "lta", "ltä"]
        return suffixes.contains { name.lowercased().hasSuffix($0) }
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
        let fillers = ["niinku", "tota", "öö", "ää", "siis niinku"]
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
    static func questions(for mentions: [MentionedEntity]) -> [String] {
        let people = mentions.filter { $0.kind == .person }.map(\.name)
        let places = mentions.filter { $0.kind == .place }.map(\.name)

        var out: [String] = []
        if let first = people.first {
            out.append("Millainen ihminen \(first) oli?")
        }
        if people.count > 1 {
            out.append("Miten \(people[0]) ja \(people[1]) tunsivat toisensa?")
        }
        if let place = places.first {
            // In the speech a place name is already inflected ("Puumalassa"), so
            // the question is built to avoid inflecting it again.
            out.append("\(place) — mitä muuta siellä tapahtui?")
        }
        out.append("Muistatko miltä siellä tuoksui tai kuulosti?")
        out.append("Kuka muu oli paikalla?")
        return Array(out.prefix(3))
    }
}
