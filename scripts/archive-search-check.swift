// Checks what the album's search finds when somebody types a year.
//
// "2000" found nothing on 28 Sep 2026, in an album with photographs from 2003
// and 2015 in it: the search read a year as four characters and looked for
// them in the words, and a photograph dated on the date sheet carries its year
// in `dateHint` and in none of its words. `ArchiveSearch` reads the year, and
// every way of reading it wrongly is silent — a century where a decade was
// meant, a side of a year off by one, an undated photograph found by a date
// nobody knows, a telling's "1960" answering "before 1960". The screen shows a
// tidy grid either way.
//
// The semantics are in the doc comment on `ArchiveSearch`. This holds them:
// the spellings, the stored date shapes, the user's own case, the order, the
// tellings, that a search without a date finds exactly what it found before,
// and that a thousand photographs are searched in well under a keystroke. Run
// it after touching ArchiveSearch.swift or the search in MemoryStore.swift. It
// needs no simulator, no network and no key.
//
//   swiftc -parse-as-library -o /tmp/archive-search-check \
//     scripts/archive-search-check.swift ios/Kinlore/Services/ArchiveSearch.swift \
//     ios/Kinlore/Services/MergeChain.swift ios/Kinlore/Model/Models.swift

import Foundation

@main
enum ArchiveSearchCheck {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if ok {
            print("  ok   \(label)")
        } else {
            failures += 1
            let said = detail()
            print("  FAIL \(label)" + (said.isEmpty ? "" : "\n       \(said)"))
        }
    }

    // MARK: - Reading what was typed

    /// A query's dates as "1950–1959 | 2020–2029", open ends as "…".
    static func spans(_ typed: String) -> String {
        ArchiveSearch.Query(typed).dates.flatMap(\.readings).map { reading in
            (reading.first == .min ? "…" : String(reading.first)) + "–"
                + (reading.last == .max ? "…" : String(reading.last))
        }
        .joined(separator: " | ")
    }

    static func reads(_ typed: String, as expected: String, words: [String] = []) {
        let query = ArchiveSearch.Query(typed)
        let said = spans(typed)
        check(
            "\"\(typed)\" is \(expected.isEmpty ? "no date" : expected)"
                + (words.isEmpty ? "" : " and the words \(words)"),
            said == expected && query.words == words,
            "read as \"\(said)\" with the words \(query.words)"
        )
    }

    // MARK: - An archive

    static let helsinki: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DateHint.zone
        return calendar
    }()

    static func day(_ year: Int, _ month: Int = 1, _ day: Int = 1) -> Date {
        helsinki.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The date sheet's shapes (`DateSheet.hint`).
    static func sheetYear(_ year: Int) -> DateHint {
        DateHint(start: day(year), end: day(year, 12, 31), precision: .year)
    }

    static func sheetDecade(_ decade: Int) -> DateHint {
        DateHint(start: day(decade), end: day(decade + 9, 12, 31), precision: .decade)
    }

    /// The server's reply (`AppServices.dateHint(from:)`): the first day of
    /// each year.
    static func reply(_ start: Int, _ end: Int?, _ precision: DatePrecision) -> DateHint {
        DateHint(start: day(start), end: end.map { day($0) }, precision: precision)
    }

    static var clock = Date(timeIntervalSince1970: 1_700_000_000)

    /// Made one second after the previous card, so that the store's order —
    /// newest first — is the reverse of the order they are made in here.
    static func card(
        _ id: String, _ kind: SubjectKind = .photo, _ title: String = "", _ date: DateHint? = nil
    ) -> Subject {
        clock += 1
        return Subject(id: id, kind: kind, title: title, dateHint: date, createdAt: clock)
    }

    static func telling(_ id: String, on subjectID: String, _ body: String, naming: [String] = []) -> Memory {
        clock += 1
        return Memory(
            id: id, subjectID: subjectID, authorName: "Mummo", body: body, source: .typed,
            createdAt: clock, mentionedSubjectIDs: naming
        )
    }

    /// `MemoryStore.subjects(of:)`: one kind's live cards, newest first.
    static func listed(_ kind: SubjectKind, in subjects: [Subject]) -> [Subject] {
        subjects
            .filter { $0.kind == kind && $0.mergedInto == nil && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// `MemoryStore.byline(for:resolve:)`, for the tellings' teller.
    static func byline(_ memory: Memory, _ resolve: (String) -> Subject?) -> String? {
        if let id = memory.tellerSubjectID, let teller = resolve(id), !teller.title.isEmpty {
            return teller.displayTitle
        }
        if memory.tellerHidden == true { return nil }
        return memory.authorName
    }

    static func found(_ kind: SubjectKind, _ typed: String, _ subjects: [Subject], _ told: [Memory]) -> [String] {
        ArchiveSearch.subjects(
            listed(kind, in: subjects),
            matching: ArchiveSearch.Query(typed),
            in: ArchiveSearch.Archive(subjects: subjects, told: told)
        )
        .map(\.id)
    }

    static func tellings(_ typed: String, _ subjects: [Subject], _ told: [Memory]) -> [String] {
        let archive = ArchiveSearch.Archive(subjects: subjects, told: told)
        return ArchiveSearch.memories(matching: ArchiveSearch.Query(typed), in: archive) {
            byline($0, archive.subject(id:))
        }
        .map(\.memory.id)
    }

    // MARK: - The search as it was

    /// `subjects(of:matching:)` and `memories(matching:)` as they were at
    /// fdd3a8f, before a year meant anything, over plain arrays.
    enum Before {
        static func subject(_ id: String, _ subjects: [Subject]) -> Subject? {
            MergeChain.resolve(id) { id in subjects.first { $0.id == id } }
        }

        static func found(_ kind: SubjectKind, _ query: String, _ subjects: [Subject], _ told: [Memory]) -> [String] {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let all = ArchiveSearchCheck.listed(kind, in: subjects)
            guard !needle.isEmpty else { return all.map(\.id) }
            return all.filter { subject in
                subject.displayTitle.localizedCaseInsensitiveContains(needle)
                    || told.filter { $0.subjectID == subject.id }.contains { memory in
                        memory.body.localizedCaseInsensitiveContains(needle)
                            || memory.mentionedSubjectIDs.contains { id in
                                self.subject(id, subjects)?.title.localizedCaseInsensitiveContains(needle) ?? false
                            }
                    }
            }
            .map(\.id)
        }

        static func tellings(_ query: String, _ subjects: [Subject], _ told: [Memory]) -> [String] {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return [] }
            func hit(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(needle) }
            return told
                .filter { !$0.body.isEmpty }
                .compactMap { memory -> (Memory, Subject)? in
                    guard let subject = subject(memory.subjectID, subjects) else { return nil }
                    let matches = hit(memory.body)
                        || hit(subject.displayTitle)
                        || (ArchiveSearchCheck.byline(memory) { self.subject($0, subjects) }.map(hit) ?? false)
                        || memory.mentionedSubjectIDs.contains { id in
                            self.subject(id, subjects).map { hit($0.title) } ?? false
                        }
                    return matches ? (memory, subject) : nil
                }
                .sorted { $0.0.createdAt > $1.0.createdAt }
                .map(\.0.id)
        }
    }

    // MARK: - A made-up archive of any size

    /// A small linear congruential generator: the same archive every run.
    struct Dice {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    static let names = ["Aino", "Eeva", "Kalle", "Sanni", "Toivo", "Helmi", "Mummo", "Vaari"]
    static let places = ["Puumala", "Karjala", "Kuopio", "Vaasa", "mökki"]
    static let phrases = [
        "soudettiin saareen kalaan", "kahvipannu oli aina mukana", "sodan jälkeen",
        "kesällä 1956", "2000-luvun alussa", "50-luvulla", "ennen vuotta 1960",
        "sauna lämpisi", "häissä tanssittiin", "joulu mummolassa", "traktorilla peltoon",
        "koulun jälkeen", "vuonna 2003", "Mökin ranta", "juhannus",
    ]

    static func archive(photos: Int, events: Int, people: Int, tellings: Int, seed: UInt64)
        -> (subjects: [Subject], told: [Memory])
    {
        var dice = Dice(state: seed)
        var subjects: [Subject] = []
        func date() -> DateHint? {
            switch dice.next(6) {
            case 0: return nil
            case 1: return sheetDecade(1900 + dice.next(12) * 10)
            case 2: return reply(1930 + dice.next(90), nil, .year)
            case 3: let start = 1930 + dice.next(90); return reply(start, start + 1 + dice.next(6), .year)
            case 4: return DateHint(start: nil, end: nil, precision: .unknown)
            default: return sheetYear(1900 + dice.next(126))
            }
        }
        for index in 0 ..< people {
            subjects.append(card("person-\(index)", .person, names[index % names.count] + (index < names.count ? "" : " \(index)")))
        }
        for index in 0 ..< places.count {
            subjects.append(card("place-\(index)", .place, places[index]))
        }
        for index in 0 ..< photos {
            let title = dice.next(3) == 0 ? phrases[dice.next(phrases.count)] : ""
            subjects.append(card("photo-\(index)", .photo, title, date()))
        }
        for index in 0 ..< events {
            subjects.append(card("event-\(index)", .event, dice.next(2) == 0 ? "Juhla \(index)" : "", date()))
        }
        // A merge and a rejection, so the resolving is exercised too.
        if photos > 2 {
            subjects[people + places.count].mergedInto = "photo-1"
            subjects[people + places.count + 2].deletedAt = clock
        }
        let cards = subjects.map(\.id)
        var told: [Memory] = []
        for index in 0 ..< tellings {
            let words = (0 ..< 1 + dice.next(4)).map { _ in phrases[dice.next(phrases.count)] }
            let naming = (0 ..< dice.next(3)).map { _ in
                dice.next(2) == 0 ? "person-\(dice.next(people))" : "place-\(dice.next(places.count))"
            }
            told.append(telling(
                "memory-\(index)", on: cards[dice.next(cards.count)],
                names[dice.next(names.count)] + " muisteli: " + words.joined(separator: ", ") + ".",
                naming: naming
            ))
        }
        return (subjects, told)
    }

    // MARK: -

    static func main() {
        print("— a year, a decade, a century —")
        reads("2000", as: "2000–2099")
        reads("1956", as: "1956–1956")
        reads("1950", as: "1950–1959")
        reads("1900", as: "1900–1999")
        reads("2010", as: "2010–2019")
        reads("vuonna 1956", as: "1956–1956")
        reads("noin 1956", as: "1956–1956")
        reads("(1956)", as: "1956–1956")
        reads("2000-luku", as: "2000–2099")
        reads("2000-luvulla", as: "2000–2099")
        reads("1900-luvulla", as: "1900–1999")
        reads("1950-luvun", as: "1950–1959")
        reads("1950-luvun alussa", as: "1950–1959")
        reads("50-luku", as: "1950–1959")
        reads("50-luvulla", as: "1950–1959")
        reads("50 luvulla", as: "1950–1959")
        reads("viisikymmentäluvulla", as: "1950–1959")
        reads("viisikymmenluvulla", as: "1950–1959")
        reads("viiskytluvulla", as: "1950–1959")
        reads("kuusikymmentäluku", as: "1960–1969")
        reads("seitsemänkymmentäluvulla", as: "1970–1979")
        reads("kasikytluvulla", as: "1980–1989")
        reads("1950s", as: "1950–1959")
        reads("1950's", as: "1950–1959")
        reads("50s", as: "1950–1959")
        reads("’50s", as: "1950–1959")
        reads("the fifties", as: "1950–1959")
        reads("Fifties", as: "1950–1959")
        reads("in the early 1950s", as: "1950–1959")
        reads("2000s", as: "2000–2099")

        print("\n— the decades that are in both centuries —")
        reads("20-luvulla", as: "1920–1929 | 2020–2029")
        reads("the twenties", as: "1920–1929 | 2020–2029")
        reads("nollaluvulla", as: "1900–1909 | 2000–2009")
        reads("1920-luku", as: "1920–1929")

        print("\n— a span —")
        reads("1950–1960", as: "1950–1960")
        reads("1950-1960", as: "1950–1960")
        reads("1950 - 1960", as: "1950–1960")
        reads("1950-60", as: "1950–1960")
        reads("1995–05", as: "1995–2005")
        reads("1950 to 1960", as: "1950–1960")
        reads("from 1950 to 1960", as: "1950–1960")
        reads("1950–60-luvuilla", as: "1950–1969")
        reads("50–60-luvulla", as: "1950–1969")
        reads("1950s–60s", as: "1950–1969")
        reads("1950- ja 1960-luvuilla", as: "1950–1959 | 1960–1969")

        print("\n— a side of a year —")
        reads("ennen 1960", as: "…–1959")
        reads("before 1960", as: "…–1959")
        reads("ennen vuotta 1960", as: "…–1959")
        reads("1960 jälkeen", as: "1961–…")
        reads("vuoden 1960 jälkeen", as: "1961–…")
        reads("after 1960", as: "1961–…")
        reads("since 1960", as: "1960–…")
        reads("1960 alkaen", as: "1960–…")
        reads("1960 lähtien", as: "1960–…")
        reads("vuodesta 1960", as: "1960–…")
        reads("vuodesta 1960 lähtien", as: "1960–…")
        reads("until 1960", as: "…–1960")
        reads("1960 asti", as: "…–1960")
        reads("1960-luvun jälkeen", as: "1970–…")
        reads("ennen 1900-lukua", as: "…–1899")
        // The words the user wrote the request in.
        reads("2000 luvulta eteenpäin", as: "2000–…")
        reads("2000-luvulta eteenpäin", as: "2000–…")

        print("\n— dates among words —")
        reads("Aino 1950", as: "1950–1959", words: ["Aino"])
        reads("Mökin ranta 1950-luvulla", as: "1950–1959", words: ["Mökin", "ranta"])
        reads("Aino ja Eeva vuonna 1956", as: "1956–1956", words: ["Aino", "Eeva"])
        reads("1950 lukio", as: "1950–1959", words: ["lukio"])
        reads("ennen sotaa 1940", as: "1940–1949", words: ["ennen", "sotaa"])

        print("\n— and words that are no date —")
        reads("Mökin ranta", as: "", words: ["Mökin ranta"])
        reads("  traktori  ", as: "", words: ["traktori"])
        reads("50-vuotispäivät", as: "", words: ["50-vuotispäivät"])
        reads("Mannerheimintie 50", as: "", words: ["Mannerheimintie 50"])
        reads("1234", as: "", words: ["1234"])
        reads("ennen sotaa", as: "", words: ["ennen sotaa"])
        check("nothing typed is no query", ArchiveSearch.Query("   ").isEmpty)

        print("\n— what an undated card's words must say —")
        check("a year: itself", ArchiveSearch.Query("1956").dates.first?.literal == "1956")
        check("a year beside \"vuonna\": the year", ArchiveSearch.Query("vuonna 1956").dates.first?.literal == "1956")
        check("a decade: as typed", ArchiveSearch.Query("50-luvulla").dates.first?.literal == "50-luvulla")
        check(
            "a side: nothing, because a telling that says 1960 may say after it",
            ArchiveSearch.Query("ennen 1960").dates.first.map { $0.literal == nil } == true
        )
        check("the year most likely meant in \"2000\" is 2000", ArchiveSearch.Query("2000").dates.first?.readings.first?.focus == 2000)
        check("… in \"ennen 1960\" is 1959", ArchiveSearch.Query("ennen 1960").dates.first?.readings.first?.focus == 1959)
        check("… in \"1960 jälkeen\" is 1961", ArchiveSearch.Query("1960 jälkeen").dates.first?.readings.first?.focus == 1961)

        print("\n— the years a stored date covers —")
        check("the date sheet's decade", ArchiveSearch.years(of: sheetDecade(1950)) == 1950 ... 1959)
        check("the date sheet's year", ArchiveSearch.years(of: sheetYear(1956)) == 1956 ... 1956)
        check("a day", ArchiveSearch.years(of: DateHint(start: day(1956, 7, 12), end: day(1956, 7, 12), precision: .day)) == 1956 ... 1956)
        check("the server's year", ArchiveSearch.years(of: reply(1956, 1956, .year)) == 1956 ... 1956)
        check("the server's decade", ArchiveSearch.years(of: reply(1950, 1959, .decade)) == 1950 ... 1959)
        check("a year with no end", ArchiveSearch.years(of: reply(1956, nil, .year)) == 1956 ... 1956)
        check("a span a telling gave", ArchiveSearch.years(of: reply(1958, 1962, .year)) == 1958 ... 1962)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        check(
            "the fixture's decade, stored as 1955",
            ArchiveSearch.years(of: DateHint(
                start: local.date(from: DateComponents(year: 1955, month: 1, day: 1)), end: nil, precision: .decade
            )) == 1950 ... 1959
        )
        check("1 January 2000 at Helsinki midnight is 2000 on any machine", ArchiveSearch.years(of: reply(2000, nil, .year)) == 2000 ... 2000)
        check("no date", ArchiveSearch.years(of: nil) == nil)
        check("a date nobody knows", ArchiveSearch.years(of: DateHint(start: nil, end: nil, precision: .unknown)) == nil)
        check("a precision with no year", ArchiveSearch.years(of: DateHint(start: nil, end: nil, precision: .year)) == nil)

        // The album of the user's case, and the rest of the semantics on it.
        let aino = card("aino", .person, "Aino", sheetDecade(1950))
        let eeva = card("eeva", .person, "Eeva")
        let p1998 = card("p1998", .photo, "Kastejuhla", sheetYear(1998))
        let p2003 = card("p2003", .photo, "Lakkiaiset", sheetYear(2003))
        let p2015 = card("p2015", .photo, "Häät", sheetYear(2015))
        let p1956 = card("p1956", .photo, "Rippikoulu", sheetYear(1956))
        let p1950 = card("p1950", .photo, "Uusi talo", reply(1950, 1950, .year))
        let fifties = card("fifties", .photo, "Mökin ranta", sheetDecade(1950))
        let p1957 = card("p1957", .photo, "Saunan rakennus", sheetYear(1957))
        let span = card("span", .photo, "Muutto", reply(1958, 1962, .year))
        let undated = card("undated", .photo)
        let untold = card("untold", .photo)
        let trip = card("trip", .event, "Häämatka", reply(2016, 2016, .year))
        let merged = card("merged", .photo, "", sheetYear(2004))
        var mergedAway = merged
        mergedAway.mergedInto = p2003.id
        var refused = card("refused", .photo, "", sheetYear(2005))
        refused.deletedAt = clock
        let subjects = [aino, eeva, p1998, p2003, p2015, p1956, p1950, fifties, p1957, span, undated, untold, trip, mergedAway, refused]
        let told = [
            telling("dance", on: p2015.id, "Aino tanssi häissä koko illan.", naming: [aino.id]),
            telling("speech", on: p1998.id, "Aino piti puheen.", naming: [aino.id]),
            telling("spring", on: p2003.id, "Kevät oli kylmä, 2000-luvun alussa aina."),
            telling("before", on: p1998.id, "Tämä oli ennen vuotta 2000."),
            telling("summer", on: undated.id, "Kesällä 1956 käytiin Puumalassa."),
            telling("born", on: aino.id, "Aino syntyi 1950-luvulla."),
            telling("neighbour", on: eeva.id, "Eeva asui naapurissa."),
            telling("moved", on: merged.id, "Muutettiin 2000-luvun alussa."),
            telling("gone", on: refused.id, "Hylätty 2000-luvulla."),
        ]

        print("\n— \"2000\", the user's own —")
        check("finds 2003 and 2015, 2003 first, and not 1998", found(.photo, "2000", subjects, told) == ["p2003", "p2015"],
              "found \(found(.photo, "2000", subjects, told))")
        check("\"2000-luvulla\" finds the same", found(.photo, "2000-luvulla", subjects, told) == ["p2003", "p2015"])
        check("and \"2000 luvulta eteenpäin\"", found(.photo, "2000 luvulta eteenpäin", subjects, told) == ["p2003", "p2015"])
        check("a moment of 2016 is found by it too", found(.event, "2000", subjects, told) == ["trip"])

        print("\n— certain, then possible, then only in words —")
        check(
            "\"1956\": the photograph from 1956, then the fifties, then the undated one whose telling says 1956",
            found(.photo, "1956", subjects, told) == ["p1956", "fifties", "undated"],
            "found \(found(.photo, "1956", subjects, told))"
        )
        check(
            "\"1950\": 1950, the fifties, 1956, 1957, then the move that only began in them",
            found(.photo, "1950", subjects, told) == ["p1950", "fifties", "p1956", "p1957", "span"],
            "found \(found(.photo, "1950", subjects, told))"
        )
        check(
            "\"1960\": only the move of 1958–62, which may have been then",
            found(.photo, "1960", subjects, told) == ["span"],
            "found \(found(.photo, "1960", subjects, told))"
        )
        check(
            "\"ennen 1960\": nearest 1959 first, the move last, and no undated card by its words",
            found(.photo, "ennen 1960", subjects, told) == ["fifties", "p1957", "p1956", "p1950", "span"],
            "found \(found(.photo, "ennen 1960", subjects, told))"
        )
        check(
            "\"1960 jälkeen\": from 1961 on, nearest first, the move last",
            found(.photo, "1960 jälkeen", subjects, told) == ["p1998", "p2003", "p2015", "span"],
            "found \(found(.photo, "1960 jälkeen", subjects, told))"
        )
        check(
            "\"1950–1960\": both ends in, 1950 first",
            found(.photo, "1950–1960", subjects, told) == ["p1950", "fifties", "p1956", "p1957", "span"],
            "found \(found(.photo, "1950–1960", subjects, told))"
        )
        check("a photograph nobody has told about or dated is found by no date", !found(.photo, "1900", subjects, told).contains("untold"))

        print("\n— words and a date together —")
        check("\"Aino 2000\": only the wedding", found(.photo, "Aino 2000", subjects, told) == ["p2015"])
        check("\"Aino\" alone: both photographs she is in", found(.photo, "Aino", subjects, told) == ["p2015", "p1998"])
        check("\"Aino 1950\" on the people list: her own telling says it", found(.person, "Aino 1950", subjects, told) == ["aino"])
        check(
            "\"1956\" on the people list: nothing, whatever date a person's card carries",
            found(.person, "1956", subjects, told).isEmpty
        )

        print("\n— the tellings —")
        check(
            "\"2000\": only the telling that says it, on a card of the time; the cards answer the rest",
            tellings("2000", subjects, told) == ["moved", "spring"],
            "listed \(tellings("2000", subjects, told))"
        )
        check(
            "\"Aino 2000\": the telling about her on the wedding photograph",
            tellings("Aino 2000", subjects, told) == ["dance"],
            "listed \(tellings("Aino 2000", subjects, told))"
        )
        check("\"1956\": the undated card's telling that says it", tellings("1956", subjects, told) == ["summer"])
        check("\"1950\": the telling on Aino's card that says it", tellings("1950", subjects, told) == ["born"])
        check("\"ennen 1960\": no telling, since only words could answer it", tellings("ennen 1960", subjects, told).isEmpty)
        check("a refused card's telling is listed by nothing", !tellings("2000-luvulla", subjects, told).contains("gone"))

        print("\n— a search without a date is the search it was —")
        let small = archive(photos: 300, events: 40, people: 30, tellings: 400, seed: 7)
        var same = true
        for typed in ["Aino", "aino", "mökki", "Mökin ranta", "soudettiin", "Puumala", "Mummo", "traktori",
                      "sodan jälkeen", "Valokuva", "Juhla 3", "kahvipannu oli", "  juhannus "] {
            for kind in SubjectKind.allCases {
                let now = found(kind, typed, small.subjects, small.told)
                let then = Before.found(kind, typed, small.subjects, small.told)
                if now != then {
                    same = false
                    print("       \(kind) \"\(typed)\": \(now.count) now, \(then.count) before")
                }
            }
            if tellings(typed, small.subjects, small.told) != Before.tellings(typed, small.subjects, small.told) {
                same = false
                print("       tellings \"\(typed)\" differ")
            }
        }
        check("every kind and the tellings, thirteen queries, the same cards in the same order", same)
        check(
            "and the undated cards a year finds are the ones whose words said it before",
            Set(found(.photo, "1956", small.subjects, small.told)).isSuperset(of: Before.found(.photo, "1956", small.subjects, small.told).filter { id in
                ArchiveSearch.years(of: small.subjects.first { $0.id == id }?.dateHint) == nil
            })
        )

        print("\n— a thousand photographs —")
        let large = archive(photos: 1_000, events: 150, people: 120, tellings: 1_500, seed: 11)
        // What the album asks per keystroke: photographs, moments, places,
        // tellings. The slowest query of five, measured three times, on the
        // process's CPU clock and on the wall's. The process's rather than the
        // thread's, so that work handed to another thread would still count.
        var slowest = (cpu: 0.0, wall: 0.0)
        for typed in ["2000", "Aino 1950", "traktori", "ennen 1960", "mökki"] {
            let times = (0 ..< 3).map { _ -> (cpu: Double, wall: Double) in
                let cpu = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
                let wall = Date()
                _ = found(.photo, typed, large.subjects, large.told)
                _ = found(.event, typed, large.subjects, large.told)
                _ = found(.place, typed, large.subjects, large.told)
                _ = tellings(typed, large.subjects, large.told)
                return (
                    Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpu) / 1e9,
                    Date().timeIntervalSince(wall)
                )
            }
            slowest.cpu = max(slowest.cpu, times.map(\.cpu).min() ?? 0)
            slowest.wall = max(slowest.wall, times.map(\.wall).min() ?? 0)
        }
        print(String(
            format: "       slowest keystroke: %.0f ms of CPU, %.0f ms on the wall clock",
            slowest.cpu * 1_000, slowest.wall * 1_000
        ))
        // A bound for a return to the scans to fail rather than a stopwatch,
        // so it is held against CPU time. The wall clock also counts the time
        // this process waits for a core, and on a machine building and running
        // simulators for other work that is most of it: on 28 Sep 2026 it read
        // 717 ms at a load average of about 370 and failed the check with
        // nothing slower. In twenty runs that evening, at load averages from
        // 20 to 270, the wall clock read 39 ms to 1.07 s and the CPU clock 39
        // to 96 ms. The CPU clock moves too, because a busy machine runs this
        // partly on its slower cores, but it stayed under a fifth of the
        // bound. The scans this replaced took 0.7 s per keystroke at this size
        // in this same unoptimised build, and `Before`'s, timed in this
        // search's place, read 1.5 s of CPU at a load average of 280. The
        // fastest of three runs, so that a busy machine does not turn it red.
        check("a keystroke over 1,000 photographs and 1,500 tellings takes under 0.5 s of CPU", slowest.cpu < 0.5)

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
