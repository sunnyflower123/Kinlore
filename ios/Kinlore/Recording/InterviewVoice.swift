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

    /// The language the questions are written in.
    ///
    /// Finnish, because every string in this app is. It is a constant here
    /// rather than a literal at the point of use so that there is one place to
    /// change rather than a search, and so that the voice follows the words
    /// instead of being decided separately from them. A Finnish voice reading
    /// an English sentence is not an accent: it applies one language's phonemes
    /// to another language's spelling, and for somebody who is 80 and listening
    /// rather than reading, that is close to noise.
    ///
    /// The same rule the pipeline uses to choose the prompt (`SpokenLanguage`):
    /// the questions come back in the speaker's language, and the speaker's
    /// language is the phone's. Hardcoded "fi-FI" read every English question
    /// with Finnish phonemes, which for somebody listening rather than reading
    /// is close to noise (founder's-eye review, 3 Sep 2026, finding #95). The
    /// device's own English variant when it has one, so an American phone is
    /// not read to in British.
    nonisolated static var questionLanguage: String {
        if SpokenLanguage.current == "fi" { return "fi-FI" }
        let preferred = Locale.preferredLanguages.first ?? "en-GB"
        return preferred.hasPrefix("en") ? preferred : "en-GB"
    }

    /// The voice to read `language` with: the system's own choice, upgraded to
    /// a better recording of that same speaker if one has been downloaded.
    ///
    /// `AVSpeechSynthesisVoice(language:)` returns the system's default voice
    /// for a language, and on a stock device that is the compact one. Apple
    /// ships enhanced and premium versions of the same voices as free
    /// downloads, and the difference is not cosmetic: a compact voice asking a
    /// question of somebody with poor hearing is the same kind of failure as
    /// text below the contrast minimum, and it is one this app can fix for
    /// nothing when the download is already on the phone.
    ///
    /// **It upgrades the speaker, it does not replace them.** The first version
    /// of this took the highest-quality voice for the language and broke the
    /// tie alphabetically, and on this machine that answered `Eddy` for every
    /// language: nine en-GB voices, all of them `.default`, and the novelty
    /// ones sort first. A question read by a cartoon is a worse outcome than
    /// the compact voice it replaced, and nothing would have said so out loud.
    /// So the candidates are only the same-named voice at a higher quality, and
    /// when there is none the system's pick stands untouched.
    ///
    /// Returns nil only when the device has no voice for that language at all.
    /// The system default then reads it with an accent, which is worse than a
    /// right voice and better than silence.
    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        guard let system = AVSpeechSynthesisVoice(language: language) else { return nil }
        let better = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.name == system.name && $0.quality.rawValue > system.quality.rawValue }
            // Identifier breaks a tie so two phones with the same downloads
            // make the same choice rather than whichever the array listed first.
            .sorted {
                $0.quality.rawValue == $1.quality.rawValue
                    ? $0.identifier < $1.identifier
                    : $0.quality.rawValue > $1.quality.rawValue
            }
        return better.first ?? system
    }

    /// Speaks one question. Returns true when it was spoken to the end, false
    /// when it was interrupted or the audio session failed. The caller uses
    /// the difference to decide whether recording may start by itself.
    ///
    /// `language` defaults to the language the questions are written in, so
    /// every existing caller keeps working; it is a parameter rather than a
    /// constant inside because the day a question arrives in another language,
    /// the wrong thing to do is read it with this one's mouth.
    func speak(_ text: String, language: String = InterviewVoice.questionLanguage) async -> Bool {
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
        utterance.voice = InterviewVoice.voice(for: language)
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
