import SwiftUI

/// A person or a place as a disc: their face, when somebody has chosen one
/// from a photograph of the archive, and their initial otherwise.
///
/// The initial came first (13 Sep 2026), and this comment used to say the app
/// had no portraits and could not get any — `imageFilename` is written only
/// for `.photo` subjects, so there was no face on file for anybody the
/// archive knew by name. Since 21 Sep 2026 there can be: a person's card
/// points at one of the family's photographs and a spot in it
/// (`Subject.portraitSubjectID`, ARCHITECTURE §25), and this view cuts the
/// disc from that picture on the way to the screen (`Portrait`). The
/// photograph itself is never cropped. When the picture is not on this phone,
/// or was rejected, the initial is drawn as before — silently, because the
/// server keeps the choice and the phone may catch up.
///
/// The initial in the serif is what the film puts in the same place, and it
/// does the one thing the SF Symbol it replaces could not: it tells two people
/// apart at a glance on a list of five, where every row used to carry the same
/// grey outline of a head.
///
/// **The badge on an unconfirmed subject is not decoration.** A proposal has to
/// be distinguishable by SHAPE and not by colour alone — rule 1, and the symbol
/// this replaces carried it in its own outline (`person.crop.circle` against
/// `person.crop.circle.badge.questionmark`). The badge is that shape now, the
/// ring is thicker as well, and the row still says *"Ehdotus — vahvista
/// henkilö"* in words underneath. Three signals where there were three.
struct SubjectAvatar: View {
    @Environment(MemoryStore.self) private var store
    let subject: Subject

    /// Grows with Dynamic Type, because the letter inside it does. A fixed
    /// disc with a scaling glyph in it is a clipped glyph at XXXL, which is
    /// the audit's most common finding and rule 1's most common failure.
    @ScaledMetric private var size: CGFloat

    /// The face cut for this disc, with the key it was cut for. The key is
    /// kept beside it because the point can move while this view lives — the
    /// card's own disc, after "Tallenna" — and an image cut for the old key
    /// must not stand in while the new one is on its way.
    @State private var cut: (key: String, image: UIImage)?

    init(subject: Subject, size: CGFloat = 40) {
        self.subject = subject
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    /// The photograph the face is cut from, when it is on this phone.
    private var photo: Subject? { store.portraitPhoto(for: subject) }

    private var focusX: Double { subject.portraitFocusX ?? 0.5 }
    private var focusY: Double { subject.portraitFocusY ?? 0.5 }

    private var faceKey: String? {
        photo?.imageFilename.map { PortraitCache.key(filename: $0, focusX: focusX, focusY: focusY) }
    }

    /// The face to draw now: from the cache when it has been cut before, from
    /// this view's own cut when it has just been, and nothing while the first
    /// cut is on its way — the initial, for the same moment the list scrolls
    /// past a row.
    private var face: UIImage? {
        guard let faceKey else { return nil }
        if let hit = PortraitCache.cached(faceKey) { return hit }
        return cut?.key == faceKey ? cut?.image : nil
    }

    private var initial: String {
        guard let first = subject.displayTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
        else { return "" }
        return String(first).uppercased()
    }

    var body: some View {
        let face = face
        ZStack(alignment: .bottomTrailing) {
            Circle()
                // **Filled dark, and the fill is the whole of the fix.** A
                // cream disc on parchment measures **1.11:1** — `card` and
                // `paper` are nearly the same colour, which is the point of
                // them everywhere else — so a portrait was a letter floating
                // on the page with no shape around it. WCAG 1.4.11 asks 3:1
                // of anything that has to read as a shape.
                //
                // The ring was tried first and is not enough: `rule` is ink at
                // 16 %, 1.26:1 against the paper, and its own doc comment says
                // it is "a hairline, and only ever a hairline… never the only
                // edge of a control" — it was the only edge here. Even
                // `supporting` as a ring left `testPeople` red four times out
                // of four, because the disc behind it still did not read.
                //
                // A dark fill is also the only answer that works on BOTH
                // grounds. This avatar sits on `paper` in the people list and
                // on `card` in the gallery's rows, so any pale fill is
                // invisible on one of them; ink at 75 % clears 3:1 against
                // each.
                //
                // **An unconfirmed subject was accidentally fine all along**,
                // which is how this hid: its ring is `proposal` at 5.14:1 and
                // two points wide, so the one portrait that looked like a
                // portrait was the one the app is least sure about. It keeps
                // that ring, and the badge, and the words in the row.
                .fill(Elder.supporting)
                .overlay {
                    if let face {
                        // The picture over the ink, and the ink is still the
                        // edge: a photograph's own border pixels can be as
                        // pale as the paper — sky, a wall, an overexposed
                        // print — so the ring below is what gives the disc a
                        // shape (WCAG 1.4.11), and it is the same ink at 75 %
                        // the filled disc measured 3:1 with on both grounds.
                        Image(uiImage: face)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        Text(initial)
                            .font(Elder.display(.title3))
                            // Cream on ink, the same pair the record button and
                            // the blind card's answers use.
                            .foregroundStyle(Elder.cream)
                            // The letter is inside a circle; a long-descender
                            // glyph at the largest sizes would otherwise touch it.
                            .minimumScaleFactor(0.6)
                            .padding(2)
                    }
                }
                .overlay(
                    Circle().strokeBorder(
                        !subject.confirmed ? Elder.proposal : face == nil ? Color.clear : Elder.supporting,
                        lineWidth: !subject.confirmed || face != nil ? 2 : 0
                    )
                )
                .frame(width: size, height: size)

            if !subject.confirmed {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(Elder.proposal)
                    // On its own plate, so the badge does not sit half on the
                    // disc's hairline and half on the paper and read as neither.
                    .background(Circle().fill(Elder.paper).padding(-1))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: size + 6, height: size + 6, alignment: .topLeading)
        // The name is in the row beside it and the state is in the row's own
        // words. A lone capital letter read aloud before both is noise — and
        // so is "image", which is all a face could add.
        .accessibilityHidden(true)
        .task(id: faceKey) {
            guard let faceKey, let filename = photo?.imageFilename,
                  PortraitCache.cached(faceKey) == nil
            else { return }
            let (x, y) = (focusX, focusY)
            // Off the main thread: a list of forty rows decoding forty
            // thumbnails on it would be forty stutters.
            let image = await Task.detached(priority: .userInitiated) {
                PortraitCache.face(filename: filename, focusX: x, focusY: y)
            }.value
            if let image { cut = (faceKey, image) }
        }
    }
}
