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

struct GuessDTO: Codable {
    var memory_id: String
    /// Outgoing: our own member id. The server takes the guesser from the
    /// session and ignores this, so that no device can manufacture agreement
    /// from the rest of the family and confirm a person nobody recognised.
    var member_id: String
    /// Incoming only: derived on the server from `member.display_name`.
    var member_name: String?
    var subject_id: String
    var created_at: Double
    var seq: Int?
}

struct SyncPayload: Codable {
    var subjects: [SubjectDTO] = []
    var memories: [MemoryDTO] = []
    var questions: [QuestionDTO] = []
    var relations: [RelationDTO] = []
    var guesses: [GuessDTO] = []
}

struct SyncPullReply: Codable {
    var seq: Int
    var more: Bool
    var subjects: [SubjectDTO]
    var memories: [MemoryDTO]
    var questions: [QuestionDTO]
    /// An older server does not send this, so a default is required.
    var relations: [RelationDTO] = []
    /// Likewise.
    var guesses: [GuessDTO] = []
}

// MARK: - Conversions

extension Subject {
    var dto: SubjectDTO {
        SubjectDTO(
            id: id,
            kind: kind.rawValue,
            title: title,
            r2_key: r2Key,
            date_start: dateHint?.start?.timeIntervalSince1970,
            date_end: dateHint?.end?.timeIntervalSince1970,
            date_precision: dateHint?.precision.rawValue,
            confirmed: confirmed ? 1 : 0,
            merged_into: mergedInto,
            created_at: createdAt.timeIntervalSince1970,
            deleted_at: nil,
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
            confirmed: dto.confirmed == 1,
            createdAt: Date(timeIntervalSince1970: dto.created_at),
            mergedInto: dto.merged_into
        )
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
            created_at: createdAt.timeIntervalSince1970,
            deleted_at: nil,
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
            mentionedSubjectIDs: dto.mentions ?? []
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
            deleted_at: nil,
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
            createdAt: Date(timeIntervalSince1970: dto.created_at)
        )
    }
}

extension Guess {
    var dto: GuessDTO {
        GuessDTO(
            memory_id: memoryID,
            member_id: memberID,
            // Never sent: the server derives the name from the member record,
            // so a renamed member is right everywhere at once.
            member_name: nil,
            subject_id: subjectID,
            created_at: createdAt.timeIntervalSince1970,
            seq: nil
        )
    }

    init(dto: GuessDTO) {
        self.init(
            memoryID: dto.memory_id,
            memberID: dto.member_id,
            subjectID: dto.subject_id,
            // The fallback is Finnish because it is shown in the UI, and it
            // matches a memory's author for the same reason.
            memberName: dto.member_name ?? "Perheenjäsen",
            createdAt: Date(timeIntervalSince1970: dto.created_at)
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
