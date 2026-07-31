import Foundation
import Security

/// Laitteen identiteetti: UUID ja satunnainen salaisuus Keychainissa.
///
/// Ei kirjautumisruutua. 80-vuotias ei näe tästä mitään — hän saa kutsulinkin
/// lapsenlapselta ja on sisällä. Ks. docs/ARKKITEHTUURI.md §4.
struct Identity {
    let memberID: String
    let secret: String

    /// Bearer-token muodossa `<member_id>.<secret>`.
    var token: String { "\(memberID).\(secret)" }

    /// Lataa olemassa olevan tai luo uuden. Luonti tapahtuu kerran laitteen
    /// elinaikana — tai kerran Apple-tilin elinaikana, koska Keychain-merkintä
    /// synkronoituu iCloudin kautta käyttäjän muille laitteille.
    static func loadOrCreate() -> Identity {
        if let memberID = Keychain.read(Keychain.memberIDKey),
           let secret = Keychain.read(Keychain.secretKey) {
            return Identity(memberID: memberID, secret: secret)
        }

        // Vanha osittainen tila siivotaan pois: puolikas identiteetti on
        // pahempi kuin ei mitään, koska palvelin hylkäisi sen hiljaa.
        Keychain.delete(Keychain.memberIDKey)
        Keychain.delete(Keychain.secretKey)

        let identity = Identity(memberID: UUID().uuidString, secret: Self.randomSecret())
        Keychain.write(identity.memberID, for: Keychain.memberIDKey)
        Keychain.write(identity.secret, for: Keychain.secretKey)
        return identity
    }

    /// 32 tavua satunnaisuutta heksana. Tämä ei ole salasana vaan avain, joten
    /// pituus korvaa muistettavuuden.
    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Käytännössä ei tapahdu, mutta hiljainen heikko avain olisi
            // pahempi kuin kaatuminen.
            bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Ohut Keychain-kääre. Merkinnät ovat synkronoituvia, jotta identiteetti
/// seuraa käyttäjää laitteesta toiseen eikä perheeseen tarvitse liittyä
/// uudelleen puhelinta vaihtaessa.
enum Keychain {
    static let memberIDKey = "member_id"
    static let secretKey = "device_secret"

    private static let service = "app.memorize.identity"

    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            // Synkronoituva merkintä vaatii tämän saatavuustason: tiukemmat
            // tasot eivät koskaan päädy iCloudiin.
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
