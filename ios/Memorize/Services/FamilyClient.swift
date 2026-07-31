import Foundation

/// Perhereittien asiakas.
///
/// Erillään `AppServices`in AI-palveluista, koska nämä vaativat aina
/// tunnistautumisen ja käsittelevät jäsenyyttä eivätkä sisältöä.
struct FamilyClient {
    let baseURL: URL
    let token: String

    struct JoinResult: Decodable {
        let familyID: String
        let role: String
    }

    // MARK: - Reitit

    func createFamily(familyName: String, displayName: String) async throws -> JoinResult {
        struct Body: Encodable {
            let memberID: String
            let secret: String
            let displayName: String
            let familyName: String
        }
        let identity = split(token)
        return try await send(
            "family",
            method: "POST",
            body: Body(
                memberID: identity.id,
                secret: identity.secret,
                displayName: displayName,
                familyName: familyName
            ),
            authenticated: false
        )
    }

    func join(code: String, displayName: String) async throws -> JoinResult {
        struct Body: Encodable {
            let memberID: String
            let secret: String
            let displayName: String
            let code: String
        }
        let identity = split(token)
        return try await send(
            "family/join",
            method: "POST",
            body: Body(
                memberID: identity.id,
                secret: identity.secret,
                displayName: displayName,
                code: code
            ),
            authenticated: false
        )
    }

    func family() async throws -> Session.Family {
        try await send("family", method: "GET", body: Optional<Int>.none, authenticated: true)
    }

    func createInvite() async throws -> String {
        struct Reply: Decodable { let code: String }
        let reply: Reply = try await send(
            "family/invite",
            method: "POST",
            body: Optional<Int>.none,
            authenticated: true
        )
        return reply.code
    }

    func revokeInvite(code: String) async throws {
        struct Reply: Decodable { let revoked: Bool }
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        let _: Reply = try await send(
            "family/invite?code=\(encoded)",
            method: "DELETE",
            body: Optional<Int>.none,
            authenticated: true
        )
    }

    // MARK: - Kuljetus

    private func split(_ token: String) -> (id: String, secret: String) {
        guard let dot = token.firstIndex(of: ".") else { return (token, "") }
        return (String(token[token.startIndex ..< dot]), String(token[token.index(after: dot)...]))
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String,
        body: (some Encodable)?,
        authenticated: Bool
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw FamilyError.message("Virheellinen osoite.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if authenticated {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FamilyError.message("Palvelin ei vastannut.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw FamilyError.forStatus(http.statusCode, data: data)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

enum FamilyError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }

    /// Virheteksti kirjoitetaan käyttäjälle, ei kehittäjälle: iäkäs ihminen ei
    /// hyödy koodista 404 vaan siitä mitä hänen pitäisi tehdä seuraavaksi.
    static func forStatus(_ status: Int, data: Data) -> FamilyError {
        struct Payload: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Payload.self, from: data))?.error

        switch code {
        case "invalid_invite":
            return .message("Kutsu ei kelpaa. Se on voinut vanhentua — pyydä uusi linkki.")
        case "member_exists":
            return .message("Tämä laite kuuluu jo toiseen perheeseen.")
        case "unauthorized":
            return .message("Tunnistautuminen epäonnistui.")
        default:
            return .message(status >= 500
                ? "Palvelimeen ei saada yhteyttä. Yritä hetken kuluttua uudelleen."
                : "Jotain meni pieleen. Yritä uudelleen.")
        }
    }
}
