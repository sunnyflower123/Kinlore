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
    /// Opens straight into placing that place — the card's "Merkitse
    /// kartalle", for a place with nowhere to be drawn yet. "Peruuta" then
    /// goes back to the card, because the map it would otherwise return to
    /// is a map about nothing.
    var editing = false
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
/// the middle of its own screen and read its point off the camera, so every
/// pan was also a move and nobody could look around a place without moving
/// it. Here the camera is only a camera: it can be dragged and pinched
/// anywhere, and no point changes until somebody asks for that with "Muuta
/// sijaintia" — and even then on this same map, with only the panel under it
/// changed, rather than on a screen of its own that a person has to find
/// their way around again.
///
/// **Editing, a tap puts the mark where the finger was.** A drag still only
/// moves the map. That keeps what the old screen's fixed mark was right
/// about — a pin dragged by a finger is a pin under a finger, the one thing
/// nobody can see while placing it, and a drag is the gesture this app's
/// user is least able to make precisely — while giving back the pan it took
/// away: the mark is drawn the moment the finger lifts, and a tap that
/// missed is answered by another tap. Nothing is stored until "Tallenna".
///
/// **Opened from a place card, the map is about that place.** The camera
/// starts on it (`framing(focus:among:)`), its own chip is left off because
/// the panel under the map names it and the chip would lead back to the
/// card just left, and the panel says how sure the archive is of the point:
/// the same two words the card's map says out loud, and where the point came
/// from.
///
/// **VoiceOver gets the task, and not only the screen.** Placing a point
/// inside a landscape is visual work, and four "move north" actions over
/// ground nothing can name would be the appearance of an answer rather than
/// one, so while editing the map is one labelled element. The way in that is
/// not visual is "Etsi nimellä" (`PlaceSearchSheet`): the answers are rows of
/// words, choosing one proposes the point at the precision it came with, and
/// the rows of how sure and "Tallenna" are ordinary buttons. The screen this
/// replaced, `PlacePinSheet`, could only let a person who cannot see the map
/// read what it was for.
///
/// The Paikat list stays. This is a third way to the same card, not the only
/// one: VoiceOver walks the list, and a place without a coordinate — nine of
/// the ten in production on 21 Sep 2026 — is on the list and not here. It is
/// behind the panel's "N paikkaa ei vielä kartalla" too, where a row starts
/// placing it.
struct PlacesMapScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss

    /// The place the panel speaks for, by subject id. The route's to begin
    /// with, and let go by "Näytä kaikki paikat".
    @State private var focus: String?
    /// Where the map is looking. A binding rather than `initialPosition`, so
    /// that "Näytä kaikki paikat" can move it — and so that coming back from a
    /// card finds the map where it was left rather than framed again.
    @State private var camera: MapCameraPosition = .automatic
    @State private var hasFramed = false
    /// What the map showed when it last stopped moving: how wide the view is
    /// decides whether a tap is followed by a closer look (`put`).
    @State private var shown: MKCoordinateRegion?
    /// A change on its way to the archive, or nil while looking.
    @State private var edit: Edit?
    /// The places with nowhere to be drawn, opened from the panel.
    @State private var isListing = false
    /// "Etsi nimellä", open over the map while a change is on its way.
    @State private var isSearching = false
    /// The map or an aerial photograph. Kept on this phone and never synced:
    /// it is how this person likes to look, not something the family knows.
    @AppStorage("map.aerial") private var aerial = false
    private let opensEditing: Bool

    init(route: PlacesMapRoute) {
        _focus = State(initialValue: route.focus)
        opensEditing = route.editing
    }

    /// What "Muuta sijaintia" has changed so far. None of it is stored until
    /// "Tallenna", and "Peruuta" throws all of it away.
    private struct Edit {
        /// What the map was about before this began, for "Peruuta".
        var previousFocus: String?
        /// Whether "Peruuta" leaves the screen: for a place that had no
        /// point when the card sent somebody here to give it one.
        var leavesTheScreen = false
        /// Where the last tap put the mark, if anywhere yet.
        var draft: CLLocationCoordinate2D?
        /// Which of the two rows is chosen: the spot, or around it.
        var exact = true
        /// Whether a person chose that row, rather than the screen opening
        /// on what the place already was. A tap then leaves it alone.
        var rowChosen = false
        /// "Poista sijainti", chosen and waiting to be confirmed.
        var removing = false
        /// The search answer the mark stands on, until a tap moves it.
        var found: PlaceLookup.Found?

        /// What "around here" stores: a province when that is what the
        /// search answered, a municipality otherwise. Never narrower than
        /// the answer, because a province is not a claim about a parish.
        var around: GeoPrecision {
            found?.hint.precision == .region ? .region : .town
        }
    }

    /// The same filter as `GalleryScreen.places`, narrowed to what has
    /// somewhere to be drawn.
    private var places: [Subject] {
        store.subjects(of: .place)
            .filter { $0.confirmed && $0.place?.precision.mapSpanMetres != nil }
            .sorted(by: Subject.byName)
    }

    /// The family's places that have nowhere to be drawn: never looked up,
    /// looked up in vain, or taken off the map by somebody in the family.
    /// Confirmed ones only, like the map itself — an unconfirmed name is a
    /// guess, and placing a guess on a map is the guess drawn (rule 4).
    private var unplaced: [Subject] {
        store.subjects(of: .place)
            .filter { $0.confirmed && $0.place?.precision.mapSpanMetres == nil }
            .sorted(by: Subject.byName)
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

    /// The place being edited, whether or not it has a point yet: a place
    /// with none is exactly the one somebody may be placing.
    private var edited: Subject? {
        guard edit != nil, let focus else { return nil }
        return store.subject(id: focus)
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
                    .accessibilityElement(children: edit == nil ? .contain : .ignore)
                    .accessibilityLabel(mapLabel)
                    .safeAreaInset(edge: .bottom) {
                        panel
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
            }
        }
        .navigationTitle("Kartta")
        .navigationBarTitleDisplayMode(.inline)
        // While a change is on its way the only ways out are "Tallenna" and
        // "Peruuta". A back chevron would be a third that says neither, and
        // what it did to the change would be a guess on the person's behalf.
        .navigationBarBackButtonHidden(edit != nil)
        .toolbar {
            // A picture and not a word, for the album bar's reason: a word
            // in a bar stays one size while the text around it grows, and the
            // audit says so (`GalleryScreen`). A toggle, so that VoiceOver
            // hears which of the two the map is showing.
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $aerial) {
                    Image(systemName: "globe.europe.africa")
                        .elderTapTarget()
                }
                .toggleStyle(.button)
                .accessibilityLabel("Ilmakuva")
            }
        }
        .elderSurface()
        .onAppear {
            // Once. A pop back from a card is the same visit, and the map
            // stays where it was left.
            guard !hasFramed else { return }
            hasFramed = true
            camera = startingFrame
            if opensEditing, let subject = focus.flatMap(store.subject(id:)) {
                beginEditing(subject, leavesTheScreen: true)
                // A place with nowhere to be drawn gives the map nothing to
                // tap beside, so the card's "Merkitse kartalle" arrives with
                // the search open on its name. The gazetteer has been asked
                // that name once already; this time every answer is shown
                // rather than the first.
                if subject.place?.precision.mapSpanMetres == nil { isSearching = true }
            }
        }
        .sheet(isPresented: $isListing) { unplacedList }
        .sheet(isPresented: $isSearching) {
            PlaceSearchSheet(query: edited?.title ?? "") { found in
                take(found)
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

    /// What the map is, said once for the whole of it. While editing it is
    /// one element, because the chips that were its children are gone and a
    /// tap anywhere on it is the control.
    private var mapLabel: LocalizedStringKey {
        edit == nil
            ? "Kartta. Jokainen paikka on nappi, joka avaa paikan kortin."
            : "Kartta. Napautus merkitsee kohdan."
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
    ///
    /// Editing is the exception, because a tap on the map is then the whole
    /// point: the map takes touches for as long as a change is on its way,
    /// the rows go (a row would be a way off this screen that says nothing
    /// about the change), and the page still scrolls anywhere outside the
    /// map's 300 points.
    private var pictureAndRows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                map(withChips: false)
                    .frame(height: 300)
                    .allowsHitTesting(edit != nil)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement()
                    .accessibilityLabel(edit == nil ? "Kartta perheen paikoista." : mapLabel)
                panel
                if edit == nil {
                    ForEach(places) { subject in
                        NavigationLink(value: subject) {
                            SubjectRow(subject: subject)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Elder.screenPadding)
        }
    }

    private func map(withChips: Bool) -> some View {
        MapReader { proxy in
            Map(position: $camera) {
                ForEach(drawn) { subject in
                    if let place = subject.place, let span = place.precision.mapSpanMetres {
                        let centre = CLLocationCoordinate2D(
                            latitude: place.latitude,
                            longitude: place.longitude
                        )
                        // The point being replaced stays in view, faintly, so
                        // that the new one is seen against the old.
                        let faded = subject.id == edited?.id && proposal != nil
                        // The card's rule, not a second one: a pin only ever
                        // for an exact answer, a circle for anything vaguer.
                        if place.precision.deservesAPin {
                            Marker(subject.displayTitle, coordinate: centre)
                                .tint(faded ? Elder.wax.opacity(0.35) : Elder.wax)
                                .annotationTitles(.hidden)
                        } else {
                            circle(
                                centre, radius: span / 3,
                                fill: faded ? 0.05 : 0.14, edge: faded ? 0.35 : 1, lineWidth: 2
                            )
                        }
                        // Not on the place the map was opened on: the panel
                        // names it, and its chip would only lead back to the
                        // card. And none while editing, when a tap on the map
                        // has to land on the map rather than open a card;
                        // the places themselves stay drawn, as landmarks.
                        if withChips, edit == nil, subject.id != focused?.id {
                            // Above the point rather than on it, so that what
                            // the card draws stays in view: centred on a
                            // municipality the chip covered the whole circle
                            // at the framing below (screenshotted 21 Sep
                            // 2026), and a map on which every place looks
                            // exact is rule 5 rounded by the layout.
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
                // What "Tallenna" would write, drawn the way the map will
                // draw it afterwards: the mark for a spot, a circle for
                // around it. A removal draws nothing, which is its answer.
                if let proposal, let span = proposal.precision.mapSpanMetres {
                    let centre = CLLocationCoordinate2D(
                        latitude: proposal.latitude,
                        longitude: proposal.longitude
                    )
                    if proposal.precision.deservesAPin {
                        Annotation(coordinate: centre) {
                            mark
                        } label: {
                            Text("Uusi kohta")
                        }
                        .annotationTitles(.hidden)
                    } else {
                        circle(centre, radius: span / 3, fill: 0.14, edge: 1, lineWidth: 3)
                    }
                }
            }
            // Points of interest off, for the card's reason: this is where the
            // family's memories happened, and a shoal of restaurant pins over
            // them is somebody else's map. The aerial photograph is `.hybrid`
            // rather than `.imagery`, so that the roads and the villages keep
            // their names over it: a yard is recognised from above, and found
            // by the road that leads to it.
            .mapStyle(aerial
                ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
                : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                shown = context.region
            }
            // Only while editing: looking at the map has no taps of its own,
            // so a chip's tap and the map's double-tap zoom are the map's.
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    if let point = proxy.convert(tap.location, from: .local) {
                        put(point)
                    }
                },
                including: edit == nil ? .subviews : .all
            )
        }
    }

    /// A circle the way the map draws "around here": wax, and over the aerial
    /// photograph on a cream line as well, for the mark's reason. Wax edges
    /// the street map's pale ground at 4.09:1, and against the photograph's
    /// forest and water it is gone, 1.03–1.07:1 at the median, where cream
    /// is 5.75–6.00:1 (measured 25 Sep 2026, ARCHITECTURE §18); cream on wax
    /// is 5.59:1 whatever the photograph holds. MapKit draws its overlays in
    /// the order given, so the cream one goes first and the wax lies along
    /// its middle.
    @MapContentBuilder
    private func circle(
        _ centre: CLLocationCoordinate2D,
        radius: Double,
        fill: Double,
        edge: Double,
        lineWidth: CGFloat
    ) -> some MapContent {
        if aerial {
            MapCircle(center: centre, radius: radius)
                .foregroundStyle(Color.clear)
                .stroke(Elder.cream.opacity(edge), lineWidth: lineWidth + 4)
        }
        MapCircle(center: centre, radius: radius)
            .foregroundStyle(Elder.wax.opacity(fill))
            .stroke(Elder.wax.opacity(edge), lineWidth: lineWidth)
    }

    /// What the map says under itself: about the place it was opened on, the
    /// change being made to it, or what is not on the map at all. Nothing
    /// on a map of every place that has every place on it, which is a map and
    /// needs no caption.
    @ViewBuilder
    private var panel: some View {
        if let subject = edited, let edit {
            editing(subject, edit)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .elderCard()
        } else if let subject = focused, let place = subject.place {
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
                VStack(spacing: 12) { focusButtons(subject, place) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderCard()
        } else if !unplaced.isEmpty {
            Button {
                isListing = true
            } label: {
                if unplaced.count == 1 {
                    buttonText("1 paikka ei vielä kartalla")
                } else {
                    buttonText("\(unplaced.count) paikkaa ei vielä kartalla")
                }
            }
            .elderPrimary(false)
            .elderTapTarget()
            .padding(16)
            .frame(maxWidth: .infinity)
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
    private func focusButtons(_ subject: Subject, _ place: PlaceHint) -> some View {
        Button {
            beginEditing(subject, leavesTheScreen: false)
        } label: {
            buttonText("Muuta sijaintia")
        }
        .elderPrimary(false)
        .elderTapTarget()
        // A point the lookup found can be vouched for as it is, which is a
        // confirmation and not an edit (rule 4): the family's word on the
        // gazetteer's answer, with nothing moved. A point that already
        // carries somebody's word has nothing to confirm.
        if !place.isConfirmed {
            Button {
                confirm(subject, place)
            } label: {
                buttonText("Sijainti on oikein")
            }
            .elderPrimary(false)
            .elderTapTarget()
        }
        Button {
            focus = nil
            withAnimation { camera = startingFrame }
        } label: {
            buttonText("Näytä kaikki paikat")
        }
        .elderPrimary(false)
        .elderTapTarget()
    }

    /// The panel while a change is on its way. The place's name is in the
    /// sentence rather than above it, so that the map keeps the height a
    /// heading would take: this panel is the tallest the screen has, and the
    /// map above it is what a finger has to hit.
    @ViewBuilder
    private func editing(_ subject: Subject, _ edit: Edit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if edit.removing {
                // In the panel rather than in an alert, and saying what stays:
                // a place taken off the map is still a place, with every
                // memory told about it.
                Text("Poistetaanko sijainti kartalta? \(subject.displayTitle) ja sen muistot säilyvät.")
                    .elderBody()
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text("Napauta karttaa kohtaan, jossa \(subject.displayTitle) on.")
                    .elderBody()
                    .accessibilityAddTraits(.isHeader)
                // Which answer the mark stands on, in the words the search
                // gave it: the one thing on the screen that tells somebody
                // who cannot see the map what "Tallenna" would save.
                if let found = edit.found {
                    let words = [found.name, found.detail].compactMap { $0 }.joined(separator: ", ")
                    Text("Hakutulos: \(words)")
                        .elderBody()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    isSearching = true
                } label: {
                    buttonText("Etsi nimellä")
                }
                .elderPrimary(false)
                .elderTapTarget()
                precisionRow("Tarkka kohta", isChosen: edit.exact) { choose(exact: true) }
                precisionRow("Suunnilleen tällä seudulla", isChosen: !edit.exact) { choose(exact: false) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { saveAndCancel(edit, singleLine: true) }
                VStack(spacing: 12) { saveAndCancel(edit, singleLine: false) }
            }
            // Only for a place that has something on the map to remove.
            if !edit.removing, subject.place?.precision.mapSpanMetres != nil {
                Button {
                    self.edit?.removing = true
                    self.edit?.draft = nil
                    self.edit?.found = nil
                } label: {
                    buttonText("Poista sijainti")
                }
                .elderPrimary(false)
                .elderTapTarget()
            }
        }
    }

    /// "Tallenna" and "Peruuta", side by side while both fit on one line and
    /// one under the other when they do not — `singleLine` is what makes the
    /// side-by-side arrangement refuse to fit rather than wrap, which is the
    /// trap the focus buttons fell into.
    ///
    /// Confirming a removal is the same button with the question's own verb
    /// on it: *"Poistetaanko…?"* is answered by "Poista sijainti", and a
    /// "Tallenna" under it would make somebody stop and work out what saving
    /// a removal means.
    @ViewBuilder
    private func saveAndCancel(_ edit: Edit, singleLine: Bool) -> some View {
        Button {
            save()
        } label: {
            if edit.removing {
                buttonText("Poista sijainti", singleLine: singleLine)
            } else {
                buttonText("Tallenna", singleLine: singleLine)
            }
        }
        .elderPrimary(true)
        .elderTapTarget()
        // Nothing to save until something has changed, and saving anyway
        // would be rule 5 broken by a button press — see `proposal`.
        .disabled(proposal == nil)
        Button {
            cancel()
        } label: {
            buttonText("Peruuta", singleLine: singleLine)
        }
        .elderPrimary(false)
        .elderTapTarget()
    }

    /// One of the two ways a place can be on the map, the way the date sheet
    /// shows its choices: the chosen one is ticked and set in bold, so the
    /// shape says which it is and not only a colour.
    private func precisionRow(
        _ key: LocalizedStringKey,
        isChosen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(key)
                    .font(.body.weight(isChosen ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if isChosen {
                    // Hidden from VoiceOver, which hears `.isSelected`
                    // instead: read out, the symbol's own name would join
                    // the row's words and say the choice twice.
                    Image(systemName: "checkmark")
                        .foregroundStyle(Elder.affirmative)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .elderTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// A label that wraps rather than truncates and fills its button, the
    /// shape the old moving screen's save button settled on after the audit
    /// read every other one as clipped. `singleLine` is for a row of buttons
    /// that must not fit by wrapping (`saveAndCancel`).
    private func buttonText(_ key: LocalizedStringKey, singleLine: Bool = false) -> some View {
        Text(key)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: singleLine, vertical: true)
            .frame(maxWidth: .infinity)
    }

    /// How sure the archive is of the point, and where it came from. A point
    /// somebody in the family put there carries their name since 25 Sep 2026,
    /// and the panel says it: that name is what tells a yard somebody marked
    /// by hand from a street address the gazetteer found, which the archive
    /// could not do before (§18). Without one the point is the lookup's
    /// answer, and a circle says so.
    private func provenance(_ place: PlaceHint) -> LocalizedStringKey {
        if place.isConfirmed, let name = place.confirmedByName, !name.isEmpty {
            return place.precision.deservesAPin
                ? "Tarkka kohta. Vahvisti \(name)."
                : "Suunnilleen tällä seudulla. Vahvisti \(name)."
        }
        return place.precision.deservesAPin
            ? "Tarkka kohta."
            : "Suunnilleen tällä seudulla. Haettu paikan nimellä."
    }

    /// The places the map cannot draw, each a way into placing it. A sheet
    /// over the map rather than a screen after it, so that choosing one
    /// lands back on the map it is about to be placed on.
    private var unplacedList: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Napauta paikkaa, niin voit merkitä sen kartalle.")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                    ForEach(unplaced) { subject in
                        Button {
                            isListing = false
                            beginEditing(subject, leavesTheScreen: false)
                        } label: {
                            SubjectRow(subject: subject)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Elder.screenPadding)
            }
            // Short, because a navigation title is the one piece of text on
            // a screen that does not grow with Dynamic Type and cannot wrap.
            .navigationTitle("Ei vielä kartalla")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sulje") { isListing = false }
                }
            }
            .elderSurface()
        }
    }

    /// The mark: wax, on a cream ring that is there so the wax is visible
    /// over water, forest and a town's grey alike. `Elder.cream` on
    /// `Elder.wax` measures 5.59:1, and the ring guarantees that pairing
    /// whatever the map happens to draw underneath — a graphic over an
    /// unknown ground is the one contrast the palette cannot state in advance.
    ///
    /// It takes no touches. The map underneath is the control, and a mark
    /// that swallowed the tap would make the spot it stands on the one spot
    /// that cannot be chosen again.
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
            // Over the aerial photograph, the circles' cream line (`circle`):
            // the words are on wax either way, and it is the chip's edge that
            // dark forest would take away.
            .overlay {
                if aerial {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Elder.cream, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Avaa paikan kortin.")
    }

    // MARK: - Changing a place

    /// Starts a change to `subject`'s point on this same map. The row that
    /// starts out chosen is what the place already is, so that the screen
    /// opens on the truth rather than on a default.
    private func beginEditing(_ subject: Subject, leavesTheScreen: Bool) {
        edit = Edit(
            previousFocus: focus,
            leavesTheScreen: leavesTheScreen,
            exact: subject.place.map { $0.precision.deservesAPin || $0.precision.mapSpanMetres == nil } ?? true
        )
        focus = subject.id
    }

    /// A tap on the map: the mark goes where the finger was.
    ///
    /// A tap chooses the spot as well, because that is what a tap says —
    /// unless somebody has chosen a row, and then the row is their answer
    /// and the tap only says where its middle is.
    ///
    /// When the map shows more than five kilometres across, the camera then
    /// glides to a kilometre and a half around the mark, so that where the
    /// finger landed can be seen at a scale where a yard is a yard — and
    /// corrected by another tap if it missed. A finger is about a centimetre
    /// wide, and at the municipality's scale a centimetre is a kilometre.
    private func put(_ point: CLLocationCoordinate2D) {
        guard var change = edit else { return }
        if !change.rowChosen { change.exact = true }
        change.draft = point
        change.found = nil
        change.removing = false
        edit = change
        guard change.exact, let shown else { return }
        let metresAcross = shown.span.longitudeDelta * 111_000 * cos(shown.center.latitude * .pi / 180)
        if metresAcross > 5_000 {
            withAnimation {
                camera = .region(MKCoordinateRegion(
                    center: point,
                    latitudinalMeters: 1_500,
                    longitudinalMeters: 1_500
                ))
            }
        }
    }

    /// One of the two rows. Choosing "around here" after a tap widens the
    /// view to the circle it will be, so that the choice is seen for what it
    /// is rather than as a close-up of its middle.
    private func choose(exact: Bool) {
        edit?.exact = exact
        edit?.rowChosen = true
        if !exact, let point = edit?.draft ?? edited?.place.map({
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }), let span = edit?.around.mapSpanMetres {
            withAnimation {
                camera = .region(MKCoordinateRegion(
                    center: point,
                    latitudinalMeters: span * 1.3,
                    longitudinalMeters: span * 1.3
                ))
            }
        }
    }

    /// What "Tallenna" would write, or nil while there is nothing to save.
    ///
    /// **A spot is only ever where somebody tapped.** Choosing "Tarkka kohta"
    /// for a circle the gazetteer drew, and saving, would turn fourteen
    /// kilometres of parish into a claim about one farmyard — rule 5 broken
    /// by a button press — so that choice waits for a tap. Going the other
    /// way needs none: "around here" over a spot claims less, and a person
    /// may always say they are less sure.
    ///
    /// **A search answer is held to the same rule.** A street address the
    /// search found is a spot, and saves as one; a municipality or a province
    /// it found is a circle of its own size under either row, until a tap
    /// says where in it. A province stays a province under "around here"
    /// (`Edit.around`) rather than shrinking to a parish.
    ///
    /// **Five metres, not equality**, for whether a tap moved anything: a
    /// map does not hand a coordinate back exactly as it was given one, and
    /// five metres is under anything a finger can mean and over anything the
    /// conversion can produce.
    private var proposal: PlaceHint? {
        guard let subject = edited, let edit else { return nil }
        let current = subject.place.flatMap { $0.precision.mapSpanMetres == nil ? nil : $0 }
        if edit.removing {
            // The coordinates stay beside `.unknown`: nothing draws them, and
            // they are what the place was before, for anybody reading the
            // archive later. The confirmation is what keeps the lookup from
            // putting it back (`placesAwaitingCoordinates`).
            guard let current else { return nil }
            return PlaceHint(latitude: current.latitude, longitude: current.longitude, precision: .unknown)
        }
        if let draft = edit.draft {
            if edit.exact, let found = edit.found, !found.hint.precision.deservesAPin { return nil }
            let precision: GeoPrecision = edit.exact ? .exact : edit.around
            if let current, current.precision == precision,
               CLLocation(latitude: draft.latitude, longitude: draft.longitude)
                   .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude)) <= 5 {
                return nil
            }
            return PlaceHint(latitude: draft.latitude, longitude: draft.longitude, precision: precision)
        }
        if let current, !edit.exact, current.precision == .exact {
            return PlaceHint(latitude: current.latitude, longitude: current.longitude, precision: .town)
        }
        return nil
    }

    /// An answer chosen in "Etsi nimellä": the mark goes where the answer is
    /// and the rows say what it pinned down, and the camera shows it the way
    /// the map will draw it — a street address close up, a municipality or a
    /// province whole. The row is the answer's and not a person's choice, so
    /// a tap afterwards is a spot, as a tap always is.
    private func take(_ found: PlaceLookup.Found) {
        guard var change = edit else { return }
        let point = CLLocationCoordinate2D(latitude: found.hint.latitude, longitude: found.hint.longitude)
        change.draft = point
        change.found = found
        change.exact = found.hint.precision.deservesAPin
        change.rowChosen = false
        change.removing = false
        edit = change
        let across = found.hint.precision.deservesAPin
            ? 1_500
            : (found.hint.precision.mapSpanMetres ?? 14_000) * 1.3
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: point,
                latitudinalMeters: across,
                longitudinalMeters: across
            ))
        }
    }

    /// Stores the change as this person's word (§18): who and when, which
    /// is what keeps it from being mistaken for a lookup and what sync lets
    /// only a newer word move.
    private func save() {
        guard let subject = edited, var place = proposal else { return }
        place.confirmedByID = session.identity.memberID
        place.confirmedByName = store.authorName
        place.confirmedAt = .now
        store.setPlace(subjectID: subject.id, place: place)
        edit = nil
        // A place taken off the map has nothing left here to be the focus
        // of; the panel then offers the list it has just joined.
        if place.precision.mapSpanMetres == nil { focus = nil }
    }

    /// "Peruuta": back to the map as it was, with nothing stored — or back to
    /// the card, when that is where the change began on a place the map had
    /// nothing to show for.
    private func cancel() {
        guard let change = edit else { return }
        if change.leavesTheScreen {
            dismiss()
            return
        }
        edit = nil
        focus = change.previousFocus
    }

    /// "Sijainti on oikein": the lookup's point, unchanged, as this person's
    /// word.
    private func confirm(_ subject: Subject, _ place: PlaceHint) {
        var confirmed = place
        confirmed.confirmedByID = session.identity.memberID
        confirmed.confirmedByName = store.authorName
        confirmed.confirmedAt = .now
        store.setPlace(subjectID: subject.id, place: confirmed)
    }

    // MARK: - Framing

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
