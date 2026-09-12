import SwiftUI

/// A person or a place as a disc with their initial in it.
///
/// The app has no portraits and cannot get any: `imageFilename` is written
/// only for `.photo` subjects — the camera and the import set it, nothing else
/// does — so there is no face on file for anybody the archive knows by name.
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
    let subject: Subject

    /// Grows with Dynamic Type, because the letter inside it does. A fixed
    /// disc with a scaling glyph in it is a clipped glyph at XXXL, which is
    /// the audit's most common finding and rule 1's most common failure.
    @ScaledMetric private var size: CGFloat

    init(subject: Subject, size: CGFloat = 40) {
        self.subject = subject
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    private var initial: String {
        guard let first = subject.displayTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
        else { return "" }
        return String(first).uppercased()
    }

    var body: some View {
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
                .overlay(
                    Circle().strokeBorder(
                        subject.confirmed ? Color.clear : Elder.proposal,
                        lineWidth: subject.confirmed ? 0 : 2
                    )
                )
                .overlay {
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
        // words. A lone capital letter read aloud before both is noise.
        .accessibilityHidden(true)
    }
}
