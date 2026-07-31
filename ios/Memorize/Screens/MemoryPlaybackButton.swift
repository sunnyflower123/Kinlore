import SwiftUI

/// "Kuuntele omalla äänellä" — nappi joka oikeasti soittaa.
///
/// Nouto on tarvepohjainen: toisen perheenjäsenen nauhoitus on aluksi vain
/// R2-avain, ja se ladataan vasta kun joku painaa. Latauksen ajan nappi näyttää
/// etenemistä eikä jää tuntumaan rikkinäiseltä.
struct MemoryPlaybackButton: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(AudioPlayer.self) private var player

    let memory: Memory

    @State private var isLoading = false

    private var isPlaying: Bool { player.isPlaying(memory.id) }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                }

                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.tint)
            .elderTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Lopeta kuuntelu" : "Kuuntele omalla äänellä")
    }

    private var label: String {
        if isPlaying { return "Soi…" }
        guard let seconds = memory.audioDuration else { return "Kuuntele omalla äänellä" }
        return "Kuuntele omalla äänellä · \(Int(seconds)) s"
    }

    private func toggle() async {
        if isPlaying {
            player.stop()
            return
        }
        isLoading = true
        defer { isLoading = false }

        guard let filename = await MediaLoader.audioFilename(
            for: memory, store: store, session: session
        ) else { return }
        player.toggle(memoryID: memory.id, fileURL: MediaStore.url(for: filename))
    }
}
