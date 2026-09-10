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

    var body: some View {
        if let place = subject.place, let span = place.precision.mapSpanMetres {
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // A card, not a toy. Panning it here would take the gesture from
            // the list underneath, and an 80-year-old who cannot get the page
            // to scroll again has lost the screen. Opening a full map is its
            // own decision and is not made here.
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(place.precision.deservesAPin
                ? "Tarkka sijainti kartalla"
                : "Suunnilleen tällä seudulla kartalla")
        }
    }
}
