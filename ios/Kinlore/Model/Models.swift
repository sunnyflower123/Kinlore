import Foundation

/// The models mirror `backend/schema.sql` one to one, on purpose. Sync does not
/// have to translate through an intermediate representation.
///
/// The Finnish string literals in this file are user-visible text. The app's UI
/// is Finnish; the code around it is English. See the language rule in CLAUDE.md.

// MARK: - Subject

/// A photo, a person, a place and an event are all the same thing: a subject
/// that memories attach to. This is the core of the whole architecture — it is
/// why "write a memory about this photo" and "tell us what grandmother was like"
/// are the same screen rather than three parallel implementations.
enum SubjectKind: String, Codable, CaseIterable {
    case photo, person, place, event

    var symbolName: String {
        switch self {
        case .photo: "photo"
        case .person: "person.crop.circle"
        case .place: "mappin.and.ellipse"
        case .event: "calendar"
        }
    }

    /// The name shown in the UI. Finnish, because the app's language is Finnish.
    /// Looked up, not literal: this is a runtime `String`, and a `Text` or
    /// a `navigationTitle` given a `String` shows it verbatim. Until 6 Sep
    /// 2026 an English phone read "Kuva" and "Henkilö" wherever a subject had
    /// no title of its own — the same leak as `displayTitle` below, and the
    /// one `scripts/localisation-check.mjs` cannot see, because the keys
    /// were in both tables all along and nothing ever asked for them.
    var label: String {
        switch self {
        case .photo: String(localized: "Kuva")
        case .person: String(localized: "Henkilö")
        case .place: String(localized: "Paikka")
        case .event: String(localized: "Tapahtuma")
        }
    }
}

/// Uncertain dating is the rule, not the exception. "Sometime in the fifties" is
/// a valid answer, and it must not be rounded into a false date.
enum DatePrecision: String, Codable {
    case day, month, year, decade, unknown
}

struct DateHint: Codable, Hashable {
    var start: Date?
    var end: Date?
    var precision: DatePrecision

    /// The archive's clock. Every date here is built as midnight in Helsinki —
    /// by the extraction, by `DateSheet` and by the fixtures — so it is read
    /// back there too. The same instant read in a zone west of it is the day
    /// before, which turns 1.1.1957 into a photograph from 1956.
    static let zone = TimeZone(identifier: "Europe/Helsinki") ?? .current

    /// The archive's calendar: Gregorian, on `zone`. A date for the archive
    /// is built in it and read back through it, never through the phone's.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }()

    /// The decade an instant is filed under: 1950 for anything from midnight
    /// on 1.1.1950 to the last minute of 1959, in Helsinki. The album's
    /// headings come from here. Read on the phone's own calendar, as they were
    /// until 28 Sep 2026, the date sheet's "1950s" is 31.12.1949 in Los
    /// Angeles, and the fifties sat among the forties
    /// (`scripts/decade-check.swift`).
    static func decade(of date: Date) -> Int {
        calendar.component(.year, from: date) / 10 * 10
    }

    /// Human-readable form that states the uncertainty honestly.
    var displayText: String {
        guard let start else { return String(localized: "Ajankohta ei tiedossa") }
        let year = Self.calendar.component(.year, from: start)
        switch precision {
        case .decade: return String(localized: "\(String(year / 10 * 10))-luku")
        case .year: return "\(year)"
        case .month, .day:
            // The phone's own language, not Finnish spelled out here. This was
            // a `DateFormatter` pinned to fi_FI, which showed "kesäkuu 1957" on
            // an English phone — invisible while nothing but the extraction
            // could write a month, and the extraction could not write a real
            // one either (19 Sep 2026).
            var style = precision == .day
                ? Date.FormatStyle.dateTime.day().month(.wide).year()
                : Date.FormatStyle.dateTime.month(.wide).year()
            style.timeZone = Self.zone
            return start.formatted(style)
        case .unknown: return String(localized: "Ajankohta ei tiedossa")
        }
    }
}

