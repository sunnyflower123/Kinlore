import MapKit
import SwiftUI

/// Where a place is, for the places the app managed to find.
///
/// The coordinate has been in the model since places started being resolved —
/// `Subject.place`, written by `PlaceResolver` out of `PlaceLookup` — and until
/// now no screen showed it. A whole column of the archive was being collected
/// and never read.
///
/// **It costs nothing to draw.** Native MapKit needs no API key, no account
/// and no quota; that is why `PlaceLookup` geocodes with it rather than with a
/// service of our own, and the same is true of the view. The key-and-billing
/// story belongs to MapKit JS and the Apple Maps Server API, neither of which
/// is what a SwiftUI `Map` uses. It also asks for **no location permission**:
/// this draws a stored coordinate and never asks where the phone is, so there
/// is no `NSLocationWhenInUseUsageDescription` and no prompt.
///
/// **Precision decides what is drawn, and that is rule 5 made visible.** A pin
/// asserts a point. "Puumala" resolved to a municipality is not a point, and a
/// pin on one house inside it is the app rounding an uncertainty it was told
/// to keep — so a pin is only for `.exact`, a circle at the right scale stands
/// for `.town` and `.region`, and `.unknown` draws nothing at all. An empty
/// map of the wrong sea is worse than no map: it looks like an answer.
/// `GeoPrecision.mapSpanMetres` holds the numbers and
/// `scripts/place-map-check.swift` asserts them.
struct PlaceMapCard: View {
    let subject: Subject

    /// What a tap on the card does — in practice, open `PlacePinSheet` so that
    /// somebody who has stood in the yard can move the point to it.
    ///
    /// **Inside the card and not in a row of its own, which is a measurement
    /// rather than a preference.** Written as an ordinary row under the map it
    /// pushed the card's last memory sixty points down, to a bottom edge of
    /// **791.67 against a tab bar whose top is 791**, and
    /// `performAccessibilityAudit` reported that text as not supporting
    /// Dynamic Type — three runs red against one green on the same simulator
    /// at the same commit, so it was not the machine. An overlay costs no
    /// height and the finding goes with it.
    ///
    /// **Those two figures are written down rather than left in a session's
    /// notes because they are one of three findings that meet the same edge,
    /// and only the numbers make the set visible.** `AccessibilityAudit.swift`
    /// carries a note of 6 Sep 2026 about a name in `Elder.supporting` passing
    /// contrast near the top of a screen and failing at y 767–782 with the bar
    /// at 791; on 19 Sep 2026 a Section footer on the person card was read as
    /// `Text clipped` with its bottom edge at exactly 791.0, and adding a
    /// line's height to it changed neither the frame nor the finding. Three
    /// elements, three audit categories, one edge — which reads like one
    /// cause and is not one.
    ///
    /// For one of the three the pixels have since answered the question the
    /// audit cannot: that footer's sentence is drawn complete. A screenshot of
    /// it at `c1e5428`, read in five-point bands, has paper at 745–755, ink
    /// from 755.33 to 785.33 and paper again to the frame's bottom at 791 —
    /// two full lines ending 5.7 points above the bar, with plain paper in the
    /// gutters beside and below it. So that finding is the frame meeting the
    /// bar and not text a reader loses, and the 45.67 points are the footer's
    /// own padding around two lines rather than room for a third.
    ///
    /// **The second of the three has now been measured, and it answers the
    /// same way.** An A/B at `e5597dc`, in a worktree pinned to that commit
    /// and on a simulator of its own in Finnish, rebuilt the row form: two
    /// `.dynamicType` findings at the default size, twice over with frames
    /// identical to the decimal — *"Kuulin nämä"* at y 765.67 and the
    /// telling's own text at y 628 — against a green control on the shipping
    /// overlay. Sixty points of `contentMargins` at the list's end moved
    /// neither frame, because this list is not scrolled to its end; shortening
    /// the map from 220 to 160 did, and both frames rose exactly sixty points,
    /// to 705.67 and 568. Both findings stayed, and a third arrived on a row
    /// the shorter map had lifted into view. So the row is what introduces
    /// them and the bar is not what causes them — the shape the footer showed
    /// on the same day, reached from a different sentence. Height is not the
    /// answer either: that arm gives back every point the row took, and the
    /// findings do not care. What about the row does cause them is unmeasured.
    /// The overlay is green, and that is the whole of what is known.
    ///
    /// It is also the truer control. The map is the thing being corrected, so
    /// tapping the map is where the correction starts; the words in the corner
    /// are what stops that being a secret.
    ///
    /// Nil leaves the card exactly what it was: a drawing that takes no
    /// touches.
    var onPlace: (() -> Void)?

