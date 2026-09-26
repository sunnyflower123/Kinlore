import UIKit

/// Fetching media for the views: local first, R2 when needed.
///
/// Fetching for the views is on demand rather than eager. A family may have
/// hundreds of photos, and they must not all be fetched at launch — an old
/// phone's battery and a cottage's network will not take it. The grid fetches
/// only what is visible. The archive's own copy is `FullCopy`'s job: the same
/// `fetch`, after a sync, on Wi-Fi, in the background.
@MainActor
enum MediaLoader {
    /// A photograph whose file has not left the phone that added it: no copy
    /// here and no key to fetch one by.
    ///
    /// On every other phone that is the card the server keeps when it refuses
    /// the file past the free ceiling — `pendingPayload` sends the card
    /// whether or not its file went up — or one whose upload has simply not
    /// happened yet.
    /// Either way nothing is being fetched, so nothing on screen may say that
    /// something is.
    static func hasNotArrived(_ subject: Subject) -> Bool {
        subject.kind == .photo && subject.imageFilename == nil && subject.r2Key == nil
    }

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

    /// The same for a photograph's confirmed colours.
    static func colourFilename(
        for subject: Subject,
        store: MemoryStore,
        session: Session
    ) async -> String? {
        if let filename = subject.colourImageFilename, MediaStore.exists(filename) {
            return filename
        }
        guard let key = subject.colourR2Key,
              let data = await fetch(key: key, session: session),
              let filename = MediaStore.saveRaw(data, extension: "jpg")
        else { return nil }

        store.setLocalColour(subjectID: subject.id, filename: filename)
        return filename
    }

    /// Fetches and unseals. PLAN.md §10 lever 3.
    ///
    /// Bytes that were never sealed pass through, so a family from before lever
    /// 3 still gets its photographs. Bytes that *are* sealed and will not open
    /// return nil rather than the envelope — the caller writes what it gets
    /// into the media store under a `.jpg` or `.m4a` name, and an envelope
    /// saved under those names is a file that fails to draw or play once, now,
    /// and every time afterwards from the local cache.
    static func fetch(key: String, session: Session) async -> Data? {
        guard let base = AppServices.apiBaseURL else { return nil }
        let client = MediaClient(baseURL: base, token: session.identity.token)
        guard let data = try? await client.download(key: key) else { return nil }
        guard let familyKey = FamilyKey.current() else { return data }
        return FamilyCrypto.open(data, with: familyKey)
    }
}
