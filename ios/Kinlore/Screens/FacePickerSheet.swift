import PhotosUI
import SwiftUI

/// Choosing the face on a person's card (ARCHITECTURE §25).
///
/// A face is a photograph of the archive and a spot in it, nothing more: the
/// photograph is not cropped, no bytes leave the phone that were not leaving
/// already, and no quota is touched. What travels is a reference and two
/// fractions, and what every phone draws is cut from its own copy of the
/// picture (`Portrait`).
///
/// The photographs the person has been told about in come first, because
/// that is where their face most likely is — the same join the blind card
/// reads, `memories(mentioning:)` — and the rest of the archive after them.
/// Only photographs on this phone are offered: a face cannot be tapped on a
/// picture that is still only a key.
///
/// **And the phone's own photographs, since 26 Sep 2026.** The person whose
/// face the family wants on a card is often the one the archive has no
/// picture of yet, and the shoebox is not the only place a photograph lives.
/// *"Valitse puhelimen kuvista"* is the album's import: the same
/// `PhotosPicker`, and the bytes through `MemoryStore.addPhotograph`, the
/// one function the album's `importPhotos` calls too — so the same
/// downscale, the same row, the same sealed upload and the same ceiling —
/// and then the picture straight to `FaceFocusScreen`. What it becomes is an
/// ordinary photograph of the archive, in the album with the rest. The face
/// stays a reference to a photograph, as everywhere in §25, and a picture
/// kept only to be a face would be a second kind of photograph nobody can
/// list, tell about or export.
///
/// **What VoiceOver gets here is the screen and not the task**, as it did
/// on the family's map until that map had a search (`PlacesMapScreen`). Each
/// photograph is a button with its name, the spot is the middle unless
/// somebody who can see the picture taps elsewhere, and "Tallenna" works
/// from the middle. Finding a face in a group photograph is visual work, and
/// a set of "move left" actions over a picture nothing can describe would be
/// the appearance of an answer.
struct FacePickerSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subject: Subject

    /// Where the sheet is: the tiles, or the spot in one photograph. Held
    /// here rather than left to the links because a picture from the phone
    /// arrives through a picker and not a tap on a tile, and it is pushed
    /// the moment it is in the archive.
    @State private var path: [Subject] = []
    @State private var isPickingFromLibrary = false
    @State private var picked: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importFailed = false

    /// Photographs on this phone, live and their own. A rejected or merged
    /// photograph is not offered, and one another phone added is a key with
    /// no file until the full copy fetches it.
    private var photographs: [Subject] {
        store.subjects.filter {
            $0.kind == .photo && $0.deletedAt == nil && $0.mergedInto == nil && $0.imageFilename != nil
        }
    }

    /// The ones this person has been told about in, newest telling first.
    private var told: [Subject] {
        let ids = store.memories(mentioning: subject.id).map(\.subjectID)
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return photographs.first { $0.id == id }
        }
    }

    private var others: [Subject] {
        let toldIDs = Set(told.map(\.id))
        return photographs.filter { !toldIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if photographs.isEmpty {
                        // True of an empty archive and of a family whose
                        // pictures the full copy has not fetched yet. The
                        // sentence it replaced said the archive had none
                        // and that a face is chosen from the archive, and
                        // the button under it is why neither held.
                        Text("Tässä puhelimessa ei ole vielä arkiston kuvia.")
                            .elderBody()
                            .foregroundStyle(Elder.supporting)
                    }

                    fromPhone

                    if !told.isEmpty {
                        heading("Kuvat, joissa hänestä kerrotaan")
                        grid(told)
                    }
                    if !others.isEmpty {
                        heading(told.isEmpty ? "Arkiston kuvat" : "Muut kuvat")
                        grid(others)
                    }

                    if subject.portraitSubjectID != nil {
                        // A removal is a choice too, and it travels like one
                        // (`MemoryStore.setPortrait`). Not red: nothing is
                        // deleted, the photograph stays where it was and the
                        // card goes back to the initial.
                        Button {
                            store.setPortrait(subjectID: subject.id, photoID: nil, focusX: 0, focusY: 0)
                            dismiss()
                        } label: {
                            Text("Poista kasvot")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                        }
                        .elderPrimary(false)
                        .elderTapTarget()
                        .padding(.top, 8)
                    }

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
            }
            .navigationTitle("Kasvot kortille")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Subject.self) { photo in
                FaceFocusScreen(subject: subject, photo: photo) { dismiss() }
            }
            .elderSurface()
        }
        .photosPicker(
            isPresented: $isPickingFromLibrary,
            selection: $picked,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await importFromPhone(item) }
        }
        .overlay {
            if isImporting {
                ProgressView(String(localized: "Tuodaan kuvaa"))
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
        // Said, not skipped: the album's import names what went missing for
        // the same reason, and here one picture is the whole import.
        .alert("Kuvaa ei saatu tuotua", isPresented: $importFailed) {
            Button("Selvä") { importFailed = false }
        } message: {
            Text("Voit yrittää uudelleen tai valita toisen kuvan.")
        }
    }

    /// The way in from the phone's own photographs, at the top in both
    /// states: found without scrolling past forty tiles at the largest size,
    /// and the one thing on the sheet when there is nothing else. A plain
    /// button and the picker presented from the flag it sets — `PhotosPicker`
    /// does not survive being a row (the album's menu says so), and a button
    /// shaped like the sheet's others is what a finger here already knows.
    /// The sentence under it says the one thing worth knowing before the
    /// tap: the picture is the family's after it, not the card's.
    ///
    /// `-library stub` (DEBUG) answers the tap with a generated picture
    /// instead of the system picker, which a test run cannot drive;
    /// everything from the bytes onward is the real path.
    private var fromPhone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                #if DEBUG
                if UserDefaults.standard.string(forKey: "library") == "stub" {
                    if let data = MemoryStore.demoPhotoData() {
                        importFromPhone(data)
                    } else {
                        importFailed = true
                    }
                    return
                }
                #endif
                isPickingFromLibrary = true
            } label: {
                Label("Valitse puhelimen kuvista", systemImage: "photo.on.rectangle.angled")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .elderPrimary(false)
            .elderTapTarget()

            Text("Kuva tulee arkistoon ja näkyy Albumissa.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
        }
    }

    /// One picture from the phone, by the album's path. Bytes that cannot be
    /// read — a picture iCloud has not downloaded, a format the phone cannot
    /// open — are said so, not skipped.
    private func importFromPhone(_ item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            picked = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            importFailed = true
            return
        }
        importFromPhone(data)
    }

    /// The bytes into the archive — `MemoryStore.addPhotograph`, the album's
    /// own path — and straight to the spot in the picture. No date sheet:
    /// the album asks that of a pile, and this is one picture somebody is
    /// about to look at, whose own card carries the row.
    private func importFromPhone(_ data: Data) {
        guard let photo = store.addPhotograph(imageData: data) else {
            importFailed = true
            return
        }
        path.append(photo)
    }

    private func heading(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.headline)
            .foregroundStyle(Elder.supporting)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func grid(_ photos: [Subject]) -> some View {
        // Two across at the default size and one at the largest, which the
        // adaptive column does on its own; the minimum is the tap target
        // twice over, so a tile is never a thumbnail to aim at.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(photos) { photo in
                NavigationLink(value: photo) {
                    FaceCandidateTile(photo: photo)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One photograph to choose from: its thumbnail, square, with its name for
/// VoiceOver — the same name the album's tile reads out, so an untitled one is
/// "Valokuva" here as it is there.
private struct FaceCandidateTile: View {
    let photo: Subject

    @State private var thumbnail: UIImage?

    var body: some View {
        Rectangle()
            .fill(Elder.card)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // An edge of its own, for the same reason the avatar has one:
            // a pale print on parchment is otherwise a picture with no
            // shape around it.
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Elder.rule, lineWidth: 1))
            .frame(minHeight: Elder.minTapTarget)
            .task {
                guard thumbnail == nil, let filename = photo.imageFilename else { return }
                thumbnail = await Task.detached(priority: .userInitiated) {
                    MediaStore.loadThumbnail(named: filename)
                }.value
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(photo.displayTitle))
    }
}

