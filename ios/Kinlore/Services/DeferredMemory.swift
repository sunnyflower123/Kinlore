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
        // `told`: a recording the teller took back before its text arrived is
        // not finished afterwards. It would come back with a body, and a body is
        // the one thing that makes a memory look like it was meant.
        guard let memory = store.told.first(where: { $0.id == memoryID }),
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
        // it. The text brings only the date — a title is never the telling's to
        // give (`TellViewModel.placeSubject`) — and `describe` fills an empty
        // field only, so a date somebody has since set by hand survives.
        store.describe(subjectID: home.id, dateHint: extracted.dateHint)

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

        // Whatever this recording cost in failed attempts, it is finished now
        // and the tally is of no further use. Typing the text by hand clears it
        // too, which is the point of clearing it here rather than in the
        // catch-up: this is the one place a memory stops waiting.
        TranscriptionAttempts.clear(memoryID)

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
        // The chosen local mode has no member the server knows, so every
        // attempt would be the same 401. The Tell screen already says the
        // text is not coming (finding B4); retrying here on every launch
        // would only keep a promise-shaped request alive.
        return AppServices.isRemote && !session.isLocalByChoice
    }

    /// Whether a failure says something about this moment rather than about
    /// this recording. A moment changes on its own; a recording does not.
    ///
    /// The distinction decides two things at once — whether the rest of the
    /// queue is worth trying now, and whether this recording has used up one of
    /// its attempts. Getting it wrong in one direction starves every memory
    /// behind a hopeless one; getting it wrong in the other abandons a perfectly
    /// good recording because the cottage had no signal for a week.
    ///
    /// Internal rather than private so that `transcription-catchup-check.swift`
    /// can ask it directly. `private` protects no invariant here — unlike
    /// `MemoryStore.advance(seq:)`, where it makes the defect that actually
    /// happened unrepresentable — and a classifier nobody outside can call is
    /// a classifier nobody has measured.
    static func isAboutTheMoment(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let remote = error as? RemoteError else { return false }
        switch remote {
        case .quotaExceeded:
            return true
        case .badStatus(let code):
            // Not authenticated, or knocking too often. Both pass.
            return code == 401 || code == 429
        case .emptyResult:
            // The server answered and there were no words in it. That is a fact
            // about the seconds that were recorded, and it will be just as true
            // tomorrow.
            return false
        }
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
            // Asked three times and refused three times. The audio is kept and
            // exported exactly as before; what stops is the asking.
            guard !TranscriptionAttempts.hasGivenUp(on: memory.id) else { continue }

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
            } catch where Self.isAboutTheMoment(error) {
                // The minutes are gone, or the network is, or this device is not
                // authenticated. Every other recording would meet the same wall,
                // so the round ends — and nothing is counted against any of
                // them, because none of this was their fault.
                //
                // When it was the minutes, the meter has just changed, and the
                // rows that read it should say so on this launch rather than
                // the next: the note on Muistot and every "Ääni tallessa" row
                // read `Session.isOutOfMinutes` (finding #104).
                if let remote = error as? RemoteError, remote.isQuota {
                    await session.refresh()
                }
                break
            } catch {
                // Something about this recording rather than about this moment:
                // audio the server will not take, or seconds the model found no
                // words in. The next memory may be perfectly fine, so the round
                // goes on without it — and this one is counted, because asking
                // again costs the family the same minutes for the same silence.
                //
                // A 5xx is counted here too, which is the debatable part: a
                // Worker that is genuinely broken spends three attempts before
                // the app gives up on a transcript it might later have got. It
                // sits on this side because the one 5xx this app produces on
                // purpose — the hallucination guard — is permanent for that
                // audio, and an uncounted permanent failure is the loop this
                // whole change exists to close.
                TranscriptionAttempts.recordFailure(memory.id)
                continue
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
