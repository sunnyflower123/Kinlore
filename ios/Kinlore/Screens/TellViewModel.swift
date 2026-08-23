import Foundation
import UIKit

/// The magic moment's state machine: record → transcribe → extract → result.
///
/// The phases are distinct because the user needs to see what is happening. One
/// generic "loading" spinner for 20 seconds feels broken; "transcribing your
/// speech" and "organising the memory" feel like work.
@MainActor
@Observable
final class TellViewModel {
    enum Phase: Equatable {
        case idle
        case recording
        /// Typing on the keyboard. Dictation is the primary path, but a
        /// grandchild adding photos often wants to type — and speaking is not
        /// always possible in a quiet room or without headphones.
        case writing
        case transcribing
        case organizing
        case done
        /// The interview loop is reading a follow-up question aloud. Recording
        /// restarts by itself when the question ends.
        case asking
        /// Quota full. The audio is saved, transcription is pending. Not an
        /// error state — the user did nothing wrong and lost nothing.
        case savedWithoutTranscript
        /// The microphone was refused.
        ///
        /// Its own phase rather than a `failed` message, because it is the one
        /// failure the app cannot answer: "Yritä uudelleen" tries the same
        /// refused permission and fails again, for ever. The way out is iOS
        /// Settings — or the keyboard, which needs no permission at all.
        case needsMicrophone
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The text of a memory being typed.
    var draft = ""
    private(set) var transcript: String?
    private(set) var result: ExtractionResult?
    /// Whether the last telling was actually organised, or only kept.
    ///
    /// False means the words are all there and nothing was made of them: no
    /// people, no year, no follow-up questions. The result screen says so rather
    /// than letting an empty result read as "the AI found nobody in it".
    private(set) var wasOrganised = true
    /// The subject the memory was filed under — the most important part of the
    /// result.
    private(set) var placedSubject: Subject?
    /// People and places proposed by the AI. The user confirms or rejects.
    private(set) var proposals: [Subject] = []
    private(set) var newQuestions: [FollowUpQuestion] = []
    /// Whether this result screen carries the offer slot — the invitation
    /// while the family is one person, the paid archive after that
    /// (`UpsellRhythm.card`, docs/UX.md §3.2).
    ///
    /// Decided once, when the telling lands, rather than read in the view body:
    /// the rhythm counts tellings, and a body that is evaluated three times
    /// would count three.
    private(set) var showsUpsell = false
    /// The saved memory's duration, or nil if it was typed. The result screen
    /// shows playback only when there is audio.
    private(set) var savedAudioDuration: TimeInterval?
    private(set) var savedMemoryID: String?

    /// A memory whose audio is already saved and whose text is being typed now.
    ///
    /// Set only by "Kirjoita se itse", and cleared the moment writing ends. Two
    /// rows for one telling — a silent recording and a voice-less text — would
    /// be the archive quietly splitting a memory in half, and it is the audio
    /// that would end up looking like the empty one.
    private var completingMemoryID: String?

    /// The saved memory itself. The result screen needs it for playback, not
    /// just the duration.
    var savedMemory: Memory? {
        guard let savedMemoryID else { return nil }
        return store.told.first { $0.id == savedMemoryID }
    }

    /// Names as written by the teller, keyed by subject id.
    /// Speech recognition gets roughly one proper noun in three wrong, and this
    /// is the only moment the error can be fixed — the teller still remembers
    /// what they said. A week later nobody knows whether it was Sotkamo or
    /// Skotlanti.
    var editedNames: [String: String] = [:]
    private(set) var isCorrecting = false

