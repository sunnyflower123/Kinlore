import UIKit

/// Median nouto näkymille: paikallinen ensin, R2 tarvittaessa.
///
/// Lataus on tarvepohjainen eikä ennakoiva. Perheellä voi olla satoja kuvia,
/// eikä niitä pidä hakea kaikkia käynnistyksessä — vanhan puhelimen akku ja
/// mökin verkko eivät kestä sitä. Ruudukko hakee vain sen mitä näkyy.
@MainActor
enum MediaLoader {
    /// Varmistaa että kohteen kuva on paikallisesti, ja palauttaa tiedostonimen.
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

    /// Sama äänelle. Alkuperäinen ääni on lopputuotetta, joten sitä ei koodata
    /// uudelleen missään vaiheessa.
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
