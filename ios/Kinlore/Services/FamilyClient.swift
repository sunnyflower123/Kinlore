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
        /// The card the invitation was made for, when it named one. The server
        /// has already linked the new member to it if the card had reached the
        /// server; if not, this phone links itself once the card arrives
        /// (`SyncEngine`). Absent from a server that predates it, and from the
        /// create route, which has no card to name.
        let personSubjectID: String?
    }

    // MARK: - Routes

    func createFamily(familyName: String, displayName: String) async throws -> JoinResult {
        struct Body: Encodable {
            let memberID: String
            let secret: String
            let displayName: String
            let familyName: String
            /// Only decides the fallback names when these two are empty, which
            /// on a phone handed to a grandparent is the ordinary case.
            let lang: String
        }
        let identity = split(token)
        return try await send(
            "family",
            method: "POST",
            body: Body(
                memberID: identity.id,
                secret: identity.secret,
                displayName: displayName,
                familyName: familyName,
                lang: SpokenLanguage.current
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
            let lang: String
        }
        let identity = split(token)
        return try await send(
            "family/join",
            method: "POST",
            body: Body(
                memberID: identity.id,
                secret: identity.secret,
                displayName: displayName,
                code: code,
                lang: SpokenLanguage.current
            ),
            authenticated: false
        )
    }

    func family() async throws -> Session.Family {
        try await send("family", method: "GET", body: Optional<Int>.none, authenticated: true)
    }

    /// `displayName` is who the invitation is for, and `personSubjectID` the
    /// card it is made for. With neither, no body is sent at all, which is the
    /// request this route answered before either existed.
    func createInvite(displayName: String, personSubjectID: String?) async throws -> String {
        // The synthesized encoder leaves a nil field out, which is what the
        // route expects of a field nobody filled in.
        struct Body: Encodable {
            let displayName: String?
            let personSubjectID: String?
        }
        struct Reply: Decodable { let code: String }
        let named = displayName.trimmingCharacters(in: .whitespaces)
        let body = Body(displayName: named.isEmpty ? nil : named, personSubjectID: personSubjectID)
        let reply: Reply = try await send(
            "family/invite",
            method: "POST",
            body: body.displayName == nil && body.personSubjectID == nil ? nil : body,
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

    /// The owner ends somebody else's membership. The memories stay, and every
    /// open invitation of the family is withdrawn with it — the invite text
    /// carries the family key, and the person being removed may hold any live
    /// link. See docs/ARCHITECTURE.md §4.
    func removeMember(id: String) async throws {
        struct Reply: Decodable { let removed: Bool }
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let _: Reply = try await send(
            "family/member?id=\(encoded)",
            method: "DELETE",
            body: Optional<Int>.none,
            authenticated: true
        )
    }

    /// This member's own name, changed on the server — where every telling's
    /// author is resolved from it, so the family sees it on their next pull.
    func rename(displayName: String) async throws -> String {
        struct Body: Encodable { let displayName: String }
        struct Reply: Decodable { let displayName: String }
        let reply: Reply = try await send(
            "family/me",
            method: "PATCH",
            body: Body(displayName: displayName),
            authenticated: true
        )
        return reply.displayName
    }

    /// This member's own card in the tree, or none with nil. The server links
    /// only a live person card of this family that it already holds, so a
    /// card made on this phone is refused until a sync has carried it up.
    func link(personSubjectID: String?) async throws -> String? {
        struct Body: Encodable {
            let personSubjectID: String?

            // Written out, because the synthesized encoder leaves a nil out
            // altogether — and a missing key is not the same request as
            // `null`, which is how unlinking is said.
            enum CodingKeys: String, CodingKey { case personSubjectID }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(personSubjectID, forKey: .personSubjectID)
            }
        }
        struct Reply: Decodable { let personSubjectID: String? }
        let reply: Reply = try await send(
            "family/me",
            method: "PATCH",
            body: Body(personSubjectID: personSubjectID),
            authenticated: true
        )
        return reply.personSubjectID
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

    // MARK: - Push

    /// This phone may be told when a question is asked of this member, or one
    /// of theirs is answered (`PushNotifications`). The environment says which
    /// of Apple's two push servers knows the token.
    func registerPush(token: String, environment: String) async throws {
        struct Body: Encodable { let token: String; let environment: String }
        struct Reply: Decodable { let registered: Bool }
        let _: Reply = try await send(
            "push/token",
            method: "POST",
            body: Body(token: token, environment: environment),
            authenticated: true
        )
    }

    /// Forgets this phone for this member, before a wipe takes the identity.
    func unregisterPush(token: String) async throws {
        struct Body: Encodable { let token: String }
        struct Reply: Decodable { let unregistered: Bool }
        let _: Reply = try await send(
            "push/token",
            method: "DELETE",
            body: Body(token: token),
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
            throw FamilyError.message(String(localized: "Virheellinen osoite."))
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
            throw FamilyError.message(String(localized: "Palvelin ei vastannut."))
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw FamilyError.forStatus(http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // The server answered something the app could not read. The person
            // can do nothing differently, so the sentence promises nothing.
            throw FamilyError.message(String(localized: "Jotain meni pieleen. Yritä uudelleen."))
        }
    }
}

/// Every sentence here is looked up with `String(localized:)` at the point it
/// is made: the message travels as a String into `Session.lastError` and on to
/// a label, and a literal put in here as a String was shown verbatim in every
/// language — the join form's "Kutsu ei kelpaa" on an English phone, on the
/// one screen a person reaches alone from a link (founder's-eye review, 3 Sep
/// 2026, finding #94).
enum FamilyError: LocalizedError {
    case message(String)
    /// The server's own `{"error":"unauthorized"}`: it does not know this
    /// identity as a member of anything. A case of its own because one caller
    /// acts on it — the question a returning phone asks (`Session.lookForFamily`)
    /// reads this answer, and only this one, as "no family". The words are the
    /// same as they always were.
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .unauthorized: String(localized: "Tunnistautuminen epäonnistui.")
        }
    }

    /// The error text is written for the user, not the developer: an elderly
    /// person gains nothing from a 404 and everything from being told what to do
    /// next. Finnish, because it is shown in the UI.
    static func forStatus(_ status: Int, data: Data) -> FamilyError {
        struct Payload: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Payload.self, from: data))?.error

        switch code {
        case "invalid_invite":
            return .message(String(localized: "Kutsu ei kelpaa. Se on voinut vanhentua — pyydä uusi linkki."))
        case "member_exists":
            return .message(String(localized: "Tämä laite kuuluu jo toiseen perheeseen."))
        case "unauthorized":
            return .unauthorized
        // Creating a family and joining one are metered per address
        // (docs/ARCHITECTURE.md §4), so this is the one refusal the app can now
        // meet that the generic wording actively misleads about: "yritä
        // uudelleen" is exactly what will not work, and a person who has just
        // been told to try again will tap the button until it does.
        case "too_many_requests":
            return .message(String(localized: "Liian monta yritystä lyhyessä ajassa. Odota hetki ja yritä sitten uudelleen."))
        case "last_member":
            return .message(String(localized: "Olet perheen ainoa jäsen, joten perheestä ei voi poistua. Voit tyhjentää tämän laitteen."))
        case "not_owner":
            return .message(String(localized: "Vain perheen perustaja voi poistaa jäsenen."))
        default:
            return .message(status >= 500
                ? String(localized: "Palvelimeen ei saada yhteyttä. Yritä hetken kuluttua uudelleen.")
                : String(localized: "Jotain meni pieleen. Yritä uudelleen."))
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
            return .message(String(localized: "Verkkoyhteyttä ei juuri nyt ole. Yritä uudelleen kun yhteys palaa."))
        case .timedOut:
            return .message(String(localized: "Palvelin ei ehtinyt vastata. Yritä hetken kuluttua uudelleen."))
        default:
            return .message(String(localized: "Yhteys ei onnistunut. Yritä hetken kuluttua uudelleen."))
        }
    }
}