/// How precisely a looked-up location places a memory.
///
/// The same idea as `DatePrecision`, for the same reason: "Karjala" is an answer
/// and it is not a point. A map that draws it as a pin claims a metre of
/// accuracy nobody ever had — rule 5, uncertainty is stored, not rounded.
enum GeoPrecision: String, Codable {
    case exact, town, region, unknown

    /// How wide a map of this has to be, in metres — and nil where there must
    /// be no map at all.
    ///
    /// The rule above, turned into the only number a view needs, and kept
    /// here rather than in the view because it is a fact about the precision
    /// and not about the drawing. `scripts/place-map-check.swift` asserts it
    /// without a simulator, because every way of being wrong here is quiet: a
    /// pin on the wrong house looks exactly as confident as a pin on the right
    /// one, and an `unknown` place drawn at any span at all is a map of
    /// somewhere the app was never told about.
    ///
    /// The spans are the scale each answer was given at. A street address is
    /// worth a kilometre and a half; a municipality — which is what MapKit
    /// returns for most of what somebody says out loud — fourteen; a region
    /// seventy. They are deliberately generous: a span too wide says "around
    /// here", and a span too narrow says something the archive does not know.
    var mapSpanMetres: Double? {
        switch self {
        case .exact: 1_500
        case .town: 14_000
        case .region: 70_000
        case .unknown: nil
        }
    }

    /// Whether a point may be drawn as a point. Only the answer that actually
    /// is one.
    var deservesAPin: Bool { self == .exact }
}

/// Where a place is: what a gazetteer made of its name, or where somebody in
/// the family put it.
///
/// The confirmation is what tells the two apart. A lookup (`PlaceResolver`)
/// writes a point with nobody's name on it — a cache of the answer to the
/// title, nil until something resolves it, nil again the moment the name is
/// corrected, and nil forever for a village that no longer exists. A point
/// somebody placed carries who and when (25 Sep 2026), and it is the family's
/// word rather than a cache: a corrected title keeps it, a lookup on another
/// phone cannot displace it, and only a newer word replaces it (`sync.ts`).
/// `.unknown` under a confirmation is a word too — the family saying the place
/// is on no map — and nothing looks it up again, because
/// `placesAwaitingCoordinates` only offers a place with no point at all.
///
/// Optional, all three, because `PlaceHint` has no hand-written decoder and a
/// file written before they existed must still load (rule 10).
struct PlaceHint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var precision: GeoPrecision
    var confirmedByID: String?
    var confirmedByName: String?
    var confirmedAt: Date?

    /// Whether this is the family's word rather than a lookup's answer.
    var isConfirmed: Bool { confirmedAt != nil }
}

