import PhotosUI
import SwiftUI

/// Perheen kuvat ja kerrotut tapahtumat.
///
/// Kuvat ruudukkona, tapahtumat listana — sama `subject`-taulu, eri esitys.
/// Ruudukko siksi että vanha valokuva tunnistetaan katsomalla, ei lukemalla
/// otsikkoa.
struct GalleryScreen: View {
    @Environment(MemoryStore.self) private var store

    @State private var picked: [PhotosPickerItem] = []
    @State private var isImporting = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    private var photos: [Subject] { store.subjects(of: .photo) }
    private var events: [Subject] { store.subjects(of: .event) }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty && events.isEmpty {
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

            // Otsikko jätetään tyhjäksi tarkoituksella: kukaan ei jaksa nimetä
            // kolmeakymmentä skannattua kuvaa. Nimi syntyy kun kuvasta
            // kerrotaan, eikä sitä ennen tarvita.
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

            // Muistojen määrä kertoo mistä on jo puhuttu ja mistä ei. Tyhjä
            // kuva ei ole virhe vaan kutsu — siksi merkintä on aina näkyvissä.
            let count = store.memories(for: subject.id).count
            Label(
                count == 0 ? "Kerro" : "\(count)",
                systemImage: count == 0 ? "mic.fill" : "text.bubble.fill"
            )
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
        }
        .task {
            guard thumbnail == nil else { return }
            // Toisen perheenjäsenen lisäämä kuva on aluksi vain avain: se
            // noudetaan vasta kun ruutu tarvitsee sen.
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
                .foregroundStyle(.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(memoryCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
