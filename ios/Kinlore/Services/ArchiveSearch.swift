import Foundation

/// What somebody typed into a search, read for years as well as for words,
/// and the cards and tellings it finds. `MemoryStore.subjects(of:matching:)`
/// and `memories(matching:)` are this over the store's own archive.
///
/// **"2000" found nothing** on 28 Sep 2026, in an album with photographs from
/// 2003 and 2015 in it. The search read a year as four characters and looked
/// for them in titles and tellings, and a photograph dated on the date sheet
/// carries its year in `dateHint` and in none of its words. Whoever typed it
/// expected everything taken from 2000 on, and said so.
///
/// **How a date is read**, in Finnish and English alike (`Query.init`):
///
///   - A year is that year, except a round one typed alone. *1956* is 1956.
///     *1950* is the fifties with 1950 first, because a round year is how a
///     decade gets typed into a search field. *1900* and *2000* are centuries:
///     *2000-luku* is the 21st century in Finnish, which is exactly "from 2000
///     on" — the 2000s first, the 2010s after them.
///   - A decade in any spelling: *1950-luku* and its cases, *50-luvulla*,
///     *viisikymmentäluvulla*, *viiskytluvulla*, *1950s*, *'50s*, *the
///     fifties*. The three decades that are in both centuries, 00, 10 and 20,
///     are read in both when typed with two digits or in words. *1900-luku*
///     and *2000s* are centuries, as a bare 1900 and 2000 are.
///   - A span, both ends included: *1950–1960*, *1950-60*, *1950 to 1960*;
///     *1950–60-luvuilla* and *1950s–60s* are both decades whole.
///   - A side: *ennen* and *before* are strictly before, *jälkeen* and *after*
///     strictly after; *alkaen*, *lähtien*, *eteenpäin*, *vuodesta*, *since*
///     and *from* are from it on; *asti*, *saakka*, *mennessä*, *vuoteen* and
///     *until* up to it. A year with a side is the year itself, so *1960
///     jälkeen* begins in 1961 whatever *1960* alone would mean, and *1960-luvun
///     jälkeen* begins in 1970.
///   - Several dates mean any of them. The words that only shape a date —
///     *vuonna*, *noin*, *alussa*, *ja*, *in*, *the*, *early* — go with it
///     and are not looked for.
///
/// **What a date finds.** A card's date is a span of years (`years(of:)`),
/// and the card is found when the span overlaps the question: "sometime in the
/// fifties" stays as uncertain as it was told (rule 5), so *1956* finds it —
/// after a photograph from 1956, because a date wholly inside the question
/// ranks before one that only overlaps it, then nearer to the year most likely
/// meant before further, then narrower before wider (`Rank`). A card whose
/// whole span lies outside the question is never found by it, whatever its
/// words say. An undated card is never found by a date either — only by the
/// date's own characters in its words, which is how the search found it
/// before, and the only way an undated card says when it was. A side is not
/// matched in words at all: a telling that says 1960 may say "after 1960".
/// Photographs and moments are from a time; a person's `dateHint` is whatever
/// `describe` left on the card, and is not read.
///
/// **And the words.** With no date typed, the query is matched as one piece,
/// exactly as the search always matched it. With a date, the date has cut the
/// typed words apart, so each word left is looked for on its own, and all of
/// them must be on the card.
///
/// **The tellings** are listed by what they say. With only a date typed, a
/// telling is listed when its words contain the date as it was typed — and on
/// a dated card only when the card's date fits too. The cards answer the date
/// themselves, under "Kuvat" and "Kerrotut hetket"; listing every telling on
/// every photograph of a century above them would bury the photographs under
/// rows that match nothing that was typed. With words and a date, a telling
/// on a dated card is listed when its words match and its card's date fits.
///
/// Indexed once per search (`Archive`). The store's `subject(id:)` and
/// `memories(for:)` are scans, so a thousand photographs with a telling each
/// asked a million questions of them per keystroke, and the album asks four
/// times per keystroke. `scripts/archive-search-check.swift` holds all of this
/// without a simulator, the user's own "2000" first.
enum ArchiveSearch {

    // MARK: - The question

    /// A span of years a date can mean, both ends included — `Int.min` or
    /// `Int.max` for a side left open — and the year in it most likely meant,
    /// which is what "nearer" is measured from.
    struct Reading: Equatable {
        var first: Int
        var last: Int
        var focus: Int

