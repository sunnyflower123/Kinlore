import AVFoundation
import Foundation

/// Reads the interview loop's questions aloud.
///
/// On-device synthesis rather than a server voice: it works at a summer cottage
/// without signal, costs nothing per question, and the question text never
/// leaves the device just to become sound. A server voice would sound better,
/// but the voice that matters in this app is grandmother's, not ours.
@MainActor
@Observable
final class InterviewVoice: NSObject {
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: CheckedContinuation<Bool, Never>?
    /// Identifies the utterance the pending continuation belongs to. `stop()`
    /// resolves the waiter immediately and the synthesizer's cancel callback
    /// arrives later — callbacks for anything but the current utterance are
    /// stale and ignored.
    private var currentID: ObjectIdentifier?

    /// Speaks one question. Returns true when it was spoken to the end, false
    /// when it was interrupted or the audio session failed. The caller uses
    /// the difference to decide whether recording may start by itself.
    func speak(_ text: String) async -> Bool {
        stop()
        synthesizer.delegate = self

        do {
            // `.playback`, as in AudioPlayer: the question must be heard even
            // with the silent switch on. An elderly person will not know to go
            // looking for why the phone says nothing.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // No sound is not a failure of the flow: the question is on the
            // screen and the record button works. Speech is the enhancement.
            return false
        }

        let utterance = AVSpeechUtterance(string: text)
        // The system's Finnish voice. On a non-Finnish device this is nil and
        // the system default reads with an accent — worse than a Finnish
        // voice, better than silence.
        utterance.voice = AVSpeechSynthesisVoice(language: "fi-FI")
        // A touch slower than the default, for the same reason the tap targets
        // are a third larger than Apple's minimum.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        // A short breath, so the question does not fire the very instant the
        // previous phase ends.
        utterance.preUtteranceDelay = 0.35

        currentID = ObjectIdentifier(utterance)
        isSpeaking = true
        return await withCheckedContinuation { continuation in
            pending = continuation
            synthesizer.speak(utterance)
        }
    }

    /// Stops mid-sentence and resolves the waiter right away. Safe to call
    /// when nothing is playing.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        resolve(completed: false)
    }

    private func resolve(completed: Bool) {
        guard pending != nil else { return }
        isSpeaking = false
        currentID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        pending?.resume(returning: completed)
        pending = nil
    }
}

extension InterviewVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.currentID else { return }
            self.resolve(completed: true)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.currentID else { return }
            self.resolve(completed: false)
        }
    }
}