    /// The edits that actually change something.
    var pendingCorrections: [NameCorrection] {
        proposals.compactMap { subject in
            guard let edited = editedNames[subject.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !edited.isEmpty,
                edited.compare(subject.title, options: .caseInsensitive) != .orderedSame
            else { return nil }
            return NameCorrection(from: subject.title, to: edited)
        }
    }

    let recorder = AudioRecorder()
    /// Reads the interview loop's questions aloud.
    let voice = InterviewVoice()

    /// True while the hands-free loop runs: each saved answer speaks the next
    /// question and restarts recording by itself.
    private(set) var isInterviewing = false
    /// The question currently being read aloud.
    private(set) var askedQuestion: FollowUpQuestion?

    private let store: MemoryStore
    private let transcription: TranscriptionService
    private let extraction: ExtractionService
    /// When a memory is told about a specific photo or person, it attaches to
    /// that. In free dictation this is nil and the subject is inferred from the
    /// speech. During an interview this moves to wherever the first memory
    /// landed, so every answer stays in the same place.
    private(set) var target: Subject?
    /// The question being answered. Marked answered only once the memory has
    /// actually been saved — an open question is a reason to come back to the
    /// app, and it must not be cleared by a mere tap. During an interview this
    /// is the question most recently asked aloud.
    private(set) var question: FollowUpQuestion?
    /// What the screen was opened with. `target` and `question` move during an
    /// interview, but presentation decisions (a modal's close button) must not
    /// move with them.
    let initialTarget: Subject?
    private let initialQuestion: FollowUpQuestion?

    init(
        store: MemoryStore,
        transcription: TranscriptionService,
        extraction: ExtractionService,
        target: Subject? = nil,
        question: FollowUpQuestion? = nil
    ) {
        self.store = store
        self.transcription = transcription
        self.extraction = extraction
        self.target = target
        self.question = question
        self.initialTarget = target
        self.initialQuestion = question

        // A recording the system cut — a call that ended without permission
        // to resume, a microphone that quietly stopped — finishes exactly as
        // if stop had been pressed: everything captured is kept, transcribed
        // and saved. The recorder can only notice the cut; what finishing
        // means is this model's to say.
        recorder.onCut = { [weak self] in
            guard let self else { return }
            Task { await self.stopAndProcess() }
        }
    }

    // MARK: - Recording

    func startRecording() async {
        guard await recorder.requestPermission() else {
            // Not a `failed` message. The old one said "salli mikrofoni
            // asetuksista" and gave a button that retried the refusal instead —
            // an instruction the person it is for cannot follow, in front of the
            // one screen this app exists for.
            leaveInterview()
            phase = .needsMicrophone
            return
        }
        do {
            try recorder.start()
            phase = .recording
        } catch {
            phase = .failed("Nauhoitus ei käynnistynyt.")
        }
    }

    func stopAndProcess() async {
        guard let url = recorder.stop() else {
            // A recording under a second is an accident, not a memory. In the
            // interview loop it is also the natural "I have nothing to add":
            // land on the last result, not on the empty idle screen.
            //
            // It is the clearest signal the ladder ever gets, too: the question
            // was put in front of somebody and nothing came back.
            recordSkip()
            if isInterviewing {
                leaveInterview()
                phase = .done
            } else {
                returnToIdle()
            }
            return
        }
        let duration = recorder.elapsed
        do {
            phase = .transcribing
            let text = try await transcription.transcribe(audioURL: url)
            await process(transcript: text, audioURL: url, duration: duration)
        } catch let error as RemoteError where error.isQuota {
            // A quota must not reject a recording. The audio is irreplaceable
            // and the transcription is replaceable: it is done when the minutes
            // reset or the family goes paid. See docs/ARCHITECTURE.md §7.
            // Without a transcript there is no next question either, so an
            // interview ends here — with the answer safe.
            leaveInterview()
            saveAudioOnly(audioURL: url, duration: duration)
            phase = .savedWithoutTranscript
        } catch {
            // The same applies to a network error: keep the audio, text later.
            leaveInterview()
            saveAudioOnly(audioURL: url, duration: duration)
            phase = .savedWithoutTranscript
        }
    }

    /// Stops a recording and keeps nothing.
    ///
    /// The way out of a telling that went wrong from the first sentence — a
    /// false start, the wrong story, somebody walking into the room. Until this
    /// existed the only button on the recording screen both stopped **and**
    /// saved, so a telling begun by accident could not be abandoned: it had to
    /// be finished, transcribed and then lived with.
    ///
    /// This is not the pipeline discarding audio (rule 3). Nothing has been
    /// saved yet, the file is still the recorder's own, and the person who made
    /// it is the one asking for it gone.
    func discardRecording() {
        let url = recorder.stop()
        // Under a second the recorder deletes it itself; over a second it is
        // ours to delete, and it goes now rather than waiting for the system to
        // empty the temporary directory whenever it feels like it.
        if let url { try? FileManager.default.removeItem(at: url) }
        // The ladder learns nothing from this. A question that was skipped tells
        // it something about difficulty; a telling somebody chose to throw away
        // tells it nothing at all.
        //
        // Mid-interview it lands on the last result rather than on the empty
        // idle screen — the same answer `stopAndProcess` gives when a round
        // produces nothing, and for the same reason: the rounds already saved
        // are the thing to come back to.
        if isInterviewing {
            leaveInterview()
            phase = .done
        } else {
            returnToIdle()
        }
    }

    /// Back to the idle screen with nothing pending.
    ///
    /// The question resets with the phase. An abandoned answer used to leave
    /// it attached, invisibly — the idle screen draws its own offers — and the
    /// next telling on this screen, about anything at all, was recorded
    /// against it: a family member's question marked answered by words that
    /// never addressed it, and the ladder taught at its level. The interview
    /// exits do not come through here; they land on `.done`, whose own exits
    /// reset everything.
    private func returnToIdle() {
        question = initialQuestion
        phase = .idle
    }

    /// Takes back the memory that was just saved.
    ///
    /// Offered where the telling ends, which is the moment somebody knows they
    /// did not mean it — and the only moment the app can be sure whose telling
    /// it is looking at.
    ///
    /// The people this telling proposed go with it when nothing else refers to
    /// them: they came out of these words, they were never confirmed, and a
    /// person left behind by a withdrawn story is a stranger in the family list
    /// with nothing to explain them. Anyone already confirmed, or named in some
    /// other memory, stays.
    func discardSavedMemory() {
        guard let savedMemoryID else { return }
        store.remove(memoryID: savedMemoryID)

        for subject in proposals where !subject.confirmed && store.isOrphaned(subjectID: subject.id) {
            store.remove(subjectID: subject.id)
        }
        // The subject this telling created for itself goes too, when the telling
        // was all it ever held. Never a photo or a person the family already
        // had: `initialTarget` is nil exactly when the home was made here.
        if initialTarget == nil, let home = placedSubject,
           home.kind == .event, store.isOrphaned(subjectID: home.id) {
            store.remove(subjectID: home.id)
        }

        // The question it answered is open again. Saving marked it answered, and
        // it was answered — by this telling, which no longer exists.
        if let question { store.reopen(questionID: question.id) }

        reset()
    }

    // MARK: - Interview loop

    /// Starts the hands-free loop from the result screen: the top follow-up
    /// question is read aloud, the answer is recorded, and the answer's own
    /// extraction yields the next question. One tap opts in; after that the
    /// hands stay in the lap until "Riittää tältä erää".
    ///
    /// Opt-in rather than automatic on purpose. A result screen that starts
    /// talking by itself would startle exactly the user this app is for, and
    /// the name-correction moment needs a calm screen more than the loop needs
    /// one saved tap.
    func beginInterview() async {
        guard phase == .done, let next = nextQuestion else { return }
        isInterviewing = true
        await ask(next)
    }

    /// Which of the fresh questions to ask next: the one that fits where the
    /// teller currently is, not whichever the model happened to emit first.
    /// See docs/ARCHITECTURE.md §12.
    private var nextQuestion: FollowUpQuestion? {
        QuestionLadder.select(newQuestions, comfort: QuestionLadder.comfort, limit: 1).first
    }

    /// The same position as a whole number, which is what extraction wants when
    /// it aims the next three questions.
    private var ladderLevel: Int { Int(QuestionLadder.comfort.rounded()) }

    private func ask(_ next: FollowUpQuestion) async {
        askedQuestion = next
        // The answer is saved through the same path an ordinary answered
        // question takes: it lands on the same subject, and saving it marks
        // the spoken question answered.
        question = next
        if let placedSubject { target = placedSubject }
        phase = .asking

        // With VoiceOver the app must not speak over the screen reader, and
        // auto-starting the microphone would record the reader's voice. The
        // question gets accessibility focus; the record button answers it.
        guard !UIAccessibility.isVoiceOverRunning else { return }

        let spokenToEnd = await voice.speak(next.text)
        guard spokenToEnd, isInterviewing, phase == .asking else { return }
        await startRecording()
    }

    /// The record button on the asking screen: answer before the question has
    /// finished playing. Also the entire path when VoiceOver is running.
    func answerNow() async {
        guard phase == .asking else { return }
        voice.stop()
        await startRecording()
    }

    /// Ends the loop and returns to the last result. The question that was
    /// being asked stays open — an ended interview must not eat a question
    /// nobody answered.
    func endInterview() {
        voice.stop()
        // Ending while the question is still on screen means it went
        // unanswered. Ending after several rounds is more likely tiredness than
        // difficulty, and reading that as strain is a knowing inaccuracy: it
        // makes the next session slightly easier, which is the right direction
        // to be wrong in for this user.
        if phase == .asking { recordSkip() }
        leaveInterview()
        if phase == .asking { phase = .done }
    }

    private func leaveInterview() {
        isInterviewing = false
        askedQuestion = nil
        // The offer slot's decision was made when the pre-interview telling
        // landed, against that telling's proposals. The rounds since then
        // have added names of their own, and three exits — "Riittää tältä
        // erää", a sub-second answer, a discarded one — used to carry the
        // old decision back to the result screen unexamined: a card beside
        // "Kuulinko nimet oikein?", the one neighbourhood UpsellRhythm's
        // first rule forbids. Narrowed here, never widened: a slot already
        // denied stays denied, and `process` still recomputes in full on
        // the ordinary path.
        showsUpsell = showsUpsell && proposals.isEmpty
    }

    // MARK: - Starters

    /// One tap on a small question and the microphone is already running.
    ///
    /// A subject nobody has spoken about yet has no questions of its own —
    /// extraction only makes them once there is a memory to make them from — so
    /// the first contact with a photo used to be a blank button. A starter is
    /// the smallest thing this app can ask: "Kuka tässä kuvassa on?" is three
    /// seconds of speech and it cannot be got wrong.
    ///
    /// Used for the subject's own open questions too. The memory is going to the
    /// same place either way, so there is nothing to present on top of this
    /// screen — the microphone just starts.
    func answer(_ chosen: FollowUpQuestion) async {
        question = chosen
        await startRecording()
    }

    // MARK: - Typing

    /// `completing` is the memory whose audio is already saved: what is typed
    /// finishes that recording rather than starting a second memory beside it.
    /// Nil — the default — for an ordinary typed memory, which is also what
    /// makes any other route into writing safe: the pending id cannot be picked
    /// up by a telling it does not belong to.
    func beginWriting(completing memoryID: String? = nil) {
        draft = ""
        completingMemoryID = memoryID
        phase = .writing
    }

    func cancelWriting() {
        draft = ""
        // Set on entry to writing, cleared on every exit. The memory itself is
        // not abandoned by this — it goes back into the catch-up's care and its
        // text arrives when the network or the minutes do.
        completingMemoryID = nil
        returnToIdle()
    }

    /// Typed text goes through the same extraction as spoken text. Otherwise a
    /// writer would be left without the discovered people and the follow-up
    /// questions, and there would be two different species of memory in the same
    /// archive.
    func submitTyped() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await process(transcript: text, audioURL: nil, duration: nil)
    }