/// One thing the family knows about a person and says in words rather than
/// in a telling — when and where she was born, what she was called, what she
/// did, where she lived (docs/ARCHITECTURE.md §26). Written by a person on
/// the card and never by the extraction (rule 4).
///
/// `kind` is a `String` and not an enum, and that is rule 10's other
/// direction: a `String` enum in a persisted model turns every value a later
/// version adds into a decoding error, which is how one relationship row
/// used to fail a whole file. A kind this build has no word for is kept,
/// shown under the one word that is true of it (*"Tieto"*), and pushed back
/// as it came. `PersonFactKind` is the table of the kinds this build knows.
///
/// A fact is never taken out of the list. Taking one off the card writes
/// `deletedAt` and empties the rest (`remove(at:)`), and the removal
/// travels: two phones' lists are joined fact by fact
/// (`Subject.withFacts`), and a removal stands over every live copy of the
/// same id whatever the two clocks said — a fact somebody took off is more
/// often wrong than a change to it was right (rule 4), and its return from
/// an older phone would be the worse mistake. Between two live copies the
/// newer `updatedAt` wins, which makes the difference between two phones'
/// clocks the accepted limit of that rule, per fact.
struct PersonFact: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var kind: String
    /// The words, where the kind has any: the other name, the occupation, the
    /// note. Nil for a birth or a death, which are a time and a place.
    var text: String?
    /// When, as exactly as the family knows (rule 5).
    var date: DateHint?
    /// Where: a `place` subject of this archive, by id, so that the place is
    /// one card and one point on the map rather than a spelling in every
    /// fact that names it. The name is read from that card when the fact is
    /// shown.
    var placeSubjectID: String?
    /// When this fact was written or last changed, for the join above.
    var updatedAt: Date = .now
    /// When it was taken off the card, or nil while it stands.
    var deletedAt: Date?

    var isLive: Bool { deletedAt == nil }

    /// The most characters a fact's words may run to: a note is a sentence
    /// or two and a trade a word. The number exists for the list's size on
    /// the wire, which `listByteLimit` bounds in bytes; this is the half of
    /// it a person can see, on the field.
    static let textLimit = 300

    /// The words as the list keeps them: trimmed, cut at `textLimit`, and
    /// nil where nothing is left.
    static func cut(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(textLimit))
    }

    /// Taken off the card: a tombstone, which keeps its id and its kind and
    /// nothing else. The words of a fact somebody took off should not go on
    /// crossing between phones for as long as the list lives.
    mutating func remove(at now: Date) {
        text = nil
        date = nil
        placeSubjectID = nil
        updatedAt = now
        deletedAt = now
    }

    /// The list with this fact in it: in place of the copy it changes, or
    /// at the end.
    static func placing(_ fact: PersonFact, in facts: [PersonFact]) -> [PersonFact] {
        var list = facts
        if let held = list.firstIndex(where: { $0.id == fact.id }) {
            list[held] = fact
        } else {
            list.append(fact)
        }
        return list
    }

    init(
        id: String = UUID().uuidString, kind: String, text: String? = nil, date: DateHint? = nil,
        placeSubjectID: String? = nil, updatedAt: Date = .now, deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.date = date
        self.placeSubjectID = placeSubjectID
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Read with every key but `id` forgiven, so that a row a later build
    /// wrote, or one missing a field this build expects, is still a fact
    /// rather than a decoding error for the whole list. The one thing a row
    /// cannot do without is its id, which is what two phones' lists are
    /// joined on; a row without one is what `Lenient` leaves out. A date
    /// this build cannot read — a precision it has no case for — is read as
    /// no date, and the rest of the fact stays.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text)
        date = (try? c.decodeIfPresent(DateHint.self, forKey: .date)) ?? nil
        placeSubjectID = try c.decodeIfPresent(String.self, forKey: .placeSubjectID)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    /// Two phones' lists as one, fact by fact: a fact only one side holds is
    /// kept; where both hold it a removal stands over any live copy, whatever
    /// the clocks say, and between two live copies the newer `updatedAt`
    /// wins. On the same moment this phone's copy stands, because it is the
    /// one that may carry a field the other build could not read and wrote
    /// back without. This phone's facts first, in their order, then the
    /// other side's new ones in theirs.
    static func joined(_ mine: [PersonFact], with theirs: [PersonFact]) -> [PersonFact] {
        var held: [String: PersonFact] = [:]
        var order: [String] = []
        for fact in mine + theirs {
            guard let holding = held[fact.id] else {
                held[fact.id] = fact
                order.append(fact.id)
                continue
            }
            if holding.isLive, !fact.isLive || fact.updatedAt > holding.updatedAt {
                held[fact.id] = fact
            }
        }
        return order.compactMap { held[$0] }
    }
}

/// The kinds of fact this build has words for, and what each one asks — one
/// row per kind, and a new kind is one row. The sheet offers `known` in this
/// order, the card sorts by it, and both read `asks` and `needs` rather than
/// switching on the kind anywhere. `id` is the word stored in
/// `PersonFact.kind` and sent over the wire, so it never changes once used.
struct PersonFactKind: Identifiable, Hashable {
    enum Part { case text, date, place }
    /// The one part without which the fact says nothing.
    enum Need { case text, place, dateOrPlace }

    let id: String
    /// What the sheet offers: *"Syntymä"*.
    let label: String
    /// The word the card puts before the value: *"Syntynyt"*. It ends in a
    /// colon where the value is a name or a word rather than a time.
    let word: String
    /// What the sheet asks, in the order it asks.
    let asks: [Part]
    let needs: Need

