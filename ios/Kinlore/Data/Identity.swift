import CryptoKit
import Foundation
import Security

/// The device's identity: a UUID and a random secret in the Keychain.
///
/// No login screen. An 80-year-old sees none of this — she gets an invite link
/// from a grandchild and she is in. See docs/ARCHITECTURE.md §4.
struct Identity {
    let memberID: String
    let secret: String

    /// Bearer token in the form `<member_id>.<secret>`.
    var token: String { "\(memberID).\(secret)" }

    /// Loads the existing identity or creates a new one. Creation happens once
    /// in the lifetime of a device — or once in the lifetime of an Apple
    /// account, because the Keychain entry syncs via iCloud to the user's other
    /// devices.
    static func loadOrCreate() -> Identity {
        if let memberID = Keychain.read(Keychain.memberIDKey),
           let secret = Keychain.read(Keychain.secretKey) {
            return Identity(memberID: memberID, secret: secret)
        }

        // An old partial state is cleaned away: half an identity is worse than
        // none, because the server would reject it silently.
        Keychain.delete(Keychain.memberIDKey)
        Keychain.delete(Keychain.secretKey)

        let identity = Identity(memberID: UUID().uuidString, secret: Self.randomSecret())
        Keychain.write(identity.memberID, for: Keychain.memberIDKey)
        Keychain.write(identity.secret, for: Keychain.secretKey)
        return identity
    }

    /// Throws the identity away. The next `loadOrCreate` makes a new one, which
    /// is the whole point: after "Tyhjennä tämä laite" the device has to be a
    /// stranger to the server, or the next sync would quietly pull the archive
    /// back in. Keychain entries survive deleting the app on purpose (§4) — this
    /// is the one place that is not what the user asked for.
    static func forget() {
        Keychain.delete(Keychain.memberIDKey)
        Keychain.delete(Keychain.secretKey)
    }

    /// 32 bytes of randomness as hex. This is not a password but a key, so
    /// length replaces memorability.
    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // In practice this does not happen, but a silently weak key would be
            // worse than crashing.
            bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// The family's encryption key. PLAN.md §10 lever 3.
///
/// One key per family, made by whoever creates it and carried to everyone else
/// in the invitation. The server never sees it: it is not in the invite the
/// Worker issues, only in the text a person sends to their grandmother.
///
/// **This key is the archive.** Lose it on every device at once and every
/// memory is ciphertext nobody can open — which fails rule 3 more completely
/// than never encrypting would, since rule 3 keeps the original audio precisely
/// because the speaker may not be there to ask again. Three things stand
/// between here and that:
///
/// - it lives in the Keychain with `kSecAttrSynchronizable`, so it follows an
///   Apple account to the next phone, which ARCHITECTURE §4 has verified
///   survives deleting the app;
/// - every member of the family holds the same key, so one lost phone loses
///   nothing;
/// - the export is written on a device that has the key, so what leaves the app
///   leaves readable.
///
/// It is deliberately not derived from the member secret. That secret is
/// per-device and is rotated by "Tyhjennä tämä laite"; a key derived from it
/// would take the archive with it.
enum FamilyKey {
    /// Base64 of 32 bytes, as it travels in an invitation and rests in the
    /// Keychain. A string rather than `Data` because both of those places take
    /// strings.
    static func create() -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        store(key)
        return key
    }

    static func current() -> SymmetricKey? {
        guard let raw = Keychain.read(Keychain.familyKeyKey),
              let data = Data(base64Encoded: raw),
              data.count == 32
        else { return nil }
        return SymmetricKey(data: data)
    }

    static func store(_ key: SymmetricKey) {
        let raw = key.withUnsafeBytes { Data($0) }.base64EncodedString()
        Keychain.write(raw, for: Keychain.familyKeyKey)
    }

    /// Takes a key out of an invitation. Returns false rather than storing
    /// something the wrong length: a key that is nearly right is a family whose
    /// memories all fail to open, one at a time, long after joining.
    @discardableResult
    static func adopt(_ shared: String) -> Bool {
        guard let data = Data(base64Encoded: standardBase64(from: shared)), data.count == 32
        else { return false }
        Keychain.write(data.base64EncodedString(), for: Keychain.familyKeyKey)
        return true
    }

    /// As it is written into an invitation: base64url, so that it survives being
    /// a query parameter without percent-encoding and survives being read off a
    /// message and pasted by hand. Ordinary base64 carries `+`, `/` and `=`, and
    /// every one of those is a way for an invitation to arrive subtly wrong.
    static func shareable() -> String? {
        guard let raw = Keychain.read(Keychain.familyKeyKey) else { return nil }
        return raw
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func standardBase64(from shared: String) -> String {
        var value = shared
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        return value
    }

    /// Leaving a family, or emptying the device. The key belongs to the family
    /// rather than to this phone, and a phone that is no longer in the family
    /// has no business keeping the means to read it.
    static func forget() {
        Keychain.delete(Keychain.familyKeyKey)
    }

    /// What `Session.rejoin` does with the key an invitation carries, given the
    /// one this phone holds (`shareable()`, or nil).
    enum OnRejoin: Equatable {
        /// Another family's key. Refused before any request: this phone's rows
        /// would otherwise be pushed into that family.
        case elsewhere
        /// This phone has lost its family's key, and the invitation carries
        /// one. Taken, but only after the server has placed the invitation's
        /// code in this phone's own family. With no key to compare against,
        /// that answer is the only thing that tells another family's key from
        /// this one's.
        case adopt(String)
        /// Nothing to change.
        case keep
    }

    /// Until 26 Sep 2026 a rejoin compared keys and never took one, so a phone
    /// that had lost its key stayed without it. The likely way to lose it is
    /// emptying another phone on the same Apple ID, which deletes the shared
    /// Keychain entry on both (`Session.renewIdentity`). Such a phone pushed in
    /// the clear from then on (`SyncSeal`). A new invitation is how the key
    /// travels to everybody else, so it is how it comes back.
    static func onRejoin(invited: String?, held: String?) -> OnRejoin {
        guard let invited else { return .keep }
        guard let held else { return .adopt(invited) }
        return invited == held ? .keep : .elsewhere
    }
}

/// A thin Keychain wrapper. The entries are synchronizable so that the identity
/// follows the user from device to device and there is no need to rejoin the
/// family when changing phones.
enum Keychain {
    static let memberIDKey = "member_id"
    static let secretKey = "device_secret"
    static let familyKeyKey = "family_key"

    private static let service = "com.kinlore.identity"

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // A synchronizable entry requires this accessibility level: stricter
            // levels never reach iCloud.
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    static func read(_ key: String) -> String? {
        var request = query(key)
        request[kSecReturnData as String] = kCFBooleanTrue as Any
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ value: String, for key: String) {
        delete(key)
        var request = query(key)
        request[kSecValueData as String] = Data(value.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(request as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
