import AVFoundation
import Foundation

/// Muistojen kuuntelu.
///
/// Yksi soitin koko sovellukselle: kaksi yhtäaikaista ääntä olisi sekaannus,
/// ja uuden aloittaminen lopettaa edellisen itsestään.
///
/// Tämä on se kohta jossa arkisto lakkaa olemasta tekstiä. Isoäidin ääni on
/// itsessään perintö — teksti on hakukelpoinen muoto siitä, ei korvaaja.
@MainActor
@Observable
final class AudioPlayer: NSObject {
    /// Soitettavan muiston tunniste, tai nil jos mikään ei soi.
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
            // `.playback` eikä `.ambient`: muiston kuuntelu on se mitä käyttäjä
            // juuri nyt tekee, ja se kuuluu myös äänettömällä kytkimellä.
            // Vanhus ei osaa etsiä miksi puhelin on hiljaa.
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
            // Rikkinäinen tai puuttuva tiedosto ei ansaitse virheruutua:
            // painallus ei vain tee mitään, ja teksti on yhä luettavissa.
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
