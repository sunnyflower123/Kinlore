import AVFoundation
import Foundation

/// Nauhoitus ja äänitason mittaus.
///
/// Tason mittaus ei ole koristetta: se on ainoa palaute siitä että laite
/// kuulee. Hiljaa puhuva vanhus ei tiedä toimiiko mikrofoni, ja vaimeneva
/// aaltokuvio kertoo sen ilman että kenenkään tarvitsee lukea mitään.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Viimeisimmät tasonäytteet, uusin viimeisenä. 0…1.
    private(set) var levels: [Float] = []
    private(set) var lastRecordingURL: URL?

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?

    /// Näytteitä pidetään sen verran kuin aaltokuvioon mahtuu. Vanhat pois,
    /// jotta muistinkäyttö ei kasva pitkässä nauhoituksessa.
    private let maxLevels = 48

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
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

        // Puhe, ei musiikki: 22 kHz mono riittää ASR:lle ja pitää tiedostot
        // pieninä. Ääni säilytetään pysyvästi, joten koko kertyy ajan myötä.
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

    /// Palauttaa nauhoitetun tiedoston, tai nil jos nauhoitus oli liian lyhyt
    /// ollakseen mitään.
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

        // averagePower on desibeleissä, tyypillisesti −60…0. Normalisoidaan
        // niin että hiljainen puhe erottuu yhä täydestä hiljaisuudesta.
        let db = recorder.averagePower(forChannel: 0)
        let normalized = max(0, (db + 55) / 55)
        levels.append(normalized)
        if levels.count > maxLevels { levels.removeFirst(levels.count - maxLevels) }
    }
}
