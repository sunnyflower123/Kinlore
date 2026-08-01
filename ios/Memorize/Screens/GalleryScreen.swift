import PhotosUI
import SwiftUI

/// The family's photos and the events that have been told about.
///
/// Photos as a grid, events as a list — the same `subject` table, a different
/// presentation. A grid because an old photograph is recognised by looking at
/// it, not by reading a title.
struct GalleryScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session

    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var picked: [PhotosPickerItem] = []
    @State private var isImporting = false

    /// Bigger tiles when the text is bigger. The memory-count badge scales with
    /// Dynamic Type, and at accessibility sizes it was clipped by a 110 pt tile —
    /// the count simply ran off the edge. Larger photographs are the right answer
    /// for this user anyway; the grid just holds fewer per row.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 170 : 110), spacing: 10)]
    }

    private var photos: [Subject] { store.subjects(of: .photo) }
    private var events: [Subject] { store.subjects(of: .event) }

    /// A family whose memories are all on people has an empty grid but can still
    /// have a round waiting, and "no photos yet" would hide it.
    private var hasRound: Bool {
        GuessRoundBuilder.nextRound(store: store, memberID: session.identity.memberID) != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty && events.isEmpty && !hasRound {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Muistot")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .elderTapTarget()
                    }
                    .accessibilityLabel("Lisää kuvia")
                }
            }
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailScreen(subject: subject)
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .overlay {
                if isImporting {
                    ProgressView("Tuodaan kuvia")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ei vielä kuvia", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Lisää vanha valokuva, niin koko perhe voi kertoa siitä omat muistonsa.")
                .elderBody()
                .foregroundStyle(Elder.supporting)
        } actions: {
            PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                Text("Valitse kuvia")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // The reading loop, above the grid because it expires: a round
                // is only interesting until somebody has answered it. It shows
                // itself only when one is waiting, so the screen does not grow a
                // permanent section for a family that has none.
                GuessSection()

                if !photos.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("Kuvat")
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(photos) { photo in
                                NavigationLink(value: photo) {
                                    PhotoTile(subject: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !events.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("Kerrotut hetket")
                        ForEach(events) { event in
                            NavigationLink(value: event) {
                                EventRow(subject: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Elder.screenPadding)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer {
            isImporting = false
            picked = []
        }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let filename = MediaStore.save(imageData: data)
            else { continue }

            // The title is left empty on purpose: nobody will name thirty
            // scanned photographs. The name arrives when someone talks about
            // the photo, and it is not needed before that.
            store.add(Subject(kind: .photo, title: "", imageFilename: filename))
        }
    }
}

private struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
    }
}

private struct PhotoTile: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    let subject: Subject

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

            // The memory count says what has already been talked about and what
            // has not. An empty photo is not an error but an invitation — which
            // is why the badge is always visible.
            let count = store.memories(for: subject.id).count
            Label(
                count == 0 ? "Kerro" : "\(count)",
                systemImage: count == 0 ? "mic.fill" : "text.bubble.fill"
            )
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            // Bounded growth: the badge sits on top of a photograph, so past a
            // point it stops being a label and starts being the tile. The count
            // is also in the tile's accessibility label and on the detail screen,
            // so nothing is only available here.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
        }
        .task {
            guard thumbnail == nil else { return }
            // A photo added by another family member is at first only a key: it
            // is fetched when the screen actually needs it.
            guard let filename = await MediaLoader.imageFilename(
                for: subject, store: store, session: session
            ) else { return }
            thumbnail = await Task.detached(priority: .userInitiated) {
                MediaStore.loadThumbnail(named: filename)
            }.value
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            store.memories(for: subject.id).isEmpty
                ? "Valokuva, ei vielä muistoja"
                : "Valokuva, \(store.memories(for: subject.id).count) muistoa"
        )
    }
}

private struct EventRow: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(Elder.supporting)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(memoryCountText)
                    .font(.subheadline)
                    .foregroundStyle(Elder.supporting)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }

    private var memoryCountText: String {
        let count = store.memories(for: subject.id).count
        return count == 1 ? "1 muisto" : "\(count) muistoa"
    }
}

#Preview {
    GalleryScreen()
        .environment(MemoryStore(filename: "preview-store.json"))
}
