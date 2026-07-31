import Foundation

/// Ostot ja perheen maksullinen taso.
///
/// Sama kuvio kuin AI-palveluilla: protokolla erillään toteutuksesta, jotta
/// sovellus toimii ilman RevenueCat-avainta ja ilman verkkoa. Ilman tätä
/// kehitys ja demoaminen pysähtyisivät aina kun ostoja ei ole konfiguroitu.
protocol PurchaseService {
    /// RevenueCatin tuntema asiakastunnus, jos ostoja on konfiguroitu.
    var customerID: String? { get async }
    /// Onko tällä laitteella voimassa oleva osto. Perheen oikeus tulee
    /// palvelimelta — tämä kertoo vain onko tämä laite se joka maksaa.
    var hasActivePurchase: Bool { get async }
}

/// Kehitysvaiheen toteutus. Ei koskaan omista mitään, joten paywall näkyy
/// normaalisti ja kiintiörajat tulevat vastaan kuten oikeallakin käyttäjällä.
struct StubPurchaseService: PurchaseService {
    var customerID: String? { get async { nil } }
    var hasActivePurchase: Bool { get async { false } }
}

// MARK: - Perheen oikeus

/// Kertoo palvelimelle ostosta ja lukee perheen tilan.
///
/// **Asiakkaan sanaan ei luoteta.** Tämä ei lähetä tilaa vaan vihjeen:
/// palvelin kysyy totuuden RevenueCatilta ja päättää perheen oikeuden sen
/// perusteella. Muuten kuka tahansa voisi avata maksullisen tason koko
/// perheelle muokkaamalla sovellusta.
struct EntitlementClient {
    let baseURL: URL
    let token: String

    struct Status: Decodable {
        let entitlement: String
        let expiresAt: Double?

        var isPaid: Bool { entitlement == "archive" }
    }

    private struct Request: Encodable {
        let customerID: String
    }

    func sync(customerID: String) async throws -> Status {
        var request = URLRequest(url: baseURL.appendingPathComponent("entitlement/sync"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(customerID: customerID))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Status.self, from: data)
    }

    /// Perheen käyttötilanne. Paywall tarvitsee tämän kertoakseen mitä on
    /// jäljellä ennen kuin raja tulee vastaan.
    struct Usage: Decodable {
        struct Meter: Decodable {
            let used: Int
            let limit: Int?

            var remaining: Int? {
                guard let limit else { return nil }
                return max(0, limit - used)
            }
        }

        let entitlement: String
        let aiSeconds: Meter
        let photos: Meter

        var isPaid: Bool { entitlement == "archive" }
    }

    func usage() async throws -> Usage {
        var request = URLRequest(url: baseURL.appendingPathComponent("usage"))
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Usage.self, from: data)
    }
}
