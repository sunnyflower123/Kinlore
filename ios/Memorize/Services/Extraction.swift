import Foundation

/// Sanelun jäsennys: raakapuheesta rakenteeksi.
///
/// Rajapinta on erillään toteutuksesta, koska oikea toteutus (Worker → LLM)
/// odottaa API-avainta. Stub tuottaa saman muotoisen tuloksen, joten vaihto on
/// yhden rivin kokoinen `TellScreen`in `.task`-lohkossa eikä kosketa
/// käyttöliittymää lainkaan.

// MARK: - Tulos

/// Vastaa suoraan sitä mitä LLM:n structured output palauttaa ja mitä skeema
/// odottaa: `memory.body`, `mention`, `subject.date_*` ja `prompt_question`.
struct ExtractionResult: Equatable {
    /// Siivottu teksti. Rönsyt pois, sisältö tallella.
    var body: String
    var mentions: [MentionedEntity]
    var dateHint: DateHint?
    /// Kolme kysymystä. Enempi ahdistaa, vähempi ei vie kertomusta eteenpäin.
    var questions: [String]
}

struct MentionedEntity: Equatable, Hashable {
    var name: String
    var kind: SubjectKind
    /// LLM:n varmuus. Alle 1.0 syntyy vahvistamattomana ehdotuksena.
    var confidence: Double
}

protocol ExtractionService {
    func extract(transcript: String) async throws -> ExtractionResult
}

// MARK: - Vaatimus oikealle toteutukselle
//
// **Nimet on palautettava perusmuodossa.** Suomen taivutus tekee tästä
// välttämättömän: puheessa esiintyy "Ainon", "Ainolle" ja "Aino", ja jos LLM
// palauttaa pintamuodon, `MemoryStore.findOrCreateSubject` luo niistä kolme eri
// henkilöä. Sukupuu täyttyy kaksoiskappaleista joita kukaan ei myöhemmin osaa
// yhdistää, ja se on juuri se virhe jota periaate "AI ehdottaa, ihminen
// vahvistaa" ei pysty korjaamaan — käyttäjä vahvistaa kolme oikeaa nimeä
// tietämättä että ne ovat sama ihminen.
//
// Sama koskee paikkoja: "Puumalassa" → "Puumala". Kysymystekstit saavat
// käyttää taivutettua muotoa, mutta `subject.title` ei.
//
// Stub ei osaa tätä, koska se poimii sanat sellaisenaan. Se on tiedostettu
// rajoite eikä korjattava bugi — perusmuotoistus kuuluu kielimallille.

// MARK: - Stub

/// Kehitysvaiheen toteutus. Poimii oikeasti erisnimet ja vuosiluvut tekstistä,
/// jotta käyttöliittymää voi kehittää realistisella datalla ennen kuin
/// LLM-avain on olemassa. Ei yritä olla älykäs — sen tekee oikea toteutus.
struct StubExtractionService: ExtractionService {
    /// Simuloi verkkoviivettä, jotta latausanimaatio tulee suunniteltua
    /// oikeissa olosuhteissa eikä välähdyksenä.
    var simulatedDelay: Duration = .milliseconds(2200)

    func extract(transcript: String) async throws -> ExtractionResult {
        try await Task.sleep(for: simulatedDelay)

        let names = Self.properNouns(in: transcript)
        let mentions = names.map {
            // Karkea jako: paikannimet taipuvat usein -ssa/-lla-päätteillä.
            MentionedEntity(
                name: $0,
                kind: Self.looksLikePlace($0) ? .place : .person,
                confidence: 0.7
            )
        }

        return ExtractionResult(
            body: Self.tidy(transcript),
            mentions: mentions,
            dateHint: Self.dateHint(in: transcript),
            questions: Self.questions(for: mentions)
        )
    }

    // MARK: Heuristiikat

    /// Isolla alkukirjaimella kirjoitetut sanat jotka eivät aloita virkettä.
    static func properNouns(in text: String) -> [String] {
        var found: [String] = []
        for sentence in text.components(separatedBy: CharacterSet(charactersIn: ".!?")) {
            let words = sentence.split(separator: " ").map(String.init)
            for word in words.dropFirst() {
                let clean = word.trimmingCharacters(in: .punctuationCharacters)
                guard let first = clean.first, first.isUppercase, clean.count > 2 else { continue }
                if !found.contains(clean) { found.append(clean) }
            }
        }
        return found
    }

    static func looksLikePlace(_ name: String) -> Bool {
        let suffixes = ["ssa", "ssä", "lla", "llä", "sta", "stä", "lta", "ltä"]
        return suffixes.contains { name.lowercased().hasSuffix($0) }
    }

    /// Poimii joko nelinumeroisen vuoden tai "50-luvulla" -tyyppisen vuosikymmenen.
    static func dateHint(in text: String) -> DateHint? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current

        func date(year: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        }

        if let match = text.firstMatch(of: /\b(1[89]\d{2}|20\d{2})\b/),
           let year = Int(match.1) {
            return DateHint(start: date(year: year), end: date(year: year), precision: .year)
        }

        if let match = text.firstMatch(of: /\b([2-9]0)-luvu/),
           let short = Int(match.1) {
            // 20–90 tulkitaan 1900-luvuksi: puhe vanhoista kuvista tarkoittaa
            // käytännössä aina viime vuosisataa.
            let decade = 1900 + short
            return DateHint(start: date(year: decade), end: date(year: decade + 9), precision: .decade)
        }

        return nil
    }

    /// Siivoaa täytesanat mutta ei tiivistä sisältöä. Muiston pituus on osa
    /// muistoa — oikea toteutus saa muotoilla, ei lyhentää.
    static func tidy(_ text: String) -> String {
        let fillers = ["niinku", "tota", "öö", "ää", "siis niinku"]
        var result = text
        for filler in fillers {
            result = result.replacingOccurrences(
                of: "\\b\(filler)\\b,?\\s*",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kysymykset kohdistuvat aukkoihin: mainittuun henkilöön josta ei kerrottu
    /// mitään, tai paikkaan josta tiedetään vain nimi.
    ///
    /// Tyyppi on otettava huomioon. Pelkkä nimilista tuottaa kysymyksiä kuten
    /// "Millainen ihminen Puumalassa oli?" — se rikkoo koko taikahetken
    /// uskottavuuden, koska käyttäjä näkee heti ettei ohjelma ymmärrä mitään.
    static func questions(for mentions: [MentionedEntity]) -> [String] {
        let people = mentions.filter { $0.kind == .person }.map(\.name)
        let places = mentions.filter { $0.kind == .place }.map(\.name)

        var out: [String] = []
        if let first = people.first {
            out.append("Millainen ihminen \(first) oli?")
        }
        if people.count > 1 {
            out.append("Miten \(people[0]) ja \(people[1]) tunsivat toisensa?")
        }
        if let place = places.first {
            // Paikannimi on puheessa jo sijamuodossa ("Puumalassa"), joten
            // kysymys rakennetaan niin ettei sitä tarvitse taivuttaa uudelleen.
            out.append("\(place) — mitä muuta siellä tapahtui?")
        }
        out.append("Muistatko miltä siellä tuoksui tai kuulosti?")
        out.append("Kuka muu oli paikalla?")
        return Array(out.prefix(3))
    }
}