/// The spot in the photograph, and what the disc will show of it.
///
/// The picture is drawn at the width of the screen and the tap lands as
/// fractions of it, which is the one form of the point that means the same
/// on every phone. The marker is the square the disc will show — cut by
/// `Portrait.window`, the same arithmetic the disc is cut with — so what is
/// under the ring on the screen is what is on the card, and the disc beside
/// the sentence is the card's own view, cut from the full picture.
struct FaceFocusScreen: View {
    @Environment(MemoryStore.self) private var store

    let subject: Subject
    let photo: Subject
    /// Closes the whole sheet, not this screen: the card is where the face is
    /// seen, and a picker left open over it would ask the question twice.
    let done: () -> Void

    @State private var image: UIImage?
    /// The spot, as fractions of the picture. The middle until somebody who
    /// can see the picture taps elsewhere, so "Tallenna" is never disabled
    /// and VoiceOver can save a face without a tap it cannot aim.
    @State private var focus = CGPoint(x: 0.5, y: 0.5)
    @State private var preview: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Napauta kasvoja kuvassa.")
                    .elderBody()

                if let image {
                    picture(image)

                    HStack(spacing: 16) {
                        disc
                        Text("Näin kasvot näkyvät kortilla.")
                            .elderBody()
                    }

                    Text("Kuva ei muutu. Kortille tulee vain tämä ympyrä.")
                        .elderBody()
                        .foregroundStyle(Elder.supporting)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                Button {
                    store.setPortrait(subjectID: subject.id, photoID: photo.id, focusX: focus.x, focusY: focus.y)
                    done()
                } label: {
                    Text("Tallenna")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .elderPrimary(true)
                .elderTapTarget()
                .disabled(image == nil)
            }
            .padding(Elder.screenPadding)
        }
        .navigationTitle("Kasvot kortille")
        .navigationBarTitleDisplayMode(.inline)
        .elderSurface()
        .task {
            guard image == nil, let filename = photo.imageFilename else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                MediaStore.loadImage(named: filename)
            }.value
            image = loaded
            recut()
        }
        .onChange(of: focus) { recut() }
    }

    /// The photograph at the width it has, with the marker over the spot.
    ///
    /// The container takes the picture's own proportions, so the image fills
    /// it exactly and a tap's place in the container is its place in the
    /// picture — no letterbox to subtract.
    private func picture(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let shown = proxy.size
            let window = Portrait.window(in: image.size, focusX: focus.x, focusY: focus.y)
            let scale = shown.width / image.size.width
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: shown.width, height: shown.height)
                // A ring in two colours, so it has an edge on a dark print
                // and on a pale one. Not the disc itself: the disc is beside
                // the sentence below, where it is not hiding the face.
                Circle()
                    .strokeBorder(Elder.cream, lineWidth: 4)
                    .overlay(Circle().strokeBorder(Elder.supporting, lineWidth: 2).padding(1))
                    .frame(width: window.width * scale, height: window.height * scale)
                    .offset(x: window.minX * scale, y: window.minY * scale)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                focus = CGPoint(
                    x: min(max(location.x / shown.width, 0), 1),
                    y: min(max(location.y / shown.height, 0), 1)
                )
            }
        }
        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("Valokuva. Kasvot otetaan kuvan keskeltä, ellei muuta kohtaa napauteta.")
    }

    /// The card's disc, at the card's size and with the card's ring.
    private var disc: some View {
        Circle()
            .fill(Elder.supporting)
            .overlay {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                }
            }
            .overlay(Circle().strokeBorder(Elder.supporting, lineWidth: 2))
            .frame(width: 72, height: 72)
            .accessibilityLabel("Kortin kasvot")
    }

    private func recut() {
        guard let image else { return }
        preview = Portrait.crop(image, focusX: focus.x, focusY: focus.y)
    }
}
