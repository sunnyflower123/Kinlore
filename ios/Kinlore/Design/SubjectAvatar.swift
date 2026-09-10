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
                .fill(Elder.card)
                .overlay(
                    Circle().strokeBorder(
                        subject.confirmed ? Elder.rule : Elder.proposal,
                        lineWidth: subject.confirmed ? 1 : 2
                    )
                )
                .overlay {
                    Text(initial)
                        .font(Elder.display(.title3))
                        .foregroundStyle(.primary)
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
