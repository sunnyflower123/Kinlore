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
    private(set) var guesses: [Guess] = []

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
    private(set) var dirtyGuesses: Set<String> = []

    private let fileURL: URL

    init(filename: String = "memorize-store.json") {
        let documents = URL.documentsDirectory
        fileURL = documents.appendingPathComponent(filename)
        load()
        #if DEBUG
        // Only with `-seed guess`, and it replaces what is on the device.
        seedDemoArchiveIfRequested()
        #endif
    }

    // MARK: - Queries

    func memories(for subjectID: String) -> [Memory] {
        memories
            .filter { $0.subjectID == subjectID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Follows the merge chain. A reference to a merged subject always resolves
    /// to the survivor, so nothing points at nothing.
    func subject(id: String) -> Subject? {
        var current = subjects.first { $0.id == id }
        // Cycle guard: broken data must not hang the UI.
        for _ in 0 ..< 8 {
            guard let target = current?.mergedInto else { return current }
            current = subjects.first { $0.id == target }
        }
        return current
    }

    /// Merged subjects are no longer their own, so they do not appear in lists.
    func subjects(of kind: SubjectKind) -> [Subject] {
        subjects
            .filter { $0.kind == kind && $0.mergedInto == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The questions worth putting in front of the teller right now.
    ///
    /// Chosen by the ladder rather than by age: the oldest three are as likely
    /// as not to be the three hardest, and a person who cannot answer the first
    /// question they are shown does not press the button again. Passing a
    /// subject narrows it to that photo's or that person's own questions.
    /// See docs/ARCHITECTURE.md §12.
    func openQuestions(limit: Int = 3, for subjectID: String? = nil) -> [FollowUpQuestion] {
        let open = questions.filter { question in
            guard !question.answered else { return false }
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

    /// A subject that has no memories yet. These are not hidden but shown as an
    /// invitation: "nobody has said anything about Aino yet".
    func isEmpty(_ subject: Subject) -> Bool {
        !memories.contains { $0.subjectID == subject.id }
    }

    // MARK: - Writes

    /// Finds a subject with the same name or creates a new one. This is the
    /// point where the same person from different memories becomes one card.
    func findOrCreateSubject(named name: String, kind: SubjectKind, confirmed: Bool) -> Subject {
        if let existing = subjects.first(where: {
            $0.kind == kind && $0.title.compare(name, options: .caseInsensitive) == .orderedSame
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
        if let existing = subjects.first(where: {
            $0.id != subjectID && $0.kind == kind && $0.mergedInto == nil &&
                $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame
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

    func confirm(subjectID: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].confirmed = true
        dirtySubjects.insert(subjectID)
        save()
    }

    func remove(subjectID: String) {
        subjects.removeAll { $0.id == subjectID }
        save()
    }

    func markAnswered(questionID: String) {
        guard let index = questions.firstIndex(where: { $0.id == questionID }) else { return }
        questions[index].answered = true
        dirtyQuestions.insert(questionID)
        save()
    }

    // MARK: - Guessing

    func guesses(for memoryID: String) -> [Guess] {
        guesses.filter { $0.memoryID == memoryID }
    }

    func guess(on memoryID: String, by memberID: String) -> Guess? {
        guesses.first { $0.memoryID == memoryID && $0.memberID == memberID }
    }

    /// The person a memory's round is about: the single person it names, if it
    /// names exactly one. The same rule `GuessRound` builds a round from, kept
    /// here so the reading side cannot drift away from it.
    func soleMentionedPerson(in memory: Memory) -> Subject? {
        let people = memory.mentionedSubjectIDs
            .compactMap { subject(id: $0) }
            .filter { $0.kind == .person && $0.mergedInto == nil }
        return people.count == 1 ? people.first : nil
    }

    /// Whether a stored guess names this person — after following the merge
    /// chain on both sides.
    ///
    /// Comparing the raw ids is wrong and fails silently. A guess is stored
    /// against the subject as it was when the guess was made, and a later merge
    /// ("Aune" → "Aino") leaves it pointing at the tombstone. Every correct
    /// guess made before the merge would quietly stop counting, which is exactly
    /// the class of bug `merged_into` exists to prevent.
    func guess(_ guess: Guess, names person: Subject) -> Bool {
        guard let guessed = guess.subjectID.flatMap({ subject(id: $0) }) else { return false }
        return guessed.id == subject(id: person.id)?.id
    }

    /// The family members who named the right person for this memory.
    ///
    /// This is what the teller gets back. Not a score — the point of telling a
    /// story about a dead sister is that somebody else still knows who she was.
    ///
    /// `reader` is left out of the list because it is their own screen: they
    /// have just seen the reveal, and "Minä tunnisti hänet" is both pointless
    /// and, in Finnish, the wrong person of the verb.
    func recognisers(of memory: Memory, excluding reader: String) -> [String] {
        guard let answer = soleMentionedPerson(in: memory) else { return [] }
        return guesses(for: memory.id)
            .filter { $0.memberID != reader && guess($0, names: answer) }
            .map(\.memberName)
    }

    /// Records one member's answer to a round.
    ///
    /// A correct answer confirms the person, and that is the whole reason this
    /// feature earns its place. A proposal card with the name already on it gets
    /// tapped "yes" without being read; someone who was not shown the name and
    /// arrived at it anyway has genuinely recognised the person. It is the least
    /// primed confirmation the app can collect — see rule 4 in CLAUDE.md.
    ///
    /// A wrong answer, and "En muista" with no subject at all, confirm nothing
    /// and un-confirm nothing. Both are kept: a family that keeps naming the
    /// same wrong person is saying the extraction picked the wrong name, and a
    /// stored "En muista" is what stops the round coming back forever.
    func record(_ newGuess: Guess, answer: Subject) {
        // One guess per person per memory. The answer is revealed immediately,
        // so a second attempt would be answering a question you already know.
        guard guess(on: newGuess.memoryID, by: newGuess.memberID) == nil else { return }
        guesses.append(newGuess)
        dirtyGuesses.insert(newGuess.id)
        if guess(newGuess, names: answer), !answer.confirmed {
            // confirm() saves; this call only has to not save twice.
            confirm(subjectID: answer.id)
            return
        }
        save()
    }

    // MARK: - Sync
    //
    // The mutations live here rather than in the extension, because they touch
    // the same private(set) fields as every other write. The transfer types are
    // in MemoryStore+Sync.swift: those are the contract with the server.

    /// The rows to push. An empty payload means there is nothing to send.
    func pendingPayload() -> SyncPayload {
        SyncPayload(
            subjects: subjects.filter { dirtySubjects.contains($0.id) }.map(\.dto),
            memories: memories.filter { dirtyMemories.contains($0.id) }.map(\.dto),
            questions: questions.filter { dirtyQuestions.contains($0.id) }.map(\.dto),
            relations: relations.filter { dirtyRelations.contains($0.id) }.map(\.dto),
            guesses: guesses.filter { dirtyGuesses.contains($0.id) }.map(\.dto)
        )
    }

    var hasPendingChanges: Bool {
        !dirtySubjects.isEmpty || !dirtyMemories.isEmpty || !dirtyQuestions.isEmpty
            || !dirtyRelations.isEmpty || !dirtyGuesses.isEmpty
    }

    /// Acknowledges the rows that were pushed. Only the ones just sent: if the
    /// user managed to write during the request, the new change stays queued
    /// rather than being lost.
    func clearPending(_ payload: SyncPayload) {
        dirtySubjects.subtract(payload.subjects.map(\.id))
        dirtyMemories.subtract(payload.memories.map(\.id))
        dirtyQuestions.subtract(payload.questions.map(\.id))
        dirtyRelations.subtract(payload.relations.map(\.id))
        dirtyGuesses.subtract(payload.guesses.map { "\($0.memory_id)|\($0.member_id)" })
        save()
    }

    /// Applies rows received from the server.
    ///
    /// A locally changed row is skipped: it is still queued, and the remote
    /// version would overwrite the memory that was just told. It reaches the
    /// server on the next push and wins there with a higher ordering number.
    func applyRemote(_ reply: SyncPullReply) {
        for dto in reply.subjects {
            guard !dirtySubjects.contains(dto.id), let incoming = Subject(dto: dto) else { continue }
            if let index = subjects.firstIndex(where: { $0.id == dto.id }) {
                subjects[index] = incoming
            } else {
                subjects.append(incoming)
            }
        }

        for dto in reply.memories {
            guard !dirtyMemories.contains(dto.id) else { continue }
            let incoming = Memory(dto: dto)
            if let index = memories.firstIndex(where: { $0.id == dto.id }) {
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

        for dto in reply.guesses {
            let incoming = Guess(dto: dto)
            guard !dirtyGuesses.contains(incoming.id) else { continue }
            if let index = guesses.firstIndex(where: { $0.id == incoming.id }) {
                guesses[index] = incoming
            } else {
                guesses.append(incoming)
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
            guard relation.kind == kind else { return nil }
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

    func relation(between a: String, and b: String, kind: RelationKind) -> Relation? {
        relations.first { relation in
            guard relation.kind == kind else { return false }
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

    func removeRelation(id: String) {
        relations.removeAll { $0.id == id }
        dirtyRelations.remove(id)
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
        memories.filter { $0.audioFilename != nil && $0.audioR2Key == nil }
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
        guesses = []
        dirtySubjects = []
        dirtyMemories = []
        dirtyQuestions = []
        dirtyRelations = []
        dirtyGuesses = []
        syncSeq = 0
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Fixture

    #if DEBUG
    /// A canned family, for the two things that have no hands: the UI tests and
    /// the demo video.
    ///
    /// A guessing round needs a second family member, four people and a memory
    /// that names exactly one of them. Producing that by tapping takes minutes
    /// and comes out slightly different every time, which is no basis for an
    /// accessibility test — the test has to fail because a label is missing, not
    /// because today's archive came out different.
    ///
    /// Only with `-seed guess`, and it **replaces** what is on the device, which
    /// is why it is behind an explicit argument and never runs by accident. It
    /// lives here rather than in a file of its own because it writes the same
    /// `private(set)` fields as every other mutation.
    ///
    /// The content is Finnish because it is shown in the app's own UI — the same
    /// rule as the sample transcripts in `scripts/`. See CLAUDE.md.
    func seedDemoArchiveIfRequested() {
        // `-seed empty` is the other half: the empty states are a screen each,
        // and on a device that has ever been used they are unreachable.
        if UserDefaults.standard.string(forKey: "seed") == "empty" {
            subjects = []
            memories = []
            questions = []
            relations = []
            guesses = []
            dirtySubjects = []
            dirtyMemories = []
            dirtyQuestions = []
            dirtyRelations = []
            dirtyGuesses = []
            save()
            return
        }
        guard UserDefaults.standard.string(forKey: "seed") == "guess" else { return }

        let aino = Subject(id: "demo-aino", kind: .person, title: "Aino", confirmed: false)
        let eeva = Subject(id: "demo-eeva", kind: .person, title: "Eeva")
        let kalle = Subject(id: "demo-kalle", kind: .person, title: "Kalle")
        let sanni = Subject(id: "demo-sanni", kind: .person, title: "Sanni")
        let photo = Subject(id: "demo-photo", kind: .photo, title: "")

        subjects = [aino, eeva, kalle, sanni, photo]
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
        questions = []
        relations = []
        guesses = []
        // Nothing is queued for the server: this archive is a fixture, and
        // pushing it into a real family would be a genuine mess.
        dirtySubjects = []
        dirtyMemories = []
        dirtyQuestions = []
        dirtyRelations = []
        dirtyGuesses = []
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
        var guesses: [Guess] = []
        var dirtyGuesses: Set<String> = []
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
        guesses = snapshot.guesses
        dirtyGuesses = snapshot.dirtyGuesses
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
            dirtyRelations: dirtyRelations,
            guesses: guesses,
            dirtyGuesses: dirtyGuesses
        )
    }

    /// The whole archive as JSON, for the export.
    ///
    /// Dates travel as ISO 8601 rather than in the on-disk form: this copy is
    /// read by whatever the family has in twenty years, not by this app. If the
    /// readable HTML ever lags behind the model, this is the file that lost
    /// nothing. See docs/ARCHITECTURE.md §14.
    func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot())
    }
}