    // MARK: - Pipeline

    private func process(transcript text: String, audioURL: URL?, duration: TimeInterval?) async {
        transcript = text
        phase = .organizing

        // The teller's own level travels with the request, so the questions that
        // come back are ones they can actually answer. See
        // docs/ARCHITECTURE.md §12.
        //
        // A failure here ends nothing. It used to end everything: the phase went
        // to `.failed`, so neither `save` nor `saveAudioOnly` ran, the recording
        // was left in the temporary directory with `persistAudio` never called,
        // and "Voit yrittää uudelleen" meant telling the whole memory again from
        // the beginning. Rule 3 says the original audio is always kept, and this
        // was the one branch that did not keep it — while the quota and the
        // network, which fail far more often, both already did.
        //
        // The catch-up settled what to do instead (§16): a transcript that has
        // been paid for is never thrown away because the cheap half failed, and
        // the memory lands in the teller's own words. Same rule here, and now
        // the same code — structure is what degrades, not the telling.
        let extracted: ExtractionResult
        do {
            extracted = try await extraction.extract(transcript: text, level: ladderLevel)
            wasOrganised = true
        } catch {
            // The developer's half of the same failure: the user's sentence says
            // what happened to their telling, this one says what the server did.
            let detail = (error as? RemoteError)?.debugText ?? error.localizedDescription
            print("[tell] organising failed, keeping the telling verbatim: \(detail)")
            extracted = .verbatim(text)
            wasOrganised = false
        }
        result = extracted

        save(extracted, transcript: text, audioURL: audioURL, duration: duration)
        // A verbatim result carries no questions, so an interview ends here of
        // its own accord — with the answer saved, which is the part that
        // matters.
        if isInterviewing, let next = nextQuestion {
            // The loop feeds itself: this answer's extraction produced the next
            // questions. No result screen between rounds — proposals pile up
            // unconfirmed and are handled when the loop ends.
            await ask(next)
        } else {
            leaveInterview()
            showsUpsell = UpsellRhythm.shouldShow(hasProposals: !proposals.isEmpty)
            phase = .done
        }
    }

