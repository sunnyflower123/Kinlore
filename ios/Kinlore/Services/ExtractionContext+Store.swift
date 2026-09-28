import Foundation

/// What a telling is extracted against, read off the store: the archive that
/// `ExtractionContext.build` is handed, and the photograph.
///
/// Its own file because `MemoryStore` reaches `MediaStore` and so reaches
/// UIKit, while everything in `ExtractionContext.swift` is Foundation alone.
/// That is what lets `scripts/extraction-context-check.swift` compile on a
/// laptop and run inside `verify.sh` for nothing, instead of needing a booted
/// simulator to spawn a binary in.
///
/// Every road into extraction comes through these two: the Tell screen, the
/// interview's rounds, "Kirjoita se itse" and the catch-up that finishes a
/// recording whose text never arrived. Until 28 Sep 2026 the catch-up sent
/// neither, so a telling that waited for its words got questions about the
/// words alone, as every telling did before 19 Sep.
extension MemoryStore {
    /// `excluding` leaves one memory out of the archive: a recording already
    /// filed and waiting for its words is the telling being extracted, not
    /// one its card already had, and counted there it would tell the model
    /// the card holds one telling more than it does.
    func extractionContext(for target: Subject?, excluding memoryID: String? = nil) -> ExtractionContext {
        ExtractionContext.build(
            target: target,
            subjects: subjects,
            memories: memories.filter { $0.id != memoryID },
            relations: relations,
            questions: questions
        )
    }

    /// The photograph a telling is about, sized for the model, or nil.
    ///
    /// Only a `photo` subject, and only the picture as it was taken: a
    /// colourisation is the family's guess at the colours (rule 4, and only
    /// after somebody said yes to it), and asking a model what it sees in
    /// another model's output is a question about the wrong picture.
    ///
    /// Read on the main actor before the call rather than inside it, because
    /// this is disk work and the caller is already awaiting a network round —
    /// but it is one downsample of one file, which `MediaStore` does through
    /// ImageIO without decoding the whole image. Nil as well when the file is
    /// not on this phone.
    func modelPhoto(for subject: Subject?) -> Data? {
        guard let subject, subject.kind == .photo, let filename = subject.imageFilename else { return nil }
        return MediaStore.modelImage(named: filename)
    }
}
