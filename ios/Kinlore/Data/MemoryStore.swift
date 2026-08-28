import Foundation

/// Local storage.
///
/// A JSON file is enough: a family's memories number in the hundreds, not the
/// hundreds of thousands. The whole file fits in memory and the write is atomic.
/// SQLite would bring indexes and partial updates, but also a dependency,
/// migrations and more code to be judged — see docs/ARCHITECTURE.md §3.
@MainActor
@Observable
final class MemoryStore {
    private(set) var subjects: [Subject] = []
    private(set) var memories: [Memory] = []
    private(set) var questions: [FollowUpQuestion] = []
    private(set) var relations: [Relation] = []

    /// The author's name. In a family this comes from the member record.
    var authorName = "Minä"

    /// The most recent ordering number received from the server. The next pull
    /// asks for everything above it.
    private(set) var syncSeq = 0

    /// The outbox: locally changed rows that have not been pushed yet. A
    /// separate set rather than a field on the model, so that the models stay
    /// clean and match exactly what is sent to the server.
    private(set) var dirtySubjects: Set<String> = []
    private(set) var dirtyMemories: Set<String> = []
    private(set) var dirtyQuestions: Set<String> = []
    private(set) var dirtyRelations: Set<String> = []

    private let fileURL: URL

    init(filename: String = "kinlore-store.json") {
        let documents = URL.documentsDirectory
        fileURL = documents.appendingPathComponent(filename)
        load()
        #if DEBUG
        // Only with `-seed archive`, and it replaces what is on the device.
        seedDemoArchiveIfRequested()
        #endif
    }

    // MARK: - Queries

    /// Everything still in the archive.
    ///
    /// `memories` itself keeps the tombstones, because a taking-back travels to
    /// the family like any other change and has to survive on the device until
    /// it does. Nothing outside sync and persistence should read that array —
    /// read this instead, or one of the queries built on it.
    var told: [Memory] {
        memories.filter { $0.deletedAt == nil }
    }

