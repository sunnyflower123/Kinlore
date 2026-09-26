import AVFoundation
import Foundation
import UIKit

/// Recording and level metering.
///
/// The level meter is not decoration: it is the only feedback that the device
/// can hear. An elderly person speaking quietly does not know whether the
/// microphone works, and a fading waveform says so without anyone having to read
/// anything.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// The most recent level samples, newest last. 0…1.
    private(set) var levels: [Float] = []
    private(set) var lastRecordingURL: URL?

    /// Called at most once per recording, when an interrupted recording cannot
    /// go on: the phone call ended without permission to resume, or the system
    /// took the microphone away and never said so. The owner finishes the
    /// telling with everything captured — the same act as pressing stop —
    /// because the alternative is "Kuuntelen" standing over a dead microphone
    /// while an 80-year-old keeps talking to it, which is the one lie this
    /// screen must never tell.
    var onCut: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var isPausedByInterruption = false
    private var frozenTicks = 0
    private var hasCut = false

    /// Only as many samples are kept as fit in the waveform. Old ones are
    /// dropped, so memory use does not grow during a long recording.
    private let maxLevels = 48

    /// Whether the phone has not put the microphone question to this person yet.
    ///
    /// **Read, never requested.** Asking is what raises the system prompt, and
    /// the whole point of this property is to say something *before* that
    /// happens — a value that triggered the thing it describes would be useless
    /// on the one screen that needs it.
    ///
    /// `-mic unasked` forces it, for the same reason `-mic denied` exists: the
    /// state is real for exactly one press per install, and neither a test run
    /// nor a screenshot run can get back to it once it is gone.
    static var isPermissionUnasked: Bool {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "mic") {
        case "unasked": return true
        case "denied": return false
        default: break
        }
        #endif
        return AVAudioApplication.shared.recordPermission == .undetermined
    }

    func requestPermission() async -> Bool {
        #if DEBUG
        // `-mic denied`: refused without touching the device's own permission.
        // The screen behind a refusal is otherwise reachable only by answering a
        // system prompt with "Älä salli" and then digging the app back out of
        // iOS Settings by hand — which no test run and no screenshot run can do,
        // and which is why nothing had ever looked at it.
        //
        // There is deliberately no `-mic granted` beside it. It was tried, for
        // the test that records for real: returning true here skips the
        // *question* but not the *need*, and the system raises the same prompt
        // from `record()` itself a moment later — at a moment nothing controls.
        // A test that needs the grant answers the prompt instead; see
        // `AccessibilitySweepTests.testAudioSaved`.
        if UserDefaults.standard.string(forKey: "mic") == "denied" { return false }
        #endif
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.orphanPrefix)\(UUID().uuidString).m4a")

        // Speech, not music: 22 kHz mono is enough for ASR and keeps the files
        // small. The audio is kept permanently, so the size accumulates.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()

        self.recorder = recorder
        isRecording = true
        elapsed = 0
        levels = []
        isPausedByInterruption = false
        frozenTicks = 0
        hasCut = false

        // The screen must not go dark mid-telling. Without this, iOS's
        // auto-lock suspends the app a couple of minutes into exactly the
        // several-minute story this screen exists for, and the recording ends
        // with nothing anywhere to say so.
        UIApplication.shared.isIdleTimerDisabled = true

        // A phone call, an alarm, Siri: the system pauses the recorder, and
        // the waveform freezes while looking exactly like a quiet room. Resume
        // when the interruption ends with permission to; finish with what was
        // captured when it does not.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(
                rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            Task { @MainActor in self?.handleInterruption(type, options) }
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Returns the recorded file, or nil if the recording was too short to be
    /// anything.
    @discardableResult
    func stop() -> URL? {
        UIApplication.shared.isIdleTimerDisabled = false
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        isPausedByInterruption = false
        ticker?.invalidate()
        ticker = nil
        recorder?.stop()
        let url = recorder?.url
        let duration = elapsed
        recorder = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url, duration >= 1.0 else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        lastRecordingURL = url
        return url
    }

    private func handleInterruption(
        _ type: AVAudioSession.InterruptionType?,
        _ options: AVAudioSession.InterruptionOptions
    ) {
        guard isRecording else { return }
        switch type {
        case .began:
            // The system has already paused the recorder. Remembering why
            // keeps the watchdog in `tick` from reading a phone call as a
            // dead microphone and cutting a telling that may still resume.
            isPausedByInterruption = true
        case .ended:
            isPausedByInterruption = false
            if options.contains(.shouldResume), recorder?.record() == true {
                // Resumed into the same file: the call is a gap in the
                // audio, not the end of the telling.
            } else {
                cut()
            }
        default:
            break
        }
    }

    /// Ends the telling with everything captured so far, exactly once.
    private func cut() {
        guard !hasCut, isRecording else { return }
        hasCut = true
        onCut?()
    }

    /// The recording's filename shape, shared with the launch-time sweep
    /// below: what start() writes is what the sweep looks for.
    ///
    /// And with `MediaStore.deleteAll`, which is the other end of the same
    /// fact: `TellViewModel.persistAudio` moves the file into Documents under
    /// the name given here, so a recording made on this phone is not a
    /// `media-` file and a sweep that looked only for those would leave every
    /// one of them behind — grandmother's voice, which is the thing rule 3 is
    /// about.
    ///
    /// `nonisolated` because a string constant needs no actor, the same
    /// reason `Session.arrivalPendingKey` carries it: `MediaStore` is not on
    /// the main actor and has to be able to read this.
    nonisolated static let orphanPrefix = "memory-"

    private func tick() {
        guard let recorder else { return }
        guard recorder.isRecording else {
            // Our flag says recording, the system's says not: the frozen
            // state — elapsed stopped, waveform flat, the screen claiming
            // "Kuuntelen" over a microphone that is not listening. During a
            // signalled interruption that is a wait, because the call may end
            // with permission to resume. Without one, two seconds is long
            // enough to know no resume is coming, and the honest end is the
            // same as pressing stop: keep everything that was captured.
            if !isPausedByInterruption {
                frozenTicks += 1
                if frozenTicks == 40 { cut() }
            }
            return
        }
        frozenTicks = 0
        recorder.updateMeters()
        elapsed = recorder.currentTime

        // averagePower is in decibels, typically −60…0. Normalised so that quiet
        // speech still stands out from complete silence.
        let db = recorder.averagePower(forChannel: 0)
        let normalized = max(0, (db + 55) / 55)
        levels.append(normalized)
        if levels.count > maxLevels { levels.removeFirst(levels.count - maxLevels) }
    }
}

