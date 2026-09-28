import SwiftUI

/// The photograph on its own, as large as the screen allows, and closer when
/// asked.
///
/// A card draws its photograph a phone's width across, which is enough to know
/// the picture by and not enough to know the faces in it: in a group of twelve
/// each face is a few points wide. So the picture opens here, where a pinch or
/// a double tap brings it closer and a finger moves around it once it is.
///
/// It knows nothing of the screen that opens it: an image and the words
/// VoiceOver says for it in, a dismiss out. The words are the ones the picture
/// had where it was tapped, so VoiceOver names the same photograph on both
/// sides of the tap. It lives at `Screens/` because any screen with a
/// photograph may open it, and every one does so through
/// `opensToTheWholeScreen(_:label:)` below, which also brings it in
/// (`StepIn`).
///
/// Ink behind the photograph rather than the paper, because a print is looked
/// at against something darker than itself; cream on ink is the pair Elder.swift
/// already measures at 16.56:1. The close control is a word with a frame, not
/// an icon in a corner, because the person closing it is the one rule 1 is
/// about. It stands above the picture and not over it, so a photograph
/// brought close is never drawn behind it to take its contrast away, and it
/// comes first to VoiceOver.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stepIn) private var arrival

    let image: UIImage
    /// What VoiceOver calls the photograph: the same words as where it was
    /// opened from, already looked up there.
    let label: String

    /// How much closer than the whole picture: 1 is all of it on screen.
    @State private var zoom: CGFloat = 1
    /// How far the picture has been moved from the middle while closer.
    @State private var pan: CGSize = .zero
    /// Both as they were when the second finger came down.
    @State private var pinchStart: Hold?
    /// Where the picture and the finger were when a drag last took hold of it.
    @State private var dragStart: (pan: CGSize, translation: CGSize)?

    private struct Hold {
        var zoom: CGFloat
        var pan: CGSize
    }

    /// Four times the whole picture: a face in a group of twelve is the width
    /// of a thumb there, and past it the scan has no more to give.
    private static let closest: CGFloat = 4
    /// Where a double tap takes the picture, around the point tapped.
    private static let doubleTapZoom: CGFloat = 2.5

    var body: some View {
        // A column, the close control and then the picture's own room, and
        // not the control laid over a picture filling the screen. Over it,
        // the control came after the picture in the tree the UI tests read
        // whether it was declared after it with a sort priority or before
        // it with a z-index (measured 28 Sep 2026): that tree followed the
        // drawing. In a column the order written, the order drawn and the
        // order down the screen are one.
        VStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text("Sulje")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Elder.cream)
                    .padding(.horizontal, 24)
                    .elderTapTarget()
                    .overlay(Capsule().strokeBorder(Elder.cream, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .stepInFollows()
            .accessibilityIdentifier("photoViewer.close")

            GeometryReader { proxy in
                picture(in: proxy.size)
            }
            // A picture brought closer stays in its room, under the control
            // and never over it.
            .clipped()
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        // The container, so that a test can walk what is on this screen and
        // nothing of the one under it (`BlindConfirmationTests`).
        .accessibilityIdentifier("photoViewer")
        // VoiceOver's two-finger scrub closes it as it closes a sheet. A
        // cover has no such way out of its own, and the button is not the
        // only way a VoiceOver user expects.
        .accessibilityAction(.escape) { dismiss() }
    }

    /// The photograph centred in `size`, at the zoom and the pan, with every
    /// way of moving it.
    private func picture(in size: CGSize) -> some View {
        let whole = shown(in: size)
        return Image(uiImage: image)
            .resizable()
            // The picture is laid out a step short of the screen and comes the
            // rest of the way as it arrives, so that the approach every
            // photograph opens with (`StepIn`) ends with the whole picture on
            // screen rather than four per cent past its edges. Without the
            // approach — Reduce Motion — it stays that step short.
            .frame(width: whole.width / StepIn.approach, height: whole.height / StepIn.approach)
            .stepInApproach()
            .scaleEffect(zoom)
            .offset(pan)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("photoViewer.photo")
            .accessibilityZoomAction { action in
                let next = action.direction == .zoomIn
                    ? min(Self.closest, zoom * 2)
                    : max(1, zoom / 2)
                // Around the middle of the screen: the pan grows with the
                // picture, so what was in the middle stays there.
                let grown = CGSize(width: pan.width * next / zoom, height: pan.height * next / zoom)
                move(to: next, pan: grown, in: size)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2).onEnded { tap in
                    if zoom > 1 {
                        move(to: 1, pan: .zero, in: size)
                    } else {
                        // What was under the finger stays under it:
                        // offset = p − p · zoom for a point p from the middle.
                        let p = CGSize(width: tap.location.x - size.width / 2, height: tap.location.y - size.height / 2)
                        let next = Self.doubleTapZoom
                        move(to: next, pan: CGSize(width: p.width * (1 - next), height: p.height * (1 - next)), in: size)
                    }
                }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? Hold(zoom: zoom, pan: pan)
                        pinchStart = start
                        let next = min(Self.closest, max(1, start.zoom * value.magnification))
                        // The point between the fingers stays between them:
                        // offset = p − (p − offset₀) · zoom / zoom₀.
                        let p = CGSize(
                            width: value.startLocation.x - size.width / 2,
                            height: value.startLocation.y - size.height / 2
                        )
                        let ratio = next / start.zoom
                        zoom = next
                        pan = clamped(
                            CGSize(width: p.width - (p.width - start.pan.width) * ratio,
                                   height: p.height - (p.height - start.pan.height) * ratio),
                            at: next, in: size
                        )
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        // Not while a pinch holds the picture: the pinch moves
                        // it, and the drag takes hold again where the pinch
                        // left it rather than jumping by what the finger did
                        // meanwhile.
                        guard pinchStart == nil else {
                            dragStart = nil
                            return
                        }
                        let start = dragStart ?? (pan, value.translation)
                        dragStart = start
                        pan = clamped(
                            CGSize(width: start.pan.width + value.translation.width - start.translation.width,
                                   height: start.pan.height + value.translation.height - start.translation.height),
                            at: zoom, in: size
                        )
                    }
                    .onEnded { _ in dragStart = nil },
                including: zoom > 1 ? .all : .subviews
            )
    }

    /// Where a double tap or VoiceOver's zoom takes the picture: at once
    /// under Reduce Motion, which asks for exactly this kind of growth to be
    /// left out, and in a quarter of a second otherwise.
    private func move(to next: CGFloat, pan target: CGSize, in size: CGSize) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            zoom = next
            pan = clamped(target, at: next, in: size)
        }
    }

    /// The picture's size on screen at zoom 1: the image fitted into `size`,
    /// and a step short of that until it has arrived (`picture(in:)`).
    private func shown(in size: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let fit = min(size.width / image.size.width, size.height / image.size.height)
        return CGSize(width: image.size.width * fit, height: image.size.height * fit)
    }

    /// `pan`, held to what keeps the picture's edges at or past the screen's:
    /// a picture closer than the screen can be moved only as far as it is
    /// larger, and not at all along a side it does not fill.
    private func clamped(_ pan: CGSize, at zoom: CGFloat, in size: CGSize) -> CGSize {
        let whole = shown(in: size)
        let arrived = arrival.approached ? 1 : 1 / StepIn.approach
        let spare = CGSize(
            width: max(0, (whole.width * arrived * zoom - size.width) / 2),
            height: max(0, (whole.height * arrived * zoom - size.height) / 2)
        )
        return CGSize(
            width: min(spare.width, max(-spare.width, pan.width)),
            height: min(spare.height, max(-spare.height, pan.height))
        )
    }
}

