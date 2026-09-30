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
/// The photograph stays on the screen while it is told about (30 Sep 2026).
/// The colours are in the picture, and until then the sheet asked for them
/// over a photograph it did not show: the telling draws a picture only as
/// the Kerro tab's card, and the listening screen draws none. So the sheet
/// lays the photograph over the telling, at what the telling can spare
/// (`PhotographOverTelling`): the question, the disc, its caption and the
/// ways on keep the room they need in every language and at every text
/// size, and the photograph takes what is left, or is not drawn at all.
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    PhotographOverTelling(
                        aspect: photograph.size.height > 0 ? photograph.size.width / photograph.size.height : 1,
                        // The Kerro tab card's numbers (`IdleView`).
                        ceiling: typeSize.isAccessibilitySize ? 150 : 200
                    ) {
                        photographAbove
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
                        tellingNeeds
                    }
                    // The telling hangs its own paper; this is the photograph's.
                    .background(Elder.paper)
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

    // MARK: - The photograph over the telling

    /// The photograph, at the height `PhotographOverTelling` hands it less
    /// the margin over it, and nothing at all when it is handed nothing: a
    /// picture too small to see is not drawn, and a button of no size is not
    /// left for VoiceOver to find.
    ///
    /// A tap opens it to the whole screen, as on its card. The label says
    /// which photograph and nothing of what is in it, as the Kerro tab's
    /// card does: guessing at the content is what rule 4 forbids.
    private var photographAbove: some View {
        GeometryReader { proxy in
            if proxy.size.height > PhotographOverTelling.margin {
                Image(uiImage: photograph)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .opensToTheWholeScreen(photograph, label: String(localized: "Valokuva, josta kerrot"))
                    .frame(
                        width: max(0, proxy.size.width - 2 * Elder.screenPadding),
                        height: proxy.size.height - PhotographOverTelling.margin
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// What the telling has to keep in sight, whichever of its screens is
    /// up, laid out as those screens lay it out and never drawn: the
    /// photograph is given only what this leaves (`PhotographOverTelling`).
    ///
    /// Three screens decide it, and the tallest wins. The first is
    /// `IdleView` as its `Squeeze` leaves it on this sheet once it has given
    /// way: the question in the title's face, the reassurance's short form,
    /// the disc, its caption and the ways on, 8 points apart, with 8 of
    /// daylight under the last and 4 for rounding; at an accessibility size
    /// only the question and the disc, which is what it keeps above the fold
    /// there. The second is `RecordingView` as its own squeeze leaves it,
    /// with the question it is answering whole above the disc and the
    /// caption in sight, at every size: without it that question would keep
    /// only what the idle screen happened to leave it, and where it is more
    /// than the sheet has, the photograph is not drawn and the listening
    /// screen opens at the disc as it always has. The third is the screen
    /// that transcribes the telling and puts it in order, with its steps and
    /// the sentence that nothing is lost (30 Sep 2026): it scrolls, and is
    /// measured here so that the photograph never pushes a step out of
    /// sight. Writing is not here, because its keyboard leaves the
    /// photograph no room.
    ///
    /// A copy of another file's layout, and it drifts when that one changes;
    /// `testColourTellingKeepsThePhotograph` and `testColourTelling` are what
    /// notice.
    /// One of `ProcessingView`'s steps, as heavy as it is while under way.
    private func processingStep(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .frame(minWidth: 32)
            Text(text)
                .elderBody()
                .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
    }

    private var tellingNeeds: some View {
        let accessibility = typeSize.isAccessibilitySize
        return ZStack(alignment: .top) {
            VStack(spacing: 8) {
                Text(question.text)
                    .font(Elder.display(.largeTitle))
                if !accessibility {
                    // `IdleView.intro(short:)`, in the form its squeeze ends on.
                    Text(AudioRecorder.isPermissionUnasked
                        ? "Puhelin kysyy ensin luvan mikrofoniin."
                        : "Puhu ihan rauhassa ja kuuluvalla äänellä.")
                        .elderBody()
                }
                Color.clear
                    .frame(height: Elder.recordButtonSize)
                if !accessibility {
                    Text("Paina ja ala puhua")
                        .font(.headline)
                        .padding(.top, 20)
                    Label("Kirjoita sen sijaan", systemImage: "keyboard")
                        .font(.body.weight(.medium))
                        .elderTapTarget()
                    if hasTold {
                        Label("Väritä jo kerrotun mukaan", systemImage: "paintpalette")
                            .font(.body.weight(.medium))
                            .elderTapTarget()
                    }
                }
            }
            .padding(.horizontal, Elder.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)

            // `RecordingView`, answering this question, with `air` and
            // `waveform` taken: the gaps 14, the disc 14 clear above and
            // below, the waveform 56.
            VStack(spacing: 14) {
                Text("Kuuntelen")
                    .font(.largeTitle.weight(.semibold))
                Text(question.text)
                    .font(Elder.display(.title3))
                    .lineSpacing(Elder.lineSpacing)
                Color.clear
                    .frame(height: 56)
                Text(verbatim: "0:00")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Color.clear
                    .frame(height: Elder.recordButtonSize)
                    .padding(.vertical, 14)
                Text("Paina kun olet valmis")
                    .font(.headline)
            }
            .padding(.horizontal, Elder.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)

            // `ProcessingView` at its tallest: the larger of its two marks of
            // work, the longer of its two titles, all three steps as heavy as
            // the one under way, and the sentence that nothing is lost, which
            // it shows whenever the recording has left tmp
            // (`TellViewModel.recordingIsKept`).
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                ZStack {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 56))
                    ProgressView()
                        .controlSize(.extraLarge)
                }
                ZStack {
                    Text("Kuuntelen mitä sanoit")
                    Text("Järjestelen muistoa")
                }
                .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 18) {
                    processingStep("Äänesi on tallessa tässä puhelimessa")
                    processingStep("Puran puheen tekstiksi.")
                    processingStep("Etsin ihmiset, paikat ja ajankohdan.")
                }
                Text("Vaikka tämä kestäisi hetken, kertomasi ei katoa.")
                    .elderBody()
                Spacer(minLength: 0)
            }
            .padding(Elder.screenPadding)
        }
        .multilineTextAlignment(.center)
        .hidden()
        .accessibilityHidden(true)
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

/// The photograph over the telling, at the height the telling can spare.
///
/// Three views, in this order: the photograph, the telling, and what the
/// telling has to keep in sight (`ColourSheet.tellingNeeds`), which is
/// measured for this width and never drawn. The photograph gets the sheet's
/// height less that, up to `ceiling` and never taller than it is at the
/// sheet's width, and under `floor` it gets nothing.
///
/// Measured in the pass that places the telling, and not proposed to it or
/// read back a pass later, because `IdleView` measures its room once, when it
/// first lays out: a photograph that arrived after that would stand on room
/// the idle screen had already given to its rows.
///
/// And a telling without the photograph keeps to what it needs, rather than
/// taking the whole sheet, because the first pass is not the last. The sheet
/// first lays out short, by 52 points at the default size and more at larger
/// ones (measured on the 17 Pro and the SE, 30 Sep 2026), and on the 17 Pro at
/// XXXL that left the photograph under the floor for that pass. The telling
/// took the whole short sheet, `IdleView` measured it and gave way to
/// nothing, and a pass later the photograph came in above it: "Väritä jo
/// kerrotun mukaan" ended 52 points below the sheet. A telling that never
/// takes more than it needs measures the same room in both passes. What that
/// leaves over, less than the floor and the margin, is paper above it: 40
/// points on the SE at the default size, where the photograph would have had
/// 32. A photograph too wide to be drawn at any height leaves the telling the
/// whole sheet, since the width does not change between passes.
private struct PhotographOverTelling: Layout {
    /// The photograph's width over its height.
    let aspect: CGFloat
    /// The tallest the photograph is drawn.
    let ceiling: CGFloat

    /// The least the photograph is drawn at, which is a button's
    /// (`Elder.minTapTarget`): a tap opens it to the whole screen. Lower than
    /// the Kerro tab card's 100, the height below which a face stops being
    /// something to recognise, because nobody is asked who is in this one: it
    /// says which picture the colours are asked about. And the lower the
    /// floor, the fewer the sizes at which paper stands where it would be.
    static let floor: CGFloat = Elder.minTapTarget
    /// Paper between the navigation bar and the photograph.
    static let margin: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let across = ProposedViewSize(width: bounds.width, height: nil)
        let needed = subviews[2].sizeThatFits(across).height
        let wide = max(0, bounds.width - 2 * Elder.screenPadding) / max(aspect, 0.01)
        let height = min(ceiling, wide, bounds.height - needed - Self.margin)
        let photograph: CGFloat
        let telling: CGFloat
        if height >= Self.floor {
            photograph = height + Self.margin
            telling = bounds.height - photograph
        } else if wide < Self.floor {
            photograph = 0
            telling = bounds.height
        } else {
            photograph = 0
            telling = min(bounds.height, needed)
        }

        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: photograph))
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - telling),
            proposal: ProposedViewSize(width: bounds.width, height: telling)
        )
        subviews[2].place(at: bounds.origin, proposal: across)
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