/// The telling the app was killed under.
///
/// The recorder writes into the temporary directory and nothing references the
/// file until stop() — so a crash, a force-quit or a low-memory kill
/// mid-telling left an m4a nobody would ever find, and the system's tmp
/// cleanup eventually made "gone without a trace" literal. Swept at launch:
/// every orphaned recording becomes the same audio-only memory a quota outage
/// leaves behind, and the catch-up writes its text on the app's own schedule —
/// rule 3's spirit applied to the file that never got as far as the rules.
@MainActor
enum RecordingRecovery {
    /// The recordings tmp held before this launch could make one of its own —
    /// the only files the sweep may touch.
    ///
    /// The sweep used to list tmp for itself, from the launch task, once the
    /// calls ahead of it there had waited on the network: as late as the
    /// network made it. The recorder writes into the same directory under the
    /// same prefix, so a telling started in the meantime looked exactly like
    /// one the app had been killed under. Mid-recording the file is a header
    /// nothing can open — 28 bytes a second into a telling — and the sweep
    /// deleted it as not audio; between the stop and the save it is a
    /// finished recording, and the sweep adopted it, after which
    /// `persistAudio`, clearing that name in Documents out of its own way,
    /// deleted the adopted copy. Either way the telling was gone. Found
    /// 26 Sep 2026, when `export-check.mjs`, whose `-defer once` records at
    /// launch, came back with no audio in the export.
    ///
    /// Leaving out the file the recorder has open would answer the first case
    /// and not the second, since by then nothing has it open. A list taken in
    /// `KinloreApp.init`, before `body` has built the screen that records,
    /// answers both by construction: nothing this launch writes can be on it,
    /// however late the sweep runs. What this launch leaves behind is the next
    /// launch's to find, which is when a killed telling was always found.
    ///
    /// Nil until then, and a sweep without a list touches nothing.
    private static var orphans: [String]?

    /// Called once, from `KinloreApp.init`.
    static func listOrphans() {
        guard orphans == nil else { return }
        #if DEBUG
        if UserDefaults.standard.string(forKey: "recovery") == "orphan" { leaveOrphanForTests() }
        #endif
        let tmp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        orphans = names.filter { $0.hasPrefix(AudioRecorder.orphanPrefix) && $0.hasSuffix(".m4a") }
    }

    static func sweep(into store: MemoryStore) {
        let tmp = FileManager.default.temporaryDirectory
        // Taken rather than read, so a second sweep has nothing to look at.
        let names = orphans ?? []
        orphans = []
        for name in names {
            let source = tmp.appendingPathComponent(name)
            // The same floor as a live recording: under a second is an
            // accident, not a memory — and an unreadable file is not audio.
            let duration = (try? AVAudioPlayer(contentsOf: source))?.duration ?? 0
            guard duration >= 1.0 else {
                try? FileManager.default.removeItem(at: source)
                continue
            }
            let destination = MediaStore.url(for: name)
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.moveItem(at: source, to: destination)) != nil else {
                continue
            }
            // The shape saveAudioOnly gives a telling whose words never
            // arrived: an untitled event — describe fills empty fields only,
            // so the name comes with the text — and a memory the row shows
            // as "Ääni tallessa" until the catch-up finishes it.
            let home = Subject(kind: .event, title: "")
            store.add(home)
            store.add(Memory(
                subjectID: home.id,
                authorName: store.authorName,
                body: "",
                audioFilename: name,
                audioDuration: duration,
                source: .voice
            ))
        }
    }

    #if DEBUG
    /// `-recovery orphan`: a finished two-second recording in tmp before the
    /// list is taken, as a launch killed between the stop and the save leaves
    /// one. It keeps the other half of the fix above true — that the sweep
    /// still takes in what an earlier launch left, and not merely nothing.
    /// `SilentFailureTests.testARecordingAnEarlierLaunchLeftBehindIsTakenIn`.
    private static func leaveOrphanForTests() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AudioRecorder.orphanPrefix)\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings),
              let silence = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44_100),
              let samples = silence.floatChannelData?[0]
        else { return }
        samples.update(repeating: 0, count: 44_100)
        silence.frameLength = 44_100
        // Written in full when `file` is released at the end of this scope,
        // which is what makes it a finished recording rather than a live one.
        try? file.write(from: silence)
    }
    #endif
}