    static let known: [PersonFactKind] = [
        PersonFactKind(id: "birth", label: String(localized: "Syntymä"), word: String(localized: "Syntynyt"), asks: [.date, .place], needs: .dateOrPlace),
        PersonFactKind(id: "death", label: String(localized: "Kuolema"), word: String(localized: "Kuollut"), asks: [.date, .place], needs: .dateOrPlace),
        PersonFactKind(id: "other_name", label: String(localized: "Muu nimi"), word: String(localized: "Muu nimi:"), asks: [.text], needs: .text),
        PersonFactKind(id: "occupation", label: String(localized: "Ammatti"), word: String(localized: "Ammatti:"), asks: [.text, .date], needs: .text),
        PersonFactKind(id: "residence", label: String(localized: "Asuinpaikka"), word: String(localized: "Asuinpaikka:"), asks: [.place, .date], needs: .place),
        PersonFactKind(id: "note", label: String(localized: "Lisätieto"), word: String(localized: "Lisätieto:"), asks: [.text], needs: .text),
    ]

    /// The row for a kind this build has no word for: the one word that is
    /// true of it, and every part the fact carries shown.
    static let unknown = PersonFactKind(
        id: "", label: String(localized: "Tieto"), word: String(localized: "Tieto:"),
        asks: [.text, .date, .place], needs: .text
    )

    /// The kind a stored word names, or `unknown`.
    static func of(_ id: String) -> PersonFactKind {
        known.first { $0.id == id } ?? unknown
    }

    /// Where a kind sorts on the card: known kinds in the table's order,
    /// unknown ones after them.
    static func rank(_ id: String) -> Int {
        known.firstIndex { $0.id == id } ?? known.count
    }
}

/// One row of a list, or nil where this version could not read it. The list
/// still fails as a whole when it is not a list at all; only its rows are
/// forgiven, one at a time.
struct Lenient<Row: Decodable>: Decodable {
    let value: Row?
    init(from decoder: Decoder) throws {
        value = try? Row(from: decoder)
    }
}

