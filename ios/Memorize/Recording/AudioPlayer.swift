import AVFoundation
import Foundation

/// Listening to memories.
///
/// One player for the whole app: two simultaneous sounds would be confusing, and
/// starting a new one stops the previous by itself.
///
/// This is the point where the archive stops being text. Grandmother's voice is
/// itself the inheritance — the text is a searchable form of it, not a
/// replacement.
@MainActor
@Observable
final class AudioPlayer: NSObject {
    /// The id of the memory being played, or nil if nothing is playing.
    private(set) var playingMemoryID: String?
    private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    func isPlaying(_ memoryID: String) -> Bool {
        playingMemoryID == memoryID
    }

    func toggle(memoryID: String, fileURL: URL) {
        if playingMemoryID == memoryID {
            stop()
            return
        }
        stop()

        do {
            // `.playback` rather than `.ambient`: listening to a memory is what
            // the user is doing right now, and it plays even with the silent
            // switch on. An elderly person will not know to look for why the
            // phone is quiet.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.play()
            self.player = player
            playingMemoryID = memoryID
            progress = 0

            ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            // A broken or missing file does not deserve an error screen: the tap
            // simply does nothing, and the text is still readable.
            stop()
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        playingMemoryID = nil
        progress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tick() {
        guard let player, player.isPlaying, player.duration > 0 else { return }
        progress = player.currentTime / player.duration
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