        /// The years on one side of this reading, or from it on, or up to it.
        func on(_ side: Side) -> Reading {
            switch side {
            case .before: Reading(first: .min, last: first - 1, focus: first - 1)
            case .after: Reading(first: last + 1, last: .max, focus: last + 1)
            case .since: Reading(first: first, last: .max, focus: first)
            case .until: Reading(first: .min, last: last, focus: last)
            }
        }
    }

    /// Which side of a year was asked for.
    enum Side {
        case before, after, since, until

        /// The words that say it in front of the year: *ennen 1960*,
        /// *vuodesta 1960*, *after 1960*.
        static let leading: [String: Side] = [
            "ennen": .before, "before": .before,
            "jälkeen": .after, "after": .after,
            "vuodesta": .since, "since": .since, "from": .since,
            "vuoteen": .until, "until": .until, "till": .until,
        ]

        /// And behind it: *1960 jälkeen*, *2000-luvulta eteenpäin*.
        static let trailing: [String: Side] = [
            "jälkeen": .after,
            "alkaen": .since, "lähtien": .since, "eteenpäin": .since,
            "onwards": .since, "onward": .since,
            "asti": .until, "saakka": .until, "mennessä": .until,
        ]
    }

    /// One date in the query: every way it can be read, and what an undated
    /// card's words must contain to be found by it — the date as it was
    /// typed, or nothing for a side, which words cannot answer.
    struct DateTerm: Equatable {
        var readings: [Reading]
        var literal: String?
    }

    struct Query: Equatable {
        /// Any of these. Empty when no date was typed.
        var dates: [DateTerm]
        /// All of these. The whole query as one piece when no date was typed.
        var words: [String]

        var isEmpty: Bool { dates.isEmpty && words.isEmpty }

        init(_ typed: String) {
            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            let whole = NSRange(text.startIndex..., in: text)
            let found = ArchiveSearch.date.matches(in: text, range: whole)
            guard !found.isEmpty else {
                dates = []
                words = text.isEmpty ? [] : [text]
                return
            }
            let string = text as NSString
            let tokens = ArchiveSearch.token.matches(in: text, range: whole).map(\.range)
            func word(_ index: Int) -> String {
                ArchiveSearch.bare(string.substring(with: tokens[index])).lowercased()
            }
            // The words that said a side, by the token they are. Taken out of
            // the words, as the dates are, and each belongs to one date.
            var sides = Set<Int>()
            var terms: [DateTerm] = []
            for match in found {
                let touched = tokens.indices.filter { NSIntersectionRange(tokens[$0], match.range).length > 0 }
                var side: Side?
                // Outwards from the date, over the words that only shape it,
                // to the first word that is something else.
                for step in [-1, 1] {
                    guard var index = step < 0 ? touched.first : touched.last else { continue }
                    index += step
                    while tokens.indices.contains(index), !sides.contains(index) {
                        let said = word(index)
                        if let named = (step < 0 ? Side.leading : Side.trailing)[said] {
                            side = side ?? named
                            sides.insert(index)
                            break
                        }
                        guard ArchiveSearch.fillers.contains(said) else { break }
                        index += step
                    }
                }
                terms.append(ArchiveSearch.term(match, in: string, side: side))
            }
            let rest = NSMutableString(string: text)
            for range in found.map(\.range) + sides.map({ tokens[$0] }) {
                rest.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
            }
            dates = terms
            words = (rest as String)
                .split(whereSeparator: \.isWhitespace)
                .map { ArchiveSearch.bare(String($0)) }
                .filter { !$0.isEmpty && !ArchiveSearch.fillers.contains($0.lowercased()) }
        }
    }

    /// Words that only shape a date, left out of what is looked for when a
    /// date was typed. A search for *vuonna 1956* wants 1956, and a card whose
    /// words never say "vuonna" is from then all the same. Only ever beside a
    /// date: without one, the query is the words and nothing is left out.
    static let fillers: Set<String> = [
        "vuonna", "vuoden", "vuotta", "vuosi", "vuosina", "vuosien",
        "noin", "n", "paikkeilla", "tienoilla", "tienoolla", "maissa", "vaiheilla",
        "alussa", "alkupuolella", "alusta", "lopulla", "lopussa", "loppupuolella",
        "puolivälissä", "aikana", "välillä", "ja", "tai",
        "in", "the", "of", "year", "years", "around", "about", "circa", "c", "ca",
        "early", "mid", "late", "during", "between", "and", "or",
    ]

