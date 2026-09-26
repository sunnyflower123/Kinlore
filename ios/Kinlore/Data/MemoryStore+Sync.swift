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
    /// The face on a person's card: a photograph of this family and a point
    /// in it, and the moment of choosing, which is the server's tiebreak.
    /// Optional in both directions like the colours above.
    var portrait_subject_id: String?
    var portrait_focus_x: Double?
    var portrait_focus_y: Double?
    var portrait_set_at: Double?
    /// What the family knows about a person in words (§26), as one sealed
    /// JSON list, and the moment the list last changed, which is the server's
    /// tiebreak between two phones' lists: the newer moment wins whole there,
    /// since a sealed list is all the server can see, and the phones join
    /// the lists fact by fact (`withFacts`). Optional in both directions like
    /// the rest: a server not yet redeployed sends neither, and most subjects
    /// have none.
    var facts: String?
    var facts_set_at: Double?
    /// A place's coordinates. Optional in both directions: a server that has not
    /// been redeployed does not send them, and most subjects are not places.
    var lat: Double?
    var lon: Double?
    var geo_precision: String?
    /// Who in the family vouched for that point, and when — optional for the
    /// same reason, and the name derived on read like the colours' and never
    /// sent.
    var geo_confirmed_by: String?
    var geo_confirmed_by_name: String?
    var geo_confirmed_at: Double?
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
    /// Outgoing: the member it is aimed at, or nil for the whole family. The
    /// server keeps it only from the asker, only once, and only for a member
    /// still in the family. Incoming: as stored, with the name derived like
    /// the asker's.
    var target_member: String?
    var target_name: String?
    /// The telling that answered it. An id, never content.
    var answered_memory_id: String?
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
            // The facts are words too — a name, a trade, a note — and the
            // server compares nothing in them, so the ordinary seal.
            row.facts = subject.facts.map { FamilyCrypto.seal($0, with: key) ?? $0 }
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
            row.facts = subject.facts.map { FamilyCrypto.open($0, with: key) ?? $0 }
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

/// The key one sync round works under, and without it no round at all.
///
/// `SyncEngine` gets everything it sends and everything it takes in through
/// this, and the only way to make one is to hold the family's key. So a phone
/// without the key has nothing to push with, nothing to upload with and nothing
/// to open a pull with. The engine holds the round and says why
/// (`SyncEngine.State.keyMissing`).
///
/// **Until 26 Sep 2026 a missing key meant no sealing rather than no syncing**
/// (0efbc6a). That kept a family from before lever 3 working, and no such
/// family ever reached the server the app talks to: lever 3 landed eight days
/// before the Worker first deployed. The fallback protected nobody, and it had
/// a road to it. With one Apple ID on two phones the key is one synchronizable
/// Keychain entry, and emptying either phone deletes it on both. The other
/// phone then pushed its rows and uploaded its recordings as they were, into
/// D1 and R2 for good. `scripts/keyless-sync-check.swift` drives that road.
///
/// **Holding loses nothing.** The outbox is cleared only by a push that
/// happened, and the cursor moves only through a pull that was applied, so
/// everything waiting goes up sealed once a new invitation brings the key
/// back (`Session.rejoin`). A pull is not taken in unopened either: its rows
/// would be stored as sealed strings and stay that way after the key
/// returned, because the cursor would already have moved past them.
struct SyncSeal {
    let key: SymmetricKey

    init?(key: SymmetricKey?) {
        guard let key else { return nil }
        self.key = key
    }

    /// What crosses to the Worker.
    func push(_ payload: SyncPayload) -> SyncPayload {
        payload.sealed(with: key)
    }

    /// A photograph, a colouring or a voice, sealed before it is uploaded. A
    /// seal that fails still sends the bytes as they are, for the reason
    /// `sealed(with:)` gives about a row. Under a key of the right length
    /// AES-GCM does not fail, and `FamilyKey.current()` hands out no other kind.
    func upload(_ bytes: Data) -> Data {
        FamilyCrypto.seal(bytes, with: key) ?? bytes
    }

