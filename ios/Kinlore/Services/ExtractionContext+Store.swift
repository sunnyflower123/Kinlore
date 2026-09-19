import Foundation

/// The one line that hands `ExtractionContext.build` the archive.
///
/// Its own file because `MemoryStore` reaches `MediaStore` and so reaches
/// UIKit, while everything in `ExtractionContext.swift` is Foundation alone.
/// That is what lets `scripts/extraction-context-check.swift` compile on a
/// laptop and run inside `verify.sh` for nothing, instead of needing a booted
/// simulator to spawn a binary in.
extension MemoryStore {
    func extractionContext(for target: Subject?) -> ExtractionContext {
        ExtractionContext.build(
            target: target,
            subjects: subjects,
            memories: memories,
            relations: relations,
            questions: questions
        )
    }
}
