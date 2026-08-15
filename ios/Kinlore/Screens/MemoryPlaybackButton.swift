import SwiftUI

/// "Kuuntele omalla äänellä" — the button that actually plays.
///
/// Fetching is on demand: another family member's recording is at first only an
/// R2 key, and it is downloaded when someone taps. While it downloads the button
/// shows progress rather than feeling broken.
struct MemoryPlaybackButton: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(AudioPlayer.self) private var player

    let memory: Memory

    @State private var isLoading = false

    /// What went wrong on the last tap, or nil.
    ///
    /// The button used to answer both failures with nothing at all: no state
    /// changed, no sound came, and the tap was indistinguishable from a phone on
    /// silent or a finger that missed. This is the control that plays a dead
    /// person's voice — it is the last one in the app that should leave somebody
    /// wondering whether they pressed it.
    @State private var failure: String?

    private var isPlaying: Bool { player.isPlaying(memory.id) }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    // The shape says which of the three states this is, not the
                    // colour: play, stop, or something that did not work.
                    Image(systemName: symbol)
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                }

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(failure == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(Elder.supporting))
            .elderTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbol: String {
        if failure != nil { return "exclamationmark.triangle" }
        return isPlaying ? "stop.circle.fill" : "play.circle.fill"
    }

    private var label: String {
        if let failure { return failure }
        if isPlaying { return "Soi…" }
        guard let seconds = memory.audioDuration else { return "Kuuntele omalla äänellä" }
        return "Kuuntele omalla äänellä · \(Int(seconds)) s"
    }

    private var accessibilityLabel: String {
        if let failure { return failure }
        return isPlaying ? "Lopeta kuuntelu" : "Kuuntele omalla äänellä"
    }

    private func toggle() async {
        if isPlaying {
            player.stop()
            return
        }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        guard let filename = await MediaLoader.audioFilename(
            for: memory, store: store, session: session
        ) else {
            // The recording is not lost — it is in R2 and this phone could not
            // reach it. Saying "yritä uudelleen" matters more than saying why:
            // the next tap on a working connection simply works.
            failure = "Ääntä ei saatu haettua — yritä uudelleen"
            return
        }
        if !player.toggle(memoryID: memory.id, fileURL: MediaStore.url(for: filename)) {
            // A different thing entirely, and a retry will not help: the file is
            // here and it will not play.
            failure = "Tätä äänitystä ei saatu soimaan"
        }
    }
}
