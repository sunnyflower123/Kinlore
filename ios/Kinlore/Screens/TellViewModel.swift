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

    private(set) var phase: Phase = .idle {
        didSet { UIApplication.shared.isIdleTimerDisabled = Self.keepsScreenAwake(phase) }
    }

    /// The screen stays on while the phone is listening, writing down,
    /// organising or asking — not only while recording. The recorder kept it
    /// on for the recording alone and let go in `stop()`, so a teller who set
    /// the phone down after a long story let it lock during the upload, iOS
    /// suspended the app, the request died, and the text she had waited for
    /// became "valmistuu myöhemmin" for no reason she was given (founder's-eye
    /// review, 3 Sep 2026, finding #21). Decided from the phase, in one place:
    /// the recorder's own toggles still run and agree with it.
    private static func keepsScreenAwake(_ phase: Phase) -> Bool {
        switch phase {
        case .recording, .transcribing, .organizing, .asking: true
        default: false
        }
    }

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

    /// The names this telling resolved to people and places the family
    /// already has. Resolved by title alone, which is also how two Mattis
    /// become one card; shown on the result screen so the teller can say
    /// "not that one" while she still knows which one she meant (finding
    /// #14). Accumulates across interview rounds like `proposals`.
    private(set) var known: [Subject] = []

    /// Every memory this telling has saved — one, or one per interview round —
    /// so a familiar name split on the result screen is re-pointed in all of
    /// them.
    private var sessionMemoryIDs: [String] = []
    private(set) var newQuestions: [FollowUpQuestion] = []
    /// The open questions the saved telling's reply took off its card
    /// (`ExtractionContext.turnover`), held while its result screen is up.
    /// Taking the telling back there, or moving it to another card, puts them
    /// back (`MemoryStore.reinstate`): they gave way to a telling the card
    /// no longer holds. Follows `savedMemoryID`, because that is the one
    /// telling both buttons act on.
    private var replaced: [FollowUpQuestion] = []
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

    /// "Riittää tältä erää" pressed while answering: this answer is saved and
    /// no further question is asked. The loop's one exit used to stand only
    /// while a question was being spoken — seconds — and once the microphone
    /// had armed itself the big button meant "next question" and the only
    /// other one threw the answer away (founder's-eye review, 3 Sep 2026,
    /// findings #113 and #114).
    private(set) var endsAfterAnswer = false

    /// The way out of the loop that keeps what was just said.
    func finishAfterThisAnswer() async {
        guard phase == .recording, isInterviewing else { return }
        endsAfterAnswer = true
        await stopAndProcess()
    }
    /// The question currently being read aloud.
    private(set) var askedQuestion: FollowUpQuestion?

    private let store: MemoryStore
    private let transcription: TranscriptionService
    private let extraction: ExtractionService
    /// Whether "the text arrives later" is a promise this configuration can
    /// keep. False in the chosen local mode of a build that has a real
    /// backend: transcription needs a member the server knows, that mode
    /// never creates one, and every call would be a 401 — so the attempt is
    /// skipped and the screens say so instead of promising (docs/UX.md §7,
    /// finding B4). The real fix — a family-less transcription identity or
    /// on-device ASR — is a v1.1 decision.
    let canTranscribe: Bool
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
    /// What a reset returns to. A `var` since the deck existed: pushing a card
    /// aside moves this too, so that finishing a telling comes back to the card
    /// in front rather than the one behind it. Its other meaning is unchanged —
    /// nil is still exactly "the home was made here", which is what keeps a
    /// taken-back telling from deleting a photograph the family already had.
    private(set) var initialTarget: Subject?
    private let initialQuestion: FollowUpQuestion?

    /// The question the screen was opened with, while it is still open. The
    /// idle screen makes it the title and the big button answers it; once a
    /// telling has answered it, the next one on this screen is about anything
    /// at all, and nothing is recorded against it again.
    var openedQuestion: FollowUpQuestion? {
        guard let initialQuestion,
              store.questions.contains(where: { $0.id == initialQuestion.id && !$0.answered })
        else { return nil }
        return initialQuestion
    }

    init(
        store: MemoryStore,
        transcription: TranscriptionService,
        extraction: ExtractionService,
        target: Subject? = nil,
        question: FollowUpQuestion? = nil,
        canTranscribe: Bool = true
    ) {
        self.store = store
        self.transcription = transcription
        self.extraction = extraction
        self.canTranscribe = canTranscribe
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
        // An answer that has gone quiet, or run for ten minutes, ends the
        // conversation the way "Riittää tältä erää" does (`AnswerWatch`).
        recorder.onLimit = { [weak self] in
            guard let self else { return }
            Task { await self.finishAfterThisAnswer() }
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
            // Only an answer in the conversation is watched. The first telling
            // is left to the hand that began it (`AnswerWatch`).
            var watch = isInterviewing ? AnswerWatch() : nil
            #if DEBUG
            // `-watch off`: only a hand ends an answer, as before 27 Sep 2026.
            // For a test that stands on the listening screen longer than the
            // quiet a simulator hears is allowed to last.
            if UserDefaults.standard.string(forKey: "watch") == "off" { watch = nil }
            #endif
            try recorder.start(watching: watch)
            phase = .recording
            #if DEBUG
            sweepForTests(at: "recording")
            #endif
        } catch {
            phase = .failed(String(localized: "Nauhoitus ei käynnistynyt."))
        }
    }

    #if DEBUG
    /// `-recovery-sweep recording` / `-recovery-sweep stopped`: runs the
    /// launch sweep a second into a live recording, or between the stop and
    /// the save — the two moments it used to be able to land on.
    ///
    /// The launch task sweeps only once the calls ahead of it have waited on
    /// the network, so where the sweep fell was the network's to say, and
    /// with a RevenueCat key the entitlement check alone can be a round trip.
    /// A test cannot schedule a slow network; it can schedule the sweep.
    /// `SilentFailureTests.testTheLaunchSweepLeavesThisLaunchsRecordingAlone`.
    private func sweepForTests(at moment: String) {
        guard UserDefaults.standard.string(forKey: "recovery-sweep") == moment else { return }
        if moment == "recording" {
            Task {
                try? await Task.sleep(for: .seconds(1))
                RecordingRecovery.sweep(into: store)
            }
        } else {
            RecordingRecovery.sweep(into: store)
        }
    }
    #endif

    /// Whether the last audio-only save was the month's minutes rather than
    /// the network. The screen after it used to say the same "valmistuu
    /// myöhemmin" for both, and for the quota that was a delay's words on a
    /// wall (findings #68, #24).
    private(set) var savedBecauseOfQuota = false

    /// The recording could not be kept: the move out of the temporary
    /// directory failed, and so did the copy. Until 5 Sep 2026 that returned
    /// nil, the memory was saved without its audio, and the screen said
    /// *"Äänesi on tallessa"* over a file that was gone — rule 3 broken in
    /// silence on the one input the app calls irreplaceable (founder's-eye
    /// review, finding #58). Now the screens say so, and a telling with no
    /// words and no recording is not saved at all.
    private(set) var audioLost = false

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
        #if DEBUG
        sweepForTests(at: "stopped")
        #endif
        let duration = recorder.elapsed
        guard canTranscribe else {
            // Not an error and not a deferral: in this mode the text is never
            // coming, and uploading the audio to be told 401 would only make
            // the screen's honest sentence arrive slower.
            leaveInterview()
            saveAudioOnly(audioURL: url, duration: duration)
            savedBecauseOfQuota = false
            phase = .savedWithoutTranscript
            return
        }
        do {
            phase = .transcribing
            #if DEBUG
            // `-answer wordless`: an answer in the conversation comes back
            // as a reply with no words in it, which the Worker does not send
            // today (see the catch below). Only an answer — the telling
            // before it is transcribed as usual, or there would be no
            // conversation to answer in.
            if isInterviewing, UserDefaults.standard.string(forKey: "answer") == "wordless" {
                throw RemoteError.emptyResult
            }
            #endif
            let text = try await transcription.transcribe(audioURL: url)
            await process(transcript: text, audioURL: url, duration: duration)
        } catch RemoteError.emptyResult where isInterviewing {
            // A reply with no words in it, which `RemoteTranscriptionService`
            // throws on a 200 whose text is blank. Until 27 Sep 2026 it fell
            // through to the last catch as though the network had failed —
            // onto "Äänesi on tallessa", with none of the names the rounds
            // before it heard on that screen and the question it never
            // answered marked answered.
            //
            // The Worker does not send that reply today. `complete()` refuses
            // a reply with no content (`openrouter.ts`), so a silent answer —
            // the one `AnswerWatch` ends, or one stopped by hand — arrives as
            // a 502 and still takes the last catch: the recording is kept, the
            // screen says "Äänesi on tallessa", and the catch-up asks again.
            keepWordlessAnswer(audioURL: url, duration: duration)
        } catch let error as RemoteError where error.isQuota {
            // A quota must not reject a recording. The audio is irreplaceable
            // and the transcription is replaceable: it is done when the minutes
            // reset or the family goes paid. See docs/ARCHITECTURE.md §7.
            // Without a transcript there is no next question either, so an
            // interview ends here — with the answer safe.
            leaveInterview()
            saveAudioOnly(audioURL: url, duration: duration)
            savedBecauseOfQuota = true
            phase = .savedWithoutTranscript
        } catch {
            // The same applies to a network error: keep the audio, text later.
            leaveInterview()
            saveAudioOnly(audioURL: url, duration: duration)
            savedBecauseOfQuota = false
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
    ///
    /// The opened question only while it is open, since 26 Sep 2026: the
    /// same defect arriving from the other side. "Kerro toinen muisto" after
    /// the answer came back to it, and the next telling was filed as that
    /// question's answer again — moving `answeredMemoryID` off the telling
    /// that answered it, under a title that no longer asked it.
    private func returnToIdle() {
        question = openedQuestion
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
        // Its own questions went with it (`remove(memoryID:)`), and the ones
        // they had replaced on the card come back.
        store.reinstate(replaced)

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
        //
        // Found by the telling rather than by `question`, since 27 Sep 2026. A
        // conversation that ends on a question nobody answered — "Riittää
        // tältä erää", an answer under a second, one with no words — leaves
        // `question` on that one, while the telling on this card answered the
        // round before it. The open question was reopened, and the answered
        // one stayed answered by a telling that was gone.
        for answered in store.questions where answered.answered && answered.answeredMemoryID == savedMemoryID {
            store.reopen(questionID: answered.id)
        }

        reset()
    }

    // MARK: - Interview loop

    /// Starts the hands-free loop: the top follow-up question is read aloud,
    /// the answer is recorded, and the answer's own extraction yields the next
    /// question. After that the hands stay in the lap until "Riittää tältä
    /// erää", which lands on the result with everything the rounds collected.
    ///
    /// A spoken telling starts it by itself (`process`, since 26 Sep 2026); a
    /// written one waits for "Jatketaan jutellen" on the result screen, which
    /// also starts it again after a conversation has ended. It used to be the
    /// button in both cases, on the argument that a result screen talking by
    /// itself would startle the user this app is for — and when the founder
    /// tried it on their own phone, telling about a photograph, nothing was
    /// asked at all, because the button sat under the names, below the fold.
    /// The question is not the result screen speaking up: it is the app's
    /// turn after the teller has ended hers, in the same voice exchange she
    /// began by pressing record.
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
        endsAfterAnswer = false
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

        // What the words are about. Ordinarily the card the screen is aimed
        // at, or none in free dictation. Typed to finish a recording that is
        // already filed, they are about that recording's card, whatever the
        // screen was aimed at when the typing began — free dictation had no
        // card at all — and the recording is left out of the card's count,
        // because it is the telling being extracted. The catch-up asks the
        // same way (`TranscriptionCatchUp.run`). A recording the catch-up
        // finished first is not waiting, and the typed text is then a
        // telling of its own (`save`).
        let waiting = completingMemoryID.flatMap { id in
            store.told.first { $0.id == id && $0.body.isEmpty }
        }
        let aim = waiting.flatMap { store.subject(id: $0.subjectID) } ?? target

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
            extracted = try await extraction.extract(
                transcript: text,
                corrections: [],
                level: ladderLevel,
                context: store.extractionContext(for: aim, excluding: waiting?.id),
                photo: store.modelPhoto(for: aim)
            )
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
        if isInterviewing, !endsAfterAnswer, let next = nextQuestion {
            // The loop feeds itself: this answer's extraction produced the next
            // questions. No result screen between rounds — proposals pile up
            // unconfirmed and are handled when the loop ends.
            await ask(next)
        } else {
            let wasRound = isInterviewing
            leaveInterview()
            showsUpsell = UpsellRhythm.shouldShow(hasProposals: !proposals.isEmpty)
            phase = .done
            // A spoken telling goes straight on to its first question
            // (`beginInterview`, 26 Sep 2026). Not a written one — the keyboard
            // was her choice of how to talk to the app — and not after a lost
            // recording, whose one sentence on the result is what she has to
            // read next. The offer slot above is decided first, so the rhythm
            // counts this telling exactly as it did when the loop was a tap
            // away; the names wait unconfirmed and meet the result card when
            // the conversation ends. No `.done` frame is drawn in between:
            // nothing here suspends before `ask` sets the phase again.
            if !wasRound, audioURL != nil, !audioLost {
                await beginInterview()
            }
        }
    }

    /// Saves the audio alone, without transcription or extraction.
    ///
    /// The memory attaches to the target subject if one is known, otherwise to
    /// an event of its own. The text is left empty, and
    /// `isAwaitingTranscription` tells the UI that transcription is pending.
    private func saveAudioOnly(audioURL: URL, duration: TimeInterval) {
        // Nothing has read the words, so nothing on the card gave way to them.
        replaced = []
        guard let audioName = Self.persistAudio(from: audioURL) else {
            // No words, and now no recording: a memory with neither is a row
            // reading "Ääni tallessa" over nothing. The screen says what
            // happened instead, the question stays open, and "Kirjoita se
            // itse" is the way to keep the telling while it is still in mind.
            audioLost = true
            savedMemoryID = nil
            return
        }
        audioLost = false
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
            audioFilename: audioName,
            audioDuration: duration,
            source: .voice
        )
        store.add(memory)
        savedAudioDuration = duration
        savedMemoryID = memory.id
        sessionMemoryIDs.append(memory.id)
        markQuestionAnswered()
    }

    /// Ends the conversation on an answer that came back with no words.
    ///
    /// Reached through `RemoteError.emptyResult`, which `-answer wordless`
    /// raises and nothing in production does today: the Worker answers a
    /// silence 502 (`openrouter.ts`), and that answer takes the network's road
    /// in `stopAndProcess`.
    ///
    /// It lands where "Riittää tältä erää" lands, on the result the rounds
    /// before it made: their names wait there to be confirmed (rule 4), and
    /// the card keeps the last answer that had words — `savedMemoryID`, the
    /// transcript and the playback stay exactly as that round left them.
    ///
    /// The recording is kept all the same (rule 3). "No words" is the model's
    /// reading of it, and a voice too quiet for the model is still a voice. It
    /// waits for its text on the card the rounds are filed under, and it joins
    /// the session's tellings, so the answer to who told them reaches it too:
    /// a name taken off the rounds must not stay on this one.
    ///
    /// The question stays open, because nothing answered it, and the ladder
    /// learns what it learns from an answer under a second (`recordSkip`).
    private func keepWordlessAnswer(audioURL: URL, duration: TimeInterval) {
        recordSkip()
        leaveInterview()
        // `ask` filed every round under the card the first one landed on. A
        // recording that cannot be moved out of tmp leaves nothing to keep,
        // and nothing to say on a card that shows another round's words.
        if let home = target, let audioName = Self.persistAudio(from: audioURL) {
            let memory = Memory(
                subjectID: home.id,
                authorName: store.authorName,
                body: "",
                audioFilename: audioName,
                audioDuration: duration,
                source: .voice
            )
            store.add(memory)
            sessionMemoryIDs.append(memory.id)
        }
        phase = .done
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
        store.markAnswered(questionID: question.id, by: savedMemoryID)
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
            let waiting = Set(proposals.map(\.id))
            proposals += fresh.filter { !waiting.contains($0.id) }
        } else {
            proposals = fresh
        }
        // The familiar ones, once each, for the "not that one" row.
        var familiar: [Subject] = []
        for subject in mentioned where subject.confirmed && !familiar.contains(where: { $0.id == subject.id }) {
            familiar.append(subject)
        }
        if isInterviewing {
            let seen = Set(known.map(\.id))
            known += familiar.filter { !seen.contains($0.id) }
        } else {
            known = familiar
        }

        // Free dictation needs a home. It is named after the place and the time
        // — precisely the organising the user would never do themselves.
        let home = placeSubject(for: extracted)
        placedSubject = home

        let audioName = audioURL.flatMap(Self.persistAudio(from:))
        // The words are here; the recording is not. Saved as text, and said.
        audioLost = audioURL != nil && audioName == nil

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
        movedByHand = false
        sessionMemoryIDs.append(memory.id)

        // The archive already told the model what was open on this subject and
        // asked it not to repeat any of it, and that is the half that buys a
        // better question rather than merely fewer. This is the other half: the
        // model was asked, not obeyed, and `add(questions:)` appends whatever
        // it is handed. Three per telling for ever, with nothing in between, is
        // why a fourth telling about one photograph used to produce the first
        // telling's questions again. No repeat, and never more than
        // `openQuestionCap` open on one subject; and the machine's older
        // questions on the card give way to these, which saw the photograph
        // and everything already asked (`ExtractionContext.turnover`). The
        // question this telling answers stays, to be marked answered below.
        let open = store.questions.filter { !$0.answered && $0.subjectID == home.id }
        let turnover = ExtractionContext.turnover(
            extracted.questions.map(\.text), on: open, answering: question?.id
        )
        let questions = extracted.questions
            .filter { turnover.admitted.contains($0.text) }
            .map {
                FollowUpQuestion(subjectID: home.id, text: $0.text, storedLevel: $0.level, askedFrom: memory.id)
            }
        replaced = open.filter { turnover.retired.contains($0.id) }
        store.add(questions: questions, retiring: turnover.retired)
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
        replaced = completion.replaced
        savedMemoryID = memoryID
        sessionMemoryIDs.append(memoryID)
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
    ///
    /// **A telling names nothing, since 12 Sep 2026.** The subject used to be
    /// titled from what was said — *"Puumalassa, 1950-luku"* — and free
    /// dictations that produced the same title were gathered under one event.
    /// Both were the app deciding, out of one telling, what a thing is called
    /// and which tellings belong together; the founder met the result as
    /// *"Sijoitin sen kohteeseen Kesä Puumalassa"*. Now a photograph keeps its
    /// own name or none, every free dictation is its own moment shown under the
    /// day it was told (`Subject.displayTitle`), and *"Nimeä hetki"* and
    /// *"Siirrä toiselle kortille"* are how a person names and gathers. The
    /// date stays: it is what was said, stored with its precision (rule 5),
    /// and it names nothing.
    private func placeSubject(for extracted: ExtractionResult) -> Subject {
        // A memory told about a photo belongs to that photo — no guessing.
        if let target {
            store.describe(subjectID: target.id, dateHint: extracted.dateHint)
            return store.subject(id: target.id) ?? target
        }
        let subject = Subject(kind: .event, title: "", dateHint: extracted.dateHint)
        store.add(subject)
        return subject
    }

    /// Moves the audio out of the temporary directory into a permanent one.
    /// Grandmother's voice is itself the inheritance, so it is not left in a
    /// place the system is allowed to empty.
    ///
    /// A move that fails is tried again as a copy — the two fail for different
    /// reasons — and nil means the bytes could not be kept, which every caller
    /// now treats as an answer rather than as a detail (`audioLost`). The
    /// realistic cause is the temporary file being gone: the move is a rename
    /// on the same volume and needs no room, and a phone with no room fails
    /// the recording itself first.
    private static func persistAudio(from url: URL) -> String? {
        #if DEBUG
        // `-audio-lost YES`: holds the failure still for the tests. The real
        // one needs the system to have emptied tmp under a live telling.
        if UserDefaults.standard.bool(forKey: "audio-lost") {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        #endif
        let destination = URL.documentsDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        if (try? FileManager.default.moveItem(at: url, to: destination)) != nil {
            return destination.lastPathComponent
        }
        if (try? FileManager.default.copyItem(at: url, to: destination)) != nil {
            return destination.lastPathComponent
        }
        return nil
    }

    // MARK: - Moving

    /// Files the telling just saved under another card. The result's placement
    /// line follows, so the sentence on screen says where it is now — in its
    /// own words, because "sijoitin" and "lisäsin" were the AI's and the card's
    /// doing, and this was the teller's.
    ///
    /// The questions it raised stay on this screen, where the conversation
    /// can go on about it on the new card, while the stored ones are retired
    /// (`MemoryStore.move`); the ones they replaced on the old card go back,
    /// once the telling has actually left it.
    func move(to subject: Subject) {
        guard let id = savedMemoryID else { return }
        let from = store.told.first { $0.id == id }?.subjectID
        store.move(memoryID: id, to: subject.id)
        if from != subject.id, store.told.contains(where: { $0.id == id && $0.subjectID == subject.id }) {
            store.reinstate(replaced)
            replaced = []
        }
        placedSubject = subject
        movedByHand = true
    }

    /// Whether the telling on the result screen was refiled by hand.
    private(set) var movedByHand = false

    // MARK: - Who told it

    /// What the result screen's teller question was answered with.
    ///
    /// Three answers and not two: *"minä"* is not the same as *"en halua
    /// nimeäni näkyviin"*, and neither is the same as the unanswered state
    /// this starts in. Only the last of those falls back to the author's
    /// name, which is what every telling did before the question existed.
    enum TellerChoice: Equatable {
        /// Whoever holds the phone. The associated value is their own card in
        /// the family tree when the member has been linked to one
        /// (`Family.You.personSubjectID`); without a link the author's name is
        /// already this person's, and nothing needs storing.
        case me(String?)
        case person(String)
        case hidden
    }

    /// Nil until the question is answered. The result screen reads it to know
    /// whether to ask or to show the answer.
    private(set) var tellerChoice: TellerChoice?

    /// Records the answer against every telling of this session.
    ///
    /// The whole session, because the interview loop saves one memory per
    /// round and the voice did not change between rounds — the question is
    /// asked once, at the end, on the screen that ends the loop.
    func chooseTeller(_ choice: TellerChoice) {
        tellerChoice = choice
        // Placing a teller in the photograph was part of the answer it
        // followed. A different answer takes it back, or the first name would
        // stay in the picture under the second one's telling.
        if let placed = placedTellerID, placed != chosenTeller?.id {
            placeTellerInPhoto(false)
        }
        let subjectID: String?
        let hidden: Bool
        switch choice {
        case let .me(card):
            subjectID = card
            hidden = false
        case let .person(id):
            subjectID = id
            hidden = false
        case .hidden:
            subjectID = nil
            hidden = true
        }
        store.setTeller(subjectID, hidden: hidden, for: sessionMemoryIDs)
    }

    /// Whether the answer was "do not name me". Written out rather than
    /// compared at the call site, where the optional makes `== .hidden`
    /// read as a question about two different things.
    var tellerIsHidden: Bool {
        if case .hidden? = tellerChoice { return true }
        return false
    }

    /// Puts the question back, when the first answer was the wrong one.
    ///
    /// **It does not unset what was stored.** The card asks again, and the
    /// next answer overwrites; somebody who taps this and then leaves the
    /// screen keeps the answer they gave, which matters for exactly one of the
    /// three — a name taken off a telling must not come back because a thumb
    /// went to the wrong row and then away.
    func clearTellerChoice() {
        tellerChoice = nil
    }

    /// The card the chosen teller has, for the answered card's one line. Nil
    /// for *"minä"* without a linked card and for a hidden name, both of which
    /// the screen has its own words for.
    var chosenTeller: Subject? {
        switch tellerChoice {
        case let .me(card): card.flatMap { store.subject(id: $0) }
        case let .person(id): store.subject(id: id)
        default: nil
        }
    }

    // MARK: - Who is in the photograph

    /// The teller this session put in the photograph by hand, so the answered
    /// card can say so and take it back. Nil when nobody was placed — which
    /// includes a teller the telling already named, whom this row did not put
    /// there and must not take out.
    private(set) var placedTellerID: String?

    /// The photograph this session's tellings are about, when they are.
    private var photo: Subject? {
        guard let placed = placedSubject, placed.kind == .photo else { return nil }
        return store.subject(id: placed.id)
    }

    /// The tellings a teller can be placed in: this session's, about the
    /// photograph.
    private var photoMemoryIDs: [String] {
        guard let photo else { return [] }
        let about = Set(store.memories(for: photo.id).map(\.id))
        return sessionMemoryIDs.filter(about.contains)
    }

    /// Whom the result screen may offer to put in the photograph: the answered
    /// teller, when the telling was about one and they are not in it yet.
    ///
    /// **Never a hidden teller.** A name placed in the picture is a name on the
    /// photograph's tellings, which is exactly what *"En halua nimeäni
    /// näkyviin"* asked not to be. Never *"minä"* without a card, because
    /// there is nothing to place. And confirmed cards only: this row is a
    /// human saying so, and it must not turn a heard name into a fact on the
    /// way (rule 4).
    var tellerToPlace: Subject? {
        guard placedTellerID == nil, !tellerIsHidden,
              let teller = chosenTeller, teller.kind == .person, teller.confirmed,
              let photo, !photoMemoryIDs.isEmpty
        else { return nil }
        let alreadyIn = store.memories(for: photo.id).contains { $0.mentionedSubjectIDs.contains(teller.id) }
        return alreadyIn ? nil : teller
    }

    /// The card placed in the photograph on this screen, for the line that
    /// says so.
    var placedTeller: Subject? {
        placedTellerID.flatMap { store.subject(id: $0) }
    }

    /// Puts the answered teller in the photograph, or takes them out again.
    func placeTellerInPhoto(_ present: Bool) {
        if present {
            guard let teller = tellerToPlace else { return }
            store.setPresent(teller.id, true, in: photoMemoryIDs)
            placedTellerID = teller.id
        } else {
            guard let placed = placedTellerID else { return }
            store.setPresent(placed, false, in: photoMemoryIDs)
            placedTellerID = nil
        }
    }

    /// The people this archive has lately been told by — the second and third
    /// voice round a table, one tap away after their first telling.
    var recentTellers: [Subject] { store.recentTellers() }

    /// Everybody who could have told it: the family's confirmed people, for
    /// the sheet behind *"Joku muu"*.
    var tellerCandidates: [Subject] {
        store.subjects(of: .person).filter { $0.confirmed && !$0.title.isEmpty }
    }

    /// A name typed into the sheet. Confirmed by the hand that typed it, like
    /// every other typed name (`MemoryStore.addPerson`).
    @discardableResult
    func addTeller(named name: String) -> Subject? {
        guard let person = store.addPerson(named: name) else { return nil }
        chooseTeller(.person(person.id))
        return person
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
            // No archive and no photograph on this one. It re-runs the same
            // transcript with the names the teller has just fixed, and what is
            // wanted back is the memory's text with those names inflected into
            // it. The questions are already on screen and are not replaced, so
            // sending the context would be paying for aiming that is thrown
            // away — and the picture would be paying for it twice.
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

    /// "Not that one": the familiar name becomes a fresh proposal of its own,
    /// mentioned by this telling's memories instead of the family's card.
    func splitMention(_ subject: Subject) {
        guard let other = store.split(mention: subject.id, in: sessionMemoryIDs) else { return }
        known.removeAll { $0.id == subject.id }
        proposals.append(other)
        // The header names where the telling was filed; when that was the
        // familiar card, it is the new one now.
        if placedSubject?.id == subject.id { placedSubject = other }
    }

    func confirm(_ subject: Subject) {
        store.confirm(subjectID: subject.id)
        proposals.removeAll { $0.id == subject.id }
    }

    func reject(_ subject: Subject) {
        store.remove(subjectID: subject.id)
        proposals.removeAll { $0.id == subject.id }
    }

    /// Moves on to the next card. Only the deck calls this, and only from
    /// `.idle` — there is nothing to lose there, which is why it needs no
    /// guard of its own.
    func moveTo(_ subject: Subject?) {
        initialTarget = subject
        target = subject
        question = nil
    }

    func reset() {
        known = []
        sessionMemoryIDs = []
        voice.stop()
        leaveInterview()
        target = initialTarget
        // Through the same door as every other return to .idle, so the
        // question-resets-with-the-phase invariant is enforced by the call
        // graph rather than kept by two lines agreeing.
        returnToIdle()
        draft = ""
        transcript = nil
        result = nil
        wasOrganised = true
        placedSubject = nil
        proposals = []
        newQuestions = []
        replaced = []
        showsUpsell = false
        savedAudioDuration = nil
        savedMemoryID = nil
        completingMemoryID = nil
        editedNames = [:]
        // The next telling is asked about on its own: the phone may have
        // changed hands, which is the whole case this question is for.
        tellerChoice = nil
        placedTellerID = nil
    }
}