    /// Saves the audio alone, without transcription or extraction.
    ///
    /// The memory attaches to the target subject if one is known, otherwise to
    /// an event of its own. The text is left empty, and
    /// `isAwaitingTranscription` tells the UI that transcription is pending.
    private func saveAudioOnly(audioURL: URL, duration: TimeInterval) {
        let home = target ?? {
            // Untitled on purpose. The title comes from the place and the time
            // in what was said, and nothing has read the speech yet — a
            // placeholder written now would never be replaced, because
            // `describe` fills empty fields only. So the subject waits with the
            // memory, and the two are named together when the text arrives.
            let subject = Subject(kind: .event, title: "")
            store.add(subject)
            return subject
        }()
        placedSubject = home

        let memory = Memory(
            subjectID: home.id,
            authorName: store.authorName,
            body: "",
            audioFilename: Self.persistAudio(from: audioURL),
            audioDuration: duration,
            source: .voice
        )
        store.add(memory)
        savedAudioDuration = duration
        savedMemoryID = memory.id
        markQuestionAnswered()
    }

    /// The question is cleared only after saving. Audio saved without a
    /// transcript answers the question too — the text arrives later.
    ///
    /// This is also where the ladder learns. `answer` is nil when the audio was
    /// saved without a transcript: that is a quota or a network outage, ours and
    /// not the teller's, and it must never cost them a level.
    private func markQuestionAnswered(answer: String? = nil, yieldedStructure: Bool = false) {
        guard let question else { return }
        // A starter is not a stored row, so this finds nothing and does nothing
        // — a starter is a prompt, not a debt. The ladder still learns from it.
        store.markAnswered(questionID: question.id)
        guard let answer else { return }
        QuestionLadder.record(
            QuestionLadder.outcome(
                forAnswer: answer,
                at: question.level,
                yieldedStructure: yieldedStructure
            ),
            at: question.level
        )
    }

