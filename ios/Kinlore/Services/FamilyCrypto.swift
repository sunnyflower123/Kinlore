import CryptoKit
import Foundation

/// Encryption at rest under a key the server never sees. PLAN.md §10 lever 3.
///
/// The distinction the plan had wrong for a while, and the one this whole file
/// rests on: **a breach dumps the database. It does not dump audio that passed
/// through a Worker in June.** Transcription still sends the recording to the
/// Worker in clear, because rule 7 puts the model key there and a model cannot
/// write down speech it cannot hear. What changes is what is left behind
/// afterwards — the rows in D1 and the objects in R2, which are the things a
/// dump actually contains.
///
/// So this is not end-to-end encryption and must not be described as such
/// anywhere a user can read it. It is encryption at rest, and the honest
/// sentence is that the server stores what it cannot read.
///
/// **What it costs.** The key is the archive. Lose it and every memory is
/// ciphertext nobody can open — a worse failure than the breach it prevents,
/// measured against rule 3, which keeps the original audio precisely because
/// the speaker may not be there to ask again. `FamilyKey` puts it in the
/// Keychain with `kSecAttrSynchronizable`, the one mechanism ARCHITECTURE §4
/// has already verified survives deleting the app, and the export stays
/// readable because it is written on the device where the key already is.
enum FamilyCrypto {
    /// Version marker. One byte of foresight: a value that does not start with
    /// this is plaintext from before lever 3, and `open` hands it back
    /// unchanged rather than failing. There is no production data to migrate —
    /// R2 was never enabled and no family exists — but a demo archive on
    /// somebody's simulator is data too, and it should not turn into an error
    /// message.
    static let marker = "k1."

    // MARK: - Text

    /// Randomised. Two identical memories encrypt differently, which is what
    /// you want everywhere the server has no business comparing anything — and
    /// the server compares nothing about a memory's body.
    static func seal(_ plaintext: String, with key: SymmetricKey) -> String? {
        guard let box = try? AES.GCM.seal(Data(plaintext.utf8), using: key),
              let combined = box.combined
        else { return nil }
        return marker + combined.base64EncodedString()
    }

    /// Deterministic, for the one field the server has to compare.
    ///
    /// `sync.ts` decides whether a subject's coordinates survive an edit by
    /// asking whether the title changed — `CASE WHEN excluded.title IS NOT
    /// subject.title`. Under a random nonce the same title encrypts to a
    /// different string every push, so every push would read as a rename and
    /// quietly wipe the coordinates somebody's device had resolved.
    ///
    /// Deriving the nonce from the plaintext fixes it with no schema change and
    /// no server change at all. What it leaks is exactly what the comparison
    /// needs and nothing more: whether two titles are the same. A title is a
    /// place or a person's name, and the alternative — a second hashed column,
    /// a migration, and a rule split across two languages — leaks the same fact
    /// while costing more.
    static func sealDeterministically(_ plaintext: String, with key: SymmetricKey) -> String? {
        let bytes = Data(plaintext.utf8)
        // A synthetic nonce, keyed so that it cannot be recomputed by anybody
        // holding the ciphertext alone. Truncated to the 12 bytes AES-GCM
        // takes.
        let mac = HMAC<SHA256>.authenticationCode(for: bytes, using: key)
        guard let nonce = try? AES.GCM.Nonce(data: Data(mac).prefix(12)),
              let box = try? AES.GCM.seal(bytes, using: key, nonce: nonce),
              let combined = box.combined
        else { return nil }
        return marker + combined.base64EncodedString()
    }

    /// Opens a sealed string.
    ///
    /// **Plaintext passes through unchanged**, which is deliberate rather than
    /// lax: a value without the marker was written before this existed, and the
    /// alternative is a family whose older memories read as nothing at all.
    ///
    /// A value that *is* marked and does not open returns nil, and every caller
    /// treats that as "not shown" rather than "empty". That case means the
    /// wrong key — a device that joined with a stale invite — and showing it as
    /// blank would be the app claiming grandmother said nothing.
    static func open(_ value: String, with key: SymmetricKey) -> String? {
        guard value.hasPrefix(marker) else { return value }
        guard let raw = Data(base64Encoded: String(value.dropFirst(marker.count))),
              let box = try? AES.GCM.SealedBox(combined: raw),
              let opened = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: opened, encoding: .utf8)
    }

    // MARK: - Bytes

    /// Photos and audio, sealed before they are uploaded and opened after they
    /// come back. R2 holds the bytes; rule 3 says the original audio is the
    /// product, and this is the one place where "the product" and "the thing a
    /// breach hands out" are the same file.
    ///
    /// The audio is not re-encoded, here least of all — sealing is not
    /// encoding. What is uploaded is the exact bytes that were recorded, inside
    /// an envelope.
    static func seal(_ data: Data, with key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.seal(data, using: key),
              let combined = box.combined
        else { return nil }
        return Data(marker.utf8) + combined
    }

    static func open(_ data: Data, with key: SymmetricKey) -> Data? {
        let prefix = Data(marker.utf8)
        guard data.starts(with: prefix) else { return data }
        guard let box = try? AES.GCM.SealedBox(combined: data.dropFirst(prefix.count)),
              let opened = try? AES.GCM.open(box, using: key)
        else { return nil }
        return opened
    }
}
