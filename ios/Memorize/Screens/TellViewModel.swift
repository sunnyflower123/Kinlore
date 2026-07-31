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
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The text of a memory being typed.
    var draft = ""
    private(set) var transcript: String?
    private(set) var result: ExtractionResult?
    /// The subject the memory was filed under — the most important part of the
    /// result.
    private(set) var placedSubject: Subject?
    /// People and places proposed by the AI. The user confirms or rejects.
    private(set) var proposals: [Subject] = []
    private(set) var newQuestions: [FollowUpQuestion] = []
    /// The saved memory's duration, or nil if it was typed. The result screen
    /// shows playback only when there is audio.
    private(set) var savedAudioDuration: TimeInterval?
    private(set) var savedMemoryID: String?

    /// The saved memory itself. The result screen needs it for playback, not
    /// just the duration.
    var savedMemory: Memory? {
        guard let savedMemoryID else { return nil }
        return store.memories.first { $0.id == savedMemoryID }
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
    }

    // MARK: - Recording

    func startRecording() async {
        guard await recorder.requestPermission() else {
            phase = .failed("Mikrofonia ei saatu käyttöön. Salli mikrofoni asetuksista.")
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
            if isInterviewing {
                leaveInterview()
                phase = .done
            } else {
                phase = .idle
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
        guard phase == .done, let next = newQuestions.first else { return }
        isInterviewing = true
        await ask(next)
    }

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
        leaveInterview()
        if phase == .asking { phase = .done }
    }

    private func leaveInterview() {
        isInterviewing = false
        askedQuestion = nil
    }

    // MARK: - Typing

    func beginWriting() {
        draft = ""
        phase = .writing
    }

    func cancelWriting() {
        draft = ""
        phase = .idle
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
        do {
            transcript = text
            phase = .organizing
            let extracted = try await extraction.extract(transcript: text)
            result = extracted

            save(extracted, transcript: text, audioURL: audioURL, duration: duration)
            if isInterviewing, let next = newQuestions.first {
                // The loop feeds itself: this answer's extraction produced the
                // next questions. No result screen between rounds — proposals
                // pile up unconfirmed and are handled when the loop ends.
                await ask(next)
            } else {
                leaveInterview()
                phase = .done
            }
        } catch {
            leaveInterview()
            phase = .failed("Muiston järjestely ei onnistunut. Voit yrittää uudelleen.")
        }
    }

    /// Saves the audio alone, without transcription or extraction.
    ///
    /// The memory attaches to the target subject if one is known, otherwise to
    /// an event of its own. The text is left empty, and
    /// `isAwaitingTranscription` tells the UI that transcription is pending.
    private func saveAudioOnly(audioURL: URL, duration: TimeInterval) {
        let home = target ?? {
            let subject = Subject(kind: .event, title: "Kertomatta purettu muisto")
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
    private func markQuestionAnswered() {
        guard let question else { return }
        store.markAnswered(questionID: question.id)
    }

    private func save(
        _ extracted: ExtractionResult,
        transcript: String,
        audioURL: URL?,
        duration: TimeInterval?
    ) {
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
        proposals = mentioned.filter { !$0.confirmed }

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
            FollowUpQuestion(subjectID: home.id, text: $0)
        }
        store.add(questions: questions)
        newQuestions = questions
        markQuestionAnswered()
    }

    /// Finds or creates the subject the memory belongs to.
    private func placeSubject(for extracted: ExtractionResult, mentioned: [Subject]) -> Subject {
        let suggested = Self.suggestedTitle(for: extracted, mentioned: mentioned)

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

    /// A title from the place and the time: "Puumalassa, 1950-luku".
    /// Nil if neither came out of the speech — then it is more honest to leave
    /// it unnamed than to invent a title out of nothing.
    private static func suggestedTitle(
        for extracted: ExtractionResult,
        mentioned: [Subject]
    ) -> String? {
        var parts: [String] = []
        if let place = mentioned.first(where: { $0.kind == .place }) {
            parts.append(place.title)
        }
        if let hint = extracted.dateHint, hint.precision != .unknown {
            parts.append(hint.displayText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
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
                corrections: corrections
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
        placedSubject = nil
        proposals = []
        newQuestions = []
        savedAudioDuration = nil
        savedMemoryID = nil
        editedNames = [:]
    }
}