    /// A word without the punctuation around it: *(1956)*, *Aino,* and the
    /// *mid-* left of *mid-1950s*.
    private static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    private static let token = try! NSRegularExpression(pattern: #"\S+"#)

    /// Every spelling of a date above, one alternative each, longest first so
    /// that *1950–60-luvuilla* is one span rather than a year and a decade.
    /// A constant: `archive-search-check.swift` runs it on every spelling.
    private static let date: NSRegularExpression = {
        let year = #"(?:18|19|20)\d{2}"#
        let round = #"(?:18|19|20)\d0"#
        let short = #"['’]?\d0"#
        // "-luku" and its cases, with or without the hyphen: "-luvulla",
        // " luvulta". Not "lu" alone — "1950 lukio" is a school and a year.
        let luku = #"\s?[-–]?\s?lu(?:ku|vu)\p{L}*"#
        let plural = #"['’]?s"#
        let dash = #"\s*[-–—]\s*"#
        let to = #"(?:\s*[-–—]\s*|\s+(?:to|till|until)\s+)"#
        let tens = "(?:kaksi|kaks|kolme|neljä|viisi|viis|kuusi|kuus|seitsemän|seitse|seiska|seit"
            + "|kahdeksan|kaheksan|kasi|yhdeksän|yheksän|ysi)(?:kymmen(?:tä)?|kyt|kymppi)"
        let english = "(?:noughties|aughts|twenties|thirties|forties|fifties|sixties|seventies|eighties|nineties)"
        let pattern = [
            #"(?<![\p{L}\p{N}])(?:"#,
            "(?<fromDecade>" + round + "|" + short + ")(?:" + luku + "|" + plural + ")?" + dash,
            "(?<toDecade>" + round + "|" + short + ")(?:" + luku + "|" + plural + ")",
            "|(?<fromYear>" + year + ")" + to + "(?<toYear>" + year + #"|\d{2})"#,
            "|(?<decade>" + round + "|" + short + ")(?:" + luku + "|" + plural + ")",
            "|(?<finnish>nolla|kymmen(?:en)?|" + tens + ")" + luku,
            "|(?<english>" + english + ")",
            "|(?<year>" + year + ")",
            #")(?![\p{L}\p{N}])"#,
        ].joined()
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// The decades said in Finnish words, by how the word begins.
    private static let finnishDecades: [(String, Int)] = [
        ("nolla", 0), ("kymmen", 10), ("kaks", 20), ("kolme", 30), ("neljä", 40),
        ("viis", 50), ("kuus", 60), ("seit", 70), ("seiska", 70),
        ("kahdeksan", 80), ("kaheksan", 80), ("kasi", 80),
        ("yhdeksän", 90), ("yheksän", 90), ("ysi", 90),
    ]

    private static let englishDecades: [String: Int] = [
        "noughties": 0, "aughts": 0, "twenties": 20, "thirties": 30, "forties": 40,
        "fifties": 50, "sixties": 60, "seventies": 70, "eighties": 80, "nineties": 90,
    ]

    /// What one match of `date` means.
    private static func term(_ match: NSTextCheckingResult, in text: NSString, side: Side?) -> DateTerm {
        func group(_ name: String) -> String? {
            let range = match.range(withName: name)
            return range.location == NSNotFound ? nil : text.substring(with: range)
        }
        func number(_ name: String) -> (value: Int, digits: Int)? {
            guard let digits = group(name)?.filter(\.isNumber), let value = Int(digits) else { return nil }
            return (value, digits.count)
        }
        let typed = text.substring(with: match.range)

        // A span is a span with or without a word beside it.
        if let from = number("fromDecade"), let to = number("toDecade") {
            let readings = starts(of: from).map { start in
                Reading(first: start, last: end(to, after: start) + 9, focus: start)
            }
            return DateTerm(readings: readings, literal: typed)
        }
        if let from = number("fromYear"), let to = number("toYear") {
            let (first, last) = (from.value, end(to, after: from.value))
            return DateTerm(
                readings: [Reading(first: min(first, last), last: max(first, last), focus: min(first, last))],
                literal: typed
            )
        }

        var readings: [Reading] = []
        if let decade = number("decade") {
            readings = decade.digits == 4 ? [alone(decade.value)] : twoDigitDecade(decade.value)
        } else if let word = group("finnish")?.lowercased(),
                  let value = finnishDecades.first(where: { word.hasPrefix($0.0) })?.1 {
            readings = twoDigitDecade(value)
        } else if let word = group("english")?.lowercased(), let value = englishDecades[word] {
            readings = twoDigitDecade(value)
        } else if let year = number("year") {
            readings = [side == nil ? alone(year.value) : Reading(first: year.value, last: year.value, focus: year.value)]
        }
        guard let side else { return DateTerm(readings: readings, literal: typed) }
        return DateTerm(readings: readings.map { $0.on(side) }, literal: nil)
    }

    /// A year typed on its own: itself, the decade if it is round, and the
    /// century if it is rounder.
    private static func alone(_ year: Int) -> Reading {
        if year % 100 == 0 { return Reading(first: year, last: year + 99, focus: year) }
        if year % 10 == 0 { return Reading(first: year, last: year + 9, focus: year) }
        return Reading(first: year, last: year, focus: year)
    }

    /// A decade typed with two digits or in words. The fifties are the 1950s
    /// to everybody; the twenties are a grandmother's parents' and her
    /// grandchild's, and 00, 10 and 20 are read in both centuries.
    private static func twoDigitDecade(_ value: Int) -> [Reading] {
        starts(of: (value, 2)).map { Reading(first: $0, last: $0 + 9, focus: $0) }
    }

    /// The years a decade typed with two digits can begin in; one typed with
    /// four is itself.
    private static func starts(of decade: (value: Int, digits: Int)) -> [Int] {
        guard decade.digits <= 2 else { return [decade.value] }
        return decade.value <= 20 ? [1900 + decade.value, 2000 + decade.value] : [1900 + decade.value]
    }

    /// The end of a span, where two digits are in the century of its start
    /// or the next one: *1995–05* ends in 2005.
    private static func end(_ typed: (value: Int, digits: Int), after start: Int) -> Int {
        guard typed.digits <= 2 else { return typed.value }
        let end = start / 100 * 100 + typed.value
        return end < start ? end + 100 : end
    }

    // MARK: - A card's date

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DateHint.zone
        return calendar
    }()

    /// The years a card's date covers, both ends included, or nil when it
    /// has none to read. On the archive's clock, as every date here is
    /// written (`DateHint.zone`).
    ///
    /// A decade is the whole decade whichever year inside it was stored —
    /// the fixture stores 1955 — and an end is kept wherever one was given:
    /// the date sheet writes a decade to its last day, the server's reply to
    /// the first day of its last year, and a span from a telling may be wider
    /// than its precision.
    static func years(of hint: DateHint?) -> ClosedRange<Int>? {
        guard let hint, hint.precision != .unknown, let start = hint.start else { return nil }
        var first = calendar.component(.year, from: start)
        var last = max(first, hint.end.map { calendar.component(.year, from: $0) } ?? first)
        if hint.precision == .decade {
            first -= ((first % 10) + 10) % 10
            last = max(last, first + 9)
        }
        return first ... last
    }

    /// Whether a card of this kind is from a time — the same two kinds the
    /// card asks "when" of (`SubjectDetailScreen.datable`).
    static func isDatable(_ kind: SubjectKind) -> Bool {
        kind == .photo || kind == .event
    }

    // MARK: - How well a card answers

    /// Lower first.
    struct Rank: Comparable {
        /// 0: the card's date lies wholly inside what was asked. 1: it only
        /// overlaps it. 2: the card has no date and its words said the date.
        var tier: Int
        /// Years from the one most likely meant to the nearest year the
        /// card's date covers.
        var distance: Int
        /// Years the card's date covers: a photograph from 1956 before one
        /// from "the fifties" when both are as near.
        var width: Int

        static let byWords = Rank(tier: 2, distance: 0, width: 0)

        static func < (a: Rank, b: Rank) -> Bool {
            (a.tier, a.distance, a.width) < (b.tier, b.distance, b.width)
        }
    }

    /// How a card's years answer the dates asked, or nil when they answer
    /// none of them.
    static func fit(_ years: ClosedRange<Int>, _ dates: [DateTerm]) -> Rank? {
        var best: Rank?
        for reading in dates.flatMap(\.readings)
        where years.lowerBound <= reading.last && years.upperBound >= reading.first {
            let inside = years.lowerBound >= reading.first && years.upperBound <= reading.last
            let distance = years.contains(reading.focus)
                ? 0
                : min(abs(reading.focus - years.lowerBound), abs(reading.focus - years.upperBound))
            let rank = Rank(tier: inside ? 0 : 1, distance: distance, width: years.count)
            if best.map({ rank < $0 }) ?? true { best = rank }
        }
        return best
    }

    // MARK: - The search

    /// The archive as a search reads it: every card by its id and every
    /// telling by its card, built once per search.
    struct Archive {
        /// The tellings not taken back, in the store's order.
        let told: [Memory]
        private let byID: [String: Subject]
        private let byCard: [String: [Memory]]

        init(subjects: [Subject], told: [Memory]) {
            self.told = told
            byID = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            byCard = Dictionary(grouping: told, by: \.subjectID)
        }

        /// `MemoryStore.subject(id:)` over the index: a merged card answers
        /// with its survivor, a rejected one with nothing.
        func subject(id: String) -> Subject? {
            MergeChain.resolve(id) { byID[$0] }
        }

        func tellings(on subjectID: String) -> [Memory] {
            byCard[subjectID] ?? []
        }
    }

    /// The cards among `candidates` that answer the query: best first when a
    /// date was asked, and in the order given otherwise, as before.
    static func subjects(_ candidates: [Subject], matching query: Query, in archive: Archive) -> [Subject] {
        guard !query.isEmpty else { return candidates }
        let found = candidates.enumerated().compactMap { index, subject in
            rank(of: subject, for: query, in: archive).map { (subject: subject, rank: $0, index: index) }
        }
        guard !query.dates.isEmpty else { return found.map(\.subject) }
        return found.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.subject)
    }

