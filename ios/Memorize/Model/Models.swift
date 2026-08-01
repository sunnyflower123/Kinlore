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
    var label: String {
        switch self {
        case .photo: "Kuva"
        case .person: "Henkilö"
        case .place: "Paikka"
        case .event: "Tapahtuma"
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

    /// Human-readable form that states the uncertainty honestly.
    var displayText: String {
        guard let start else { return "Ajankohta ei tiedossa" }
        let year = Calendar.current.component(.year, from: start)
        switch precision {
        case .decade: return "\(year / 10 * 10)-luku"
        case .year: return "\(year)"
        case .month, .day:
            let f = DateFormatter()
            f.locale = Locale(identifier: "fi_FI")
            f.dateFormat = precision == .day ? "d.M.yyyy" : "LLLL yyyy"
            return f.string(from: start)
        case .unknown: return "Ajankohta ei tiedossa"
        }
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
    /// A subject proposed by the AI is created unconfirmed. Unconfirmed never
    /// appears in the family tree as fact — a wrong relationship is worse than a
    /// missing one.
    var confirmed: Bool = true
    var createdAt: Date = .now
    /// The forwarding address of a merge. When this is set, the subject is no
    /// longer its own person but redirects to another — see `MemoryStore.rename`.
    var mergedInto: String?

    /// A photo is imported without a title on purpose, because nobody will name
    /// thirty scanned photographs. The name arrives when someone talks about it.
    var displayTitle: String {
        if !title.isEmpty { return title }
        return kind == .photo ? "Valokuva" : kind.label
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

    /// The audio is saved but not yet transcribed — the quota was full or the
    /// network was down. A derived property, not a separate state to sync.
    ///
    /// This is the visible form of rule 3: a quota never rejects a recording, it
    /// defers its transcription. Grandmother's voice is the product.
    var isAwaitingTranscription: Bool {
        body.isEmpty && (audioFilename != nil || audioR2Key != nil)
    }
}

// MARK: - Relationships

/// The kind of a relationship.
///
/// `parentOf` is directed and reads `from → to`. Spouse and sibling are
/// symmetric: they are stored once and read in both directions, so the same
/// relationship cannot be created twice the other way round.
enum RelationKind: String, Codable, CaseIterable {
    case parentOf = "parent_of"
    case spouseOf = "spouse_of"
    case siblingOf = "sibling_of"

    var isSymmetric: Bool { self != .parentOf }

    /// How the relationship is named when adding it: "X is this person's ___".
    var addLabel: String {
        switch self {
        case .parentOf: "Vanhempi"
        case .spouseOf: "Puoliso"
        case .siblingOf: "Sisarus"
        }
    }
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
}

// MARK: - Follow-up question

/// Both the tail of the magic moment and the retention engine: an open question
/// is a reason to come back.
struct FollowUpQuestion: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var subjectID: String?
    var text: String
    var answered: Bool = false
    var createdAt: Date = .now
    /// Who asked. Nil for questions the extraction generated — the difference
    /// matters, because "Ville kysyy" carries a pull no machine question has.
    /// Optional so stores written before the field existed still decode.
    var authorID: String?
    var authorName: String?
}
