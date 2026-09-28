import SwiftUI
import UIKit

/// A photograph coloured by what was told about it — asked for first, and
/// answered before anything is kept.
///
/// The sheet opens on the card's own telling, titled *"Mitä värejä muistat
/// tästä kuvasta?"*, because the colours are what the model cannot see and a
/// person may remember (28 Sep 2026; until then the button coloured at once
/// from whatever had been told, which was rarely about colour). Saved, the
/// telling hands over to the colouring by itself and is the first thing the
/// model reads. It is a telling like any other: its recording and raw
/// transcript are kept (rule 3), and it is kept when the month's colourings
/// are spent (rule 2). Somebody with nothing to add has a second way, from
/// what has been told before, whenever something has.
///
/// The model's picture is a proposal: the lock lays only its hue on the
/// photograph's own brightness, and refuses one whose shapes moved. What
/// survives waits on this screen for a person. "Kyllä" keeps it beside the
/// original, marked in its own pixels. "Ei, kerron lisää" asks for the colours
/// again, so the next round is coloured by the correction. "En tiedä" keeps
/// nothing, and that is an answer: rule 5 stores uncertainty rather than
/// rounding it into a yes.
struct ColourSheet: View {
    @Environment(MemoryStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    let subject: Subject
    let photograph: UIImage

    private enum Phase {
        case telling
        case colouring
        case proposal(UIImage)
        case refused(String)
    }

    @State private var phase = Phase.telling
    /// One more for every hand-over to the colouring, which is what runs it.
    @State private var round = 0
    /// A telling was saved on this sheet, and a refusal says it is kept.
    @State private var toldHere = false

    var body: some View {
        NavigationStack {
            Group {
                if case .telling = phase {
                    // One screen in place of another, and not a second sheet:
                    // a sheet cannot be presented over one that is leaving,
                    // and the correction comes back here the same way.
                    TellScreen(
                        target: subject,
                        question: question,
                        onClose: { dismiss() },
                        onTold: {
                            toldHere = true
                            colourNow()
                        },
                        onColourFromTold: hasTold ? { colourNow() } : nil
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch phase {
                            case .telling, .colouring:
                                colouring
                            case .proposal(let coloured):
                                proposal(coloured)
                            case .refused(let reason):
                                refused(reason)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Elder.screenPadding)
                    }
                    .elderSurface()
                }
            }
            .navigationTitle("Värit kerronnan mukaan")
            .navigationBarTitleDisplayMode(.inline)
        }
        // The accent, named. Without this the answers here were drawn in the
        // system blue — measured from the audit's own screenshot, white on
        // #0088FF, 13 Sep 2026 — while the ask sheet presented from the same
        // card keeps the app's accent. What stops it reaching this sheet was
        // not isolated; naming the asset is what brought it back, and the
        // sweep is what says so.
        .tint(Color("AccentColor"))
        .task(id: round) {
            guard round > 0 else { return }
            await colour()
        }
    }

    /// The question the telling opens on: concrete, and answered in a word or
    /// two, like the ladder's starters (`QuestionLadder.starters(for:)`). A
    /// prompt like them, too, which no row holds and nothing marks answered.
    private var question: FollowUpQuestion {
        FollowUpQuestion(
            id: "colours-\(subject.id)",
            subjectID: subject.id,
            text: String(localized: "Mitä värejä muistat tästä kuvasta?"),
            storedLevel: QuestionLevel.naming.rawValue
        )
    }

    /// Whether anything with words has been told about the photograph, which
    /// is what the second way colours from.
    private var hasTold: Bool {
        store.memories(for: subject.id).contains {
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func colourNow() {
        phase = .colouring
        round += 1
    }

    // The ways out are rows on the screen and not a toolbar button: a toolbar
    // button's text barely grows with Dynamic Type, which put the way out of
    // `AskQuestionSheet` in the smallest text on it.
    private var colouring: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressView()
            Text("Väritetään kerronnan mukaan…")
                .elderBody()
            answer(Text("Peruuta"), prominent: false) { dismiss() }
        }
    }

    private func proposal(_ coloured: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Opened to the whole screen by a tap, as the photograph it colours
            // is: the question is whether it looks right, and the answer is
            // in the faces as much as in the sky.
            Image(uiImage: coloured)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .opensToTheWholeScreen(
                    coloured,
                    label: String(localized: "Väritetty ehdotus. Värit ovat tekoälyn arvaus siitä, mitä kuvasta on kerrottu.")
                )

            Text("Näyttääkö tältä?")
                .font(Elder.display(.title2))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // The colours, and not "anything": a telling saved on this sheet
            // is already in the archive.
            Text("Värit on arvattu kuvasta kerrotun mukaan. Niitä ei tallenneta, ellet vahvista.")
                .elderBody()
                .foregroundStyle(Elder.supporting)

            answer(Text("Kyllä, tallenna värit"), prominent: true) { keep(coloured) }
            answer(Text("Ei, kerron lisää"), prominent: false) { phase = .telling }
            answer(Text("En tiedä"), prominent: false) { dismiss() }
        }
    }