    /// A question that was put in front of somebody and got no answer. One of
    /// these drops the ladder a whole level; climbing back takes two good
    /// answers.
    private func recordSkip() {
        guard let question else { return }
        QuestionLadder.record(.strained, at: question.level)
    }

    private func save(
        _ extracted: ExtractionResult,
        transcript: String,
        audioURL: URL?,
        duration: TimeInterval?
    ) {
        // The audio of this same telling is already in the archive, so the text
        // completes that memory instead of starting a second one beside it.
        //
        // If it has been completed in the meantime — the catch-up reached it
        // first — this falls through and the typed text becomes a memory of its
        // own. A duplicate is a small harm; throwing away what somebody has
        // just typed is not.
        if let completingMemoryID,
           completeAudioMemory(completingMemoryID, extracted, transcript: transcript) {
            return
        }

        // Mentioned people and places are created as unconfirmed proposals.
        // Unconfirmed never appears in the family tree as fact — a wrong
        // relationship is worse than a missing one.
        var mentioned: [Subject] = []
        for entity in extracted.mentions {
            // A new person is ALWAYS created unconfirmed, no matter how certain
            // the model is. The confidence covers the model's own parsing, not
            // whether the person is right: it heard "Aino", but the speaker may
            // have said "Aune". Confident-but-wrong is exactly the dangerous
            // case, and if confidence could bypass confirmation, it always would.
            //
            // `findOrCreateSubject` returns an already known person as is, so
            // confirmation is asked once per person, not once per memory.
            let subject = store.findOrCreateSubject(
                named: entity.name,
                kind: entity.kind,
                confirmed: false
            )
            mentioned.append(subject)
        }
        // During an interview the rounds accumulate: each answer's names join
        // the names already waiting, so the loop-end result screen checks
        // every round — a plain assignment here quietly narrowed the check to
        // whichever round happened to be last, while the comment in `process`
        // promised otherwise. Outside the loop each telling starts its own
        // check. Deduplicated by id, because the same person mentioned twice
        // is one row to confirm, not two.
        let fresh = mentioned.filter { !$0.confirmed }
        if isInterviewing {
            let known = Set(proposals.map(\.id))
            proposals += fresh.filter { !known.contains($0.id) }
        } else {
            proposals = fresh
        }

        // Free dictation needs a home. It is named after the place and the time
        // — precisely the organising the user would never do themselves.
        let home = placeSubject(for: extracted, mentioned: mentioned)
        placedSubject = home

        let audioName = audioURL.flatMap(Self.persistAudio(from:))

        let memory = Memory(
            subjectID: home.id,
            authorName: store.authorName,
            body: extracted.body,
            // In a typed memory the raw text equals the cleaned one, but it is
            // stored anyway: if the cleanup is ever changed, the original
            // wording is still on file.
            rawTranscript: transcript,
            audioFilename: audioName,
            audioDuration: duration,
            source: audioURL == nil ? .typed : .voice,
            mentionedSubjectIDs: mentioned.map(\.id)
        )
        store.add(memory)
        savedAudioDuration = duration
        savedMemoryID = memory.id

        let questions = extracted.questions.map {
            FollowUpQuestion(subjectID: home.id, text: $0.text, storedLevel: $0.level)
        }
        store.add(questions: questions)
        newQuestions = questions
        // Measured on the raw transcript rather than the cleaned body: what was
        // actually said is the evidence, and the cleanup can lengthen a
        // three-word answer into a sentence.
        markQuestionAnswered(
            answer: transcript,
            yieldedStructure: !mentioned.isEmpty || extracted.dateHint != nil
        )
    }

