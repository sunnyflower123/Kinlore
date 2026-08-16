import Foundation

/// Client for the family routes.
///
/// Kept apart from the AI services in `AppServices`, because these always
/// require authentication and deal with membership rather than content.
struct FamilyClient {
    let baseURL: URL
    let token: String

    struct JoinResult: Decodable {
        let familyID: String
        let role: String
    }

    // MARK: - Routes

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

    /// Ends this device's membership. The memories stay with the family — see
    /// docs/ARCHITECTURE.md §14.
    func leave() async throws {
        struct Reply: Decodable { let left: Bool }
        let _: Reply = try await send(
            "family/me",
            method: "DELETE",
            body: Optional<Int>.none,
            authenticated: true
        )
    }

    // MARK: - Transport

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

        // Everything thrown out of here is a `FamilyError` carrying a Finnish
        // sentence. `Session` shows `localizedDescription` straight to the
        // person, and a `URLError`'s own text arrives in English on this
        // bundle — there are no localisation files, so Foundation never speaks
        // Finnish. The screen this lands on is the join form, the one an
        // 80-year-old reaches alone from a link, and a dead cottage connection
        // is its most ordinary failure.
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw FamilyError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FamilyError.message("Palvelin ei vastannut.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw FamilyError.forStatus(http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // The server answered something the app could not read. The person
            // can do nothing differently, so the sentence promises nothing.
            throw FamilyError.message("Jotain meni pieleen. Yritä uudelleen.")
        }
    }
}

enum FamilyError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let text): text }
    }

    /// The error text is written for the user, not the developer: an elderly
    /// person gains nothing from a 404 and everything from being told what to do
    /// next. Finnish, because it is shown in the UI.
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
        // Creating a family and joining one are metered per address
        // (docs/ARCHITECTURE.md §4), so this is the one refusal the app can now
        // meet that the generic wording actively misleads about: "yritä
        // uudelleen" is exactly what will not work, and a person who has just
        // been told to try again will tap the button until it does.
        case "too_many_requests":
            return .message("Liian monta yritystä lyhyessä ajassa. Odota hetki ja yritä sitten uudelleen.")
        case "last_member":
            return .message("Olet perheen ainoa jäsen, joten perheestä ei voi poistua. Voit tyhjentää tämän laitteen.")
        default:
            return .message(status >= 500
                ? "Palvelimeen ei saada yhteyttä. Yritä hetken kuluttua uudelleen."
                : "Jotain meni pieleen. Yritä uudelleen.")
        }
    }

    /// The connection itself failed — nothing was refused, nothing arrived.
    ///
    /// Said in the words the rest of the app already uses for a missing
    /// network: "kun yhteys palaa", the phrasing of the offline note and the
    /// Lähetys row. The two named cases are the ones whose advice differs;
    /// everything else collapses into one sentence, because "NSURLErrorDomain
    /// -1005" has no Finnish and no advice in it.
    static func transport(_ error: URLError) -> FamilyError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .message("Verkkoyhteyttä ei juuri nyt ole. Yritä uudelleen kun yhteys palaa.")
        case .timedOut:
            return .message("Palvelin ei ehtinyt vastata. Yritä hetken kuluttua uudelleen.")
        default:
            return .message("Yhteys ei onnistunut. Yritä hetken kuluttua uudelleen.")
        }
    }
}