    /// How a card answers the query, or nil when it does not. Its words are
    /// the three the search has always read: its title, the words of every
    /// telling on it, and the names those tellings mention.
    private static func rank(of subject: Subject, for query: Query, in archive: Archive) -> Rank? {
        func says(_ needle: String) -> Bool {
            subject.displayTitle.localizedCaseInsensitiveContains(needle)
                || archive.tellings(on: subject.id).contains { memory in
                    memory.body.localizedCaseInsensitiveContains(needle)
                        || memory.mentionedSubjectIDs.contains { id in
                            archive.subject(id: id)?.title.localizedCaseInsensitiveContains(needle) ?? false
                        }
                }
        }
        var rank = Rank.byWords
        if !query.dates.isEmpty {
            if isDatable(subject.kind), let years = years(of: subject.dateHint) {
                guard let fit = fit(years, query.dates) else { return nil }
                rank = fit
            } else if !query.dates.contains(where: { $0.literal.map(says) ?? false }) {
                return nil
            }
        }
        return query.words.allSatisfy(says) ? rank : nil
    }

    /// The tellings that answer the query, with the card each is on: best
    /// first when a date was asked, newest first otherwise, as before. The
    /// words of a telling are its own, its card's title, who told it
    /// (`byline`) and the names it mentions. A telling not yet transcribed
    /// has no words to match, and one on a card that resolves to nothing is
    /// not listed.
    static func memories(
        matching query: Query,
        in archive: Archive,
        byline: (Memory) -> String?
    ) -> [(memory: Memory, subject: Subject)] {
        guard !query.isEmpty else { return [] }
        var found: [(memory: Memory, subject: Subject, rank: Rank)] = []
        for memory in archive.told where !memory.body.isEmpty {
            guard let subject = archive.subject(id: memory.subjectID) else { continue }
            func says(_ needle: String) -> Bool {
                memory.body.localizedCaseInsensitiveContains(needle)
                    || subject.displayTitle.localizedCaseInsensitiveContains(needle)
                    || (byline(memory)?.localizedCaseInsensitiveContains(needle) ?? false)
                    || memory.mentionedSubjectIDs.contains { id in
                        archive.subject(id: id)?.title.localizedCaseInsensitiveContains(needle) ?? false
                    }
            }
            func saysADate() -> Bool {
                query.dates.contains { $0.literal.map(says) ?? false }
            }
            var rank = Rank.byWords
            if !query.dates.isEmpty {
                if isDatable(subject.kind), let years = years(of: subject.dateHint) {
                    guard let fit = fit(years, query.dates) else { continue }
                    // Only a date typed: the card answers it, and the telling
                    // is listed when it says the date itself.
                    if query.words.isEmpty, !saysADate() { continue }
                    rank = fit
                } else if !saysADate() {
                    continue
                }
            }
            guard query.words.allSatisfy(says) else { continue }
            found.append((memory, subject, rank))
        }
        let ordered = query.dates.isEmpty
            ? found.sorted { $0.memory.createdAt > $1.memory.createdAt }
            : found.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.memory.createdAt > $1.memory.createdAt }
        return ordered.map { ($0.memory, $0.subject) }
    }
}
