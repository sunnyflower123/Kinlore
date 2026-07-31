import Foundation

/// Mallit vastaavat `backend/schema.sql`:ää tarkoituksella yksi yhteen.
/// Kun synkronointi backendiin tulee, näitä ei tarvitse kääntää välimallin läpi.

// MARK: - Subject

/// Kuva, henkilö, paikka ja tapahtuma ovat kaikki sama asia: kohde, johon
/// muistoja kiinnittyy. Tämä on koko sovelluksen arkkitehtuurin ydin — sen
/// ansiosta "kirjoita muisto kuvaan" ja "kerro millainen isoäiti oli" ovat sama
/// ruutu eikä kolmea rinnakkaista toteutusta.
enum SubjectKind: String, Codable, CaseIterable {
    case photo, person, place, event

    var symbolName: String {
        switch self {
        case .photo: "photo"
        case .person: "person.crop.circle"
        case .place: "mappin.and.ellipse"
        case .event: "calendar"
        }
    }

    /// Käyttöliittymässä näytettävä nimi. Suomeksi, koska sovelluksen kieli on suomi.
    var label: String {
        switch self {
        case .photo: "Kuva"
        case .person: "Henkilö"
        case .place: "Paikka"
        case .event: "Tapahtuma"
        }
    }
}

/// Epävarma ajoitus on sääntö, ei poikkeus. "Joskus 50-luvulla" on kelvollinen
/// vastaus, eikä sitä pidä pyöristää valheelliseksi päivämääräksi.
enum DatePrecision: String, Codable {
    case day, month, year, decade, unknown
}

struct DateHint: Codable, Hashable {
    var start: Date?
    var end: Date?
    var precision: DatePrecision

    /// Ihmisluettava muoto joka kertoo epävarmuuden rehellisesti.
    var displayText: String {
        guard let start else { return "Ajankohta ei tiedossa" }
        let year = Calendar.current.component(.year, from: start)
        switch precision {
        case .decade: return "\(year / 10 * 10)-luku"
        case .year: return "\(year)"
        case .month, .day:
            let f = DateFormatter()
            f.locale = Locale(identifier: "fi_FI")
            f.dateFormat = precision == .day ? "d.M.yyyy" : "LLLL yyyy"
            return f.string(from: start)
        case .unknown: return "Ajankohta ei tiedossa"
        }
    }
}

struct Subject: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var kind: SubjectKind
    var title: String
    /// Paikallinen välimuistitiedosto. Nil vastaanottavalla laitteella kunnes
    /// kuva on ladattu.
    var imageFilename: String?
    /// R2-avain. Nil kunnes kuva on työnnetty palvelimelle. Nämä ovat eri
    /// asioita: sama kuva on eri laitteilla eri tiedostonimellä mutta samalla
    /// avaimella.
    var r2Key: String?
    var dateHint: DateHint?
    /// AI:n ehdottama kohde syntyy vahvistamattomana. Vahvistamaton ei näy
    /// sukupuussa faktana — väärä sukulaisuussuhde on pahempi kuin puuttuva.
    var confirmed: Bool = true
    var createdAt: Date = .now
    /// Sulautuksen osoite. Kun tämä on asetettu, kohde ei ole enää oma
    /// henkilönsä vaan ohjaa toiseen — ks. `MemoryStore.rename`.
    var mergedInto: String?

    /// Kuva tuodaan ilman otsikkoa, koska kukaan ei jaksa nimetä kolmeakymmentä
    /// skannattua valokuvaa. Nimi syntyy vasta kun kuvasta kerrotaan.
    var displayTitle: String {
        if !title.isEmpty { return title }
        return kind == .photo ? "Valokuva" : kind.label
    }
}

// MARK: - Memory

enum MemorySource: String, Codable {
    case typed, voice
}

struct Memory: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var subjectID: String
    /// Palvelimen tuntema kirjoittaja. Paikallisesti luodussa muistossa nil,
    /// koska palvelin asettaa sen istunnosta — asiakas ei saa väittää muistoa
    /// jonkun toisen kertomaksi.
    var authorID: String?
    var authorName: String
    /// Siivottu, luettava teksti.
    var body: String
    /// Alkuperäinen purku säilytetään aina. Jos siivous menee pieleen, totuus on
    /// yhä tallessa — puhuja ei ehkä ole enää kysyttävissä.
    var rawTranscript: String?
    /// Alkuperäinen ääni. Isoäidin ääni on itsessään perintö, ei välivaihe
    /// kohti tekstiä, ja se on soitettavissa muistokortista.
    var audioFilename: String?
    /// R2-avain äänelle. Ks. `Subject.r2Key`.
    var audioR2Key: String?
    var audioDuration: TimeInterval?
    var source: MemorySource
    var createdAt: Date = .now
    /// Muistossa mainitut kohteet. Tämä kudos on se mitä tekoäly "yhdistelee":
    /// sama henkilö esiintyy kymmenessä muistossa eri kuvien alla.
    var mentionedSubjectIDs: [String] = []

    /// Ääni on tallessa mutta purkua ei ole tehty — kiintiö oli täynnä tai
    /// verkko poikki. Johdettu kenttä, ei erillistä tilaa synkronoitavaksi.
    ///
    /// Tämä on säännön 3 näkyvä muoto: kiintiö ei koskaan hylkää nauhoitusta
    /// vaan lykkää sen purkua. Isoäidin ääni on lopputuotetta.
    var isAwaitingTranscription: Bool {
        body.isEmpty && (audioFilename != nil || audioR2Key != nil)
    }
}

// MARK: - Sukulaisuus

/// Suhteen laji.
///
/// `parentOf` on suunnattu ja luetaan `from → to`. Puoliso ja sisarus ovat
/// symmetrisiä: ne tallennetaan kertaalleen ja luetaan molempiin suuntiin,
/// jottei sama suhde synny kahdesti eri päin.
enum RelationKind: String, Codable, CaseIterable {
    case parentOf = "parent_of"
    case spouseOf = "spouse_of"
    case siblingOf = "sibling_of"

    var isSymmetric: Bool { self != .parentOf }

    /// Miten suhde nimetään kun sitä lisätään: "X on tämän henkilön ___".
    var addLabel: String {
        switch self {
        case .parentOf: "Vanhempi"
        case .spouseOf: "Puoliso"
        case .siblingOf: "Sisarus"
        }
    }
}

struct Relation: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var fromSubjectID: String
    var toSubjectID: String
    var kind: RelationKind
    /// Tekoälyn päättelemä suhde syntyy vahvistamattomana. Vahvistamaton ei näy
    /// sukupuussa faktana — väärä sukulaisuussuhde on pahempi kuin puuttuva,
    /// koska kukaan ei myöhemmin tiedä että se oli arvaus.
    var confirmed: Bool = false
    var createdAt: Date = .now
}

// MARK: - Jatkokysymys

/// Sekä taikahetken loppuosa että retention-moottori: avoin kysymys on syy
/// palata sovellukseen.
struct FollowUpQuestion: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var subjectID: String?
    var text: String
    var answered: Bool = false
    var createdAt: Date = .now
}