    /// What comes back, opened.
    func pull(_ reply: SyncPullReply) -> SyncPullReply {
        reply.opened(with: key)
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
            portrait_subject_id: portraitSubjectID,
            portrait_focus_x: portraitFocusX,
            portrait_focus_y: portraitFocusY,
            portrait_set_at: portraitSetAt?.timeIntervalSince1970,
            // Both or neither: a list without its moment is no opinion to
            // the server, and a moment without a list would be one about
            // nothing.
            facts: factsSetAt == nil ? nil : facts.flatMap(PersonFact.encodedList),
            facts_set_at: facts == nil ? nil : factsSetAt?.timeIntervalSince1970,
            lat: place?.latitude,
            lon: place?.longitude,
            geo_precision: place?.precision.rawValue,
            geo_confirmed_by: place?.confirmedByID,
            geo_confirmed_by_name: nil,
            geo_confirmed_at: place?.confirmedAt?.timeIntervalSince1970,
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
            portraitSubjectID: dto.portrait_subject_id,
            portraitFocusX: dto.portrait_focus_x,
            portraitFocusY: dto.portrait_focus_y,
            portraitSetAt: dto.portrait_set_at.map { Date(timeIntervalSince1970: $0) },
            facts: dto.facts.flatMap(PersonFact.decodedList),
            factsSetAt: dto.facts_set_at.map { Date(timeIntervalSince1970: $0) },
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

    /// A pulled row laid over this phone's copy of it, as far as the face goes.
    ///
    /// The server keeps the newest choice, and a pull is its answer — with the
    /// one exception the colours have too: a row that says nothing about the
    /// face takes nothing away. A Worker that has not been redeployed sends no
    /// `portrait_set_at`, and would otherwise wipe every face the family had
    /// chosen on the first pull after an update. A choice this phone has not
    /// pushed yet needs no rule here: the row is dirty, and `applyRemote`
    /// skips it whole.
    ///
    /// A removal is not "nothing": it arrives as a nil id under a moment, and
    /// the moment is what this reads.
    func withPortrait(from local: Subject) -> Subject {
        guard portraitSetAt == nil else { return self }
        var row = self
        row.portraitSubjectID = local.portraitSubjectID
        row.portraitFocusX = local.portraitFocusX
        row.portraitFocusY = local.portraitFocusY
        row.portraitSetAt = local.portraitSetAt
        return row
    }

    /// A pulled row laid over this phone's copy of it, as far as the point on
    /// the map goes.
    ///
    /// The server keeps the family's newest word on where a place is
    /// (`sync.ts`), and a pull is its answer — with the exception the colours
    /// and the face have too: a row that says nothing about who placed the
    /// point takes nothing away from a phone that knows. A Worker that has not
    /// been redeployed sends no `geo_confirmed_at`, and its own rule keeps a
    /// stored exact point over anything coarser, so its answer to a point the
    /// family had just taken off the map would be the point, back on it.
    func withPlace(from local: Subject) -> Subject {
        guard local.place?.isConfirmed == true, place?.isConfirmed != true else { return self }
        var row = self
        row.place = local.place
        return row
    }

    /// A pulled row laid over this phone's copy of it, as far as the facts go.
    ///
    /// The server keeps the newer of two lists whole (`sync.ts`), because a
    /// sealed list is all it can see; the phones can see inside, and join
    /// them fact by fact (`PersonFact.joined`). A row that says nothing about
    /// facts takes nothing away and marks nothing to push — a Worker not yet
    /// redeployed sends none, and a phone that pushed on every pull because
    /// of it would push for ever; neither does a list this phone's key could
    /// not open, which reads as no list at all. When the join holds anything
    /// the server did not send, the row has to go up again, under a moment
    /// strictly later than the server's: on the same moment the server would
    /// keep its own list, and the fact the other phone wrote would never land
    /// there. Later than the server's and not merely this phone's *now*,
    /// because a phone whose clock runs behind would otherwise lose that
    /// push every time, and push again on every pull until its clock caught
    /// up. One millisecond past the server's moment is enough, and the
    /// column is a REAL.
    func withFacts(from local: Subject, now: Date = .now) -> (row: Subject, needsPush: Bool) {
        var row = self
        guard let pulled = facts else {
            row.facts = local.facts
            row.factsSetAt = local.factsSetAt
            return (row, false)
        }
        let joined = PersonFact.joined(local.facts ?? [], with: pulled)
        row.facts = joined
        let differs = Set(joined) != Set(pulled)
        if differs {
            row.factsSetAt = max(now, (factsSetAt ?? .distantPast).addingTimeInterval(0.001))
        }
        return (row, differs)
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
            precision: dto.geo_precision.flatMap(GeoPrecision.init(rawValue:)) ?? .unknown,
            confirmedByID: dto.geo_confirmed_by,
            confirmedByName: dto.geo_confirmed_by_name,
            confirmedAt: dto.geo_confirmed_at.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

extension PersonFact {
    /// The list as one JSON string for the wire: dates as seconds since 1970
    /// and keys in order, so the same list is the same bytes. Nothing
    /// compares them today; a web client reading the same blob one day
    /// (`webcrypto-interop-check`) is easier to write against a fixed shape.
    static func encodedList(_ facts: [PersonFact]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(facts)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The most bytes a list may take as JSON before it is sealed, against
    /// the Worker's 65 536 on the sealed column (`MAX_FACTS_LENGTH` in
    /// `sync.ts`). Sealing adds 28 bytes and base64 a third, so the largest
    /// list this phone will write crosses at about 53 400 — which
    /// `facts-check.swift` measures rather than trusts. The two numbers have
    /// to stand well apart: a list the Worker refused would leave the
    /// server's older one standing, the join here would differ from it on
    /// every pull, and the phone would push the same refusal for ever.
    static let listByteLimit = 40_000

    /// Whether a list is one this phone may write.
    static func fits(_ facts: [PersonFact]) -> Bool {
        guard let json = encodedList(facts) else { return false }
        return json.utf8.count <= listByteLimit
    }

    /// The list read back, row by row: a row that is not a fact is left out
    /// rather than failing the list, and a string that is not a list at all
    /// — a blob the key could not open — is nil, which `Subject.withFacts`
    /// treats as no opinion.
    static func decodedList(_ json: String) -> [PersonFact]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = json.data(using: .utf8),
              let rows = try? decoder.decode([Lenient<PersonFact>].self, from: data)
        else { return nil }
        return rows.compactMap(\.value)
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
            //
            // The fallback is a word and not a name, so it is looked up like
            // one. This comment used to read "the fallback is Finnish because
            // it is shown in the UI", which names the right reason and draws
            // the opposite conclusion from it: being shown is exactly what
            // makes a translation necessary, and English has been the default
            // since 30 Aug 2026. Nothing reported it, because the string went
            // into `authorName` and reached the screen through an
            // interpolation rather than through a literal.
            //
            // The word is the server's own — `DEFAULTS` in `family.ts` writes
            // "Perheenjäsen" or "Family member" into `member.display_name`
            // when a joiner types no name, following the `lang` the client
            // sends. So this is the last resort below that one, for a row
            // whose author has no member record at all, and it has to read
            // the same as the name the server would have written.
            authorName: dto.author_name ?? String(localized: "Perheenjäsen"),
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
            author_name: nil,
            target_member: targetMemberID,
            target_name: nil,
            answered_memory_id: answeredMemoryID
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
            authorName: dto.author_name,
            targetMemberID: dto.target_member,
            targetName: dto.target_name,
            answeredMemoryID: dto.answered_memory_id
        )
    }
}
