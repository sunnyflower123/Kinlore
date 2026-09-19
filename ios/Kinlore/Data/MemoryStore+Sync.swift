import CryptoKit
import Foundation

/// The sync transfer types and the conversions to and from them.
///
/// Kept apart from the storage logic because these are the contract with the
/// server: the fields match the row shapes in `backend/src/sync.ts` one to one.

// MARK: - Transfer types

struct SubjectDTO: Codable {
    var id: String
    var kind: String
    var title: String?
    var r2_key: String?
    /// A photograph's confirmed colours: the object, who said yes and when.
    /// Optional in both directions, like the coordinates below — a server that
    /// has not been redeployed sends none of it, and most subjects have none.
    /// The name is the server's, derived on read, and never sent.
    var colour_r2_key: String?
    var colour_confirmed_by: String?
    var colour_confirmed_by_name: String?
    var colour_confirmed_at: Double?
    /// A place's coordinates. Optional in both directions: a server that has not
    /// been redeployed does not send them, and most subjects are not places.
    var lat: Double?
    var lon: Double?
    var geo_precision: String?
    var date_start: Double?
    var date_end: Double?
    var date_precision: String?
    var confirmed: Int
    var merged_into: String?
    var created_at: Double
    var deleted_at: Double?
    var seq: Int?
}

struct MemoryDTO: Codable {
    var id: String
    var subject_id: String
    var author_id: String?
    var author_name: String?
    var body: String
    var raw_transcript: String?
    var audio_r2_key: String?
    var audio_seconds: Double?
    var source: String
    var mentions: [String]?
    /// Who told it, and whether they asked not to be named. Optional in both
    /// directions for the same reason the colours above are: a Worker that has
    /// not been redeployed sends neither, and most tellings until now have
    /// neither. Not sealed, and not needing to be — it is a UUID pointing at a
    /// subject whose own title is sealed, which is the argument the relations
    /// already travel on.
    var teller_subject_id: String?
    var teller_hidden: Int?
    var created_at: Double
    var deleted_at: Double?
    var seq: Int?
}

struct QuestionDTO: Codable {
    var id: String
    var subject_id: String?
    var text: String
    /// How much the question asks of the answerer, 1–5. Optional in both
    /// directions: an older server does not send it, and a question nobody
    /// labelled travels without it.
    var level: Int?
    var status: String
    var created_at: Double
    var deleted_at: Double?
    var seq: Int?
    /// Outgoing: the asker's own member id, or nil for an AI question. The
    /// server accepts only the session's own id — the same rule as a memory's
    /// author. Incoming: as stored.
    var author_id: String?
    /// Incoming only: derived on the server from `member.display_name`.
    var author_name: String?
}

struct RelationDTO: Codable {
    var id: String
    var from_subject: String
    var to_subject: String
    var kind: String
    var confirmed: Int
    var created_at: Double
    var deleted_at: Double?
    var seq: Int?
}

struct SyncPayload: Codable {
    var subjects: [SubjectDTO] = []
    var memories: [MemoryDTO] = []
    var questions: [QuestionDTO] = []
    var relations: [RelationDTO] = []

    /// Whether there is anything to send. Read off the payload itself rather
    /// than off the outbox: a row that is queued but not yet sendable — an
    /// untranscribed memory whose audio has not reached R2 — is still waiting,
    /// and a push containing nothing else would be a wasted request.
    var isEmpty: Bool {
        subjects.isEmpty && memories.isEmpty && questions.isEmpty
            && relations.isEmpty
    }
}

struct SyncPullReply: Codable {
    var seq: Int
    var more: Bool
    var subjects: [SubjectDTO]
    var memories: [MemoryDTO]
    var questions: [QuestionDTO]
    /// An older server does not send this, so a default is required.
    var relations: [RelationDTO] = []
}

// MARK: - Encryption at rest

/// PLAN.md §10 lever 3, applied in exactly two places.
///
/// **The boundary is the payload, not the model.** The store on disk stays
/// plaintext: it is inside the app's container, protected by the device
/// passcode, and it is what the export is written from. What is sealed is what
/// crosses to the Worker, because a breach dumps the database and not this
/// phone. Doing it any deeper would mean decrypting to draw every screen and
/// encrypting to save a draft, for no gain against the threat this is about.
///
/// One transform each way, so that there is one place to read when asking what
/// the server can see. Threading a key through every DTO conversion was the
/// other option and would have put the question in nine places.
///
/// **Relations are not sealed and do not need to be**: they are UUIDs pointing
/// at other UUIDs. What they leak is the shape of a family tree, which the row
/// count leaks anyway.
extension SyncPayload {
    func sealed(with key: SymmetricKey) -> SyncPayload {
        var copy = self
        // Every one of these falls back to the plaintext rather than to nil.
        //
        // `flatMap` was the obvious spelling and it is a data-loss bug: sealing
        // returns an optional, so a failure would replace a title or a raw
        // transcript with *nothing* and push that — and rule 3 says the raw
        // transcript is not an intermediate step, it is the product. Sending a
        // row in clear because the seal failed is a bad day; sending an empty
        // one is the memory gone from every other device in the family.
        copy.subjects = subjects.map { subject in
            var row = subject
            // Deterministic, because the server compares this field to decide
            // whether a rename should drop the coordinates. See FamilyCrypto.
            row.title = subject.title.map { title in
                title.isEmpty ? title : (FamilyCrypto.sealDeterministically(title, with: key) ?? title)
            }
            return row
        }
        copy.memories = memories.map { memory in
            var row = memory
            row.body = memory.body.isEmpty
                ? memory.body
                : (FamilyCrypto.seal(memory.body, with: key) ?? memory.body)
            row.raw_transcript = memory.raw_transcript.map {
                FamilyCrypto.seal($0, with: key) ?? $0
            }
            return row
        }
        copy.questions = questions.map { question in
            var row = question
            row.text = FamilyCrypto.seal(question.text, with: key) ?? question.text
            return row
        }
        return copy
    }
}

