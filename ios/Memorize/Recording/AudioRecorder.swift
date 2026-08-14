import AVFoundation
import Foundation

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

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?

    /// Only as many samples are kept as fit in the waveform. Old ones are
    /// dropped, so memory use does not grow during a long recording.
    private let maxLevels = 48

    func requestPermission() async -> Bool {
        #if DEBUG
        // `-mic denied`: refused without touching the device's own permission.
        // The screen behind a refusal is otherwise reachable only by answering a
        // system prompt with "Älä salli" and then digging the app back out of
        // iOS Settings by hand — which no test run and no screenshot run can do,
        // and which is why nothing had ever looked at it.
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
            .appendingPathComponent("memory-\(UUID().uuidString).m4a")

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

        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Returns the recorded file, or nil if the recording was too short to be
    /// anything.
    @discardableResult
    func stop() -> URL? {
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

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
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