struct Subject: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var kind: SubjectKind
    var title: String
    /// The local cache file. Nil on a receiving device until the photo has been
    /// downloaded.
    var imageFilename: String?
    /// The R2 key. Nil until the photo has been pushed to the server. These are
    /// different things: the same photo has a different filename on each device
    /// but the same key.
    var r2Key: String?
    var dateHint: DateHint?
    /// Where a `place` lives on the map. Set by `PlaceResolver` from the title,
    /// nil on every other kind of subject and on any name nothing recognised.
    var place: PlaceHint?
    /// A photograph's colours as the family told them, in a file of their own —
    /// never in place of `imageFilename`, which stays the photograph as it was
    /// taken. Nil until somebody looked at a colouring and said yes to it
    /// (`ColourSheet`), which is the only thing that writes it (rule 4).
    ///
    /// Optional, all four of these, because a file written before they existed
    /// must still load and `Subject` has no hand-written decoder (rule 10).
    var colourImageFilename: String?
    /// The R2 key of that file, the same on every phone. Nil until this phone's
    /// yes has been uploaded — and a yes does not travel until it has one.
    var colourR2Key: String?
    /// Who said yes, and when. The colours are a guess until a person vouches
    /// for them, and the card says whose word they stand on.
    var colourConfirmedByID: String?
    var colourConfirmedByName: String?
    var colourConfirmedAt: Date?
    /// The face on a person's card: a photograph in the archive, and the point
    /// in it somebody tapped, as fractions of its width and height. The
    /// photograph itself is never cropped — `SubjectAvatar` draws a disc
    /// around the point at whatever size a screen needs, and the original
    /// stays what it was. Nil until somebody chose one (*"Valitse kasvot"* on
    /// the person card). A reference to a photograph that has since been
    /// rejected, or one this phone holds no file for, draws the initial again.
    ///
    /// `portraitSetAt` is when the choice was made, and it is what settles two
    /// phones choosing differently: the newest choice wins on the server
    /// (`sync.ts`), and a removal is a choice too — nil id under a new moment
    /// — so it travels where a bare nil, which is also what a phone that never
    /// saw the face sends, could not. Optional, all four, for rule 10.
    var portraitSubjectID: String?
    var portraitFocusX: Double?
    var portraitFocusY: Double?
    var portraitSetAt: Date?
    /// What the family knows about a person in words (§26): births, deaths,
    /// names, occupations, homes. Nil on every other kind and on a person
    /// nobody has written about; `PersonFact` says why a fact taken off the
    /// card stays in the list. `factsSetAt` is when the list last changed
    /// on any phone, which is the server's tiebreak between two phones'
    /// lists (`sync.ts`) — the phones themselves join fact by fact
    /// (`withFacts`). Optional, both, for rule 10.
    var facts: [PersonFact]?
    var factsSetAt: Date?
    /// A subject proposed by the AI is created unconfirmed. Unconfirmed never
    /// appears in the family tree as fact — a wrong relationship is worse than a
    /// missing one.
    var confirmed: Bool = true
    var createdAt: Date = .now
    /// The forwarding address of a merge. When this is set, the subject is no
    /// longer its own person but redirects to another — see `MemoryStore.rename`.
    var mergedInto: String?
    /// When somebody rejected this, or nil while it stands.
    ///
    /// A tombstone rather than a removal, and for the reason soft deletion
    /// exists at all (docs/ARCHITECTURE.md §3): a row taken off one device is a
    /// row the other devices never hear about, and the next pull hands it
    /// straight back. That is what used to happen to a rejected proposal — and
    /// rejecting is only offered in the seconds after telling, so what came back
    /// could never be got rid of again.
    var deletedAt: Date?

    /// The facts still on the card, in the order the card shows them: by
    /// kind as `PersonFactKind` lists them, and within a kind by when they
    /// were written.
    var liveFacts: [PersonFact] {
        (facts ?? []).filter(\.isLive).sorted {
            let (a, b) = (PersonFactKind.rank($0.kind), PersonFactKind.rank($1.kind))
            return a != b ? a < b : $0.updatedAt < $1.updatedAt
        }
    }

    /// A photo is imported without a title on purpose, because nobody will name
    /// thirty scanned photographs. The name arrives when someone talks about it.
    var displayTitle: String {
        if !title.isEmpty { return title }
        switch kind {
        case .photo: return String(localized: "Valokuva")
        // A moment nobody has named is shown under the day it was told. It
        // used to be named from the place and the time in what was said, and
        // since 12 Sep 2026 a telling names nothing: the date is a fact about
        // the telling, a title is a person's to give ("Nimeä hetki").
        case .event:
            return String(localized: "Kerrottu \(createdAt.formatted(date: .abbreviated, time: .omitted))")
        default: return kind.label
        }
    }

    /// The order the family's lists of people and places read in: by name,
    /// in the alphabet of the phone's own language — Ä and Ö after Z on a
    /// Finnish phone, beside A and O on an English one — with case ignored
    /// and a number read as a number, "Talo 2" before "Talo 10".
    static func byName(_ a: Subject, _ b: Subject) -> Bool {
        a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
    }
}

// MARK: - Memory

enum MemorySource: String, Codable {
    case typed, voice
}