extension SyncPullReply {
    /// The mirror. A row that will not open keeps whatever came back, and every
    /// screen then shows the sealed string rather than nothing — which is ugly
    /// and is the point. The case means the wrong key, and an archive that
    /// silently draws unreadable memories as empty ones would be the app
    /// claiming grandmother said nothing.
    func opened(with key: SymmetricKey) -> SyncPullReply {
        var copy = self
        copy.subjects = subjects.map { subject in
            var row = subject
            row.title = subject.title.map { FamilyCrypto.open($0, with: key) ?? $0 }
            return row
        }
        copy.memories = memories.map { memory in
            var row = memory
            row.body = FamilyCrypto.open(memory.body, with: key) ?? memory.body
            row.raw_transcript = memory.raw_transcript.map { FamilyCrypto.open($0, with: key) ?? $0 }
            return row
        }
        copy.questions = questions.map { question in
            var row = question
            row.text = FamilyCrypto.open(question.text, with: key) ?? question.text
            return row
        }
        return copy
    }
}

// MARK: - Conversions

extension Subject {
    var dto: SubjectDTO {
        SubjectDTO(
            id: id,
            kind: kind.rawValue,
            title: title,
            r2_key: r2Key,
            // A yes travels with its file or not at all: until the upload has
            // a key, the colours stay on this phone.
            colour_r2_key: colourR2Key,
            colour_confirmed_by: colourR2Key == nil ? nil : colourConfirmedByID,
            colour_confirmed_by_name: nil,
            colour_confirmed_at: colourR2Key == nil ? nil : colourConfirmedAt?.timeIntervalSince1970,
            lat: place?.latitude,
            lon: place?.longitude,
            geo_precision: place?.precision.rawValue,
            date_start: dateHint?.start?.timeIntervalSince1970,
            date_end: dateHint?.end?.timeIntervalSince1970,
            date_precision: dateHint?.precision.rawValue,
            confirmed: confirmed ? 1 : 0,
            merged_into: mergedInto,
            created_at: createdAt.timeIntervalSince1970,
            // The one field the client used to hardcode to nil, which is why a
            // rejection never left the device. See docs/ARCHITECTURE.md §3.
            deleted_at: deletedAt?.timeIntervalSince1970,
            seq: nil
        )
    }

    init?(dto: SubjectDTO) {
        guard let kind = SubjectKind(rawValue: dto.kind) else { return nil }
        self.init(
            id: dto.id,
            kind: kind,
            title: dto.title ?? "",
            r2Key: dto.r2_key,
            dateHint: Self.hint(from: dto),
            place: Self.place(from: dto),
            colourR2Key: dto.colour_r2_key,
            colourConfirmedByID: dto.colour_confirmed_by,
            colourConfirmedByName: dto.colour_confirmed_by_name,
            colourConfirmedAt: dto.colour_confirmed_at.map { Date(timeIntervalSince1970: $0) },
            confirmed: dto.confirmed == 1,
            createdAt: Date(timeIntervalSince1970: dto.created_at),
            mergedInto: dto.merged_into,
            deletedAt: dto.deleted_at.map { Date(timeIntervalSince1970: $0) }
        )
    }

    /// A pulled row laid over this phone's copy of it, as far as the colours go.
    ///
    /// The server keeps the newest yes (`sync.ts`), and a pull is its answer —
    /// with two exceptions only this phone can keep. A row that says nothing
    /// about colours takes nothing away: a Worker that has not been redeployed
    /// sends none, and would otherwise wipe every colouring the family had
    /// confirmed on the first pull after an update. And a yes this phone has
    /// not uploaded yet is newer than anything the server can hold; it travels
    /// on the next push, and is kept until then.
    ///
    /// Otherwise the pulled yes stands. Under the same key the file on this
    /// phone is still its picture; under another key it is not, and it comes
    /// back as `stale` for the caller to delete.
    func withColours(from local: Subject) -> (row: Subject, stale: String?) {
        var row = self
        let pendingHere = local.colourImageFilename != nil && local.colourR2Key == nil
        guard colourR2Key != nil, !pendingHere else {
            row.colourImageFilename = local.colourImageFilename
            row.colourR2Key = local.colourR2Key
            row.colourConfirmedByID = local.colourConfirmedByID
            row.colourConfirmedByName = local.colourConfirmedByName
            row.colourConfirmedAt = local.colourConfirmedAt
            return (row, nil)
        }
        guard colourR2Key != local.colourR2Key else {
            row.colourImageFilename = local.colourImageFilename
            return (row, nil)
        }
        return (row, local.colourImageFilename)
    }