    /// Fills in the memory whose audio was saved without a transcript, using the
    /// text the teller has just typed for it.
    ///
    /// The same work the catch-up does in the background, and the same code:
    /// the memory keeps its recording, its home subject gets the name and the
    /// date, the people it names appear as proposals, and the follow-up
    /// questions are stored. From here the result screen cannot tell that the
    /// text took the long way round — which is the point.
    ///
    /// Returns false if the memory was no longer waiting.
    private func completeAudioMemory(
        _ memoryID: String,
        _ extracted: ExtractionResult,
        transcript: String
    ) -> Bool {
        guard let completion = DeferredMemory.fillIn(
            memoryID: memoryID,
            transcript: transcript,
            extracted: extracted,
            store: store
        ) else { return false }

        completingMemoryID = nil
        proposals = completion.proposals
        placedSubject = completion.home
        newQuestions = completion.questions
        savedMemoryID = memoryID
        // Kept from the recording rather than from this pass, which had no
        // audio of its own: the result screen still offers her voice.
        savedAudioDuration = store.told.first { $0.id == memoryID }?.audioDuration

        // The question was already marked answered when the audio was saved, but
        // the ladder was deliberately not told — an outage must not cost a
        // level. Now there is a real answer to learn from.
        markQuestionAnswered(
            answer: transcript,
            yieldedStructure: !completion.mentioned.isEmpty || extracted.dateHint != nil
        )
        return true
    }

