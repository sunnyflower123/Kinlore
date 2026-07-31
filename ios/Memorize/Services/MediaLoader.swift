import UIKit

/// Fetching media for the views: local first, R2 when needed.
///
/// Fetching is on demand rather than eager. A family may have hundreds of
/// photos, and they must not all be fetched at launch — an old phone's battery
/// and a cottage's network will not take it. The grid fetches only what is
/// visible.
@MainActor
enum MediaLoader {
    /// Ensures the subject's photo is present locally and returns its filename.
    static func imageFilename(
        for subject: Subject,
        store: MemoryStore,
        session: Session
    ) async -> String? {
        if let filename = subject.imageFilename, MediaStore.exists(filename) {
            return filename
        }
        guard let key = subject.r2Key,
              let data = await fetch(key: key, session: session),
              let filename = MediaStore.saveRaw(data, extension: "jpg")
        else { return nil }

        store.setLocalImage(subjectID: subject.id, filename: filename)
        return filename
    }

    /// The same for audio. The original audio is the product, so it is never
    /// re-encoded at any point.
    static func audioFilename(
        for memory: Memory,
        store: MemoryStore,
        session: Session
    ) async -> String? {
        if let filename = memory.audioFilename, MediaStore.exists(filename) {
            return filename
        }
        guard let key = memory.audioR2Key,
              let data = await fetch(key: key, session: session),
              let filename = MediaStore.saveRaw(data, extension: "m4a")
        else { return nil }

        store.setLocalAudio(memoryID: memory.id, filename: filename)
        return filename
    }

    private static func fetch(key: String, session: Session) async -> Data? {
        guard let base = AppServices.apiBaseURL else { return nil }
        let client = MediaClient(baseURL: base, token: session.identity.token)
        return try? await client.download(key: key)
    }
}
