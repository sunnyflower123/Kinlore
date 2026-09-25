import CoreImage
import Foundation

/// Colouring a photograph by what was told about it.
///
/// The real implementation sends the framed photograph and the tellings to the
/// Worker, which asks the image model — the key never reaches the app, and the
/// Worker refuses a photograph nobody has told anything about. What comes back
/// is a proposal and nothing more: `ColourLock` decides whether it can be laid
/// on the photograph at all, and a person decides whether it is kept
/// (`ColourSheet`).
protocol ColourisationService {
    /// The model's picture for `canvas`, as image bytes. `told` is newest
    /// first: the instruction the Worker gives says the first quotation wins
    /// where two disagree, which is what makes a correction count.
    func colourise(canvas: Data, told: [String], aspect: String) async throws -> Data
}

/// The development implementation: the canvas back, tinted warm, with every
/// edge where it was — what a model that behaves answers — so the whole of it
/// can be walked through without a key, a network or a cent.
struct StubColourisationService: ColourisationService {
    var simulatedDelay: Duration = .milliseconds(900)

    func colourise(canvas: Data, told: [String], aspect: String) async throws -> Data {
        try await Task.sleep(for: simulatedDelay)
        #if DEBUG
        // The film's own captured reply, when a shooting day has put one in
        // the container. Same arrangement as `MemoryStore.filmPhotoFile()` and
        // the same reason as `StubExtractionService.filmResult`: what a take
        // shows has to be what the real pipeline answered, not what a
        // development stub invented. `ColourLock` still decides how much of it
        // may be laid on the photograph, so this is a reply and not a result.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let captured = try? Data(contentsOf: documents.appendingPathComponent("film-coloured.jpg")),
           !captured.isEmpty {
            return captured
        }
        #endif
        guard let input = CIImage(data: canvas) else { throw RemoteError.emptyResult }
        let tinted = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1.08, y: 0.06, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0.02, w: 0),
            "inputBVector": CIVector(x: 0, y: 0.08, z: 0.78, w: 0),
        ])
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = CIContext().jpegRepresentation(of: tinted, colorSpace: space)
        else { throw RemoteError.emptyResult }
        return data
    }
}