    private static func hint(from dto: SubjectDTO) -> DateHint? {
        guard let raw = dto.date_precision,
              let precision = DatePrecision(rawValue: raw),
              precision != .unknown
        else { return nil }
        return DateHint(
            start: dto.date_start.map { Date(timeIntervalSince1970: $0) },
            end: dto.date_end.map { Date(timeIntervalSince1970: $0) },
            precision: precision
        )
    }

    /// Both halves or neither: a latitude without a longitude is not half a
    /// location. An unrecognised precision degrades to `.unknown` rather than
    /// dropping the point — where it is matters more than how exactly.
    private static func place(from dto: SubjectDTO) -> PlaceHint? {
        guard let lat = dto.lat, let lon = dto.lon else { return nil }
        return PlaceHint(
            latitude: lat,
            longitude: lon,
            precision: dto.geo_precision.flatMap(GeoPrecision.init(rawValue:)) ?? .unknown
        )
    }
}

extension Memory {
    var dto: MemoryDTO {
        MemoryDTO(
            id: id,
            subject_id: subjectID,
            author_id: authorID,
            author_name: authorName,
            body: body,
            raw_transcript: rawTranscript,
            audio_r2_key: audioR2Key,
            audio_seconds: audioDuration,
            source: source.rawValue,
            mentions: mentionedSubjectIDs,
            teller_subject_id: tellerSubjectID,
            teller_hidden: tellerHidden == true ? 1 : nil,
            created_at: createdAt.timeIntervalSince1970,
            // Hardcoded to nil until a memory could be taken back at all. The
            // same field on a subject was hardcoded the same way once, and a
            // rejection never left the device (§3) — this one is sent for the
            // same reason: a removal that stops here is not a removal.
            deleted_at: deletedAt?.timeIntervalSince1970,
            seq: nil
        )
    }

    init(dto: MemoryDTO) {
        self.init(
            id: dto.id,
            subjectID: dto.subject_id,
            authorID: dto.author_id,
            // The server attaches the member's display name so the client does
            // not have to keep a separate member directory just for reading.
            // The fallback is Finnish because it is shown in the UI.
            authorName: dto.author_name ?? "Perheenjäsen",
            body: dto.body,
            rawTranscript: dto.raw_transcript,
            audioR2Key: dto.audio_r2_key,
            audioDuration: dto.audio_seconds,
            source: MemorySource(rawValue: dto.source) ?? .typed,
            createdAt: Date(timeIntervalSince1970: dto.created_at),
            mentionedSubjectIDs: dto.mentions ?? [],
            tellerSubjectID: dto.teller_subject_id,
            tellerHidden: dto.teller_hidden == 1 ? true : nil,
            deletedAt: dto.deleted_at.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

extension Relation {
    var dto: RelationDTO {
        RelationDTO(
            id: id,
            from_subject: fromSubjectID,
            to_subject: toSubjectID,
            kind: kind.rawValue,
            confirmed: confirmed ? 1 : 0,
            created_at: createdAt.timeIntervalSince1970,
            deleted_at: deletedAt?.timeIntervalSince1970,
            seq: nil
        )
    }

    init?(dto: RelationDTO) {
        guard let kind = RelationKind(rawValue: dto.kind) else { return nil }
        self.init(
            id: dto.id,
            fromSubjectID: dto.from_subject,
            toSubjectID: dto.to_subject,
            kind: kind,
            confirmed: dto.confirmed == 1,
            createdAt: Date(timeIntervalSince1970: dto.created_at),
            deletedAt: dto.deleted_at.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

extension FollowUpQuestion {
    var dto: QuestionDTO {
        QuestionDTO(
            id: id,
            subject_id: subjectID,
            text: text,
            level: storedLevel,
            status: answered ? "answered" : "open",
            created_at: createdAt.timeIntervalSince1970,
            deleted_at: nil,
            seq: nil,
            author_id: authorID,
            // Never sent: the server derives the name from the member record,
            // so a renamed member is right everywhere at once.
            author_name: nil
        )
    }

    init(dto: QuestionDTO) {
        self.init(
            id: dto.id,
            subjectID: dto.subject_id,
            text: dto.text,
            storedLevel: dto.level,
            answered: dto.status != "open",
            createdAt: Date(timeIntervalSince1970: dto.created_at),
            authorID: dto.author_id,
            authorName: dto.author_name
        )
    }
}
