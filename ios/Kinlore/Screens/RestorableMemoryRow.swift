import SwiftUI

/// A telling its teller took back, offered back to them from the card it was
/// filed under: for thirty days (`MemoryStore.restorationWindow`), on this
/// phone's own tellings only, and as a quiet row where the card's memories
/// end rather than a list of its own (ARCHITECTURE §19).
///
/// It is the promise the dialog that takes a telling away makes, kept: *"voit
/// palauttaa sen tältä kortilta 30 päivän ajan"*. So it sits in both of the
/// card's shapes — under the tellings, and alone on a card whose only telling
/// was taken back.
///
/// Bringing back asks nothing first. It is the reversible half of a pair: a
/// telling brought back by mistake can be taken back again, and the question
/// belongs to the act that hides something from the family, not to the one
/// that undoes it. Two lines rather than one, so that the date and the button
/// have room at every text size; the button carries the date in what
/// VoiceOver reads, because a card may hold more than one of these.
struct RestorableMemoryRow: View {
    @Environment(MemoryStore.self) private var store
    let memory: Memory

    private var takenBack: String {
        (memory.deletedAt ?? .now).formatted(date: .numeric, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Poistettu \(takenBack)")
                .elderBody()
                .foregroundStyle(Elder.supporting)
            Button("Palauta") { store.restore(memoryID: memory.id) }
                .buttonStyle(.borderless)
                .font(.body.weight(.medium))
                // Ink, as every text button is: left to the accent it read
                // in the red of *Poista tämä muisto* (`Elder.wax`), and a way
                // back must not look like a removal.
                .foregroundStyle(Color.primary)
                .elderTapTarget()
                .accessibilityLabel("Palauta muisto, poistettu \(takenBack)")
                .accessibilityIdentifier("card.restoreMemory")
        }
        .padding(.vertical, 6)
    }
}