extension View {
    /// This picture as a button that opens `image` to the whole screen
    /// (`PhotoViewer`), out of the picture and back into it, the way the
    /// album opens a card (`StepIn`).
    ///
    /// On every photograph the app draws large: the picture on its card and
    /// its colours under it, the proposal on the colouring's question, the
    /// Kerro tab's card and the blind card. Not on the face picker's
    /// photograph, where a tap chooses the face, and not on a thumbnail,
    /// which opens the card the picture is large on.
    ///
    /// `label` is what VoiceOver calls the picture on both sides of the tap,
    /// already looked up, and it is set here, on the button, so that the two
    /// cannot part: the picture passed in carries no label of its own.
    func opensToTheWholeScreen(_ image: UIImage, label: String) -> some View {
        modifier(OpensToTheWholeScreen(image: image, label: label))
    }
}

private struct OpensToTheWholeScreen: ViewModifier {
    let image: UIImage
    let label: String

    @State private var isOpen = false
    @Namespace private var namespace

    /// The one picture in `namespace`, which is this modifier's own.
    private static let source = "photograph"

    func body(content: Content) -> some View {
        Button {
            isOpen = true
        } label: {
            content
        }
        // Plain, so the picture keeps its own colours and a list row is not
        // lit as a row is.
        .buttonStyle(.plain)
        .stepInSource(Self.source, in: namespace)
        .accessibilityLabel(label)
        .accessibilityHint("Avaa kuvan koko näytölle.")
        .fullScreenCover(isPresented: $isOpen) {
            PhotoViewer(image: image, label: label)
                .steppedInto(from: Self.source, in: namespace)
        }
    }
}
