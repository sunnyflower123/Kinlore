import MapKit
import SwiftUI

/// Moving a place's point to where the place actually is.
///
/// `PlaceMapCard` draws what the gazetteer answered, and §18 measures how
/// coarse that answer usually is: sixteen farm, house and hamlet names through
/// the shipping `PlaceLookup` came back as sixteen municipalities and not one
/// pin. "Koivula" is a fourteen-kilometre circle over a parish, and the only
/// person who can make it a farmyard is somebody in the family who has stood
/// in it.
///
/// So this is the confirmation §18 says does not exist — "a judgement about
/// the coordinate", from a human who knows which *Karjala* it was. It is
/// rule 4 in its ordinary direction: the machine proposed a circle, a person
/// replaces it with a point, and the point is theirs rather than the
/// gazetteer's. Nothing here asks the model anything and nothing leaves the
/// device but the archive's own sync.
///
/// **The mark stays still and the map moves under it.** A pin dragged by a
/// finger is a pin under a finger — the one thing you cannot see while you are
/// placing it — and a drag is the gesture this app's user is least able to
/// make precisely. A fixed mark makes the whole map the control and pinch the
/// zoom, which is how every map that asks this question does it.
///
/// **What is saved is `.exact`, and that is the honest reading**: the family
/// said this is the spot, so the card may draw a pin there. Two limits follow
/// from having no field for who said it, and both are deliberate for v1 (§18).
/// A hand-placed point is indistinguishable from a street address the
/// gazetteer resolved, and correcting the place's *name* still clears it —
/// the coordinates answer the title, and `MemoryStore.rename` cannot tell a
/// point somebody stood on from a point somebody looked up.
///
/// **What VoiceOver gets here is the screen and not the task.** The map is one
/// labelled element, the buttons are ordinary buttons, and a person who cannot
/// see the map can read what the screen is for and leave it as it was. Placing
/// a point inside a landscape is visual work, and four "move north" actions
/// over ground nothing can name would be the appearance of an answer rather
/// than one. The stored coordinate stands until somebody who can see it says
/// otherwise.
struct PlacePinSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject

    /// The point the screen opened on: the gazetteer's answer, or the last one
    /// somebody placed. Kept because nothing may be saved until the mark has
    /// left it — see `hasMoved`.
    private let start: CLLocationCoordinate2D

    @State private var camera: MapCameraPosition
    /// Where the mark is now, in the map's terms. Read back from the camera
    /// rather than tracked by hand: the map is the thing that moves, and its
    /// own idea of the centre is the only one that is certain to be right.
    @State private var centre: CLLocationCoordinate2D

    init(subject: Subject, place: PlaceHint) {
        self.subject = subject
        let point = CLLocationCoordinate2D(
            latitude: place.latitude,
            longitude: place.longitude
        )
        start = point
        // Opens at the scale the stored answer was given at, so the first
        // thing on screen is the circle's worth of country the family has to
        // choose inside. A tighter opening would hide the very ground the
        // point has to move across; `.unknown` has no span and never reaches
        // this screen, so the municipality's is the only fallback needed.
        let span = place.precision.mapSpanMetres ?? 14_000
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: point,
            latitudinalMeters: span,
            longitudinalMeters: span
        )))
        _centre = State(initialValue: point)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                map

                Text("Siirrä karttaa niin, että merkki osuu oikeaan paikkaan. Kahdella sormella kartta lähenee.")
                    .elderBody()
                    .foregroundStyle(Elder.supporting)

                // The label carries its own width and its own wrapping, which
                // is not a style choice: written as `Button("…")` with the
                // width put on the button instead, the audit reported the save
                // button's text clipped at the default size — a 354 x 60 frame
                // with the words drawn past its edge. `CameraScreen` has the
                // shape that measures clean, and it is this one.
                Button {
                    save()
                } label: {
                    Text("Tallenna tämä paikka")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .elderPrimary(true)
                .elderTapTarget()
                // Nothing to save until the mark has been moved, and saving
                // anyway would be rule 5 broken by a button press: the stored
                // answer for "Puumala" is a municipality, and writing it back
                // as `exact` because somebody opened the map and pressed the
                // blue button turns fourteen kilometres of parish into a claim
                // about one farmyard. The person is the only thing that can
                // make this point exact, and moving the map is how they say so.
                .disabled(!hasMoved)

                Button {
                    dismiss()
                } label: {
                    Text("Peruuta")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .elderPrimary(false)
                .elderTapTarget()
            }
            .padding(Elder.screenPadding)
            // Short, because a navigation title is the one piece of text on a
            // screen that does not grow with Dynamic Type and cannot wrap. The
            // question itself is under the map, where it can do both.
            .navigationTitle("Tarkka paikka")
            .navigationBarTitleDisplayMode(.inline)
            .elderSurface()
        }
    }

    private var map: some View {
        Map(position: $camera)
            // The same map as the card's, for the same reason: this is where a
            // memory happened, and a shoal of restaurant pins over it is
            // somebody else's map. Roads, water and the names of villages stay
            // — they are what somebody recognises the place by.
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .continuous) { context in
                centre = context.region.center
            }
            .overlay { mark }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(maxWidth: .infinity, minHeight: 180)
            .accessibilityElement()
            .accessibilityLabel("Kartta. Merkki pysyy keskellä ja kartta liikkuu sen alla.")
    }

    /// The mark itself: wax, on a cream ring that is there so the wax is
    /// visible over water, forest and a town's grey alike. `Elder.cream` on
    /// `Elder.wax` measures 5.59:1, and the ring guarantees that pairing
    /// whatever the map happens to draw underneath — a graphic over an unknown
    /// ground is the one contrast the palette cannot state in advance.
    ///
    /// It takes no touches. The map underneath is the control, and a mark that
    /// swallowed the drag would make the screen look broken exactly in the
    /// middle, where every finger starts.
    private var mark: some View {
        ZStack {
            Circle()
                .strokeBorder(Elder.cream, lineWidth: 7)
                .frame(width: 46, height: 46)
            Circle()
                .strokeBorder(Elder.wax, lineWidth: 3)
                .frame(width: 46, height: 46)
            Circle()
                .fill(Elder.cream)
                .frame(width: 14, height: 14)
            Circle()
                .fill(Elder.wax)
                .frame(width: 8, height: 8)
        }
        .allowsHitTesting(false)
    }

    /// Whether the mark is somewhere else than it was.
    ///
    /// Metres rather than an equality, because a map does not hand a region
    /// back exactly as it was given one: it fits the span to the view's aspect
    /// ratio and answers with its own centre, which differs in the last
    /// decimals. Five metres is under anything a finger can mean and over
    /// anything the fitting can produce.
    private var hasMoved: Bool {
        CLLocation(latitude: centre.latitude, longitude: centre.longitude)
            .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)) > 5
    }

    private func save() {
        store.setPlace(
            subjectID: subject.id,
            place: PlaceHint(
                latitude: centre.latitude,
                longitude: centre.longitude,
                precision: .exact
            )
        )
        dismiss()
    }
}
