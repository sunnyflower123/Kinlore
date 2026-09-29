import SwiftUI

/// The way from a card to a telling that names it and is filed under another:
/// that card's picture and name, above the telling on the card being read.
///
/// A row of its own rather than a link on the telling, because a link anywhere
/// in a row takes the whole row over, and the telling's row has buttons of its
/// own — the voice to listen to, the author's menu.
///
/// On a person's card since 30 Sep 2026 the telling is not listed under it:
/// the link is the way to it, once for each card whose tellings name them.
struct NamedElsewhereLink: View {
    let home: Subject
    /// Whether the telling is listed under the link, as on a place's card.
    var tellingBelow = true

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Side by side, until the name would be left a column of single letters
    /// beside the picture.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
    }

    var body: some View {
        NavigationLink(value: home) {
            layout {
                if home.kind == .photo {
                    HomePicture(photo: home)
                } else {
                    SubjectAvatar(subject: home, size: 44)
                }
                Text(home.displayTitle)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    // For `AccessibilityPolicy.isDefaultSizeSimulationArtefact`
                    // and nothing else (27 Sep 2026). On the words rather
                    // than the link: the audit reports the label.
                    .accessibilityIdentifier("namedElsewhere.title")
            }
            .frame(maxWidth: .infinity, minHeight: Elder.minTapTarget, alignment: .leading)
        }
        .accessibilityHint(
            tellingBelow
                ? Text("Avaa kortin, jolla alla oleva muisto on.")
                : Text("Avaa kortin, jolla koko muisto on.")
        )
        .accessibilityIdentifier("card.namedElsewhere")
    }
}

/// The photograph a telling is filed under, small: the picture when it is on
/// this phone or can be fetched, and the kind's own symbol until then.
private struct HomePicture: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    let photo: Subject

    /// Grows with the name beside it.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 52

    @State private var thumbnail: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Elder.paper)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: photo.kind.symbolName)
                        .font(.title3)
                        .foregroundStyle(Elder.supporting)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            // The album's edge, for the album's reason: a pale print is
            // otherwise a picture with no shape around it.
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Elder.rule, lineWidth: 1))
            // The name beside it says which card this is.
            .accessibilityHidden(true)
            // Keyed for the album's reason too: a photograph another member
            // added can arrive as a card before it has a key to fetch by.
            .task(id: [photo.r2Key, photo.imageFilename]) {
                guard thumbnail == nil,
                      let filename = await MediaLoader.imageFilename(
                          for: photo, store: store, session: session
                      )
                else { return }
                thumbnail = await Task.detached(priority: .userInitiated) {
                    MediaStore.loadThumbnail(named: filename)
                }.value
            }
    }
}
