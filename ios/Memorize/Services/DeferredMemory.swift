import Foundation

/// A memory whose audio was saved before its text — and the finishing of it.
///
/// A quota never rejects a recording, and neither does a lost network: the audio
/// is kept and the transcription waits (docs/ARCHITECTURE.md §7). Waiting was all
/// it ever did. Nothing came back for it, so one moment without signal cost the
/// family everything the pipeline makes of a memory — the people it names, the
/// year, the follow-up questions, the round the others could have guessed — and
/// left a card reading "teksti valmistuu myöhemmin" that was telling the truth
/// about the intent and a lie about the code.
///
/// This is the other half of that promise. See docs/ARCHITECTURE.md §16.
@MainActor
enum DeferredMemory {
    /// What the fill-in produced, for a caller that has a screen to update.
    struct Completion {
        /// The subject the memory was already filed under, now named and dated
        /// by what was actually said.
        var home: Subject
        /// People and places the text turned out to name — exactly as if it had
        /// arrived on time.
        var mentioned: [Subject]
        var questions: [FollowUpQuestion]

        /// The ones a human still has to confirm. Someone already known is not
        /// asked about again, which is why this is narrower than `mentioned`.
        var proposals: [Subject] { mentioned.filter { !$0.confirmed } }
    }

    /// Turns a waiting memory into an ordinary one.
    ///
    /// Everything after transcription is the same work whether the text arrived
    /// a second after the audio or a week later, so it lives here once and is
    /// shared by the catch-up below and by "Kirjoita se itse" on the Tell
    /// screen. Two implementations of this would drift, and the one that drifted
    /// would be the one nobody watches.
    ///
    /// Returns nil if the memory is no longer waiting. That makes it safe to
    /// call twice: the same recording must not be filled in from two directions
    /// at once.
    @discardableResult
    static func fillIn(
        memoryID: String,
        transcript: String,
        extracted: ExtractionResult,
        store: MemoryStore
    ) -> Completion? {
        guard let memory = store.memories.first(where: { $0.id == memoryID }),
              memory.body.isEmpty,
              let home = store.subject(id: memory.subjectID)
        else { return nil }

        // The people are created unconfirmed, for the same reason as in the
        // ordinary path: the model heard "Aino", but the speaker may have said
        // "Aune", and confident-but-wrong is the dangerous case.
        let mentioned = extracted.mentions.map {
            store.findOrCreateSubject(named: $0.name, kind: $0.kind, confirmed: false)
        }

        // The home is the one the audio already picked. It is not chosen again:
        // the memory has been sitting in the archive under that subject, and
        // moving it now would take it out from under whoever has been looking at
        // it. The text only describes it better — and `describe` fills empty
        // fields only, so a title somebody has since written by hand survives.
        store.describe(
            subjectID: home.id,
            title: extracted.suggestedTitle(mentioned: mentioned),
            dateHint: extracted.dateHint
        )

        store.complete(
            memoryID: memory.id,
            body: extracted.body,
            rawTranscript: transcript,
            mentionedSubjectIDs: mentioned.map(\.id)
        )

        let questions = extracted.questions.map {
            FollowUpQuestion(subjectID: home.id, text: $0.text, storedLevel: $0.level)
        }
        store.add(questions: questions)

        return Completion(
            home: store.subject(id: home.id) ?? home,
            mentioned: mentioned,
            questions: questions
        )
    }
}

// MARK: - The catch-up

/// Finishes the memories whose text never arrived.
///
/// Driven by the app's lifecycle like `SyncEngine`, and after a purchase: those
/// are the three moments the two things that stop a transcription — no network
/// and no minutes — are most likely to have changed.
@MainActor
@Observable
final class TranscriptionCatchUp {
    private let store: MemoryStore
    private let session: Session
    private let sync: SyncEngine
    private var isRunning = false

    init(store: MemoryStore, session: Session, sync: SyncEngine) {
        self.store = store
        self.session = session
        self.sync = sync
    }

    /// Never with stubs. The stub transcriber returns a canned sample of Finnish
    /// elderly speech, which is right for developing a UI against and would be a
    /// forgery in an archive: the one thing that must never happen here is words
    /// nobody said appearing under grandmother's name.
    private var isEnabled: Bool {
        #if DEBUG
        // `-defer once` builds the waiting memory out of the stub pipeline on
        // purpose, so the catch-up has to be allowed to finish it — otherwise
        // the argument shows only the half that already worked. Every word in
        // that archive is canned to begin with; there is nothing to forge.
        if AppServices.defersNextTranscription { return true }
        #endif
        return AppServices.isRemote
    }

    /// One round. Safe to call often — overlapping calls are ignored, as in the
    /// sync engine.
    func run() async {
        guard isEnabled, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // The token is read on every call rather than captured once, so a device
        // that is emptied mid-round stops authenticating as the old identity.
        let transcription = AppServices.transcription { [session] in session.identity.token }
        let extraction = AppServices.extraction { [session] in session.identity.token }
        // Read, never written. The ladder aims the questions that come back, but
        // an outage is ours and not the teller's, and it must not cost them a
        // level — so this round records no outcome at all.
        let level = Int(QuestionLadder.comfort.rounded())

        var completedAny = false

        for memory in store.memoriesAwaitingTranscription(author: session.identity.memberID) {
            // A phone that joined last week holds the key and not the file, so
            // this may fetch from R2. Audio that is on neither is skipped rather
            // than abandoned: another memory's may well be here.
            guard let filename = await MediaLoader.audioFilename(
                for: memory, store: store, session: session
            ) else { continue }

            let text: String
            do {
                text = try await transcription.transcribe(
                    audioURL: MediaStore.url(for: filename)
                )
            } catch {
                // The minutes are still gone, or the network still is. The next
                // memory would fail for the same reason, so the round ends here
                // and the recordings stay exactly as safe as they were.
                break
            }

            // Transcription has now cost the family real minutes, and extraction
            // is text — a fraction of a cent, and deliberately unmetered (§7). So
            // a transcript that has been paid for is never thrown away because
            // the cheap half failed: the memory lands in the teller's own words
            // instead, which is what `raw_transcript` is for anyway. Structure is
            // what degrades, not the telling.
            let extracted = (try? await extraction.extract(transcript: text, level: level))
                ?? .verbatim(text)

            if DeferredMemory.fillIn(
                memoryID: memory.id, transcript: text, extracted: extracted, store: store
            ) != nil {
                completedAny = true
            }
        }

        // A memory that has just become readable is of no use sitting on one
        // phone — the whole point of finishing it is that the family can read it.
        if completedAny { await sync.sync() }
    }
}
