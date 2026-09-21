import MapKit
import SwiftUI

/// The family's places on one map, every one of them a door to the card
/// that already exists.
///
/// ARCHITECTURE §18 said until 21 Sep 2026 that there was no screen of
/// places and that the absence was deliberate; PLAN.md §5 keeps the reasons,
/// and its condition that a browsable map "owes its own removal" is still
/// owed. The founder asked for the map on 21 Sep, and this is the cheapest
/// shape it has: nothing new is stored or fetched, and nothing is drawn here
/// that `PlaceMapCard` does not already draw. Each confirmed place with a
/// coordinate is drawn by the card's rule — a pin for an exact answer, a
/// circle a third of the span for a municipality (rule 5) — and carries a
/// chip with its name and how many memories it holds. The chip is a
/// `NavigationLink` to the same `SubjectDetailScreen` the Paikat list opens,
/// pushed on the same stack, so the back chevron and the list underneath
/// are unchanged.
///
/// The Paikat list stays. This is a third way to the same card, not the only
/// one: VoiceOver walks the list, and a place without a coordinate — nine of
/// the ten in production on 21 Sep 2026 — is on the list and not here.
struct PlacesMapScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The same filter as `GalleryScreen.places`, narrowed to what has
    /// somewhere to be drawn.
    private var places: [Subject] {
        store.subjects(of: .place)
            .filter { $0.confirmed && $0.place?.precision.mapSpanMetres != nil }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                pictureAndRows
            } else {
                map(withChips: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Kartta. Jokainen paikka on nappi, joka avaa paikan kortin.")
            }
        }
        .navigationTitle("Kartta")
        .navigationBarTitleDisplayMode(.inline)
        .elderSurface()
    }

    /// At the accessibility text sizes the chips give way to the album's own
    /// rows under a map that is a picture.
    ///
    /// Measured 21 Sep 2026 on the film-week archive at
    /// `accessibilityExtraExtraExtraLarge`, six launches on one build: a chip
    /// is 215–290 pt wide on a 402 pt screen, Sulkava's lay across
    /// Savonlinna's at every framing tried, and MapKit's annotation
    /// container leaves a chip that crosses the edge of the map out of the
    /// accessibility tree — Savonlinna's was absent at 1.5, 2.0 and 2.5 times
    /// the spread, Puumala's at 1.5. So VoiceOver was offered one place of
    /// three and a sighted reader two names on top of each other, and
    /// zooming out cannot fix what zooming out causes. The rows are
    /// `SubjectRow`, the album's own, so this list and the Paikat list are
    /// the same list (rule 1 is why they are here at all). The map above
    /// them shows where and the rows say which; it does not pan, for the
    /// place card's reason (`PlaceMapCard`): a map that takes the drag takes
    /// the page's scroll with it.
    private var pictureAndRows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                map(withChips: false)
                    .frame(height: 300)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement()
                    .accessibilityLabel("Kartta perheen paikoista.")
                ForEach(places) { subject in
                    NavigationLink(value: subject) {
                        SubjectRow(subject: subject)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Elder.screenPadding)
        }
    }

    private func map(withChips: Bool) -> some View {
        Map(initialPosition: Self.framing(places.compactMap(\.place))) {
            ForEach(places) { subject in
                if let place = subject.place, let span = place.precision.mapSpanMetres {
                    let centre = CLLocationCoordinate2D(
                        latitude: place.latitude,
                        longitude: place.longitude
                    )
                    // The card's rule, not a second one: a pin only ever for
                    // an exact answer, a circle for anything vaguer.
                    if place.precision.deservesAPin {
                        Marker(subject.displayTitle, coordinate: centre)
                            .tint(Elder.wax)
                            .annotationTitles(.hidden)
                    } else {
                        MapCircle(center: centre, radius: span / 3)
                            .foregroundStyle(Elder.wax.opacity(0.14))
                            .stroke(Elder.wax, lineWidth: 2)
                    }
                    if withChips {
                        // Above the point rather than on it, so that what the
                        // card draws stays in view: centred on a municipality
                        // the chip covered the whole circle at the framing
                        // below (screenshotted 21 Sep 2026), and a map on
                        // which every place looks exact is rule 5 rounded
                        // by the layout.
                        Annotation(coordinate: centre, anchor: .bottom) {
                            chip(for: subject)
                                .padding(.bottom, place.precision.deservesAPin ? 40 : 8)
                        } label: {
                            Text(verbatim: subject.displayTitle)
                        }
                        // The chip already says the name; the map's own
                        // caption under it would say it twice.
                        .annotationTitles(.hidden)
                    }
                }
            }
        }
        // Points of interest off, for the card's reason: this is where the
        // family's memories happened, and a shoal of restaurant pins over
        // them is somebody else's map.
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    /// The place's name and how many memories it holds, on wax so that the
    /// words do not depend on what the map draws underneath them:
    /// `Elder.cream` on `Elder.wax` is 5.59:1, and text lying straight on
    /// tiles has no ratio anybody can state in advance. Counted the way the
    /// place's row on the album counts (`SubjectRow`), so the two agree.
    private func chip(for subject: Subject) -> some View {
        let count = store.memories(for: subject.id).count
        return NavigationLink(value: subject) {
            VStack(spacing: 2) {
                Text(verbatim: subject.displayTitle)
                    .font(.headline)
                if count == 1 {
                    Text("1 muisto")
                        .font(.subheadline)
                } else if count > 1 {
                    Text("\(count) muistoa")
                        .font(.subheadline)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Elder.cream)
            // At its own size, whatever the annotation's host proposes.
            // Measured 21 Sep 2026, six chip variants on one build: without
            // this the audit reported every chip as "Text clipped" at the
            // default size — a 97 × 60 pt button around a name drawn whole —
            // and the finding was indifferent to the minimum frame, to
            // `.combine` and to `NavigationLink` against `Button`. This one
            // modifier removed it.
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minWidth: Elder.minTapTarget, minHeight: Elder.minTapTarget)
            .background(Elder.wax, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Avaa paikan kortin.")
    }

    /// How much wider than the places' spread the first framing is.
    ///
    /// The outermost place then sits 22 % of the width in from the edge —
    /// 89 pt on a 402 pt screen — which is more than half of the widest chip
    /// at the largest text size the chips are drawn at: the headline grows
    /// from 17 to 23 pt at `xxxLarge`, so a chip 115 pt wide at the default
    /// size is about 150 there. It matters because MapKit's annotation
    /// container leaves a chip that crosses the edge out of the
    /// accessibility tree (measured 21 Sep 2026: at 1.5 the outermost place
    /// sat 67 pt in, and Puumala's chip was absent from the tree at the
    /// largest size and present at 2.0, before that size was given rows).
    static let framingMargin = 1.8

    /// Where the camera starts: every place at once, with room around the
    /// outermost for its chip.
    ///
    /// The spread of the places plus the largest single span, so that one
    /// municipality on its own is framed the way its card frames it and three
    /// of them are framed together, then `framingMargin` times that. A region
    /// and not `.automatic`, because `.automatic` frames the coordinates and
    /// not the chips drawn around them, and a chip cut by the edge of the
    /// screen is a button that cannot be read.
    static func framing(_ hints: [PlaceHint]) -> MapCameraPosition {
        let drawable = hints.filter { $0.precision.mapSpanMetres != nil }
        guard let first = drawable.first else { return .automatic }
        var south = first.latitude, north = first.latitude
        var west = first.longitude, east = first.longitude
        var largestSpan = 0.0
        for hint in drawable {
            south = min(south, hint.latitude)
            north = max(north, hint.latitude)
            west = min(west, hint.longitude)
            east = max(east, hint.longitude)
            largestSpan = max(largestSpan, hint.precision.mapSpanMetres ?? 0)
        }
        let centre = CLLocationCoordinate2D(
            latitude: (south + north) / 2,
            longitude: (west + east) / 2
        )
        // One degree of latitude is 111 km everywhere; one degree of
        // longitude shrinks with the cosine of the latitude, and at Puumala
        // it is under half of that.
        let metresPerDegreeLatitude = 111_000.0
        let metresPerDegreeLongitude = metresPerDegreeLatitude * cos(centre.latitude * .pi / 180)
        let side = max(
            (north - south) * metresPerDegreeLatitude,
            (east - west) * metresPerDegreeLongitude
        ) + largestSpan
        return .region(MKCoordinateRegion(
            center: centre,
            latitudinalMeters: side * framingMargin,
            longitudinalMeters: side * framingMargin
        ))
    }
}

#Preview {
    NavigationStack {
        PlacesMapScreen()
            .environment(MemoryStore(filename: "preview-store.json"))
    }
}
