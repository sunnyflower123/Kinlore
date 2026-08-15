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

/// A thin Keychain wrapper. The entries are synchronizable so that the identity
/// follows the user from device to device and there is no need to rejoin the
/// family when changing phones.
enum Keychain {
    static let memberIDKey = "member_id"
    static let secretKey = "device_secret"

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
