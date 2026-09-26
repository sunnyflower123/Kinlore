import AVFoundation
import SwiftUI

/// Photographing paper photographs.
///
/// The archive's whole premise is that somebody's memories are in a shoebox,
/// and until this existed there was no way to get them in: the only import was
/// `PhotosPicker`, which reads the phone's own library. An 80-year-old's
/// photographs are not in iCloud. They are in an album on a shelf, and the
/// person who will photograph them is the grandchild — in one sitting, at a
/// table, thirty of them.
///
/// **That sitting is what this screen is shaped by, and it decides one thing
/// above all: the shutter does not close.** After a shot the camera stays where
/// it is and the line under it changes to *"Tallennettu. Kuvaa seuraava."* An
/// album is thirty photographs; returning to the gallery after each one is
/// thirty round trips, and it is the point at which the job is abandoned
/// half-done. Nothing else on this screen matters as much.
///
/// **No cropping, no deskewing, no correction.** Each of those is its own
/// swamp and none is needed to remember a face. A photograph of a photograph
/// is a photograph. `MediaStore.save(imageData:)` downscales it exactly as it
/// does a picked one, and the row it produces is the same row — a `subject`
/// with an empty title, because nobody will name thirty scanned photographs
/// and the name arrives when somebody talks about it.
///
/// **Nothing is drawn over the preview.** Text on a live camera image has no
/// contrast to measure and the audit is right to say so, so the preview takes
/// the top and every word sits on a solid ground below it. The same shape as
/// the rest of the app: what has to be readable is pinned, and the picture
/// takes what is left.
struct CameraScreen: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Offered wherever the camera cannot be, so that a refusal is never a dead
    /// end — the same trade as the refused microphone (ARCHITECTURE §8.9): the
    /// way out is replaced by the way on, rather than being made prettier.
    let pickFromLibraryInstead: () -> Void

    @State private var camera = CameraSession()
    @State private var captured = 0
    /// True for a moment after a shot, so the hint can say the photograph
    /// arrived. A count alone does not: numbers change quietly.
    @State private var justSaved = false

    var body: some View {
        NavigationStack {
            Group {
                switch camera.state {
                case .checking:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    capturing
                case .denied:
                    wayOut(
                        title: String(localized: "Kamera ei ole käytössä"),
                        detail: String(localized: "Kuvaaminen tarvitsee luvan kameraan. Voit antaa sen puhelimen asetuksista — tai valita kuvia puhelimen omista kuvista."),
                        offersSettings: true
                    )
                case .unavailable:
                    wayOut(
                        title: String(localized: "Tässä laitteessa ei ole kameraa"),
                        detail: String(localized: "Voit silti lisätä vanhoja valokuvia puhelimen omista kuvista."),
                        offersSettings: false
                    )
                }
            }
            .navigationTitle("Kuvaa vanha valokuva")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Capturing

    private var capturing: some View {
        VStack(spacing: 0) {
            // The preview, and the only thing on this screen that gives way.
            // A minimum height rather than a fraction: at the largest text size
            // the words below grow and the picture yields to them, but never so
            // far that the person cannot see what they are aiming at.
            CameraPreview(session: camera.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 200)
                .clipped()
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                // Said before the count, because the first shot has no count
                // and the screen must still say what to do.
                Text(hint)
                    .elderBody()
                    .foregroundStyle(justSaved ? Elder.affirmative : Elder.supporting)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await shoot() }
                } label: {
                    // A disc, like the record button, and for the same reason:
                    // it has to be findable without reading. Smaller than that
                    // one at 96 pt against 200 — this screen belongs to the
                    // grandchild, and a 200 pt disc would take the picture's
                    // place on it.
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 96, height: 96)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(camera.isCapturing)
                .elderTapTarget()
                .accessibilityLabel("Kuvaa")

                if captured > 0 {
                    Text(captured == 1
                        ? String(localized: "Kuvattu 1 kuva")
                        : String(localized: "Kuvattu \(captured) kuvaa"))
                        .font(.subheadline)
                        .foregroundStyle(Elder.supporting)
                        .fixedSize(horizontal: false, vertical: true)
                }

                done
            }
            .padding(Elder.screenPadding)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
        }
    }

    private var hint: String {
        if justSaved {
            return String(localized: "Tallennettu. Kuvaa seuraava.")
        }
        return captured == 0
            ? String(localized: "Aseta vanha valokuva näkyviin ja paina.")
            : String(localized: "Aseta seuraava kuva näkyviin.")
    }

    private func shoot() async {
        guard let data = await camera.capture() else { return }
        guard let filename = MediaStore.save(imageData: data) else { return }
        // The identical row a picked photograph makes. The title is left empty
        // on purpose — see `GalleryScreen.importPhotos`, which says why.
        store.add(Subject(kind: .photo, title: "", imageFilename: filename))
        captured += 1
        justSaved = true
        try? await Task.sleep(for: .seconds(2))
        justSaved = false
    }

    // MARK: - When the camera cannot be used

    private func wayOut(title: String, detail: String, offersSettings: Bool) -> some View {
        // Scrolling, as the onboarding fork does. A centred stack taller than
        // the screen overflows both ends, and at the largest text size the
        // heading ran up over the bar's title while the way out sat below the
        // bottom edge (the English read-through of 26 Sep 2026, 071).
        GeometryReader { proxy in
            ScrollView {
                wayOutStack(title: title, detail: detail, offersSettings: offersSettings)
                    .padding(Elder.screenPadding)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func wayOutStack(title: String, detail: String, offersSettings: Bool) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .elderBody()
                .foregroundStyle(Elder.supporting)
                .multilineTextAlignment(.center)

            // The settings row opens the place itself rather than describing
            // how to get there: four taps into a list of apps is the one
            // instruction this audience is least able to follow.
            if offersSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Avaa asetukset")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .elderTapTarget()
            }

            Button {
                dismiss()
                pickFromLibraryInstead()
            } label: {
                Label("Valitse kuvista", systemImage: "photo.on.rectangle.angled")
                    .font(.body.weight(offersSettings ? .medium : .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .elderPrimary(!offersSettings)
            .elderTapTarget()

            done

            Spacer(minLength: 0)
        }
    }

    /// The way off this screen, and a row rather than a toolbar button.
    ///
    /// It was a toolbar button, and the audit reported it on all three of this
    /// screen's states as "Dynamic Type font sizes are partially unsupported"
    /// — which `AskQuestionSheet` had already met and written down: a toolbar
    /// button's text barely grows, so the way out of a screen ends up in the
    /// smallest text on it. That is the wrong place for the only control that
    /// is on every state of this one.
    private var done: some View {
        Button("Valmis") { dismiss() }
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .elderTapTarget()
    }
}

// MARK: - The session

/// The capture session, and the permission in front of it.
///
/// `AVCaptureSession` rather than `UIImagePickerController`, and the batch loop
/// is the whole reason: the picker's camera dismisses itself on "Use Photo",
/// and fighting it back open for every one of thirty photographs is more code
/// than owning the session — with a worse result, because the shutter would
/// blink through a confirmation screen nobody asked for each time.
@Observable
final class CameraSession: NSObject, AVCapturePhotoCaptureDelegate {
    enum State: Equatable { case checking, ready, denied, unavailable }

    private(set) var state: State = .checking
    private(set) var isCapturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    /// `startRunning` blocks until the hardware is up, which on the main actor
    /// is a frozen screen.
    private let queue = DispatchQueue(label: "kinlore.camera")
    private var pending: CheckedContinuation<Data?, Never>?

    @MainActor
    func start() async {
        #if DEBUG
        // The states behind a permission answer, reachable without one. The
        // same hole `-mic denied` was written for, and worse here: the
        // simulator has no camera at all, so `.ready` is unreachable on the
        // one device every test and screenshot run uses. `-camera stub` draws
        // the controls over an empty preview so the audit can measure them.
        switch UserDefaults.standard.string(forKey: "camera") {
        case "denied": state = .denied; return
        case "unavailable": state = .unavailable; return
        case "stub": state = .ready; return
        default: break
        }
        #endif

        guard AVCaptureDevice.default(for: .video) != nil else {
            state = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }

        configure()
        state = .ready
    }

    func stop() {
        queue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    private func configure() {
        queue.async { [session, output] in
            guard !session.isRunning else { return }
            session.beginConfiguration()
            session.sessionPreset = .photo
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    /// One photograph, as bytes. Nil when the capture failed, which the caller
    /// answers by doing nothing: a shutter that produced no file is a shutter
    /// worth pressing again, and an error message over a camera is a sentence
    /// nobody reads.
    @MainActor
    func capture() async -> Data? {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "camera") == "stub" { return nil }
        #endif
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await withCheckedContinuation { continuation in
            pending = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let continuation = pending
        pending = nil
        continuation?.resume(returning: data)
    }
}

// MARK: - The preview

/// The live image. A `UIView` whose backing layer *is* the preview layer, so
/// there is no second layer to keep in step with the view's bounds.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.layer.session = session
        view.layer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer {
            super.layer as! AVCaptureVideoPreviewLayer
        }
    }
}
