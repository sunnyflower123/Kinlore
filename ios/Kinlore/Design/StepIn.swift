import SwiftUI

/// Opening a photograph by stepping into it (27 Sep 2026). The picture grows
/// out of its tile to the top of its card, comes four per cent closer and
/// stops there, and only then does the rest of the card come in under it:
/// the date and the name, the button, what has been told.
///
/// Nothing keeps moving once it has arrived. A picture drifting on in front
/// of an eighty-year-old's eyes is the one thing this was not allowed to be,
/// which is why the approach stops and why there is no Ken Burns.
///
/// One place for all of it, because a photograph opens from more than one
/// place — the album's tiles, and every picture that opens to the whole
/// screen (`opensToTheWholeScreen`) — and every one of them should open the
/// same way. The picture it opens from takes `stepInSource(_:in:)`; the
/// screen it opens into takes `steppedInto(from:in:)`, which zooms and keeps
/// the time; the picture there takes `stepInApproach()`, and whatever comes
/// in under it `stepInFollows()`.
///
/// Reduce Motion takes the movement away and keeps the way in. The zoom
/// stays, because with Reduce Motion on the system draws it as a cross-fade,
/// the album and the card crossing in place (measured on iOS 26.5, 27 Sep
/// 2026); the approach and the rise are not drawn at all. Without the zoom
/// that setting got the sideways slide every other screen arrives with.
///
/// A pull down at the top of a card opened this way closes it: the card
/// shrinks back into its tile. That is the zoom's own gesture, and SwiftUI
/// has no switch for it — `interactiveDismissDisabled()` is for sheets and
/// changed nothing (measured 27 Sep 2026, SDK 27.0). The back button stays.
enum StepIn {
    /// How much closer the picture comes before it stops.
    static let approach: CGFloat = 1.04

    /// How far into its arrival an opened screen is. The default is a screen
    /// nobody stepped into: its picture as it is, everything under it in.
    struct Arrival: Equatable {
        var approached = false
        var followed = true
    }
}

extension EnvironmentValues {
    /// Where the screen around this view is in its arrival (`StepIn`).
    @Entry var stepIn = StepIn.Arrival()
}

extension View {
    /// The picture a photograph opens from, known by `id` in `namespace`. The
    /// zoom starts from its frame with a card's corner, which is the shape
    /// every picture in this app is shown in.
    @ViewBuilder
    func stepInSource(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: Elder.cardRadius, style: .continuous))
            }
        } else {
            self
        }
    }

    /// The screen a photograph opens into from the source with the same `id`:
    /// the zoom, and the time the picture and what follows it keep.
    func steppedInto(from id: some Hashable, in namespace: Namespace.ID) -> some View {
        modifier(StepInArrival(id: id, namespace: namespace))
    }

    /// The picture on the opened screen, 1.00 → 1.04 over 0.8 s. Put it
    /// before the picture's clip, which is what keeps the four per cent
    /// inside the frame.
    func stepInApproach() -> some View {
        modifier(StepInApproach())
    }

    /// Whatever comes in under the picture: 8 points up and in from nothing,
    /// from 380 to 700 ms, once the picture has most of its way behind it.
    func stepInFollows() -> some View {
        modifier(StepInFollows())
    }
}

private struct StepInArrival<ID: Hashable>: ViewModifier {
    let id: ID
    let namespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Held here, outside the list the card is drawn in, so that a row the
    /// list builds again after a scroll reads the arrival as it stands and
    /// does not arrive a second time.
    @State private var arrival = StepIn.Arrival(approached: false, followed: false)

    func body(content: Content) -> some View {
        transition(content)
            .environment(\.stepIn, reduceMotion ? StepIn.Arrival() : arrival)
            .onAppear {
                // Once. The card appears again when a card pushed over it is
                // closed, and by then it has long arrived.
                guard !arrival.followed else { return }
                withAnimation(.easeOut(duration: 0.8)) {
                    arrival.approached = true
                }
                withAnimation(.easeOut(duration: 0.32).delay(0.38)) {
                    arrival.followed = true
                }
            }
    }

    @ViewBuilder
    private func transition(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

private struct StepInApproach: ViewModifier {
    @Environment(\.stepIn) private var arrival

    func body(content: Content) -> some View {
        content.scaleEffect(arrival.approached ? StepIn.approach : 1)
    }
}

private struct StepInFollows: ViewModifier {
    @Environment(\.stepIn) private var arrival

    func body(content: Content) -> some View {
        content
            .opacity(arrival.followed ? 1 : 0)
            .offset(y: arrival.followed ? 0 : 8)
    }
}