struct Memory: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var subjectID: String
    /// The author as the server knows them. Nil on a locally created memory,
    /// because the server sets it from the session — a client must not be able
    /// to claim a memory was told by someone else.
    var authorID: String?
    var authorName: String
    /// Cleaned, readable text.
    var body: String
    /// The original transcript is always kept. If the cleanup goes wrong, the
    /// truth is still on file — the speaker may no longer be around to ask.
    var rawTranscript: String?
    /// The original audio. Grandmother's voice is itself the inheritance, not a
    /// step on the way to text, and it is playable from the memory card.
    var audioFilename: String?
    /// The R2 key for the audio. See `Subject.r2Key`.
    var audioR2Key: String?
    var audioDuration: TimeInterval?
    var source: MemorySource
    var createdAt: Date = .now
    /// Subjects mentioned in the memory. This web is what the AI "connects": the
    /// same person appears in ten memories under different photos.
    var mentionedSubjectIDs: [String] = []

    /// Who told it, when somebody said so on the result screen.
    ///
    /// The author is the phone; the teller is the voice. They are the same
    /// person alone on the sofa and different people the moment one phone goes
    /// round a table, which is the case this field exists for — `authorID` is
    /// the session's own member and a client must not be able to claim
    /// otherwise (`backend/src/sync.ts`), so the teller is a second field
    /// rather than a correction to that one.
    ///
    /// A person card's id, confirmed like any other: typing a name is
    /// vouching for it (`MemoryStore.addPerson`), so rule 4 is satisfied by
    /// the hand that chose rather than by a later confirmation.
    ///
    /// `Optional` because rule 10 leaves no other choice here: `Models.swift`
    /// has no hand-written decoder, so a non-optional field with a default
    /// throws on every archive file written before this existed.
    var tellerSubjectID: String?

    /// The teller asked not to be named.
    ///
    /// Distinct from "nobody said", which is what `nil` on both fields means
    /// and what every telling before 19 Sep 2026 is — those keep falling back
    /// to the author's name, as they always have. This one names nobody at
    /// all, not even the phone's owner.
    ///
    /// **It hides the name that is shown, not the row that is kept.** The
    /// author id still travels, because the server decides from it who may
    /// edit or take back a telling (rule 3's half of the memory upsert), and
    /// a family member with the database in front of them could read it. What
    /// this promises is what the app displays and what the export prints.
    var tellerHidden: Bool?

    /// Taken back by the teller. A tombstone, not a removal — the same shape as
    /// a rejected subject, and for the same reason: the row has to stay so that
    /// the taking-back reaches the family instead of stopping at one device.
    ///
    /// Only the author can set it. The server enforces that on its side
    /// (`backend/src/sync.ts`: the memory upsert matches on `author_id`), which
    /// is what keeps rule 3 intact — nobody gets to tidy away what grandmother
    /// said, and she is the one person who may.
    var deletedAt: Date?

    /// Brought back by the teller, and the moment it was: the one thing
    /// that reopens a taking-back (§19).
    ///
    /// Two moments, and the later one is the state, on the server
    /// (`backend/src/sync.ts`) as on this phone — except that this phone
    /// keeps its one rule: `restore(memoryID:)` clears `deletedAt` and
    /// stamps this, so `told` never reads it. It travels so that the server
    /// can tell a restoration from a stale phone that never saw the
    /// deletion, which sends nil on both, and so that this phone's copy of
    /// the row, pushed back later, cannot bury the telling again.
    ///
    /// `Optional` for rule 10's reason, like the teller above.
    var restoredAt: Date?

    /// The audio is saved but not yet transcribed — the quota was full or the
    /// network was down. A derived property, not a separate state to sync.
    ///
    /// This is the visible form of rule 3: a quota never rejects a recording, it
    /// defers its transcription. Grandmother's voice is the product.
    ///
    /// It is a waiting state and not a resting one: `PendingTranscription`
    /// finishes these as soon as the minutes or the network come back.
    var isAwaitingTranscription: Bool {
        body.isEmpty && (audioFilename != nil || audioR2Key != nil)
    }

    /// Whether the server can store this row yet.
    ///
    /// A memory with neither text nor an uploaded recording is nothing anybody
    /// else could see, and the server refuses it. It must not be *offered* for
    /// push either: everything in a pushed payload is cleared from the outbox
    /// whether the server kept it or not, so this row would be forgotten while
    /// it still existed on one device alone. That is precisely how a recording
    /// made at a cottage with no signal used to disappear from the family.
    ///
    /// It becomes pushable the moment its audio reaches R2 — normally in the
    /// same sync round, because media is uploaded before the push.
    var isPushable: Bool {
        !body.isEmpty || audioR2Key != nil
    }
}

// MARK: - Relationships