    /// Finds or creates the subject the memory belongs to.
    private func placeSubject(for extracted: ExtractionResult, mentioned: [Subject]) -> Subject {
        let suggested = extracted.suggestedTitle(mentioned: mentioned)

        // A memory told about a photo belongs to that photo — no guessing. The
        // photo also gets its name and date from what was told about it: exactly
        // the organising nobody would do for thirty scanned photographs.
        if let target {
            store.describe(subjectID: target.id, title: suggested, dateHint: extracted.dateHint)
            return store.subject(id: target.id) ?? target
        }

        // Free dictation needs a home. The same place and time gather the
        // memories together instead of every dictation spawning its own
        // disconnected event.
        let title = suggested ?? "Kerrottu muisto"
        if let existing = store.subjects(of: .event).first(where: { $0.title == title }) {
            return existing
        }
        let subject = Subject(kind: .event, title: title, dateHint: extracted.dateHint)
        store.add(subject)
        return subject
    }

    /// Moves the audio out of the temporary directory into a permanent one.
    /// Grandmother's voice is itself the inheritance, so it is not left in a
    /// place the system is allowed to empty.
    private static func persistAudio(from url: URL) -> String? {
        let destination = URL.documentsDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination.lastPathComponent
        } catch {
            return nil
        }
    }

    // MARK: - Name correction

    /// Sends the corrected names back through extraction.
    ///
    /// Renaming the subject alone is not enough: the memory text would still say
    /// "Skotlannissa" while the place card reads "Sotkamo". Because of Finnish
    /// inflection a string replacement never matches the inflected form, so the
    /// text is requested again from the model, which knows how to inflect the
    /// corrected name properly.
    func applyCorrections() async {
        let corrections = pendingCorrections
        guard !corrections.isEmpty, let transcript, let memoryID = savedMemoryID else { return }

        isCorrecting = true
        defer { isCorrecting = false }

        // The subject names are always corrected, even if re-extracting the text
        // fails. The right name in the family tree matters more than consistent
        // wording in the memory text.
        for subject in proposals {
            if let edited = editedNames[subject.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !edited.isEmpty {
                store.rename(subjectID: subject.id, to: edited)
            }
        }

        do {
            let corrected = try await extraction.extract(
                transcript: transcript,
                corrections: corrections,
                level: ladderLevel
            )
            store.updateBody(memoryID: memoryID, body: corrected.body)
            result = corrected
        } catch {
            // The names are already corrected, so a failure only costs the
            // consistency of the text. That is not worth showing as an error.
            print("[tell] re-extracting the text failed: \(error.localizedDescription)")
        }

        // Corrected subjects were written by the teller themselves, so they are
        // confirmed. A separate confirmation prompt would be asking the same
        // thing twice.
        for subject in proposals where editedNames[subject.id] != nil {
            store.confirm(subjectID: subject.id)
        }
        proposals = proposals.filter { editedNames[$0.id] == nil }
        editedNames = [:]
    }

    // MARK: - Handling proposals

    func confirm(_ subject: Subject) {
        store.confirm(subjectID: subject.id)
        proposals.removeAll { $0.id == subject.id }
    }

    func reject(_ subject: Subject) {
        store.remove(subjectID: subject.id)
        proposals.removeAll { $0.id == subject.id }
    }

    func reset() {
        voice.stop()
        leaveInterview()
        target = initialTarget
        question = initialQuestion
        phase = .idle
        draft = ""
        transcript = nil
        result = nil
        wasOrganised = true
        placedSubject = nil
        proposals = []
        newQuestions = []
        showsUpsell = false
        savedAudioDuration = nil
        savedMemoryID = nil
        completingMemoryID = nil
        editedNames = [:]
    }
}
