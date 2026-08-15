import Foundation

/// Purchases and the family's paid tier.
///
/// The same pattern as the AI services: the protocol is separate from the
/// implementation, so the app works without a RevenueCat key and without a
/// network. Otherwise development and demoing would stop whenever purchases were
/// not configured.
protocol PurchaseService {
    /// The customer id as RevenueCat knows it, if purchases are configured.
    var customerID: String? { get async }
    /// Whether this device has an active purchase. The family's entitlement
    /// comes from the server — this only says whether this device is the one
    /// paying.
    var hasActivePurchase: Bool { get async }
}

/// The development implementation. It never owns anything, so the paywall shows
/// normally and the quota limits are hit just as a real user would hit them.
struct StubPurchaseService: PurchaseService {
    var customerID: String? { get async { nil } }
    var hasActivePurchase: Bool { get async { false } }
}

// MARK: - The family's entitlement

/// Reports a purchase to the server and reads the family's state.
///
/// **The client's word is not trusted.** This does not send a state but a hint:
/// the server asks RevenueCat for the truth and decides the family's
/// entitlement from that. Otherwise anyone could unlock the paid tier for a
/// whole family by editing the app.
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

    /// The family's usage. The paywall needs this to say what is left before the
    /// limit is reached.
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