    var body: some View {
        if let place = subject.place, place.precision.mapSpanMetres != nil {
            if let onPlace {
                Button(action: onPlace) {
                    drawing(place)
                        // Without this the button has no tap region at all.
                        // Its whole label is a map that takes no touches (see
                        // `drawing`), so hit testing finds nothing inside it
                        // and the tap lands on the row behind — measured:
                        // every test that opens this screen failed at once,
                        // and not one of them failed on the button, which
                        // XCUITest could see and tap and which simply did
                        // nothing.
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spoken(place))
                .accessibilityHint("Avaa kartan, jolla paikan voi merkitä tarkemmin.")
            } else {
                drawing(place)
                    .accessibilityElement()
                    .accessibilityLabel(spoken(place))
            }
        }
    }

    /// What the card says it is showing. A pin is only ever for an exact
    /// answer; anything vaguer is a region, said out loud as one.
    private func spoken(_ place: PlaceHint) -> LocalizedStringKey {
        place.precision.deservesAPin
            ? "Tarkka sijainti kartalla"
            : "Suunnilleen tällä seudulla kartalla"
    }

    @ViewBuilder
    private func drawing(_ place: PlaceHint) -> some View {
        if let span = place.precision.mapSpanMetres {
            let centre = CLLocationCoordinate2D(
                latitude: place.latitude,
                longitude: place.longitude
            )
            Map(initialPosition: .region(MKCoordinateRegion(
                center: centre,
                latitudinalMeters: span,
                longitudinalMeters: span
            ))) {
                if place.precision.deservesAPin {
                    Marker(subject.title, coordinate: centre)
                        .tint(Elder.wax)
                } else {
                    // A third of the span, so the circle is plainly a region
                    // and plainly smaller than the map around it — a circle
                    // that fills its own frame reads as a pin drawn badly.
                    MapCircle(center: centre, radius: span / 3)
                        .foregroundStyle(Elder.wax.opacity(0.14))
                        .stroke(Elder.wax, lineWidth: 2)
                }
            }
            // Points of interest off: this is where a memory happened, and a
            // shoal of restaurant pins over it is somebody else's map.
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 220)
            // A card, not a toy. Panning it here would take the gesture from
            // the list underneath, and an 80-year-old who cannot get the page
            // to scroll again has lost the screen. That stays true now that a
            // tap opens a map which does pan: the panning happens on a screen
            // of its own, where nothing is underneath to lose.
            .allowsHitTesting(false)
            .overlay(alignment: .bottomTrailing) { invitation }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// The words in the corner, on wax so that they do not depend on what the
    /// map happens to draw underneath them: `Elder.cream` on `Elder.wax` is
    /// 5.59:1, and a label lying straight on tiles has no ratio anybody can
    /// state in advance.
    ///
    /// Present only when the card can be tapped, and worded by what is drawn:
    /// a circle is asking to become a point, a point is only being nudged.
    @ViewBuilder
    private var invitation: some View {
        if onPlace != nil, let place = subject.place {
            Text(place.precision.deservesAPin
                ? "Siirrä paikkaa kartalla"
                : "Merkitse tarkka paikka")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Elder.cream)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Elder.wax, in: RoundedRectangle(cornerRadius: 10))
                .padding(10)
        }
    }
}