    func memories(for subjectID: String) -> [Memory] {
        told
            .filter { $0.subjectID == subjectID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Follows the merge chain. A reference to a merged subject always resolves
    /// to the survivor, so nothing points at nothing.
    ///
    /// A rejected subject resolves to nothing at all, which is the point of
    /// rejecting it: a memory may still list it among the names it mentioned,
    /// and that mention must stop producing a person.
    func subject(id: String) -> Subject? {
        var current = subjects.first { $0.id == id && $0.deletedAt == nil }
        // Cycle guard: broken data must not hang the UI.
        for _ in 0 ..< 8 {
            guard let target = current?.mergedInto else { return current }
            current = subjects.first { $0.id == target }
        }
        return current
    }

    /// Merged subjects are no longer their own, so they do not appear in lists.
    /// Neither do rejected ones — they are kept only so the rejection travels.
    func subjects(of kind: SubjectKind) -> [Subject] {
        subjects
            .filter { $0.kind == kind && $0.mergedInto == nil && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Subjects of a kind that match what somebody typed.
    ///
    /// The words of the memories count, not only the title. A photograph has no
    /// title until somebody says something about it, and what a person is
    /// looking for is "the one about the cottage" rather than a name nobody ever
    /// gave it — searching titles alone would find least on exactly the archive
    /// that most needs finding.
    ///
    /// An empty query is not a filter: everything comes back, so the screen does
    /// not have to know whether a search is running.
    func subjects(of kind: SubjectKind, matching query: String) -> [Subject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = subjects(of: kind)
        guard !needle.isEmpty else { return all }
        return all.filter { subject in
            subject.displayTitle.localizedCaseInsensitiveContains(needle)
                || memories(for: subject.id).contains {
                    $0.body.localizedCaseInsensitiveContains(needle)
                }
        }
    }

    /// The questions worth putting in front of the teller right now.
    ///
    /// Chosen by the ladder rather than by age: the oldest three are as likely
    /// as not to be the three hardest, and a person who cannot answer the first
    /// question they are shown does not press the button again. Passing a
    /// subject narrows it to that photo's or that person's own questions.
    /// See docs/ARCHITECTURE.md §12.
    func openQuestions(
        limit: Int = 3,
        for subjectID: String? = nil,
        excludingAuthor: String? = nil
    ) -> [FollowUpQuestion] {
        let open = questions.filter { question in
            guard !question.answered else { return false }
            // A question whose subject is no longer there has nothing left to be
            // answered about: the person was rejected, or the telling that
            // created the subject was taken back. It would otherwise keep being
            // offered on the Tell screen, where the subject's own card is not
            // there to make the emptiness visible.
            if let id = question.subjectID, subject(id: id) == nil { return false }
            // The Tell screen passes the asker's own id: a question asked FOR
            // the family must not come back at its asker as a prompt — with
            // the default display name it read "Minä kysyy", and the ladder
            // even pinned it first, because pinning keys on having an author.
            if let author = excludingAuthor, question.authorID == author { return false }
            return subjectID == nil || question.subjectID == subjectID
        }
        return QuestionLadder.select(open, comfort: QuestionLadder.comfort, limit: limit)
    }

    /// What to offer on a subject nobody has spoken about yet. These are
    /// generated on the spot and never stored — see `QuestionLadder.starters`.
    func starterQuestions(for subject: Subject, limit: Int = 2) -> [FollowUpQuestion] {
        guard isEmpty(subject) else { return [] }
        return Array(QuestionLadder.starters(for: subject).prefix(limit))
    }

    /// What to offer in free dictation when the archive is empty.
    ///
    /// The counterpart of `starterQuestions(for:)` for the case where there is no
    /// subject yet — the first launch, which is the one screen this audience is
    /// least able to get past on its own. See `QuestionLadder.opening`.
    ///
    /// Gated on the archive being empty rather than on there being no open
    /// questions: once anything has been told there are real questions to answer,
    /// and a generic one would compete with them for the same two slots.
    func openingQuestions() -> [FollowUpQuestion] {
        told.isEmpty ? QuestionLadder.opening : []
    }

    /// A subject that has no memories yet. These are not hidden but shown as an
    /// invitation: "nobody has said anything about Aino yet".
    func isEmpty(_ subject: Subject) -> Bool {
        !told.contains { $0.subjectID == subject.id }
    }

    /// Tellings the family cannot see yet: told on this device, not yet accepted
    /// by the server.
    ///
    /// Memories only. The outbox also carries subjects, questions and
    /// relationships, and nobody has ever wondered whether a relationship row
    /// reached their family — the question this answers is "did what I told get
    /// through", and it is asked about tellings.
    var waitingToBeSent: Int {
        told.filter { dirtyMemories.contains($0.id) }.count
    }

    /// Everything queued for the family, across all four tables. Watched by
    /// the app so that a write pushes the moment it lands rather than waiting
    /// for the next lifecycle moment; `waitingToBeSent` above stays the
    /// user-facing count, because tellings are what anybody ever asks about.
    var outboxCount: Int {
        dirtySubjects.count + dirtyMemories.count + dirtyQuestions.count + dirtyRelations.count
    }

    /// Whether anything in the archive still refers to this subject.
    ///
    /// Both directions count: a memory filed under it, and a memory that merely
    /// names it. A person who is only *mentioned* has no memory of their own,
    /// so asking "has it any memories" would call them orphaned while ten
    /// stories still say their name.
    func isOrphaned(subjectID: String) -> Bool {
        !told.contains {
            $0.subjectID == subjectID || $0.mentionedSubjectIDs.contains(subjectID)
        }
    }

    // MARK: - Writes

    /// Finds a subject with the same name or creates a new one. This is the
    /// point where the same person from different memories becomes one card.
    func findOrCreateSubject(named name: String, kind: SubjectKind, confirmed: Bool) -> Subject {
        // A rejected subject is not "existing". Somebody said this was not a
        // person, and the answer to hearing the name again is a fresh proposal
        // they can reject again — not the quiet return of the one they buried.
        if let existing = subjects.first(where: {
            $0.kind == kind && $0.deletedAt == nil
                && $0.title.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }
        let subject = Subject(kind: kind, title: name, confirmed: confirmed)
        subjects.append(subject)
        dirtySubjects.insert(subject.id)
        save()
        return subject
    }

    func add(_ subject: Subject) {
        subjects.append(subject)
        dirtySubjects.insert(subject.id)
        save()
    }

    func add(_ memory: Memory) {
        memories.append(memory)
        dirtyMemories.insert(memory.id)
        save()
    }

    func add(questions newQuestions: [FollowUpQuestion]) {
        questions.append(contentsOf: newQuestions)
        dirtyQuestions.formUnion(newQuestions.map(\.id))
        save()
    }

    /// Fills in a subject's details from what was told about it.
    ///
    /// **Only empty fields are filled.** A title written by a human, or a date
    /// brought by an earlier memory, is not overwritten — a later dictation must
    /// not silently change what the family has already agreed on.
    func describe(subjectID: String, title: String?, dateHint: DateHint?) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        if let title, subjects[index].title.isEmpty {
            subjects[index].title = title
        }
        if let dateHint, subjects[index].dateHint == nil {
            subjects[index].dateHint = dateHint
        }
        dirtySubjects.insert(subjectID)
        save()
    }

    /// A date somebody typed in, or cleared.
    ///
    /// Unlike `describe`, this **overwrites**. That one fills empty fields only,
    /// because it speaks for the extraction and a machine's guess must not walk
    /// over a person's knowledge. This one is the person: a granddaughter who
    /// knows the summer was 1957 outranks anything the model heard, and rule 5
    /// was only ever about not *rounding* uncertainty — not about refusing an
    /// answer from somebody who has one.
    ///
    /// Nil clears it, which is an answer too: a date that turned out to be wrong
    /// is worse than no date, and until now there was no way to say so.
    func setDateHint(subjectID: String, hint: DateHint?) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].dateHint = hint
        dirtySubjects.insert(subjectID)
        save()
    }

    /// Renames a subject. Used when the teller corrects a name that speech
    /// recognition misheard — that is the only moment the error can still be
    /// fixed, because later nobody knows what was said on the recording.
    ///
    /// If a subject with the same name already exists, the corrected one merges
    /// into it: the teller meant the same person, and two cards would be exactly
    /// the duplicate that the whole base-form requirement exists to prevent.
    func rename(subjectID: String, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = subjects.firstIndex(where: { $0.id == subjectID })
        else { return }

        let kind = subjects[index].kind
        // Not into a tombstone. Correcting a name onto somebody the family
        // rejected would move this subject's memories into a card nothing can
        // open — the merge is a forwarding address, and there has to be somebody
        // at the other end of it.
        if let existing = subjects.first(where: {
            $0.id != subjectID && $0.kind == kind
                && $0.mergedInto == nil && $0.deletedAt == nil
                && $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            // References move immediately, so the local view stays coherent...
            for i in memories.indices where memories[i].subjectID == subjectID {
                memories[i].subjectID = existing.id
            }
            for i in memories.indices {
                memories[i].mentionedSubjectIDs = memories[i].mentionedSubjectIDs.map {
                    $0 == subjectID ? existing.id : $0
                }
            }
            // ...but the row is NOT deleted. Another device that is offline may
            // be adding memories to this subject right now, and deleting it
            // would leave them pointing at nothing. A tombstone with a
            // forwarding address solves that and makes the merge reversible.
            // See docs/ARCHITECTURE.md §2.5.
            subjects[index].mergedInto = existing.id
            dirtyMemories.formUnion(
                memories.filter { $0.subjectID == existing.id }.map(\.id)
            )
        } else {
            subjects[index].title = trimmed
            // The coordinates were the answer to the old name. "Sortavala"
            // corrected from "Sortala" is a different point on the map, and a
            // stale one is worse than none: a wrong place looks like a fact.
            // `PlaceResolver` looks the new name up on the next sweep.
            subjects[index].place = nil
        }
        dirtySubjects.insert(subjectID)
        save()
    }

    /// Updates a memory's cleaned text. `rawTranscript` never changes — the
    /// original transcript is the evidence of what was actually said.
    func updateBody(memoryID: String, body: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].body = body
        dirtyMemories.insert(memoryID)
        save()
    }

    /// Memories whose audio is saved but whose text never arrived.
    ///
    /// Only our own. The server accepts a body only from the memory's author,
    /// so another member's device transcribing this would spend the family's AI
    /// minutes on an update that is then refused. A memory that has never been
    /// pushed has no author id yet and is ours by definition.
    ///
    /// Oldest first: the one that has waited longest is the one closest to
    /// being forgotten.
    func memoriesAwaitingTranscription(author memberID: String) -> [Memory] {
        told
            .filter { $0.isAwaitingTranscription }
            .filter { $0.authorID == nil || $0.authorID == memberID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Fills in a memory whose audio was saved before its text.
    ///
    /// This is the write that turns a waiting memory into an ordinary one. From
    /// here it is a memory like any other: it names people, it can carry a
    /// guessing round, and it reads as itself in the export.
    ///
    /// Unlike `updateBody` this does set `rawTranscript`, because it is the
    /// memory's *first* transcript rather than a correction of one. It refuses
    /// a memory that already has text, which makes it safe to call twice — two
    /// completions of the same recording must not race into a double write.
    func complete(
        memoryID: String,
        body: String,
        rawTranscript: String,
        mentionedSubjectIDs: [String]
    ) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }),
              memories[index].body.isEmpty
        else { return }
        memories[index].body = body
        memories[index].rawTranscript = rawTranscript
        memories[index].mentionedSubjectIDs = mentionedSubjectIDs
        dirtyMemories.insert(memoryID)
        save()
    }

    // MARK: - Places

    /// Named places whose location nobody has looked up yet.
    ///
    /// A tombstone is skipped, whether it was left by a merge or by a
    /// rejection: neither is its own place any more, and resolving one would
    /// spend a lookup on a name the family has already taken back. See
    /// docs/ARCHITECTURE.md §19.
    func placesAwaitingCoordinates() -> [Subject] {
        subjects.filter {
            $0.kind == .place && $0.mergedInto == nil && $0.deletedAt == nil
                && $0.place == nil && !$0.title.isEmpty
        }
    }

    /// Records a looked-up location.
    ///
    /// Queued for the server, unlike a downloaded photo's filename: the answer
    /// to "where is Puumala" is the same on every phone in the family, so it is
    /// worth looking up once rather than once per device.
    func setPlace(subjectID: String, place: PlaceHint) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].place = place
        dirtySubjects.insert(subjectID)
        save()
    }

    func confirm(subjectID: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].confirmed = true
        dirtySubjects.insert(subjectID)
        save()
    }

    /// Rejects a subject: a tombstone, not a removal.
    ///
    /// The row stays with `deletedAt` set and goes to the server like any other
    /// change. Taking it off the device was the bug: the server still had it,
    /// the next pull handed it back, and it came back as an unconfirmed
    /// proposal — which the people list shows with "vahvista henkilö" on it and
    /// offers no way to reject a second time, because rejecting only exists in
    /// the seconds after telling. A person who said no once should not have to
    /// say it again, least of all to somebody they said no to.
    func remove(subjectID: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].deletedAt = .now
        dirtySubjects.insert(subjectID)
        save()
    }

    /// The teller takes back what they just told: a tombstone, like a rejected
    /// subject.
    ///
    /// Rule 3 says the original audio and the raw transcript are always kept,
    /// and this does not bend it. That rule is about the *pipeline*: a quota, an
    /// outage or a failed extraction must never decide that something told is
    /// worth discarding. It was never about holding somebody to a telling they
    /// did not mean to give — and until now the app had no way to take one back
    /// at all, which is a heavier promise than the rule ever made.
    ///
    /// Only the teller's own, and only the server can enforce that: the memory
    /// upsert matches on `author_id`, so a tombstone for somebody else's memory
    /// is refused. The audio file stays on the device and in R2 exactly as a
    /// rejected person's row stays — nothing reads either.
    func remove(memoryID: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].deletedAt = .now
        dirtyMemories.insert(memoryID)
        save()
    }

    func markAnswered(questionID: String) {
        guard let index = questions.firstIndex(where: { $0.id == questionID }) else { return }
        questions[index].answered = true
        dirtyQuestions.insert(questionID)
        save()
    }

    /// Puts a question back on the open list.
    ///
    /// One case only: the answer was taken back. A question marked answered by a
    /// telling that is no longer in the archive has not been answered, and an
    /// open question is a reason to come back to the app — losing one quietly is
    /// losing exactly that.
    func reopen(questionID: String) {
        guard let index = questions.firstIndex(where: { $0.id == questionID }) else { return }
        questions[index].answered = false
        dirtyQuestions.insert(questionID)
        save()
    }

    // MARK: - Sync
    //
    // The mutations live here rather than in the extension, because they touch
    // the same private(set) fields as every other write. The transfer types are
    // in MemoryStore+Sync.swift: those are the contract with the server.

    /// The rows to push. An empty payload means there is nothing to send.
    ///
    /// A memory the server would refuse is deliberately left out rather than
    /// sent and dropped: see `Memory.isPushable`. It stays in the outbox and
    /// goes on the next round, once its audio has a key.
    func pendingPayload() -> SyncPayload {
        SyncPayload(
            subjects: subjects.filter { dirtySubjects.contains($0.id) }.map(\.dto),
            memories: memories.filter { dirtyMemories.contains($0.id) && $0.isPushable }.map(\.dto),
            questions: questions.filter { dirtyQuestions.contains($0.id) }.map(\.dto),
            relations: relations.filter { dirtyRelations.contains($0.id) }.map(\.dto)
        )
    }

    /// Acknowledges the rows that were pushed. Only the ones just sent: if the
    /// user managed to write during the request, the new change stays queued
    /// rather than being lost.
    func clearPending(_ payload: SyncPayload) {
        dirtySubjects.subtract(payload.subjects.map(\.id))
        dirtyMemories.subtract(payload.memories.map(\.id))
        dirtyQuestions.subtract(payload.questions.map(\.id))
        dirtyRelations.subtract(payload.relations.map(\.id))
        save()
    }

    /// Applies rows received from the server.
    ///
    /// A locally changed row is skipped: it is still queued, and the remote
    /// version would overwrite the memory that was just told. It reaches the
    /// server on the next push and wins there with a higher ordering number.
    func applyRemote(_ reply: SyncPullReply) {
        for dto in reply.subjects {
            guard !dirtySubjects.contains(dto.id), var incoming = Subject(dto: dto) else { continue }
            if let index = subjects.firstIndex(where: { $0.id == dto.id }) {
                // The DTO never carries the device-local half of the row: the
                // photo file on this disk. A pull replaces the row — including
                // the echo of this device's own push, now that the cursor only
                // moves through pulls — and dropping the filename would orphan
                // a photograph the free tier had refused: still on disk, no
                // longer referenced, and never uploaded even after the family
                // goes paid.
                incoming.imageFilename = subjects[index].imageFilename
                subjects[index] = incoming
            } else {
                subjects.append(incoming)
            }
        }

        for dto in reply.memories {
            guard !dirtyMemories.contains(dto.id) else { continue }
            var incoming = Memory(dto: dto)
            if let index = memories.firstIndex(where: { $0.id == dto.id }) {
                // Same rule as the subject's photo file above — and here it is
                // rule 3's file: the recording on this disk is the original.
                incoming.audioFilename = memories[index].audioFilename
                memories[index] = incoming
            } else {
                memories.append(incoming)
            }
        }

        for dto in reply.questions {
            guard !dirtyQuestions.contains(dto.id) else { continue }
            let incoming = FollowUpQuestion(dto: dto)
            if let index = questions.firstIndex(where: { $0.id == dto.id }) {
                questions[index] = incoming
            } else {
                questions.append(incoming)
            }
        }

        for dto in reply.relations {
            guard !dirtyRelations.contains(dto.id), let incoming = Relation(dto: dto) else { continue }
            if let index = relations.firstIndex(where: { $0.id == dto.id }) {
                relations[index] = incoming
            } else {
                relations.append(incoming)
            }
        }

        advance(seq: reply.seq)
    }

    func advance(seq: Int) {
        guard seq > syncSeq else { return }
        syncSeq = seq
        save()
    }

    // MARK: - Relationships

    /// A person's relationships, grouped the way a human thinks of them.
    ///
    /// Symmetric relationships are read in both directions, `parentOf` as
    /// directed: the same row means a parent to one side and a child to the other.
    func relatives(of subjectID: String, kind: RelationKind, asParent: Bool = false) -> [Subject] {
        relations.compactMap { relation -> Subject? in
            guard relation.kind == kind, relation.deletedAt == nil else { return nil }
            let otherID: String?
            if kind.isSymmetric {
                otherID = relation.fromSubjectID == subjectID ? relation.toSubjectID
                    : relation.toSubjectID == subjectID ? relation.fromSubjectID : nil
            } else if asParent {
                // Looking for this person's children: they are the `from` side.
                otherID = relation.fromSubjectID == subjectID ? relation.toSubjectID : nil
            } else {
                otherID = relation.toSubjectID == subjectID ? relation.fromSubjectID : nil
            }
            guard let otherID else { return nil }
            return subject(id: otherID)
        }
    }

    /// The live relationship between two people, whatever kind it is.
    ///
    /// Here rather than in the view that wants it. A view reaching into
    /// `relations` reaches past the tombstones too, and then a relationship
    /// somebody took back goes on colouring the row it was removed from.
    func relation(between a: String, and b: String) -> Relation? {
        relations.first {
            $0.deletedAt == nil
                && (($0.fromSubjectID == a && $0.toSubjectID == b)
                    || ($0.fromSubjectID == b && $0.toSubjectID == a))
        }
    }

    /// Whether this person has a relationship somebody still has to confirm.
    /// Removed ones do not count — they are not waiting for anything.
    func hasUnconfirmedRelation(for subjectID: String) -> Bool {
        relations.contains {
            !$0.confirmed && $0.deletedAt == nil
                && ($0.fromSubjectID == subjectID || $0.toSubjectID == subjectID)
        }
    }

    func relation(between a: String, and b: String, kind: RelationKind) -> Relation? {
        relations.first { relation in
            guard relation.kind == kind, relation.deletedAt == nil else { return false }
            if kind.isSymmetric {
                return (relation.fromSubjectID == a && relation.toSubjectID == b)
                    || (relation.fromSubjectID == b && relation.toSubjectID == a)
            }
            return relation.fromSubjectID == a && relation.toSubjectID == b
        }
    }

    /// Adds a relationship, or confirms an existing proposal.
    @discardableResult
    func addRelation(from: String, to: String, kind: RelationKind, confirmed: Bool = true) -> Relation? {
        guard from != to else { return nil }
        if let existing = relation(between: from, and: to, kind: kind) {
            if confirmed { confirmRelation(id: existing.id) }
            return existing
        }
        let relation = Relation(fromSubjectID: from, toSubjectID: to, kind: kind, confirmed: confirmed)
        relations.append(relation)
        dirtyRelations.insert(relation.id)
        save()
        return relation
    }

    func confirmRelation(id: String) {
        guard let index = relations.firstIndex(where: { $0.id == id }) else { return }
        relations[index].confirmed = true
        dirtyRelations.insert(id)
        save()
    }

    /// The same tombstone as a rejected subject, for the same reason: a
    /// relationship taken off this device and nowhere else is one every other
    /// device goes on showing as fact.
    func removeRelation(id: String) {
        guard let index = relations.firstIndex(where: { $0.id == id }) else { return }
        relations[index].deletedAt = .now
        dirtyRelations.insert(id)
        save()
    }

    // MARK: - Media

    /// Subjects that have a local photo but no R2 key yet.
    func subjectsAwaitingUpload() -> [Subject] {
        subjects.filter { $0.imageFilename != nil && $0.r2Key == nil }
    }

    /// Memories whose audio is still only local. The original audio is always
    /// uploaded, free tier included — it is the core of the product.
    func memoriesAwaitingUpload() -> [Memory] {
        // Taken-back recordings are not uploaded. The tombstone still travels —
        // it is a row, not a file — but there is no reason to spend the family's
        // bandwidth putting audio into R2 that nothing will ever play.
        told.filter { $0.audioFilename != nil && $0.audioR2Key == nil }
    }

    func setR2Key(subjectID: String, key: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].r2Key = key
        dirtySubjects.insert(subjectID)
        save()
    }

    func setAudioR2Key(memoryID: String, key: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].audioR2Key = key
        dirtyMemories.insert(memoryID)
        save()
    }

    /// The local cache of downloaded media. Not marked dirty: the filename is
    /// device specific and is none of the server's business.
    func setLocalImage(subjectID: String, filename: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].imageFilename = filename
        save()
    }

    func setLocalAudio(memoryID: String, filename: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].audioFilename = filename
        save()
    }

    /// Forgets where sync had got to, without touching a single row.
    ///
    /// The counter is granted per family (§2.2), so carrying a high one into the
    /// next family would silently suppress everything in it: a pull asking for
    /// "anything above 412" returns nothing at all from a family that has
    /// reached 3. Leaving is the one moment that can happen.
    func resetSyncCursor() {
        syncSeq = 0
        save()
    }

    // MARK: - Wiping

    /// Empties the archive on this device: every row, every media file and the
    /// outbox with them.
    ///
    /// Only "Tyhjennä tämä laite" in Settings calls this, and the screen has
    /// already said what it costs — in a family the memories are still on the
    /// server, in a local archive they are gone. That sentence belongs there
    /// rather than here, but this is the code it is describing.
    func wipe() {
        for filename in subjects.compactMap(\.imageFilename) {
            MediaStore.delete(filename: filename)
        }
        for filename in memories.compactMap(\.audioFilename) {
            MediaStore.delete(filename: filename)
        }
        subjects = []
        memories = []
        questions = []
        relations = []
        dirtySubjects = []
        dirtyMemories = []
        dirtyQuestions = []
        dirtyRelations = []
        syncSeq = 0
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Fixture

    #if DEBUG
    /// A canned family, for the two things that have no hands: the UI tests and
    /// the demo video.
    ///
    /// An archive with something in it: a second family member, four people, a
    /// photograph and memories about them. Producing that by tapping takes
    /// minutes and comes out slightly different every time, which is no basis
    /// for an accessibility test — the test has to fail because a label is
    /// missing, not because today's archive came out different.
    ///
    /// **It was called `-seed guess` until 16 Aug 2026**, after the one feature
    /// it was first built to reach. That feature was cut (PLAN.md §5) and the
    /// name outlived it by a few hours: a fixture named after something the app
    /// no longer has is a small lie that nine test files repeat. `archive` says
    /// what it is, and it is the opposite of `empty` below.
    ///
    /// Only with `-seed archive`, and it **replaces** what is on the device, which
    /// is why it is behind an explicit argument and never runs by accident. It
    /// lives here rather than in a file of its own because it writes the same
    /// `private(set)` fields as every other mutation.
    ///
    /// The content is Finnish because it is shown in the app's own UI — the same
    /// rule as the sample transcripts in `scripts/`. See CLAUDE.md.
    func seedDemoArchiveIfRequested() {
        // `-seed empty` is the other half: the empty states are a screen each,
        // and on a device that has ever been used they are unreachable.
        //
        // `-seed arrival` and `-seed alone` empty it the same way. Both hold a
        // Session-side state still (see `Session`), and both need the archive
        // itself out of the way: a fixture left over from an earlier run would
        // put content on a screen whose whole point is that none has arrived,
        // or a history under a result screen that is meant to be a first one.
        if ["empty", "arrival", "alone"]
            .contains(UserDefaults.standard.string(forKey: "seed") ?? "") {
            subjects = []
            memories = []
            questions = []
            relations = []
            dirtySubjects = []
            dirtyMemories = []
            dirtyQuestions = []
            dirtyRelations = []
            save()
            return
        }
        let seed = UserDefaults.standard.string(forKey: "seed")
        guard seed == "archive" || seed == "unseen" else { return }
        // `-seed unseen` is the archive with a reading debt: the same fixture,
        // plus a seen-baseline with nothing in it, so every telling by the
        // fixture's Mummo is one this phone has not seen. The section and the
        // landing that follow are otherwise unreachable — a real one needs a
        // second device to have told something between two visits.
        if seed == "unseen" {
            UserDefaults.standard.set([String](), forKey: NewFromFamily.seenKey)
        }
        // An open question from the fixture's Mummo, in the unseen branch
        // only. The demo video's fourth scene (docs/UX.md §10, the return) is
        // a "<nimi> kysyy" question answered aloud, and until pre-production
        // dry-ran the scenes (28 Aug 2026, docs/VIDEO.md) no seed carried one
        // — the state needs a second member to have asked, so no launch could
        // film it.
        // Deliberately not in `-seed archive`: the plain archive is what most
        // tests launch with, and a question offer appearing on their idle
        // screen would move furniture under every one of them.
        let mummoAsks: [FollowUpQuestion] = seed == "unseen"
            ? [FollowUpQuestion(
                id: "demo-question-mummo",
                subjectID: "demo-photo",
                text: "Kuka souti veneen saareen sinä aamuna?",
                authorID: "demo-mummo",
                authorName: "Mummo"
            )]
            : []

        let aino = Subject(id: "demo-aino", kind: .person, title: "Aino", confirmed: false)
        let eeva = Subject(id: "demo-eeva", kind: .person, title: "Eeva")
        let kalle = Subject(id: "demo-kalle", kind: .person, title: "Kalle")
        let sanni = Subject(id: "demo-sanni", kind: .person, title: "Sanni")
        let photo = Subject(id: "demo-photo", kind: .photo, title: "")
        // A place with nothing said about it yet, which is the ordinary state of
        // a place: it is named inside somebody's memory and gets a card of its
        // own. It is here so the accessibility sweep actually covers the Paikat
        // section and its invitation — an empty subject is the row with the
        // colour on it, and colour is the thing eyes cannot check.
        let puumala = Subject(id: "demo-puumala", kind: .place, title: "Puumala")
        // Somebody the extraction proposed and a human rejected. The row is kept
        // so the rejection can travel to the rest of the family, and it must
        // never be shown again — which is the half of soft deletion that can go
        // wrong quietly, so the fixture carries a case of it.
        let rejected = Subject(
            id: "demo-rejected",
            kind: .person,
            title: "Skotlanti",
            confirmed: false,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        subjects = [aino, eeva, kalle, sanni, photo, puumala, rejected]
        memories = [
            Memory(
                id: "demo-memory-aino",
                subjectID: photo.id,
                // Somebody else's story: you cannot guess your own.
                authorID: "demo-mummo",
                authorName: "Mummo",
                body: "Aino tuli mökille joka kesä, ja Ainon kanssa soudettiin saareen "
                    + "kalaan aamuvarhaisella. Kahvipannu oli aina mukana, ja rannassa "
                    + "istuttiin pitkään puhumassa siitä, millaista sodan jälkeen oli ollut.",
                // A key with nothing behind it, on purpose. A voice memory with
                // no audio at all was a fixture telling a small lie — and the
                // playback button, which is only drawn when there is audio to
                // play, was unreachable in the one archive every test uses. With
                // a dead address this is also the failing download, which is
                // exactly the case that used to do nothing at all.
                audioR2Key: "demo-audio-that-is-not-there",
                audioDuration: 42,
                source: .voice,
                mentionedSubjectIDs: [aino.id]
            ),
            // The decoys need memories of their own, or they are bare names and
            // the round answers itself.
            Memory(id: "demo-memory-eeva", subjectID: eeva.id, authorID: "demo-mummo",
                   authorName: "Mummo", body: "Eeva asui naapurissa.", source: .typed),
            Memory(id: "demo-memory-kalle", subjectID: kalle.id, authorID: "demo-mummo",
                   authorName: "Mummo", body: "Kalle ajoi puutavaraa.", source: .typed),
            Memory(id: "demo-memory-sanni", subjectID: sanni.id, authorID: "demo-mummo",
                   authorName: "Mummo", body: "Sanni hoiti kauppaa.", source: .typed),
        ]
        questions = mummoAsks
        relations = []
        // Nothing is queued for the server: this archive is a fixture, and
        // pushing it into a real family would be a genuine mess.
        dirtySubjects = []
        dirtyMemories = []
        dirtyQuestions = []
        dirtyRelations = []
        save()
    }
    #endif

    // MARK: - Disk

    struct Snapshot: Codable {
        var subjects: [Subject]
        var memories: [Memory]
        var questions: [FollowUpQuestion]
        var syncSeq: Int = 0
        var dirtySubjects: Set<String> = []
        var dirtyMemories: Set<String> = []
        var dirtyQuestions: Set<String> = []
        var relations: [Relation] = []
        var dirtyRelations: Set<String> = []
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        subjects = snapshot.subjects
        memories = snapshot.memories
        questions = snapshot.questions
        syncSeq = snapshot.syncSeq
        // The outbox persists on disk: a memory told offline must not go
        // unpushed just because the app was closed in between.
        dirtySubjects = snapshot.dirtySubjects
        dirtyMemories = snapshot.dirtyMemories
        dirtyQuestions = snapshot.dirtyQuestions
        relations = snapshot.relations
        dirtyRelations = snapshot.dirtyRelations
    }

    func save() {
        guard let data = try? JSONEncoder().encode(snapshot()) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            subjects: subjects,
            memories: memories,
            questions: questions,
            syncSeq: syncSeq,
            dirtySubjects: dirtySubjects,
            dirtyMemories: dirtyMemories,
            dirtyQuestions: dirtyQuestions,
            relations: relations,
            dirtyRelations: dirtyRelations
        )
    }

    /// The whole archive as JSON, for the export.
    ///
    /// Dates travel as ISO 8601 rather than in the on-disk form: this copy is
    /// read by whatever the family has in twenty years, not by this app. If the
    /// readable HTML ever lags behind the model, this is the file that lost
    /// nothing. See docs/ARCHITECTURE.md §14.
    ///
    /// **Its own shape, not the on-disk snapshot.** The snapshot carries the
    /// outbox — which rows this phone has not pushed yet — and the server's
    /// ordering cursor, and both were travelling into the family's permanent
    /// copy: opened in twenty years it said `dirtyMemories` at somebody. They
    /// are facts about one phone's sync on one afternoon, not about anything
    /// anybody told. What is left is the archive: what was said, who was
    /// spoken about, what was asked, and how people are related.
    struct Archive: Codable {
        var subjects: [Subject]
        var memories: [Memory]
        var questions: [FollowUpQuestion]
        var relations: [Relation]
    }

    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            Archive(
                subjects: subjects,
                // A telling the teller took back is not in the copy the family
                // keeps. Rejected *subjects* still are, and the difference is
                // the point: a rejected proposal is a note about what the
                // machine got wrong, while a taken-back memory is content
                // somebody withdrew.
                memories: told,
                questions: questions,
                relations: relations
            )
        )
    }
}
