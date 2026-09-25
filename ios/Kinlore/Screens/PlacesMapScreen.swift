import MapKit
import SwiftUI

/// What opens the family's map, and where it opens.
///
/// A value on the navigation path rather than a Boolean, so that the map lives
/// on the same `NavigationStack` as the cards it opens and the back chevron
/// walks back through both (see `GalleryScreen.path`). Both stacks that can
/// show a place card register it (`placesMapDestinations`): the album's, and
/// Ihmiset's, where a place card is reached through a person's memories.
struct PlacesMapRoute: Hashable {
    /// The place the map opens centred on, by subject id — what a place
    /// card's own small map asks for. Nil opens on every place at once, which
    /// is what the album's two doors ask for.
    var focus: String?
}

extension View {
    /// The family's map, on a stack that shows place cards.
    func placesMapDestinations() -> some View {
        navigationDestination(for: PlacesMapRoute.self) { route in
            PlacesMapScreen(route: route)
        }
    }
}

/// The family's places on one map, every one of them a door to the card
/// that already exists.
///
/// ARCHITECTURE §18 said until 21 Sep 2026 that there was no screen of
/// places and that the absence was deliberate; PLAN.md §5 keeps the reasons,
/// and its condition that a browsable map "owes its own removal" is still
/// owed. The founder asked for the map on 21 Sep, and asked on 25 Sep for it
/// to be somewhere a person finds without looking for it — the album's top
/// bar — and for looking at it to move nothing. Each confirmed place with a
/// coordinate is drawn by the card's rule — a pin for an exact answer, a
/// circle a third of the span for a municipality (rule 5) — and carries a
/// chip with its name and how many memories it holds. The chip is a
/// `NavigationLink` to the same `SubjectDetailScreen` the Paikat list opens,
/// pushed on the same stack, so the back chevron and the list underneath
/// are unchanged.
///
/// **Looking is not editing.** The mark that corrected a place used to sit in
/// the middle of the screen and read its point off the camera
/// (`PlacePinSheet`), so every pan was also a move and nobody could look
/// around a place without moving it. Here the camera is only a camera: it
/// can be dragged and pinched anywhere, and no point changes until somebody
/// asks for that with "Muuta sijaintia".
///
/// **Opened from a place card, the map is about that place.** The camera
/// starts on it (`framing(focus:among:)`), its own chip is left off because
/// the panel under the map names it and the chip would lead back to the
/// card just left, and the panel says how sure the archive is of the point:
/// the same two words the card's map says out loud, and where the point came
/// from.
///
/// The Paikat list stays. This is a third way to the same card, not the only
/// one: VoiceOver walks the list, and a place without a coordinate — nine of
/// the ten in production on 21 Sep 2026 — is on the list and not here.
struct PlacesMapScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The place the panel speaks for, by subject id. The route's to begin
    /// with, and let go by "Näytä kaikki paikat".
    @State private var focus: String?
    /// Where the map is looking. A binding rather than `initialPosition`, so
    /// that "Näytä kaikki paikat" can move it — and so that coming back from a
    /// card finds the map where it was left rather than framed again.
    @State private var camera: MapCameraPosition = .automatic
    @State private var hasFramed = false
    /// "Muuta sijaintia": the sheet the card used to open.
    @State private var isPinning = false

    init(route: PlacesMapRoute) {
        _focus = State(initialValue: route.focus)
    }

    /// The same filter as `GalleryScreen.places`, narrowed to what has
    /// somewhere to be drawn.
    private var places: [Subject] {
        store.subjects(of: .place)
            .filter { $0.confirmed && $0.place?.precision.mapSpanMetres != nil }
    }

    /// The place the map was opened on, as the store has it now: a point
    /// moved on another phone while the map is open is the point drawn. Only
    /// while it has something to draw — a focus on nothing is no focus.
    private var focused: Subject? {
        guard let focus, let subject = store.subject(id: focus),
              subject.place?.precision.mapSpanMetres != nil
        else { return nil }
        return subject
    }

    /// What the map draws: the family's places, and the place it was opened
    /// on even before anybody has confirmed it. That place's own card draws
    /// it already, and a map opened on a place that is missing from it reads
    /// as a map that failed. It gets no chip and no row; the panel is what
    /// names it.
    private var drawn: [Subject] {
        guard let focused, !places.contains(where: { $0.id == focused.id }) else { return places }
        return places + [focused]
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                pictureAndRows
            } else {
                map(withChips: true)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Kartta. Jokainen paikka on nappi, joka avaa paikan kortin.")
                    .safeAreaInset(edge: .bottom) {
                        panel
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
            }
        }
        .navigationTitle("Kartta")
        .navigationBarTitleDisplayMode(.inline)
        .elderSurface()
        .onAppear {
            // Once. A pop back from a card is the same visit, and the map
            // stays where it was left.
            guard !hasFramed else { return }
            hasFramed = true
            camera = startingFrame
        }
        // Framed again on the point that was saved, so the move is seen.
        .sheet(isPresented: $isPinning, onDismiss: {
            withAnimation { camera = startingFrame }
        }) {
            if let subject = focused, let place = subject.place {
                PlacePinSheet(subject: subject, place: place)
            }
        }
    }

    /// The focused place with its neighbours around it, or every place.
    private var startingFrame: MapCameraPosition {
        if let place = focused?.place {
            return Self.framing(
                focus: place,
                among: places.filter { $0.id != focused?.id }.compactMap(\.place)
            )
        }
        return Self.framing(places.compactMap(\.place))
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
    /// the page's scroll with it. The panel sits between the two, where the
    /// picture it describes is still in view.
    private var pictureAndRows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                map(withChips: false)
                    .frame(height: 300)
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement()
                    .accessibilityLabel("Kartta perheen paikoista.")
                panel
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
        Map(position: $camera) {
            ForEach(drawn) { subject in
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
                    // Not on the place the map was opened on: the panel names
                    // it, and its chip would only lead back to the card.
                    if withChips, subject.id != focused?.id {
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

    /// What the map says under itself: about the place it was opened on, or
    /// that there is nothing on it yet. Nothing at all on a map of every
    /// place, which is a map and needs no caption.
    @ViewBuilder
    private var panel: some View {
        if let subject = focused, let place = subject.place {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: subject.displayTitle)
                    .font(Elder.display(.title2))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(provenance(place))
                    .elderBody()
                    .foregroundStyle(Elder.supporting)
                // One under the other at every size. Side by side, the
                // default size's screenshot (25 Sep 2026) had "Näytä kaikki
                // paikat" wrapped onto two lines beside a one-line "Muuta
                // sijaintia", two buttons of two heights — and `ViewThatFits`
                // had chosen that row itself.
                VStack(spacing: 12) { focusButtons }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderCard()
        } else if store.subjects(of: .place).filter(\.confirmed).isEmpty {
            // Framed on Finland (`framing`), which is where these places will
            // be: a blank map of nowhere would read as a map that failed.
            Text("Kun kerrotte paikoista, ne tulevat tähän kartalle.")
                .elderBody()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderCard()
        }
    }

    @ViewBuilder
    private var focusButtons: some View {
        Button {
            isPinning = true
        } label: {
            buttonText("Muuta sijaintia")
        }
        .elderPrimary(false)
        .elderTapTarget()
        Button {
            focus = nil
            withAnimation { camera = startingFrame }
        } label: {
            buttonText("Näytä kaikki paikat")
        }
        .elderPrimary(false)
        .elderTapTarget()
    }

    /// A label that wraps rather than truncates and fills its button, the
    /// shape `PlacePinSheet`'s save button settled on after the audit read
    /// every other one as clipped.
    private func buttonText(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    /// How sure the archive is of the point, and where it came from. A circle
    /// is only ever the lookup's answer — the only other way to write a point,
    /// `PlacePinSheet`, writes an exact one — and an exact point says nothing
    /// about its source, because the archive cannot tell a street address the
    /// gazetteer found from a yard somebody marked by hand (§18).
    private func provenance(_ place: PlaceHint) -> LocalizedStringKey {
        place.precision.deservesAPin
            ? "Tarkka kohta."
            : "Suunnilleen tällä seudulla. Haettu paikan nimellä."
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
    ///
    /// With nothing to draw, the lookup's own Finland (`PlaceLookup`): the
    /// places the family tells about will land there, and a blank map of
    /// wherever MapKit starts reads as a map that failed.
    static func framing(_ hints: [PlaceHint]) -> MapCameraPosition {
        let drawable = hints.filter { $0.precision.mapSpanMetres != nil }
        guard let first = drawable.first else { return .region(PlaceLookup.searchRegion) }
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

    /// Where the camera starts when the map is opened on one place: centred on
    /// it, wide enough that the family's nearest other place is on the screen
    /// too, and never so wide that the place itself stops being the subject.
    ///
    /// Three times the distance to the nearest neighbour puts that neighbour
    /// two thirds of the way from the middle to the edge. Clamped to two to
    /// six times the place's own span — the width its card's map shows — so
    /// that a neighbour across the country does not shrink the place to a
    /// dot, and a place with no neighbour at all still opens wider than the
    /// card it came from.
    static func framing(focus: PlaceHint, among others: [PlaceHint]) -> MapCameraPosition {
        guard let span = focus.precision.mapSpanMetres else { return framing([focus]) }
        let here = CLLocation(latitude: focus.latitude, longitude: focus.longitude)
        let nearest = others
            .filter { $0.precision.mapSpanMetres != nil }
            .map { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
            .filter { $0 > 1 }
            .min()
        let side = min(max(3 * (nearest ?? 0), 2 * span), 6 * span)
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: focus.latitude, longitude: focus.longitude),
            latitudinalMeters: side,
            longitudinalMeters: side
        ))
    }
}

#Preview {
    NavigationStack {
        PlacesMapScreen(route: PlacesMapRoute())
            .environment(MemoryStore(filename: "preview-store.json"))
    }
}
