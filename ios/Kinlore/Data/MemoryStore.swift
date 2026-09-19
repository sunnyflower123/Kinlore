import Foundation
import UIKit

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

    /// The name this device puts beside a telling of its own: *"Minä"* until
    /// a pull answers with the member's `display_name`, and for good on a
    /// phone that never joins a family.
    ///
    /// The line here used to say the name comes from the member record, and it
    /// does — but by another road than assignment. Nothing writes to this
    /// property anywhere in the app; the server derives `author_name` from
    /// `member.display_name` on every pull (`sync.ts`), so a family's own name
    /// arrives with the row rather than being set here.
    ///
    /// `String(localized:)` and not a bare literal, because this one is
    /// INTERPOLATED rather than shown. `byline(for:)` hands it to
    /// `Text("\(teller) kertoi")`, and a `String` interpolated into a
    /// `LocalizedStringKey` is substituted word for word — the key is the
    /// sentence around it, never the value dropped into it. So the entry
    /// `"Minä" = "Me"` sat in `en.lproj` with nothing able to reach it, and an
    /// English phone read *"Minä told this"* under every memory told on a
    /// phone with no family — which is the blind spot
    /// `localisation-check.mjs` names in its own header, in its own words:
    /// it cannot see a string composed at runtime, only a literal.
    var authorName = String(localized: "Minä")

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

    /// What this version writes into `Snapshot.schemaVersion`. Bumped only
    /// when a file this version writes could not be read by the previous one;
    /// a field added as Optional needs no bump.
    static let schemaVersion = 1

    /// Where an archive this version could not read was moved, if that has
    /// happened on this launch. The file is kept exactly as it was: a store
    /// that could not be decoded used to come up empty, and the next save
    /// wrote empty over the family's only local copy (CLAUDE.md rule 10).
    private(set) var unreadableArchive: URL?

    /// False only when an unreadable file could not even be moved aside. Then
    /// nothing is written at all: an empty archive on screen is recoverable,
    /// an overwritten file is not.
    private var mayWrite = true

    init(filename: String = "kinlore-store.json") {
        let documents = URL.documentsDirectory
        fileURL = documents.appendingPathComponent(filename)
        #if DEBUG
        // `-store outdated` writes a file in the shape of one saved before the
        // newer fields existed; `-store unreadable` writes one that is not
        // JSON at all. They are how SilentFailureTests drives rule 10.
        Self.writeFixture(UserDefaults.standard.string(forKey: "store"), to: fileURL)
        #endif
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

    /// The tellings that *named* a subject rather than being about it.
    ///
    /// The other half of the same web `memories(for:)` reads. A person the
    /// extraction proposed usually has no memory of their own — their name was
    /// heard inside somebody else's story — so this is the only way back from
    /// that person to what was being talked about when the name was said.
    /// `BlindConfirmation` is what needed it, and it is a join rather than a
    /// column for the same reason the deck needed no schema.
    func memories(mentioning subjectID: String) -> [Memory] {
        told
            .filter { $0.mentionedSubjectIDs.contains(subjectID) }
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
    /// **And who and where the memories name**, since 6 Sep 2026. The words
    /// are what was heard; the mentions are what the family made of them —
    /// a name corrected on its card, two cards merged into one — and until
    /// then the search read only the first: a photograph whose telling was
    /// about grandmother, corrected from "Aino" to "Kaarina" the day after,
    /// was still found by the wrong name and never by the right one
    /// (founder's-eye review, finding #5). `subject(id:)` follows a merge to
    /// its survivor and answers nothing for a rejected proposal, so a name
    /// the family refused finds nothing either.
    ///
    /// An empty query is not a filter: everything comes back, so the screen does
    /// not have to know whether a search is running.
    func subjects(of kind: SubjectKind, matching query: String) -> [Subject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = subjects(of: kind)
        guard !needle.isEmpty else { return all }
        return all.filter { subject in
            subject.displayTitle.localizedCaseInsensitiveContains(needle)
                || memories(for: subject.id).contains { memory in
                    memory.body.localizedCaseInsensitiveContains(needle)
                        || memory.mentionedSubjectIDs.contains { id in
                            self.subject(id: id)?.title.localizedCaseInsensitiveContains(needle) ?? false
                        }
                }
        }
    }

    /// A telling the search found, with the card it lives on.
    struct MemoryMatch: Identifiable {
        let memory: Memory
        let subject: Subject
        var id: String { memory.id }
    }

    /// The memories themselves that match what somebody typed, newest first.
    ///
    /// `subjects(of:matching:)` answers "which photographs, moments and places
    /// have something about the cottage" and the album shows the card. Since
    /// 19 Sep 2026 it also shows the telling: a tile found by a word inside
    /// its story looked exactly like a tile found by its title, and the
    /// sentence that matched was on the card two taps away. And every card
    /// counts here, a person's included — a memory told about grandmother
    /// lives on her card on the Ihmiset tab, and until now the album's search
    /// could not reach it at all.
    ///
    /// Matched the three ways the cards are — the words, the names the family
    /// made of them, the title of the card it is under — and by who told it,
    /// so a teller's name finds her tellings. A telling not yet transcribed
    /// has no words to match. The card is resolved through `subject(id:)`
    /// like everywhere else: a merged one answers with its survivor, a
    /// rejected one is not listed.
    func memories(matching query: String) -> [MemoryMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        func hit(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(needle) }
        return told
            .filter { !$0.body.isEmpty }
            .compactMap { memory -> MemoryMatch? in
                guard let subject = subject(id: memory.subjectID) else { return nil }
                let matches = hit(memory.body)
                    || hit(subject.displayTitle)
                    || (byline(for: memory).map(hit) ?? false)
                    || memory.mentionedSubjectIDs.contains { id in
                        self.subject(id: id).map { hit($0.title) } ?? false
                    }
                return matches ? MemoryMatch(memory: memory, subject: subject) : nil
            }
            .sorted { $0.memory.createdAt > $1.memory.createdAt }
    }

    /// The questions worth putting in front of the teller right now.
    ///
    /// Chosen by the ladder rather than by age: the oldest three are as likely
    /// as not to be the three hardest, and a person who cannot answer the first
    /// question they are shown does not press the button again. Passing a
    /// subject narrows it to that photo's or that person's own questions.
    /// See docs/ARCHITECTURE.md §12.
    ///
    /// `onlyAuthored`: questions a person asked, and none the extraction
    /// made. The deck's and the blind cards' guards ask this (ARCHITECTURE
    /// §23): a family member's question outranks a card, the telling's own
    /// follow-ups do not. Counted, they took the pack off the screen after
    /// its first telling, until the follow-ups were answered — and a deck
    /// meant to go from photograph to photograph stopped at one. Decided
    /// 12 Sep 2026.
    func openQuestions(
        limit: Int = 3,
        for subjectID: String? = nil,
        excludingAuthor: String? = nil,
        onlyAuthored: Bool = false
    ) -> [FollowUpQuestion] {
        let open = questions.filter { question in
            guard !question.answered else { return false }
            if onlyAuthored, question.authorID == nil { return false }
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
        let matches = subjects.filter {
            $0.kind == kind && $0.deletedAt == nil && $0.mergedInto == nil
                && $0.title.compare(name, options: .caseInsensitive) == .orderedSame
        }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            // Two Mattis. A name is not an identity — the father and the
            // cousin's son share one by the habit of naming after grandparents
            // — and since 4 Sep 2026 a family may hold two live cards with
            // one title, told apart on the result screen ("Eri henkilö"). A
            // new mention goes to the one the family talked about last: a
            // guess, but a visible one, because the result screen shows every
            // familiar name it resolved and lets it be switched (finding #14).
            let ids = Set(matches.map(\.id))
            if let last = told.sorted(by: { $0.createdAt > $1.createdAt }).first(where: {
                ids.contains($0.subjectID) || $0.mentionedSubjectIDs.contains(where: ids.contains)
            }) {
                if let home = matches.first(where: { $0.id == last.subjectID }) { return home }
                if let named = matches.first(where: { last.mentionedSubjectIDs.contains($0.id) }) { return named }
            }
            return matches[0]
        }
        let subject = Subject(kind: kind, title: name, confirmed: confirmed)
        subjects.append(subject)
        dirtySubjects.insert(subject.id)
        save()
        return subject
    }

    /// A person somebody typed, rather than one the extraction heard.
    ///
    /// Confirmed, because a person wrote the name: rule 4 is about who vouches,
    /// and typing a name is vouching for it. A card that already exists under
    /// the name is the one returned, and a proposal waiting under it is
    /// confirmed rather than doubled — typing "Aino" while the extraction's
    /// Aino waits behind the heard-names row is the same act as confirming her.
    ///
    /// Until 13 Sep 2026 a person could only come out of a telling, which left
    /// whoever set the archive up with nobody to put in it, and a family tree
    /// with nobody to draw.
    @discardableResult
    func addPerson(named name: String) -> Subject? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let person = findOrCreateSubject(named: trimmed, kind: .person, confirmed: true)
        if !person.confirmed { confirm(subjectID: person.id) }
        return subject(id: person.id) ?? person
    }

    /// "Not that Matti": a fresh, unconfirmed card with the same name, and the
    /// given memories now mention it instead of the familiar one. The
    /// familiar card keeps everything else it has; nothing is merged or
    /// tombstoned, so this is the one correction here that cannot lose a
    /// story. The new card comes back as a proposal, where its name can be
    /// told apart — "Matti Virtanen" — and confirmed like any other.
    func split(mention subjectID: String, in memoryIDs: [String]) -> Subject? {
        guard let original = subject(id: subjectID) else { return nil }
        let other = Subject(kind: original.kind, title: original.title, confirmed: false)
        subjects.append(other)
        dirtySubjects.insert(other.id)
        for i in memories.indices where memoryIDs.contains(memories[i].id) {
            var touched = false
            if memories[i].mentionedSubjectIDs.contains(subjectID) {
                memories[i].mentionedSubjectIDs = memories[i].mentionedSubjectIDs.map {
                    $0 == subjectID ? other.id : $0
                }
                touched = true
            }
            // A telling about a familiar person is filed under them, not only
            // as a mention — "Lisäsin sen kohteeseen Toivo" — so the home
            // moves with the name, or the story would stay on the wrong card.
            if memories[i].subjectID == subjectID {
                memories[i].subjectID = other.id
                touched = true
            }
            if touched { dirtyMemories.insert(memories[i].id) }
        }
        save()
        return other
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

    /// Fills in a subject's date from what was told about it.
    ///
    /// **Only an empty field is filled.** A date brought by an earlier memory
    /// is not overwritten — a later dictation must not silently change what
    /// the family has already agreed on. It took a title too until 12 Sep
    /// 2026; a telling names nothing now (`TellViewModel.placeSubject`).
    func describe(subjectID: String, dateHint: DateHint?) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        if let dateHint, subjects[index].dateHint == nil {
            subjects[index].dateHint = dateHint
        }
        dirtySubjects.insert(subjectID)
        save()
    }

    /// A name somebody typed in, for a photograph or a moment.
    ///
    /// Overwrites, like `setDateHint` below and for the same reason: `describe`
    /// speaks for the extraction and fills only an empty field, and this is
    /// the person. Until 6 Sep 2026 a photograph's name was whatever its first
    /// telling left — a place and a year, or nothing — and no screen could
    /// change it (founder's-eye review, finding #12). People and places keep
    /// `rename`, which knows about merging two cards; a photograph has nothing
    /// to merge with.
    func setTitle(subjectID: String, title: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].title = title
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

    /// A photograph's colours, the moment somebody said yes to them.
    ///
    /// Only `ColourSheet`'s "Kyllä" calls this, and only with a file the lock
    /// made from the photograph's own brightness. The original is not touched:
    /// `imageFilename` stays the picture as it was taken, and this is a second
    /// file beside it. A later yes replaces an earlier one — the newest word
    /// from the family wins — and the file it replaces is deleted, because
    /// nothing else points at it.
    func setColour(subjectID: String, filename: String, confirmedByID: String, confirmedByName: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        let replaced = subjects[index].colourImageFilename
        subjects[index].colourImageFilename = filename
        // A new yes is a new file, and it travels once it has a key of its own.
        subjects[index].colourR2Key = nil
        subjects[index].colourConfirmedByID = confirmedByID
        subjects[index].colourConfirmedByName = confirmedByName
        subjects[index].colourConfirmedAt = .now
        dirtySubjects.insert(subjectID)
        save()
        if let replaced, replaced != filename { MediaStore.delete(filename: replaced) }
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
            //
            // Both kinds of reference are counted as they are moved, the way
            // `split` counts them. The outbox used to be filled from
            // `subjectID == existing.id` instead, which is a different set:
            // it caught every telling filed under the survivor, including
            // ones this merge never touched, and it missed the telling that
            // is filed somewhere else and only *mentions* the old card. That
            // one was remapped on this phone and queued nowhere — and
            // because it was not queued, the next pull's `applyRemote`
            // overwrote it with the server's row and the mention went back
            // to the tombstone. A correction that undoes itself one sync
            // later, with nothing on any screen to say so (10 Sep 2026).
            var touched: Set<String> = []
            for i in memories.indices {
                if memories[i].subjectID == subjectID {
                    memories[i].subjectID = existing.id
                    touched.insert(memories[i].id)
                }
                if memories[i].mentionedSubjectIDs.contains(subjectID) {
                    memories[i].mentionedSubjectIDs = memories[i].mentionedSubjectIDs.map {
                        $0 == subjectID ? existing.id : $0
                    }
                    touched.insert(memories[i].id)
                }
            }
            // ...but the row is NOT deleted. Another device that is offline may
            // be adding memories to this subject right now, and deleting it
            // would leave them pointing at nothing. A tombstone with a
            // forwarding address solves that and makes the merge reversible.
            // See docs/ARCHITECTURE.md §2.5.
            subjects[index].mergedInto = existing.id
            dirtyMemories.formUnion(touched)
            // The relationships move too. They did not, until 4 Sep 2026:
            // `relatives(of:)` reads this side of every edge by raw id, so a
            // confirmed spouse of the tombstoned card simply vanished from
            // the survivor's tree the moment a name was tidied — the one flow
            // that exists to keep the tree right, erasing what the family had
            // confirmed (founder's-eye review, 3 Sep 2026, finding #15).
            // A tombstone and a fresh edge rather than a remap in place: the
            // server never updates an edge's ends on conflict, only its
            // confirmation and its tombstone, so a remapped row would stay
            // pointing at the old card on every other phone. `addRelation`
            // refuses a self-loop and folds a duplicate into the edge the
            // survivor already has.
            for i in relations.indices where relations[i].deletedAt == nil
                && (relations[i].fromSubjectID == subjectID || relations[i].toSubjectID == subjectID) {
                let old = relations[i]
                relations[i].deletedAt = .now
                dirtyRelations.insert(old.id)
                addRelation(
                    from: old.fromSubjectID == subjectID ? existing.id : old.fromSubjectID,
                    to: old.toSubjectID == subjectID ? existing.id : old.toSubjectID,
                    kind: old.kind,
                    confirmed: old.confirmed
                )
            }
            // A confirmed card corrected onto a proposal confirms the
            // proposal: a person has just said that this somebody, whom the
            // family already vouched for, is Aino. Until 12 Sep 2026 the
            // survivor kept the proposal's flag, which left the family's
            // confirmed spouse waiting behind the people list's door as a
            // name nobody had checked.
            if subjects[index].confirmed, !existing.confirmed {
                confirm(subjectID: existing.id)
            }
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
    ///
    /// **Confirmed places only, since 12 Sep 2026.** A place the extraction
    /// heard and nobody has vouched for is a guess, and a coordinate under a
    /// guess is the guess drawn on a map. The lookup waits for the
    /// confirmation; the next sweep after it — launch, foreground, a sync —
    /// picks the place up.
    func placesAwaitingCoordinates() -> [Subject] {
        subjects.filter {
            $0.kind == .place && $0.confirmed && $0.mergedInto == nil
                && $0.deletedAt == nil && $0.place == nil && !$0.title.isEmpty
        }
    }

    /// Records a location: the one `PlaceLookup` found, or the one somebody in
    /// the family moved the mark to (`PlacePinSheet`).
    ///
    /// Queued for the server, unlike a downloaded photo's filename: the answer
    /// to "where is Puumala" is the same on every phone in the family, so it is
    /// worth looking up once rather than once per device — and a hand-placed
    /// point is worth even more, because nothing on another phone can produce
    /// it again.
    ///
    /// The two callers are one method because the archive stores one point per
    /// place and has no field for who put it there (§18). What keeps a
    /// gazetteer's answer from landing on top of a family's is a rule on the
    /// server rather than a flag here: a stored `exact` is not displaced by a
    /// coarser push under the same title. Locally nothing can overwrite it at
    /// all — `placesAwaitingCoordinates` only ever offers a place with no
    /// point.
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

    /// The same taking back, from the memory's own card the day after.
    ///
    /// `discardSavedMemory` on the result screen knows what its telling
    /// proposed and which question it answered; a card knows only the row. So
    /// the tidying here is what the row itself can vouch for: the people this
    /// memory alone put in the family list, and the moment it alone was filed
    /// under. Anyone confirmed, or named by another telling, stays — and so
    /// does a photo or a person, whatever they hold.
    ///
    /// Returns whether the home subject went with it: the card the caller is
    /// standing on has then nothing left to show.
    @discardableResult
    func takeBack(memoryID: String) -> Bool {
        guard let memory = memories.first(where: { $0.id == memoryID }) else { return false }
        remove(memoryID: memoryID)
        for id in memory.mentionedSubjectIDs {
            if let subject = subjects.first(where: { $0.id == id }),
               !subject.confirmed, subject.deletedAt == nil, isOrphaned(subjectID: id) {
                remove(subjectID: id)
            }
        }
        if let home = subjects.first(where: { $0.id == memory.subjectID }),
           home.kind == .event, home.deletedAt == nil, isOrphaned(subjectID: home.id) {
            remove(subjectID: home.id)
            return true
        }
        return false
    }

    /// Moves a telling to another card.
    ///
    /// The AI's placement is the most important piece of the result — the
    /// organising the teller would never do herself — and until 5 Sep 2026 it
    /// was the one thing on that screen nobody could correct: grandfather's
    /// war years filed under "Kesä Puumalassa" stayed there for good
    /// (founder's-eye review, finding #27). The server takes the new card from
    /// the author alone, as it takes the words.
    ///
    /// The mentions stay: who was named in the telling does not change with
    /// where it is filed. A moment the AI made for this telling alone goes
    /// with it, exactly as it goes when the telling is taken back — an
    /// untitled or auto-named event with nothing left under it is not a card.
    ///
    /// Returns whether the old home went: the card the caller is standing on
    /// has then nothing left to show.
    @discardableResult
    func move(memoryID: String, to subjectID: String) -> Bool {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }),
              memories[index].subjectID != subjectID,
              subjects.contains(where: { $0.id == subjectID && $0.deletedAt == nil && $0.mergedInto == nil })
        else { return false }
        let from = memories[index].subjectID
        memories[index].subjectID = subjectID
        dirtyMemories.insert(memoryID)
        save()
        if let home = subjects.first(where: { $0.id == from }),
           home.kind == .event, home.deletedAt == nil, isOrphaned(subjectID: home.id) {
            remove(subjectID: home.id)
            return true
        }
        return false
    }

    // MARK: - Who told it

    /// Files the given tellings under a teller, or under nobody.
    ///
    /// All of them at once, because the interview loop saves one memory per
    /// round and the person answering did not change between rounds — the
    /// result screen asks once at the end and the answer covers what was said
    /// into it. The same reason `split(mention:in:)` takes a list.
    ///
    /// `subjectID` nil with `hidden` false is the state nothing sets: it is
    /// what a telling nobody was asked about already is.
    func setTeller(_ subjectID: String?, hidden: Bool, for memoryIDs: [String]) {
        var touched = false
        for index in memories.indices where memoryIDs.contains(memories[index].id) {
            memories[index].tellerSubjectID = subjectID
            memories[index].tellerHidden = hidden ? true : nil
            dirtyMemories.insert(memories[index].id)
            touched = true
        }
        guard touched else { return }
        save()
    }

    /// The name shown beside a telling, in one place because three surfaces
    /// ask it: a memory's row on its card, the gallery's *"Uutta perheeltä"*
    /// row, and the export that outlives the app.
    ///
    /// Three answers, and the middle one is the point of the field:
    ///
    ///   - a chosen teller's card title, which follows the card if the name is
    ///     ever corrected — that is why the id is stored and the name is not;
    ///   - `nil` when the teller asked not to be named, and the caller shows
    ///     the day instead of a name;
    ///   - the author otherwise, which is every telling made before there was
    ///     anything to ask and every one that arrives from another client.
    ///
    /// A teller whose card has since been removed or merged away falls back to
    /// the author rather than to nothing: a missing card is not a request for
    /// privacy, and `subject(id:)` already follows a merge.
    func byline(for memory: Memory) -> String? {
        if let id = memory.tellerSubjectID, let teller = subject(id: id), !teller.title.isEmpty {
            return teller.displayTitle
        }
        if memory.tellerHidden == true { return nil }
        return memory.authorName
    }

    /// The people this archive has most recently been told by, newest first.
    ///
    /// The card offers these above the full list, so that the second and third
    /// person round a table are one tap away after their first telling. Built
    /// from what was chosen rather than from the person list, because a family
    /// of fifty-three has fifty-three people in it and two of them are in the
    /// room.
    func recentTellers(limit: Int = 2) -> [Subject] {
        var seen = Set<String>()
        var out: [Subject] = []
        for memory in told.sorted(by: { $0.createdAt > $1.createdAt }) {
            guard let id = memory.tellerSubjectID, !seen.contains(id),
                  let person = subject(id: id), person.confirmed, !person.title.isEmpty
            else { continue }
            seen.insert(id)
            out.append(person)
            if out.count == limit { break }
        }
        return out
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

    /// One request's worth of the outbox, and never more.
    ///
    /// The number is `MAX_ROWS` in `backend/src/sync.ts`, which slices every
    /// table to it and writes no more than that. Offering more used to mean
    /// `clearPending` acknowledged rows the server had never stored: the
    /// payload was uncapped, 600 memories went up, 500 were written, and all
    /// 600 came out of the outbox. The remaining 100 existed on one phone,
    /// were never offered again, and the engine's state read `.idle` —
    /// the silent shape this project keeps finding. Found and fixed
    /// 10 Sep 2026.
    ///
    /// The rest is not lost, it is next: `SyncEngine` pushes until this comes
    /// back empty, the way the pull loop already drains a capped reply.
    ///
    /// **Nothing checks this, and the reason is worth writing down rather
    /// than leaving as a gap somebody rediscovers.** The Swift checks in
    /// `scripts/` compile one service file against a harness; this file
    /// imports UIKit, so it cannot be built for macOS that way, and XCUITest
    /// drives the app rather than calling this. `memory-rules-check.mjs`
    /// pins the server's half — that a push of more than `MAX_ROWS` really
    /// does store only `MAX_ROWS` — so what is unchecked is narrowly this
    /// number agreeing with that one. Change either and change both.
    static let maxRowsPerPush = 500

    /// The rows to push. An empty payload means there is nothing to send.
    ///
    /// A memory the server would refuse is deliberately left out rather than
    /// sent and dropped: see `Memory.isPushable`. It stays in the outbox and
    /// goes on the next round, once its audio has a key.
    func pendingPayload() -> SyncPayload {
        let cap = Self.maxRowsPerPush
        let pendingSubjects = subjects.filter { dirtySubjects.contains($0.id) }

        // While the subjects alone do not fit, the request carries subjects
        // and nothing else.
        //
        // A memory, a question and a relation all point at a subject by id,
        // and `schema.sql` makes every one of those a foreign key. SQLite's
        // `ON CONFLICT` clause does not cover a foreign key — `INSERT OR
        // IGNORE` will not swallow one — so a single row pointing at a
        // subject the server has not got aborts `env.DB.batch` and takes the
        // whole push with it. The client then gets a 502, clears nothing,
        // and builds the identical request next round: a sync wedged for
        // good while the screen says only "waiting for the network".
        //
        // Splitting a push at the cap is exactly what could produce that
        // pointer — a memory in this request naming a subject that fell into
        // the next one. Draining the subjects first means the subject is
        // either already on the server or in this very request, which is the
        // condition the foreign key is asking about. It costs one extra
        // round on the one archive big enough to need it.
        guard pendingSubjects.count <= cap else {
            return SyncPayload(subjects: pendingSubjects.prefix(cap).map(\.dto))
        }

        return SyncPayload(
            subjects: pendingSubjects.map(\.dto),
            memories: memories.filter { dirtyMemories.contains($0.id) && $0.isPushable }
                .prefix(cap).map(\.dto),
            questions: questions.filter { dirtyQuestions.contains($0.id) }.prefix(cap).map(\.dto),
            relations: relations.filter { dirtyRelations.contains($0.id) }.prefix(cap).map(\.dto)
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

    /// Puts every row on this device into the outbox.
    ///
    /// One caller: a single-device archive being opened to a family
    /// (`EnableSharingScreen`). Rows told before there was anywhere to
    /// send them were never queued — nothing queues for a server that does not
    /// exist — so without this the archive would sit on the phone while the app
    /// said it was shared, which is the silent failure this project keeps
    /// finding. Media needs no marking: the upload queue is `r2Key == nil`, not
    /// the outbox.
    func markAllPending() {
        dirtySubjects.formUnion(subjects.map(\.id))
        dirtyMemories.formUnion(memories.map(\.id))
        dirtyQuestions.formUnion(questions.map(\.id))
        dirtyRelations.formUnion(relations.map(\.id))
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
                // The colours follow the same idea with one rule more, which
                // `withColours` keeps: see there.
                let merged = incoming.withColours(from: subjects[index])
                if let stale = merged.stale { MediaStore.delete(filename: stale) }
                subjects[index] = merged.row
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
                // A row that says nothing about the teller takes nothing away,
                // which is the colours' rule (`withColours`) for the same
                // reason: a Worker that has not been redeployed sends neither
                // field, and the first pull after an update would otherwise
                // wipe every answer the family had given. Nothing sets a teller
                // back to nobody, so there is no case this loses.
                if incoming.tellerSubjectID == nil, incoming.tellerHidden != true {
                    incoming.tellerSubjectID = memories[index].tellerSubjectID
                    incoming.tellerHidden = memories[index].tellerHidden
                }
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

    /// The pull cursor, moved from a pull reply and from nothing else.
    ///
    /// **`private` is the rule, not the comment above `client.push`.** Three
    /// defects lived in this number (23 Aug 2026, ARCHITECTURE §3) and every
    /// one showed a working app while a telling silently never reached
    /// another phone. The first of them was a cursor advanced from a *push*
    /// reply, whose number is the family-global counter — taking it steps
    /// past everything the others committed since this device last pulled,
    /// and their tellings are then never fetched, on that round or any later
    /// one, with nothing on any screen to say so.
    ///
    /// `sync-cursor-check.mjs` drives the server's half of that rule. This is
    /// the client's half, and until 12 Sep 2026 it was held by a comment in
    /// `SyncEngine` that whoever adds the next call site has to happen to
    /// read. It has exactly one caller, three lines above; `private` is free
    /// and makes the defect that actually happened unrepresentable.
    private func advance(seq: Int) {
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
    /// `saving: false` is for the full copy, which records files by the
    /// hundred and writes the archive once per ten of them (`FullCopy`); a
    /// view fetching one file on demand keeps the default.
    func setLocalImage(subjectID: String, filename: String, saving: Bool = true) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].imageFilename = filename
        if saving { save() }
    }

    /// Photographs whose confirmed colours are still only on this phone.
    func coloursAwaitingUpload() -> [Subject] {
        subjects.filter { $0.deletedAt == nil && $0.colourImageFilename != nil && $0.colourR2Key == nil }
    }

    func setColourR2Key(subjectID: String, key: String) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].colourR2Key = key
        dirtySubjects.insert(subjectID)
        save()
    }

    /// The local copy of colours confirmed on another phone. Not marked dirty,
    /// like `setLocalImage`: the filename is this device's own business.
    func setLocalColour(subjectID: String, filename: String, saving: Bool = true) {
        guard let index = subjects.firstIndex(where: { $0.id == subjectID }) else { return }
        subjects[index].colourImageFilename = filename
        if saving { save() }
    }

    func setLocalAudio(memoryID: String, filename: String, saving: Bool = true) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].audioFilename = filename
        if saving { save() }
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
        // Every media file on the disk, not every one the rows name. Those
        // are different sets: `FullCopy` saves the bytes and records the
        // filename in memory, flushing once per ten files, so a phone killed
        // mid-round holds up to nine of the family's photographs and voices
        // that no row points at. Walking `imageFilename` and `audioFilename`
        // could not reach them, and they survived a dialog saying the
        // memories were gone (11 Sep 2026). See `MediaStore.deleteAll`.
        MediaStore.deleteAll()
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
    /// A plain generated photograph for `-seed deck`, written through the same
    /// `MediaStore` call a real one goes through — so what the card draws is a
    /// file on disk and not a special case.
    private static func demoPhotoFile() -> String? {
        let size = CGSize(width: 900, height: 600)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.36, green: 0.31, blue: 0.26, alpha: 1).setFill()
            context.fill(CGRect(x: 330, y: 140, width: 240, height: 330))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        return MediaStore.save(imageData: data)
    }

    /// The film's own photographs for the `film` seeds, if the shooting day put
    /// them in the app's Documents folder — `film-photo.jpg` for the first and
    /// `film-photo-2.jpg` onwards for the rest (the video project's SHOOT-v16.md
    /// says how); the plain generated one otherwise, so a seed never fails to
    /// build a card for want of a picture. Saved through `MediaStore` like any
    /// photograph, so nothing downstream is a special case.
    ///
    /// More than one since 19 Sep 2026, for the two takes that need a picture
    /// the grandmother never spoke about: the album a week later, which is six
    /// prints from the table rather than one, and the blind card, whose
    /// question has to be about a photograph the film has shown and nobody has
    /// named. A shooting day that copies one file still gets six cards; five of
    /// them are then the generated placeholder, which is visibly wrong on
    /// camera and correct everywhere else.
    private static func filmPhotoFile(_ index: Int = 1) -> String? {
        let name = index == 1 ? "film-photo.jpg" : "film-photo-\(index).jpg"
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? Data(contentsOf: documents.appendingPathComponent(name)),
           let saved = MediaStore.save(imageData: data) {
            return saved
        }
        return demoPhotoFile()
    }

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
        // `-seed clan` is the opposite end of the same idea: a family too big
        // for the screen, with every hard connection in it, for the one screen
        // whose defects only appear at size. The table is `ClanFixture`.
        if seed == "clan" {
            let fixture = ClanFixture.archive()
            subjects = fixture.subjects
            memories = []
            questions = []
            relations = fixture.relations
            dirtySubjects = []
            dirtyMemories = []
            dirtyQuestions = []
            dirtyRelations = []
            save()
            return
        }
        guard [
            "archive", "unseen", "deck", "blind", "related", "dated",
            "film", "film-untold", "film-week", "film-family", "film-tree",
        ].contains(seed) else { return }
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
        // `-seed blind` is the archive with a face on its one photograph.
        //
        // The picture is the whole difference, and it is also the guard:
        // `BlindConfirmation` will not build a card without one, because "who
        // is this?" over a grey placeholder asks nothing. That is why the plain
        // archive is untouched by this feature — `demo-photo` has no file
        // there, so no card appears on the idle screen every other test
        // launches into.
        let photo = Subject(
            id: "demo-photo",
            kind: .photo,
            title: "",
            imageFilename: seed == "blind" ? Self.demoPhotoFile() : seed?.hasPrefix("film") == true ? Self.filmPhotoFile() : nil
        )
        // A place with nothing said about it yet, which is the ordinary state of
        // a place: it is named inside somebody's memory and gets a card of its
        // own. It is here so the accessibility sweep actually covers the Paikat
        // section and its invitation — an empty subject is the row with the
        // colour on it, and colour is the thing eyes cannot check.
        //
        // It carries a coordinate, and the coordinate is a prop like the rest
        // of the fixture: `PlaceResolver` refuses to look anything up under a
        // seed on purpose (a UI run launches the app dozens of times and a
        // gazetteer request has no business inside a contrast measurement), so
        // without one the place card's map is unreachable from every seeded
        // launch — which is to say from the accessibility sweep and from every
        // recorded take. `.town` and not `.exact`: Puumala is a municipality,
        // and what the card draws for it is a circle rather than a pin.
        let puumala = Subject(
            id: "demo-puumala",
            kind: .place,
            title: "Puumala",
            place: PlaceHint(latitude: 61.5236, longitude: 28.1806, precision: .town)
        )
        // **Puumala is confirmed; Karjala below is not, and the pair is the
        // point.** A place carries the proposal badge on its symbol and its
        // row says *"Ehdotus — vahvista paikka"* underneath (ARCHITECTURE §18,
        // `SubjectRow` in GalleryScreen) — and for a day neither rendered in a
        // single test, because this fixture had one place and had vouched for
        // it. Two places, two states, and every sweep now draws both.
        //
        // The name is §18's own worked example rather than a pretty one.
        // `Karjala` is what a grandmother says meaning the region, and the
        // gazetteer answers with a village in Mynämäki — confidently, with a
        // single result, and there is no cheap rule that separates it from a
        // right answer. Measured through the shipping `PlaceLookup` on
        // 11 Sep 2026 and again as `geo-check.swift`'s sixth claim, which is
        // where the coordinate below comes from. `.town`, so the card draws a
        // circle: a wrong answer that reads as a region is the honest shape
        // for one, and rule 5 is doing rule 4's work there by accident.
        //
        // It is on camera. `-seed archive` is also the demo video's archive
        // (docs/VIDEO.md), so phase F films a row that says a name is still
        // a proposal. That is the app telling the truth about what it heard,
        // which is rule 4, and it was a decision rather than an oversight.
        let karjala = Subject(
            id: "demo-karjala",
            kind: .place,
            title: "Karjala",
            place: PlaceHint(latitude: 60.838, longitude: 22.000, precision: .town),
            confirmed: false
        )
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

        // `-seed related` also knows Toivo, confirmed: the canned telling names
        // him, which is how the result screen's "Tutut nimet" row is reached
        // by a test — the plain archive knows nobody the samples mention.
        let toivo = Subject(id: "demo-toivo", kind: .person, title: "Toivo")
        subjects = [aino, eeva, kalle, sanni, photo, puumala, karjala, rejected]
            + (seed == "related" ? [toivo] : [])
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
                // Puumala too, and the body never says the word: the search
                // over mentions is only testable on a name the words do not
                // carry. The place stays a card nobody has told anything on —
                // `memories(for:)` is what the row and the card read.
                mentionedSubjectIDs: [aino.id, puumala.id]
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
        // `-seed film` and `-seed film-untold`: the archive the demo video's
        // takes are shot from (docs/VIDEO.md, the v16 takes). The blind card
        // needs exactly what `-seed blind` gives it — a proposal heard in a
        // telling about a photograph that has a picture — but with the film's
        // people and the film's words, so that the four names on the card are
        // the four the narration says, and the transcript on screen is the one
        // her voice reads. `film-untold` is the same archive a minute earlier:
        // the photograph nobody has spoken about yet, which is what the Kerro
        // tab's card is drawn from, so the telling can be filmed into it.
        //
        // The two names the telling says are the two it heard — Helmi and
        // Toivo — and Helmi is the proposal: the film's blind card is her name
        // given by somebody who knows the photograph without being shown it,
        // which is the strongest confirmation the app collects (rule 4).
        // Until 13 Sep 2026 the proposal was a misheard "Elli" and the take
        // ended on a name left open; the cut built on it had to explain a
        // quiz. Exactly three confirmed people are not named in the telling,
        // because `BlindConfirmation` takes its decoys from them in store
        // order and a fourth would push the film's names off the card; Toivo
        // is named in it, and is therefore never a decoy.
        //
        // English, unlike the rest of this fixture, because the film is shot in
        // English and the words on a filmed screen have to be the words on its
        // soundtrack. The picture comes from `filmPhotoFile()`.
        //
        // `-seed film-tree` is the same archive after the blind card: Helmi
        // confirmed and a card for Grandma herself, and no relation yet — the
        // film's take adds the two on camera, on the tree (a spouse, a child),
        // because that is how a name gets into the tree and the film has to
        // show it. The tree draws confirmed people and confirmed relations
        // only, so `-seed film` draws nothing. Grandma stops the tree: the app
        // has parent, spouse and sibling, and a grandchild drawn straight
        // under her would be drawn as her child.
        if seed?.hasPrefix("film") == true {
            let told = seed != "film-untold"
            let treeShot = seed == "film-tree"
            // Two later hours of the same archive, added 19 Sep 2026 for the
            // takes the video's §4 marks as needing a seed. `film-week` is her
            // phone after a week of telling and `film-family` is mine after the
            // invitation; both are the block below plus what that hour added,
            // because the film is one archive growing rather than five.
            let week = seed == "film-week"
            let family = seed == "film-family"
            // Confirmed by the time the family is here: the blind card asks
            // about somebody else by then (see `film-family` below), and Helmi
            // was answered on the orange proposal row in the week between — the
            // weaker instrument, which is what rule 4 keeps it for.
            // Each card is dated, and until 19 Sep 2026 none of them was.
            // Six `Subject`s made inside one `if` take their `createdAt` from
            // `Date.now` six times over, microseconds apart — and the tree
            // orders people by that date, so whether two of them tied decided
            // which row a person stood in. Measured on this seed: four
            // launches of one build on one simulator, three different orders
            // of the same six people; four more with the tie broken by
            // identifier, two orders. A take that taps Helmi where the
            // recording had her can only be re-shot if the archive comes up
            // the same way twice, so the archive is given the history the
            // story already gives it — the three cousins were in it before
            // the telling, Helmi and Toivo are named in the telling, and
            // Grandma's own card is made last, for the tree.
            let before = Date().addingTimeInterval(-30 * 86_400)
            let justNow = Date().addingTimeInterval(-180)
            let proposal = Subject(
                id: "demo-film-proposal", kind: .person, title: "Helmi",
                confirmed: treeShot || family, createdAt: justNow
            )
            let grandma = Subject(id: "demo-film-grandma", kind: .person, title: "Grandma",
                                  createdAt: justNow.addingTimeInterval(20))
            let elli = Subject(id: "demo-film-elli", kind: .person, title: "Elli",
                               createdAt: before)
            let filmAino = Subject(id: "demo-film-aino", kind: .person, title: "Aino",
                                   createdAt: before.addingTimeInterval(86_400))
            let liisa = Subject(id: "demo-film-liisa", kind: .person, title: "Liisa",
                                createdAt: before.addingTimeInterval(2 * 86_400))
            let filmToivo = Subject(id: "demo-film-toivo", kind: .person, title: "Toivo",
                                    createdAt: justNow.addingTimeInterval(10))
            var filmPhoto = photo
            // The thirties, as a decade: rule 5 on the one photograph the film
            // is about. Only once it has been told about — before that the
            // picture is as undated as it was in the album.
            if told {
                filmPhoto.dateHint = DateHint(
                    start: Calendar.current.date(from: DateComponents(year: 1930, month: 1, day: 1)),
                    end: nil,
                    precision: .decade
                )
            }
            // Before the telling, neither Helmi nor Toivo exists: both are
            // first named in it, and the result screen has to be able to
            // propose them.
            subjects = [elli, filmAino, liisa, filmPhoto, puumala] + (told ? [proposal, filmToivo] : []) + (treeShot ? [grandma] : [])
            let telling = StubTranscriptionService.film
            memories = [
                // The decoys need memories of their own, or they are bare names
                // and the round answers itself.
                Memory(id: "demo-film-memory-elli", subjectID: elli.id, authorID: "demo-mummo",
                       authorName: "Grandma", body: "Elli was her cousin.", source: .typed),
                Memory(id: "demo-film-memory-aino", subjectID: filmAino.id, authorID: "demo-mummo",
                       authorName: "Grandma", body: "Aino lived next door.", source: .typed),
                Memory(id: "demo-film-memory-liisa", subjectID: liisa.id, authorID: "demo-mummo",
                       authorName: "Grandma", body: "Liisa kept the shop.", source: .typed),
            ] + (told ? [
                Memory(
                    id: "demo-film-telling",
                    subjectID: filmPhoto.id,
                    authorID: "demo-mummo",
                    authorName: "Grandma",
                    body: telling,
                    rawTranscript: telling,
                    source: .voice,
                    mentionedSubjectIDs: [proposal.id, filmToivo.id, puumala.id]
                ),
            ] : [])
            // `-seed film-week`: the same archive a week later, and everything
            // it adds is quantity. The video's fifth scene scrolls it past the
            // bottom of the screen while the narration says *"A week later
            // there are thirty. She had more to say than anyone asked."* —
            // so thirty is counted here rather than rounded to: the four above,
            // ten about the five other prints from the table, and sixteen free
            // dictations.
            //
            // The moments carry no title, and that is the app and not the
            // fixture: since 12 Sep 2026 a telling names nothing, so a free
            // dictation is listed under the day it was told with its own first
            // words beneath it (`SubjectRow`). Seven days of her voice, one
            // line each, is the scene — and it is also why the week is dated
            // backwards from now instead of arriving all at once.
            if week {
                // Two more places, because a week of telling names more than
                // one. Confirmed, or the list does not draw them
                // (`GalleryScreen.places`), and each with a coordinate for the
                // reason Puumala carries one: the lookup refuses to run under a
                // seed, so a place without one has no map on its card.
                let savonlinna = Subject(
                    id: "demo-film-savonlinna", kind: .place, title: "Savonlinna",
                    place: PlaceHint(latitude: 61.8694, longitude: 28.8856, precision: .town)
                )
                let sulkava = Subject(
                    id: "demo-film-sulkava", kind: .place, title: "Sulkava",
                    place: PlaceHint(latitude: 61.7864, longitude: 28.3711, precision: .town)
                )
                subjects += [savonlinna, sulkava]

                // The photograph was the first thing she told about, not the
                // last: the four tellings above are pushed back behind the week
                // so the album reads downwards through it.
                let start = Date().addingTimeInterval(-7 * 86_400)
                for index in memories.indices {
                    memories[index].createdAt = start.addingTimeInterval(Double(index) * 600)
                }

                // A week of evenings, oldest first. `photo` is which print of
                // the table it belongs to, 2 … 6, or nil for a free dictation
                // that becomes a moment of its own — which is what the app makes
                // of one (`TellViewModel`). `place` is a place the words name,
                // and the only reason the archive has three places in it.
                let evenings: [(words: String, photo: Int?, place: String?)] = [
                    ("Toivo built that boat in the winter of the war, out of whatever the shed had. He said it leaked for a year and then it stopped.", 2, nil),
                    ("We rowed it out to the island every summer until the motor came.", 2, nil),
                    ("The school had one room and one stove, and the boys sat nearest the stove.", 3, nil),
                    ("Liisa walked six kilometres to it and six back, and never once said it was far.", 3, nil),
                    ("Liisa kept the shop after the war. Everything was behind the counter then; you asked, and she fetched it.", 4, nil),
                    ("Sugar came in a blue paper bag, and my mother saved every one of them.", 4, nil),
                    ("That is the hay meadow behind the cottage. Everyone came, and nobody was paid.", 5, nil),
                    ("Elli is the one laughing. She was always the one laughing.", 5, nil),
                    ("Aino's wedding. They had coffee and one cake, and the fiddler came from Sulkava.", 6, "demo-film-sulkava"),
                    ("I do not know the year of it. Sometime before I was born, I think.", 6, nil),
                    ("The ice went out late that spring, and we could not get to the island until June.", nil, nil),
                    ("Mother made rieska on the stove every Saturday, and the smell got into the curtains.", nil, nil),
                    ("Father walked to Savonlinna to sell the fish. It took him a day each way.", nil, "demo-film-savonlinna"),
                    ("There was one radio in the village and it stood in the schoolhouse.", nil, nil),
                    ("When we were evacuated we took the cow and the sewing machine, and left the rest of it standing.", nil, nil),
                    ("I was given skis one Christmas. They were my brother's, painted over.", nil, nil),
                    ("There was a bear in the potato field the summer I turned nine. Nobody believed me.", nil, nil),
                    ("We sang at the jetty on midsummer night, and the sound went right across the water.", nil, "demo-puumala"),
                    ("My mother's hands were cold even in August.", nil, nil),
                    ("The post came twice a week, and we walked out to meet it.", nil, nil),
                    ("Toivo taught me to swim by rowing out and telling me to follow.", nil, nil),
                    ("The berries were picked into a birch basket, and the basket is still in the loft.", nil, nil),
                    ("We had no shoes at all in the summer. None of us did.", nil, nil),
                    ("When the men came back, nobody spoke about where they had been.", nil, nil),
                    ("Sundays were long. Church in the morning and nothing whatever after it.", nil, nil),
                    ("I still know every stone on the path down to that jetty.", nil, "demo-puumala"),
                ]
                // The decade of each print, and 6 is left undated on purpose:
                // the grid's basket for what nobody has dated is a heading of
                // its own, and a fixture where everything is dated never draws
                // it. She says so out loud in the tenth telling.
                let decades = [2: 1940, 3: 1950, 4: 1950, 5: 1930]
                var prints: [Int: String] = [:]
                var count = 0
                for entry in evenings {
                    count += 1
                    let created = start.addingTimeInterval(Double(count) * 6 * 3600)
                    let subjectID: String
                    if let index = entry.photo {
                        if prints[index] == nil {
                            let id = "demo-film-print-\(index)"
                            subjects.append(Subject(
                                id: id,
                                kind: .photo,
                                title: "",
                                imageFilename: Self.filmPhotoFile(index),
                                dateHint: decades[index].map {
                                    DateHint(
                                        start: Calendar.current.date(
                                            from: DateComponents(year: $0, month: 1, day: 1)
                                        ),
                                        end: nil,
                                        precision: .decade
                                    )
                                },
                                createdAt: created
                            ))
                            prints[index] = id
                        }
                        subjectID = prints[index] ?? ""
                    } else {
                        let id = "demo-film-moment-\(count)"
                        subjects.append(Subject(id: id, kind: .event, title: "", createdAt: created))
                        subjectID = id
                    }
                    memories.append(Memory(
                        id: "demo-film-week-\(count)",
                        subjectID: subjectID,
                        authorID: "demo-mummo",
                        authorName: "Grandma",
                        body: entry.words,
                        rawTranscript: entry.words,
                        source: .voice,
                        createdAt: created,
                        mentionedSubjectIDs: [entry.place].compactMap { $0 }
                    ))
                }
                // Her own phone, and she told every word of it: none of this is
                // news from the family. The baseline is written rather than
                // left alone, because `NewFromFamily` answers "nothing is new"
                // only while the key is ABSENT, and a filming device has opened
                // this tab before — which is not a hypothetical. The first run
                // of this seed put all twenty-six rows in the section and left
                // the album itself below the fold.
                UserDefaults.standard.set(memories.map(\.id), forKey: NewFromFamily.seenKey)
            }
            // `-seed film-family`: the same archive after the invitation, and
            // the one state in this fixture that is not one person's. Two takes
            // come out of it.
            //
            // The album's *"Uutta perheeltä"* section lists three tellings of
            // one photograph with three names under them — `byline(for:)` draws
            // *"<nimi> kertoi"* — and that is the whole of the eighth scene: a
            // photograph is not one person's memory. It needed no new code, only
            // a seed where three members have told about the same picture
            // (docs/VIDEO.md; the video project's SCRIPT-v21.md §2.10, which
            // also says what this is NOT — the gathering round one phone is an
            // open question in PLAN §8 and no screen does it).
            //
            // And the blind card then asks about a SECOND photograph, which is
            // why one exists here. Until 19 Sep 2026 it asked about the one the
            // grandmother had just been heard telling about, so the film had to
            // spend ten seconds explaining why the app was asking something it
            // had been told — §2.9. Uncle Jussi's telling about the other print
            // names Kerttu, nobody has confirmed her, and the photograph on the
            // card is one the film has shown on the table and named nowhere.
            //
            // His telling names Helmi and Toivo as well, and that is load-bearing
            // rather than colour: decoys are confirmed people the same telling
            // did NOT name (`BlindConfirmation`), so naming those two leaves
            // exactly Elli, Aino and Liisa — four names that do not move between
            // rehearsals, which is what a take needs.
            if family {
                let kerttu = Subject(
                    id: "demo-film-kerttu", kind: .person, title: "Kerttu", confirmed: false
                )
                let other = Subject(
                    id: "demo-film-print-2",
                    kind: .photo,
                    title: "",
                    imageFilename: Self.filmPhotoFile(2),
                    dateHint: DateHint(
                        start: Calendar.current.date(from: DateComponents(year: 1940, month: 1, day: 1)),
                        end: nil,
                        precision: .decade
                    )
                )
                subjects += [kerttu, other]

                // Everything the fixture built above happened while she was
                // alone, a week ago; the family has been here for a day.
                let alone = Date().addingTimeInterval(-7 * 86_400)
                for index in memories.indices {
                    memories[index].createdAt = alone.addingTimeInterval(Double(index) * 600)
                }
                memories += [
                    Memory(
                        id: "demo-film-mum",
                        subjectID: filmPhoto.id,
                        authorID: "demo-film-mum",
                        authorName: "Mum",
                        body: "The little one at the end of the jetty is my mother. "
                            + "I have looked at this picture all my life and never thought to ask about it.",
                        source: .voice,
                        createdAt: Date().addingTimeInterval(-26 * 3600),
                        mentionedSubjectIDs: [proposal.id]
                    ),
                    Memory(
                        id: "demo-film-jussi-other",
                        subjectID: other.id,
                        authorID: "demo-film-jussi",
                        authorName: "Uncle Jussi",
                        body: "This is Kerttu, Helmi's sister. Toivo took the picture, which is why he is not in it.",
                        source: .voice,
                        createdAt: Date().addingTimeInterval(-20 * 3600),
                        mentionedSubjectIDs: [kerttu.id, proposal.id, filmToivo.id]
                    ),
                    Memory(
                        id: "demo-film-jussi",
                        subjectID: filmPhoto.id,
                        authorID: "demo-film-jussi",
                        authorName: "Uncle Jussi",
                        body: "Toivo was my father's brother. He is the one with the oar, "
                            + "and he held it exactly like that all his life.",
                        source: .voice,
                        createdAt: Date().addingTimeInterval(-2 * 3600),
                        mentionedSubjectIDs: [filmToivo.id]
                    ),
                ]
                // Seen: everything but those three. The baseline is written
                // here rather than emptied — `-seed unseen` does the opposite
                // with the same key — because the scene is three rows and the
                // archive holds seven tellings. The decoys' one-liners and the
                // telling about the other print are older news, and a section
                // of seven says nothing about one photograph.
                let scene = ["demo-film-telling", "demo-film-mum", "demo-film-jussi"]
                UserDefaults.standard.set(
                    memories.map(\.id).filter { !scene.contains($0) },
                    forKey: NewFromFamily.seenKey
                )
            }
            // Which cards were pushed aside outlives a launch by design (see
            // the deck seed below); the untold photograph has to be offered
            // again on every take.
            if !told {
                UserDefaults.standard.removeObject(forKey: Deck.skippedKey)
            }
        }
        // `-seed deck`: the archive plus one photograph nobody has spoken
        // about, which is what the Kerro tab's card is drawn from. The plain
        // archive deliberately has none — every photograph in it carries a
        // memory, so the deck finds nothing and the tab keeps the blank button
        // that most tests launch into. A card appearing on their idle screen
        // would change what every one of them is looking at.
        // `-seed dated` is the deck's three undated photographs plus the
        // archive's one, dated to the fifties: the grid's decade heading and
        // its basket for the undated, on one screen, for the sweep.
        if seed == "deck" || seed == "dated" {
            // Three, so that the deck's patience — also three — is what ends a
            // run of pushes rather than the archive simply running out. Two
            // different endings that look identical on screen, and only one of
            // them is the promise worth testing.
            for index in 1 ... 3 {
                // The first one carries a file that really exists. No fixture
                // in this project ever has, and it did not matter until the
                // Tell screen started drawing the photograph itself: a card
                // audited without its picture is an audit of the one element
                // the screen was changed for, missing.
                subjects.append(Subject(
                    id: "demo-untold-\(index)",
                    kind: .photo,
                    title: "",
                    // Every one of them, not just the first: which card the
                    // deck offers depends on how `subjects(of:)` happens to
                    // order three rows created in the same instant, and a
                    // fixture that is only sometimes a photograph is a fixture
                    // that only sometimes tests the thing.
                    imageFilename: Self.demoPhotoFile()
                ))
            }
            // A seed puts the device in a known state, and which cards were
            // pushed aside is device state that outlives a launch by design.
            // Without this a second run of the same test starts where the
            // first one left off. Same shape as the seen baseline above.
            UserDefaults.standard.removeObject(forKey: Deck.skippedKey)
        }
        // Same reason as the skips above: which proposals this device has
        // already answered is device state that outlives a launch on purpose,
        // and a second run of the same test would otherwise start with the
        // card already spent.
        UserDefaults.standard.removeObject(forKey: BlindConfirmation.answeredKey)
        if seed == "dated", let index = subjects.firstIndex(where: { $0.id == photo.id }) {
            subjects[index].dateHint = DateHint(
                start: Calendar.current.date(from: DateComponents(year: 1955, month: 1, day: 1)),
                end: nil,
                precision: .decade
            )
            // And a title, the way a telling that named a place leaves one:
            // the one fixture photograph whose tile reads as more than
            // "Valokuva". The plain archive's stays untitled, because every
            // sweep that taps the tile finds it by that word.
            subjects[index].title = "Mökin ranta"
        }
        questions = mummoAsks
        // `-seed related`: the archive with one confirmed relationship, Eeva
        // and Kalle as spouses (and Toivo, above). NameCorrectionTests merges
        // Eeva into Aino and expects Kalle on Aino's card afterwards; adding
        // the edge through the card's own menu proved unreachable for
        // XCUITest, and a fixture is a fact rather than a race.
        relations = seed == "related"
            ? [Relation(fromSubjectID: eeva.id, toSubjectID: kalle.id, kind: .spouseOf, confirmed: true)]
            : []
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

    /// The file on disk.
    ///
    /// Decoded by hand, and this is not tidiness: Swift's synthesized
    /// `Codable` does not use a property's default value for a missing key, so
    /// every field after the first three would throw on a file written before
    /// it existed — and a snapshot that fails to decode used to be an empty
    /// archive (rule 10). Each later field is read `IfPresent`; a file from
    /// any earlier version decodes with the defaults below. Adding a field
    /// here means adding it to `init(from:)` the same way.
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
        /// What wrote the file. Absent in files from before 4 Sep 2026.
        var schemaVersion: Int? = MemoryStore.schemaVersion

        enum CodingKeys: String, CodingKey {
            case subjects, memories, questions, syncSeq
            case dirtySubjects, dirtyMemories, dirtyQuestions
            case relations, dirtyRelations, schemaVersion
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            // Never come up empty over a file that exists. The file is moved
            // aside under a name that says what happened, and the app goes
            // on with an empty store that will be written to a *new* file —
            // the old one stays on disk, byte for byte, for a version that
            // can read it. If even the move fails, nothing is written at all.
            // Nothing about the file is logged: the words in it are somebody's
            // memories (rule 9), and the failure is shown on screen instead.
            let kept = fileURL.deletingLastPathComponent().appendingPathComponent(
                fileURL.deletingPathExtension().lastPathComponent
                    + ".unreadable-\(Int(Date.now.timeIntervalSince1970)).json"
            )
            do {
                try FileManager.default.moveItem(at: fileURL, to: kept)
                unreadableArchive = kept
            } catch {
                mayWrite = false
                unreadableArchive = fileURL
            }
            return
        }
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
        guard mayWrite, let data = try? JSONEncoder().encode(snapshot()) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The alert has been read. The file stays where it was moved.
    func acknowledgeUnreadableArchive() {
        unreadableArchive = nil
    }

    #if DEBUG
    /// The two files rule 10 is tested against. See `init`.
    private static func writeFixture(_ shape: String?, to url: URL) {
        switch shape {
        case "unreadable":
            try? Data("{ this is not an archive".utf8).write(to: url, options: .atomic)
        case "outdated":
            // Encode a snapshot this version writes, then strip every key that
            // was added after the first three: what is left is a file from
            // before those fields existed, produced by the real encoder rather
            // than typed by hand, so it stays an old file as the model moves.
            let snapshot = Snapshot(
                subjects: [Subject(kind: .person, title: "Vanha Aino")],
                memories: [], questions: []
            )
            guard let data = try? JSONEncoder().encode(snapshot),
                  var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            for key in ["syncSeq", "dirtySubjects", "dirtyMemories", "dirtyQuestions",
                        "relations", "dirtyRelations", "schemaVersion"] {
                object.removeValue(forKey: key)
            }
            if let old = try? JSONSerialization.data(withJSONObject: object) {
                try? old.write(to: url, options: .atomic)
            }
        default:
            break
        }
    }
    #endif

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

extension MemoryStore.Snapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjects = try c.decode([Subject].self, forKey: .subjects)
        memories = try c.decode([Memory].self, forKey: .memories)
        questions = try c.decode([FollowUpQuestion].self, forKey: .questions)
        syncSeq = try c.decodeIfPresent(Int.self, forKey: .syncSeq) ?? 0
        dirtySubjects = try c.decodeIfPresent(Set<String>.self, forKey: .dirtySubjects) ?? []
        dirtyMemories = try c.decodeIfPresent(Set<String>.self, forKey: .dirtyMemories) ?? []
        dirtyQuestions = try c.decodeIfPresent(Set<String>.self, forKey: .dirtyQuestions) ?? []
        relations = try c.decodeIfPresent([Relation].self, forKey: .relations) ?? []
        dirtyRelations = try c.decodeIfPresent(Set<String>.self, forKey: .dirtyRelations) ?? []
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
    }
}