/// The kind of a relationship.
///
/// `parentOf` is directed and reads `from → to`. Spouse, sibling and friend
/// are symmetric: they are stored once and read in both directions, so the
/// same relationship cannot be created twice the other way round.
///
/// `friendOf` is not kinship (since 21 Sep 2026). A friend is a person card
/// like any other — the same card, the same tellings, the same picture —
/// joined to somebody by a line that is not descent: the tree draws a friend
/// apart rather than as a sibling, and the card lists them under *Ystävät*
/// rather than under *Suku* (ARCHITECTURE §21). The extraction never proposes
/// one, so a friendship is always something a person entered.
///
/// The first case added since the archive had files and a server to read it
/// from. A build that does not know it drops the row when reading the file
/// (`Snapshot`) and at the wire (`Relation.init(dto:)`), and pulls again from
/// the start once it does (`MemoryStore.kindsKnown`, rule 10).
enum RelationKind: String, Codable, CaseIterable {
    case parentOf = "parent_of"
    case spouseOf = "spouse_of"
    case siblingOf = "sibling_of"
    case friendOf = "friend_of"

    var isSymmetric: Bool { self != .parentOf }

    /// The kinds a family tree is drawn from and the *Suku* list is made of.
    /// `friendOf` is the one that is neither.
    static let kinship: [RelationKind] = [.parentOf, .spouseOf, .siblingOf]
}

struct Relation: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var fromSubjectID: String
    var toSubjectID: String
    var kind: RelationKind
    /// A relationship inferred by the AI is created unconfirmed. Unconfirmed
    /// never appears in the family tree as fact — a wrong relationship is worse
    /// than a missing one, because later nobody knows it was a guess.
    var confirmed: Bool = false
    var createdAt: Date = .now
    /// When it was taken back. Same reasoning as `Subject.deletedAt`: a removed
    /// relationship that never leaves the device is one the other devices go on
    /// showing, and this is the half of the family tree a person is most likely
    /// to want undone.
    var deletedAt: Date?
}

// MARK: - Follow-up question

/// Both the tail of the magic moment and the retention engine: an open question
/// is a reason to come back.
struct FollowUpQuestion: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var subjectID: String?
    var text: String
    /// How much the question asks of the person answering it, 1–5, as labelled
    /// by the extraction that produced it. Nil when nobody labelled it — a row
    /// written before the field existed, or a question a person asked — and the
    /// level is then read off the wording instead. See `QuestionLadder`.
    var storedLevel: Int?
    var answered: Bool = false
    var createdAt: Date = .now
    /// Who asked. Nil for questions the extraction generated — the difference
    /// matters, because "Ville kysyy" carries a pull no machine question has.
    /// Optional so stores written before the field existed still decode.
    var authorID: String?
    var authorName: String?
    /// Who it is aimed at: a member id, or nil for the whole family. The asker
    /// chooses it once (`AskQuestionSheet`), and it narrows two things — whose
    /// Kerro tab offers the question, and who is notified — never who may
    /// answer: every member still sees it on the card. Optional, like every
    /// field added to this model (CLAUDE.md, rule 10).
    var targetMemberID: String?
    var targetName: String?
    /// The telling that answered it, when this phone knows. Recorded so the
    /// archive keeps which telling answered which question.
    var answeredMemoryID: String?
    /// The telling whose extraction raised it, on the phone that told it and
    /// nowhere else: never sent, kept through a pull by `applyRemote`. What
    /// lets taking that telling back take its open questions with it
    /// (`MemoryStore.remove(memoryID:)`), since 27 Sep 2026, and moving it to
    /// another card too (`move(memoryID:to:)`), since 28 Sep. Nil for a
    /// question a person asked, for one raised on another phone, and for
    /// every question raised before the field existed.
    var askedFrom: String?
    /// When it was taken off its card for good: withdrawn or moved away with
    /// the telling that raised it, or replaced by a newer telling's questions
    /// (`ExtractionContext.turnover`). Set only on the copy waiting in
    /// `MemoryStore.retiredQuestions` to go to the server as a tombstone; a
    /// question in `questions` never carries it.
    var deletedAt: Date?

    /// Whether the extraction wrote it rather than a person. Only the
    /// machine's questions are ever retired by a newer telling
    /// (`ExtractionContext.turnover`): a person's question is a request
    /// somebody made of the family. Either half of an asker makes it a
    /// person's. Computed, so nothing new is stored (rule 10).
    var isMachine: Bool { authorID == nil && authorName == nil }
}