    private func refused(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(reason)
                .elderBody()
            // A spent month, or a colouring that failed, takes nothing that
            // was told (rule 2), and the one who told it is the one reading.
            if toldHere {
                Text("Kertomasi on tallessa kuvan kortilla.")
                    .elderBody()
            }
            answer(Text("Sulje"), prominent: false) { dismiss() }
        }
    }

    /// One of the answers, full width.
    ///
    /// "Kyllä" is the screen's one prominent button (ARCHITECTURE §22). The
    /// others are ink on the paper inside an ink outline rather than iOS's
    /// `.bordered`, which draws the accent on a wash of itself: on this
    /// parchment the audit measured "Ei, kerron lisää" as nearly failing even
    /// once the accent was right (13 Sep 2026), and an outline has no wash to
    /// lose contrast to. The 60-point minimum goes on the button and not on the
    /// text, and the text may wrap (`AskQuestionSheet`).
    ///
    /// Handed a `Text` rather than a key, so that each answer is written as
    /// `Text("…")` at its call site, where `localisation-check.mjs` looks.
    @ViewBuilder
    private func answer(_ title: Text, prominent: Bool, action: @escaping () -> Void) -> some View {
        let label = title
            .font(.body.weight(prominent ? .semibold : .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .elderTapTarget()
        } else {
            Button(action: action) {
                label
                    .foregroundStyle(.primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(minHeight: Elder.minTapTarget)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary, lineWidth: 2))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Colouring

    private func colour() async {
        let failed = String(localized: "Väritys ei onnistunut. Kuva on ennallaan.")
        guard let original = photograph.cgImage else {
            phase = .refused(failed)
            return
        }
        let framing = ColourLock.framing(width: original.width, height: original.height)
        // Newest first: the Worker's instruction follows the first quotation
        // where two disagree, so a correction told a minute ago outranks the
        // telling it corrects.
        let told = store.memories(for: subject.id)
            .sorted { $0.createdAt > $1.createdAt }
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            guard let canvas = ColourLock.canvas(for: original, framing: framing) else {
                phase = .refused(failed)
                return
            }
            let service = AppServices.colourisation { session.identity.token }
            let reply = try await service.colourise(canvas: canvas, told: told, aspect: framing.aspect)
            guard let picture = ColourLock.image(from: reply) else {
                phase = .refused(failed)
                return
            }
            // A 2048-pixel photograph is a few million pixels of arithmetic,
            // and none of it belongs on the main thread.
            let outcome = await Task.detached(priority: .userInitiated) {
                ColourLock.lock(original: original, reply: picture, framing: framing)
            }.value
            switch outcome {
            case .kept(let coloured)?:
                phase = .proposal(ColourMark.stamped(coloured))
            case .moved?:
                phase = .refused(String(
                    localized: "Väritys muutti kuvan muotoja, joten sitä ei näytetä. Kuva on ennallaan."
                ))
            case nil:
                phase = .refused(failed)
            }
        } catch is CancellationError {
            return
        } catch let error as RemoteError where error.isQuota {
            phase = .refused(error.errorDescription ?? failed)
        } catch {
            phase = .refused(failed)
        }
    }

    private func keep(_ coloured: UIImage) {
        guard let data = coloured.jpegData(compressionQuality: 0.9),
              let filename = MediaStore.saveRaw(data, extension: "jpg")
        else {
            phase = .refused(String(localized: "Väritys ei onnistunut. Kuva on ennallaan."))
            return
        }
        store.setColour(
            subjectID: subject.id,
            filename: filename,
            confirmedByID: session.identity.memberID,
            confirmedByName: store.authorName
        )
        dismiss()
    }
}

/// The mark that says the colours are a guess, drawn into the picture itself.
///
/// A caption does not travel. A screenshot, a print or a file sent onwards
/// carries the pixels and nothing else, and a colour photograph of a
/// great-grandmother with nothing on it reads as a photograph of her in colour.
/// So the palette goes into the image, in the bottom-left corner.
///
/// Black on paper inside a black ring: the mark is a graphic, and a graphic
/// needs 3:1 against whatever is around it. A disc of paper alone would have
/// no edge at all on a pale sky; the ring gives it one on any photograph.
private enum ColourMark {
    static func stamped(_ image: CGImage) -> UIImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))

            let diameter = max(48, min(size.width, size.height) * 0.11)
            let inset = diameter * 0.3
            let disc = CGRect(x: inset, y: size.height - diameter - inset, width: diameter, height: diameter)
            let ring = UIBezierPath(ovalIn: disc)
            (UIColor(named: "Paper") ?? .white).setFill()
            ring.fill()
            ring.lineWidth = max(2, diameter * 0.06)
            UIColor.black.setStroke()
            ring.stroke()

            let glyph = UIImage(
                systemName: "paintpalette.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.46, weight: .semibold)
            )?.withTintColor(.black, renderingMode: .alwaysOriginal)
            if let glyph {
                glyph.draw(in: CGRect(
                    x: disc.midX - glyph.size.width / 2,
                    y: disc.midY - glyph.size.height / 2,
                    width: glyph.size.width,
                    height: glyph.size.height
                ))
            }
        }
    }
}
