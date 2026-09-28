#if DEBUG
import UIKit

/// `-seed large`: a family's archive after a year or two of use, for looking
/// at the app at the size it is built for.
///
/// Every other archive seed holds a handful of cards, which is the family an
/// hour after installing, and `-seed clan` holds a tree with nothing told
/// about anybody in it. This is the archive the album, the map, the search
/// and the tree are meant to carry: a hundred and fifty photographs from
/// 1903 to 2025, drawn by `LargeArchivePictures`, dated the way people date
/// them — a day, a month, a year, "around 1955", "sometime in the fifties",
/// "I do not know" and never (rule 5); `ClanFixture`'s sixty people and
/// their relationships; twenty-odd places, most of them on the map; about two
/// hundred and fifty tellings by nine phones and by Sirkka, Elina's
/// great-aunt, telling through Elina's; open and answered questions, from the
/// extraction and from members; names and places heard and not confirmed
/// (rule 4), one of them waiting on a blind card; faces, facts, and three
/// colourings somebody said yes to.
///
/// **The words follow the phone's language**, English or Finnish, where the
/// other archive seeds are Finnish whatever the phone says. They are for
/// tests, which pin Finnish; this one is for looking at, in the language the
/// app is shown in. So a test that finds a title by its words launches in
/// Finnish, as every test here does.
///
/// Nothing is sent anywhere: the photographs carry an R2 key so that nothing
/// reads as waiting to upload, and a seeded launch has no server to push to.
/// The photographs are drawn on the first launch, about a hundred and fifty
/// files, and kept: a later launch replaces the archive and finds them there.
enum LargeArchiveFixture {
    /// Another member of the family, with a phone of their own.
    struct Phone {
        let id: String
        let name: String
        /// The key of their person card, `clan-` + this.
        let card: String
        /// Days before the launch.
        let joined: Double
    }

    /// Everybody but the phone the seed runs on, first to join first.
    static let phones: [Phone] = [
        Phone(id: "large-member-matti", name: "Matti", card: "matti", joined: 530),
        Phone(id: "large-member-ritva", name: "Ritva", card: "ritva", joined: 528),
        Phone(id: "large-member-mikko", name: "Mikko", card: "mikko", joined: 500),
        Phone(id: "large-member-jukka", name: "Jukka", card: "jukka", joined: 410),
        Phone(id: "large-member-liisa", name: "Liisa", card: "liisa", joined: 380),
        Phone(id: "large-member-kaarina", name: "Kaarina", card: "kaarina", joined: 300),
        Phone(id: "large-member-sanni", name: "Sanni", card: "sanni", joined: 200),
        Phone(id: "large-member-venla", name: "Venla", card: "venla", joined: 90),
    ]

    /// This phone's member: Elina, who started the archive.
    static let myName = "Elina"
    static let myJoined: Double = 540
    /// The one invitation still open.
    static let invited = "Oskari"

    static var inFinnish: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("fi") == true
    }

    static var familyName: String { inFinnish ? "Koivulan suku" : "The Koivula family" }

    struct Archive {
        var subjects: [Subject]
        var memories: [Memory]
        var questions: [FollowUpQuestion]
        var relations: [Relation]
        /// Every telling this phone has seen: all but the three newest from
        /// other members, which `NewFromFamily` then shows.
        var seen: [String]
        /// How many files this launch drew, and how long it took.
        var drawn: Int
        var drawing: TimeInterval
    }

    // MARK: - People

    /// Born, died, and whether the pictures dress them as a woman. Every card
    /// of `ClanFixture`, and the five names the family has only heard.
    private static let lives: [String: (born: Int, died: Int?, female: Bool)] = [
        "aapo": (1862, 1931, false), "hilma": (1866, 1899, true), "lyyli": (1874, 1950, true),
        "vaino": (1889, 1965, false), "hilja": (1894, 1978, true), "impi": (1891, 1970, true),
        "urho": (1887, 1960, false), "sulo": (1896, 1968, false), "kerttu": (1902, 1985, true),
        "oiva": (1899, 1972, false), "eemeli": (1904, 1981, false),
        "toivo": (1920, 1999, false), "anneli": (1926, 2019, true), "martta": (1922, 2008, true),
        "eino": (1924, 1994, false), "aune": (1927, 2016, true), "reino": (1930, 1996, false),
        "sirkka": (1934, nil, true), "onni": (1921, 1990, false), "helvi": (1927, 2011, true),
        "paavo": (1925, 2003, false),
        "matti": (1950, nil, false), "liisa": (1953, nil, true), "veikko": (1947, nil, false),
        "tuula": (1949, nil, true), "kaarina": (1951, nil, true), "heikki": (1948, 2020, false),
        "ritva": (1952, nil, true),
        "elina": (1978, nil, true), "mikko": (1976, nil, false), "jukka": (1981, nil, false),
        "petra": (1983, nil, true), "sanni": (1979, nil, true), "aleksi": (1975, nil, false),
        "noora": (1980, nil, true),
        "venla": (2006, nil, true), "oskari": (2009, nil, false), "aino": (2013, nil, true),
        "elias": (2012, nil, false), "iiris": (2015, nil, true),
        "sisko": (1940, nil, true), "mauri": (1942, 2015, false), "tarja": (1946, nil, true),
        "onerva": (1965, nil, true), "otto": (1938, 2012, false), "helmi": (1941, nil, true),
        "jonne": (1978, nil, false), "rauha": (1944, nil, true),
        "kustaa": (1885, 1950, false), "alma": (1890, 1962, true), "yrjo": (1915, 1940, false),
        "saima": (1920, 2001, true), "lauri": (1948, nil, false), "hellin": (1900, 1985, true),
        "verneri": (1930, 2010, false),
        // Heard in a telling and never confirmed (rule 4).
        "eeva": (1962, nil, true), "selma": (1897, 1975, true), "arvo": (1925, nil, false),
        "ilmari": (1920, 1987, false), "tyyne": (1930, 2012, true),
    ]

    /// The names the extraction proposed and nobody has confirmed: cards of
    /// their own, `confirmed = false`, made when the telling that named them
    /// was told. Eeva is `ClanFixture`'s own proposal.
    private static let heardPeople: [String: String] = [
        "selma": "Selma", "arvo": "Arvo", "ilmari": "Ilmari", "tyyne": "Tyyne",
    ]

    /// The order `ClanFixture` makes its cards in, with the seven nobody has
    /// placed moved so that the three newest are women of the older
    /// generations. The blind card deals its other names from the newest
    /// confirmed cards, and its first card here is a photograph of three
    /// girls in 1947.
    private static let lastMade = ["kustaa", "yrjo", "lauri", "verneri", "alma", "hellin", "saima"]

    private static func personID(_ key: String) -> String {
        if key == "eeva" { return "clan-epavarma" }
        return heardPeople[key] != nil ? "large-" + key : "clan-" + key
    }

    // MARK: - Places and events

    private struct Place {
        let key: String
        let en: String
        let fi: String
        let point: (Double, Double)?
        let precision: GeoPrecision
        let inEn: String
        let inFi: String
        /// The member who put it on the map by hand, or nil for a lookup.
        var placedBy: String? = nil
        /// Heard in a telling and not confirmed.
        var heard = false
    }

    private static let places: [Place] = [
        Place(key: "puumala", en: "Puumala", fi: "Puumala", point: (61.5236, 28.1797), precision: .town, inEn: "in Puumala", inFi: "Puumalassa"),
        Place(key: "savonlinna", en: "Savonlinna", fi: "Savonlinna", point: (61.8687, 28.8786), precision: .town, inEn: "in Savonlinna", inFi: "Savonlinnassa"),
        Place(key: "kuopio", en: "Kuopio", fi: "Kuopio", point: (62.8924, 27.6770), precision: .town, inEn: "in Kuopio", inFi: "Kuopiossa"),
        Place(key: "helsinki", en: "Helsinki", fi: "Helsinki", point: (60.1699, 24.9384), precision: .town, inEn: "in Helsinki", inFi: "Helsingissä"),
        Place(key: "tampere", en: "Tampere", fi: "Tampere", point: (61.4978, 23.7610), precision: .town, inEn: "in Tampere", inFi: "Tampereella"),
        Place(key: "jyvaskyla", en: "Jyväskylä", fi: "Jyväskylä", point: (62.2426, 25.7473), precision: .town, inEn: "in Jyväskylä", inFi: "Jyväskylässä"),
        Place(key: "oulu", en: "Oulu", fi: "Oulu", point: (65.0121, 25.4651), precision: .town, inEn: "in Oulu", inFi: "Oulussa"),
        Place(key: "turku", en: "Turku", fi: "Turku", point: (60.4518, 22.2666), precision: .town, inEn: "in Turku", inFi: "Turussa"),
        Place(key: "viipuri", en: "Viipuri", fi: "Viipuri", point: (60.7139, 28.7575), precision: .town, inEn: "in Viipuri", inFi: "Viipurissa"),
        Place(key: "sortavala", en: "Sortavala", fi: "Sortavala", point: (61.7036, 30.6917), precision: .town, inEn: "in Sortavala", inFi: "Sortavalassa"),
        Place(key: "mikkeli", en: "Mikkeli", fi: "Mikkeli", point: (61.6886, 27.2723), precision: .town, inEn: "in Mikkeli", inFi: "Mikkelissä"),
        Place(key: "lappeenranta", en: "Lappeenranta", fi: "Lappeenranta", point: (61.0583, 28.1887), precision: .town, inEn: "in Lappeenranta", inFi: "Lappeenrannassa"),
        Place(key: "joensuu", en: "Joensuu", fi: "Joensuu", point: (62.6010, 29.7636), precision: .town, inEn: "in Joensuu", inFi: "Joensuussa"),
        Place(key: "rovaniemi", en: "Rovaniemi", fi: "Rovaniemi", point: (66.5039, 25.7294), precision: .town, inEn: "in Rovaniemi", inFi: "Rovaniemellä"),
        Place(key: "hanko", en: "Hanko", fi: "Hanko", point: (59.8236, 22.9681), precision: .town, inEn: "in Hanko", inFi: "Hangossa"),
        Place(key: "lahti", en: "Lahti", fi: "Lahti", point: (60.9827, 25.6612), precision: .town, inEn: "in Lahti", inFi: "Lahdessa"),
        Place(key: "vaasa", en: "Vaasa", fi: "Vaasa", point: (63.0951, 21.6165), precision: .town, inEn: "in Vaasa", inFi: "Vaasassa"),
        Place(key: "tukholma", en: "Stockholm", fi: "Tukholma", point: (59.3293, 18.0686), precision: .town, inEn: "in Stockholm", inFi: "Tukholmassa"),
        Place(key: "karjala", en: "Karelia", fi: "Karjala", point: (61.5, 30.2), precision: .region, inEn: "in Karelia", inFi: "Karjalassa"),
        Place(key: "mokki", en: "The Puumala cottage", fi: "Puumalan mökki", point: (61.55, 28.25), precision: .exact,
              inEn: "at the cottage", inFi: "mökillä", placedBy: "ritva"),
        Place(key: "koivula", en: "Koivula farm", fi: "Koivulan tila", point: (61.72, 27.10), precision: .exact,
              inEn: "at Koivula", inFi: "Koivulassa", placedBy: "matti"),
        // A farm the gazetteer never heard of and a croft nobody can find:
        // most of a family's places, and the map's list of places not on it.
        Place(key: "riihiniemi", en: "Riihiniemi", fi: "Riihiniemi", point: nil, precision: .unknown,
              inEn: "at Riihiniemi", inFi: "Riihiniemessä"),
        Place(key: "makela", en: "The Mäkelä croft", fi: "Mäkelän torppa", point: nil, precision: .unknown,
              inEn: "at the Mäkelä croft", inFi: "Mäkelän torpalla"),
        Place(key: "taipale", en: "Taipale", fi: "Taipale", point: nil, precision: .unknown,
              inEn: "at Taipale", inFi: "Taipaleella", heard: true),
        Place(key: "kannas", en: "The Karelian Isthmus", fi: "Kannas", point: nil, precision: .unknown,
              inEn: "on the Isthmus", inFi: "Kannaksella", heard: true),
    ]

    /// How a date was told. The year it belongs to is the row's.
    private enum Told {
        case day(Int, Int)      // month, day
        case month(Int)
        case year
        case about              // "around 1955"
        case decade
        case unknown            // somebody said they do not know
        case never              // nobody has said anything
        case span(Int)          // from the row's year to this one
    }

    private struct Event {
        let key: String
        let en: String
        let fi: String
        let year: Int
        let told: Told
    }

    private static let events: [Event] = [
        Event(key: "wedding1918", en: "Väinö and Hilja's wedding", fi: "Väinön ja Hiljan häät", year: 1918, told: .day(6, 24)),
        Event(key: "winterwar", en: "The Winter War", fi: "Talvisota", year: 1939, told: .span(1940)),
        Event(key: "evacuation", en: "Leaving Karelia", fi: "Evakkomatka", year: 1944, told: .month(8)),
        Event(key: "olympics", en: "The Helsinki Olympics", fi: "Helsingin olympialaiset", year: 1952, told: .month(7)),
        Event(key: "auction", en: "The Koivula auction", fi: "Koivulan huutokauppa", year: 1958, told: .about),
        Event(key: "sweden", en: "Reino moves to Sweden", fi: "Reinon muutto Ruotsiin", year: 1960, told: .decade),
        Event(key: "wedding1976", en: "Matti and Ritva's wedding", fi: "Matin ja Ritvan häät", year: 1976, told: .day(6, 12)),
        Event(key: "sold", en: "Koivula is sold", fi: "Koivula myydään", year: 1987, told: .year),
        Event(key: "aune80", en: "Aune's eightieth birthday", fi: "Aunen 80-vuotispäivät", year: 2007, told: .day(8, 12)),
        Event(key: "reunion", en: "The family reunion", fi: "Sukukokous", year: 2019, told: .day(7, 6)),
    ]

    /// The event the first telling of a photograph names.
    private static let eventOfRow: [Int: String] = [
        9: "wedding1918", 31: "evacuation", 45: "olympics", 55: "auction", 72: "sweden",
        94: "wedding1976", 123: "sold", 140: "aune80", 147: "reunion",
    ]

    // MARK: - Photographs

    private struct Row {
        let year: Int
        let told: Told
        let scene: LargeArchivePictures.Scene
        let cast: [String]
        let place: String
        let tellings: Int
        let en: String?
        let fi: String?
    }

    private static func r(
        _ year: Int, _ told: Told, _ scene: LargeArchivePictures.Scene, _ cast: String, _ place: String,
        _ tellings: Int, _ en: String? = nil, _ fi: String? = nil
    ) -> Row {
        Row(year: year, told: told, scene: scene, cast: cast.split(separator: " ").map(String.init),
            place: place, tellings: tellings, en: en, fi: fi)
    }

    /// The album, in the order it was scanned. Row n is `large-photo-n`.
    private static let rows: [Row] = [
        r(1903, .decade, .studio, "aapo", "sortavala", 2, "Aapo at the photographer's", "Aapo valokuvaamossa"),
        r(1905, .decade, .couple, "aapo lyyli", "sortavala", 2, "Aapo and Lyyli", "Aapo ja Lyyli"),
        r(1907, .unknown, .group, "aapo lyyli vaino impi sulo kerttu", "riihiniemi", 3, "The Riihiniemi household", "Riihiniemen väki"),
        r(1910, .about, .farm, "aapo vaino sulo", "riihiniemi", 1),
        r(1912, .year, .wedding, "impi urho aapo lyyli vaino", "savonlinna", 2, "Impi and Urho's wedding", "Impin ja Urhon häät"),
        r(1914, .decade, .haying, "vaino sulo kerttu selma", "riihiniemi", 1),
        r(1916, .never, .studio, "kerttu", "sortavala", 0),
        r(1917, .decade, .winter, "sulo vaino", "karjala", 1),
        r(1918, .day(6, 24), .wedding, "vaino hilja aapo lyyli impi urho sulo kerttu", "makela", 3,
          "Väinö and Hilja's wedding day", "Väinön ja Hiljan hääpäivä"),
        r(1919, .about, .farm, "vaino hilja", "koivula", 2, "Moving to Koivula", "Muutto Koivulaan"),
        r(1921, .year, .baby, "hilja toivo", "koivula", 1),
        r(1922, .decade, .studio, "sulo onni", "oulu", 1),
        r(1924, .day(8, 2), .wedding, "kerttu oiva aapo lyyli eemeli", "viipuri", 2, "Kerttu and Oiva's wedding", "Kertun ja Oivan häät"),
        r(1925, .unknown, .group, "impi urho hilja toivo martta", "savonlinna", 1),
        r(1927, .decade, .haying, "vaino hilja toivo martta eino kustaa", "koivula", 3, "Haymaking at Koivula", "Heinänteko Koivulassa"),
        r(1928, .about, .studio, "aapo", "sortavala", 2, "Grandfather Aapo", "Aapo-vaari"),
        r(1929, .never, .lake, "oiva kerttu paavo helvi", "viipuri", 0),
        r(1930, .year, .group, "aapo lyyli kerttu oiva paavo helvi", "viipuri", 1),
        r(1931, .decade, .winter, "toivo martta eino", "koivula", 1),
        r(1932, .year, .school, "eino martta hellin", "koivula", 2, "The village school", "Kyläkoulu"),
        r(1933, .about, .sauna, "vaino toivo eino", "koivula", 1),
        r(1934, .day(6, 10), .baby, "hilja sirkka", "koivula", 2, "Sirkka's christening", "Sirkan ristiäiset"),
        r(1936, .year, .town, "lyyli kerttu", "viipuri", 2, "Market day in Viipuri", "Markkinapäivä Viipurissa"),
        r(1937, .decade, .group, "vaino hilja toivo martta eino aune reino sirkka", "koivula", 4,
          "The Koivula family in front of the house", "Koivulan perhe talon edessä"),
        r(1938, .unknown, .lake, "reino sirkka aune", "koivula", 0),
        r(1939, .month(10), .soldiers, "toivo yrjo onni", "karjala", 3, "Before the Winter War", "Ennen talvisotaa"),
        r(1940, .year, .soldiers, "toivo onni ilmari", "karjala", 1),
        r(1941, .unknown, .studio, "anneli", "tampere", 1),
        r(1942, .about, .soldiers, "eino toivo", "karjala", 2, "Eino and Toivo at the front", "Eino ja Toivo rintamalla"),
        r(1943, .never, .winter, "hilja sirkka reino", "koivula", 0),
        r(1944, .month(8), .farm, "kerttu oiva helvi eemeli", "karjala", 3, "Leaving Karelia", "Lähtö Karjalasta"),
        r(1945, .year, .group, "vaino hilja toivo martta eino aune reino sirkka", "koivula", 3, "Everyone came home", "Kaikki tulivat kotiin"),
        r(1946, .decade, .haying, "aune reino sirkka tyyne", "koivula", 1),
        r(1947, .about, .lake, "aune helvi tyyne", "puumala", 2, "The girls at the lake", "Tytöt rannalla"),
        r(1948, .day(6, 19), .wedding, "toivo anneli vaino hilja martta eino", "tampere", 3, "Toivo and Anneli's wedding", "Toivon ja Annelin häät"),
        r(1948, .unknown, .studio, "sirkka", "mikkeli", 0),
        r(1949, .year, .town, "toivo anneli", "tampere", 1, "Hämeenkatu", "Hämeenkatu"),
        r(1949, .decade, .beach, "martta eino helvi", "hanko", 1),
        r(1946, .year, .graduation, "anneli", "tampere", 2, "Anneli's white cap", "Annelin lakki"),
        r(1947, .decade, .sauna, "paavo eino reino", "puumala", 1),
        r(1950, .month(7), .wedding, "eino helvi kerttu oiva vaino hilja", "kuopio", 2, "Eino and Helvi's wedding", "Einon ja Helvin häät"),
        r(1950, .year, .wedding, "paavo aune kerttu oiva hilja", "savonlinna", 2, "Aune and Paavo", "Aune ja Paavo"),
        r(1950, .day(4, 2), .baby, "anneli matti", "tampere", 2, "Matti's first photograph", "Matin ensimmäinen kuva"),
        r(1951, .about, .baby, "helvi kaarina", "kuopio", 1),
        r(1952, .month(7), .town, "toivo anneli matti", "helsinki", 3, "The Olympics in Helsinki", "Olympialaiset Helsingissä"),
        r(1952, .unknown, .baby, "aune ritva", "savonlinna", 1),
        r(1953, .decade, .group, "vaino hilja toivo anneli matti martta veikko", "koivula", 1),
        r(1954, .year, .lake, "paavo aune ritva", "puumala", 2, "Rowing at Puumala", "Soutelemassa Puumalassa"),
        r(1954, .never, .baby, "anneli liisa", "tampere", 0),
        r(1955, .about, .haying, "vaino toivo eino matti", "koivula", 2, "The last haymaking with horses", "Viimeinen heinänteko hevosella"),
        r(1956, .year, .wedding, "sirkka eemeli hilja vaino aune", "savonlinna", 3, "Sirkka's wedding", "Sirkan häät"),
        r(1956, .decade, .christmas, "toivo anneli matti liisa", "tampere", 1),
        r(1957, .unknown, .winter, "matti liisa veikko", "tampere", 0),
        r(1957, .year, .town, "reino verneri", "helsinki", 1),
        r(1958, .about, .farm, "vaino hilja alma toivo", "koivula", 2, "The Koivula auction", "Koivulan huutokauppa"),
        r(1958, .decade, .beach, "helvi kaarina eino", "hanko", 1),
        r(1959, .year, .car, "toivo anneli matti liisa", "tampere", 3, "The first car", "Ensimmäinen auto"),
        r(1959, .unknown, .studio, "onni", "rovaniemi", 1),
        r(1953, .never, .sauna, "paavo eino toivo", "puumala", 0),
        r(1958, .year, .school, "matti anneli", "tampere", 2, "Mother as the teacher", "Äiti opettajana"),
        r(1954, .year, .graduation, "sirkka hilja vaino", "mikkeli", 2, "Sirkka's white cap", "Sirkan ylioppilaslakki"),
        r(1959, .month(12), .christmas, "vaino hilja toivo anneli matti liisa sirkka eemeli", "koivula", 3, "Christmas at Koivula", "Joulu Koivulassa"),
        r(1960, .year, .car, "paavo aune ritva", "savonlinna", 1),
        r(1961, .decade, .beach, "matti liisa kaarina", "hanko", 1),
        r(1962, .about, .table, "aune paavo ritva eemeli sirkka", "mokki", 3, "The first summer at the cottage", "Ensimmäinen mökkikesä"),
        r(1962, .day(6, 30), .wedding, "helmi otto rauha", "hanko", 1, "Otto and Helmi", "Otto ja Helmi"),
        r(1963, .unknown, .lake, "matti liisa toivo", "mokki", 0),
        r(1963, .year, .sauna, "toivo paavo matti", "mokki", 1),
        r(1964, .decade, .car, "eino helvi kaarina", "kuopio", 1),
        r(1965, .month(6), .graduation, "matti toivo anneli", "tampere", 2, "Matti's confirmation", "Matin rippijuhla"),
        r(1965, .about, .group, "hilja toivo anneli matti liisa martta veikko sirkka", "koivula", 2,
          "After Väinö's funeral", "Väinön hautajaisten jälkeen"),
        r(1966, .year, .town, "reino verneri", "tukholma", 2, "Reino in Stockholm", "Reino Tukholmassa"),
        r(1966, .decade, .winter, "matti liisa", "tampere", 1),
        r(1967, .never, .table, "sisko mauri tarja", "joensuu", 0),
        r(1967, .year, .beach, "ritva kaarina", "hanko", 1),
        r(1968, .about, .studio, "sirkka", "savonlinna", 1),
        r(1968, .decade, .haying, "toivo matti veikko", "koivula", 1),
        r(1969, .day(6, 1), .graduation, "matti toivo anneli liisa", "tampere", 3, "Matti's white cap", "Matin lakkiaiset"),
        r(1969, .unknown, .car, "onni ilmari", "rovaniemi", 1),
        r(1960, .decade, .christmas, "toivo anneli matti liisa hilja", "tampere", 1),
        r(1961, .year, .lake, "eemeli sirkka reino", "savonlinna", 1),
        r(1962, .year, .group, "kerttu oiva helvi eino kaarina paavo aune ritva", "lappeenranta", 2, "Kerttu's sixtieth", "Kertun kuusikymppiset"),
        r(1964, .about, .table, "aune paavo ritva tyyne", "mokki", 1),
        r(1966, .year, .baby, "sisko onerva", "joensuu", 1),
        r(1968, .unknown, .lake, "ritva liisa", "mokki", 0),
        r(1961, .year, .school, "liisa", "tampere", 1, "Liisa's class", "Liisan luokka"),
        r(1970, .year, .table, "toivo anneli matti liisa aune paavo ritva", "mokki", 2, "Coffee at the cottage", "Kahvit mökillä"),
        r(1971, .about, .car, "matti lauri", "helsinki", 1),
        r(1970, .year, .soldiers, "matti lauri", "lappeenranta", 2, "Matti in the army", "Matti armeijassa"),
        r(1973, .day(8, 11), .wedding, "kaarina heikki eino helvi", "jyvaskyla", 2, "Kaarina and Heikki's wedding", "Kaarinan ja Heikin häät"),
        r(1974, .unknown, .beach, "liisa kaarina ritva", "hanko", 1),
        r(1975, .year, .baby, "kaarina aleksi", "jyvaskyla", 1),
        r(1975, .about, .wedding, "tuula veikko martta", "lahti", 1, "Veikko and Tuula", "Veikko ja Tuula"),
        r(1976, .day(6, 12), .wedding, "ritva matti toivo anneli aune paavo liisa", "tampere", 4, "Matti and Ritva's wedding", "Matin ja Ritvan häät"),
        r(1977, .decade, .table, "matti ritva aune paavo", "mokki", 1),
        r(1978, .month(5), .baby, "ritva elina", "tampere", 2, "Elina comes home", "Elina tulee kotiin"),
        r(1978, .year, .christmas, "toivo anneli matti ritva elina liisa", "tampere", 1),
        r(1979, .about, .baby, "tuula sanni", "lahti", 1),
        r(1979, .unknown, .lake, "matti elina", "mokki", 0),
        r(1970, .decade, .town, "liisa", "helsinki", 1),
        r(1972, .year, .graduation, "liisa toivo anneli", "tampere", 1, "Liisa's white cap", "Liisan lakki"),
        r(1972, .never, .studio, "hilja", "mikkeli", 0),
        r(1973, .year, .sauna, "toivo matti paavo", "mokki", 1),
        r(1974, .decade, .winter, "matti ritva liisa", "lahti", 2, "The Lahti ski games", "Salpausselän kisat"),
        r(1976, .unknown, .car, "eemeli sirkka", "savonlinna", 1),
        r(1977, .year, .group, "kerttu helvi eino kaarina heikki aleksi", "kuopio", 1),
        r(1978, .about, .town, "reino", "tukholma", 1),
        r(1979, .decade, .farm, "matti toivo elina", "koivula", 0),
        r(1980, .year, .table, "aune paavo ritva elina matti", "mokki", 1),
        r(1981, .month(9), .baby, "ritva jukka elina", "tampere", 2, "Jukka is born", "Jukka syntyi"),
        r(1982, .about, .beach, "matti elina ritva", "hanko", 1),
        r(1983, .decade, .christmas, "toivo anneli matti ritva elina jukka", "tampere", 1),
        r(1985, .day(8, 15), .school, "elina", "helsinki", 2, "Elina's first school day", "Elinan ensimmäinen koulupäivä"),
        r(1985, .unknown, .lake, "elina jukka matti", "mokki", 1),
        r(1986, .year, .car, "matti ritva elina jukka", "helsinki", 1, "The Volvo", "Volvo"),
        r(1986, .about, .winter, "elina jukka sanni", "lahti", 1),
        r(1987, .decade, .table, "aune paavo tyyne ritva", "mokki", 1),
        r(1988, .never, .sauna, "matti jukka paavo", "mokki", 0),
        r(1986, .day(4, 20), .group, "anneli toivo matti liisa elina jukka", "tampere", 2, "Anneli's sixtieth", "Annelin kuusikymppiset"),
        r(1989, .decade, .beach, "jukka elina aleksi", "hanko", 1),
        r(1984, .unknown, .town, "liisa", "helsinki", 1),
        r(1983, .year, .studio, "elina", "tampere", 1, "Elina at five", "Elina viisivuotiaana"),
        r(1985, .about, .farm, "toivo anneli matti elina", "koivula", 2, "Koivula before it was sold", "Koivula ennen myyntiä"),
        r(1989, .month(7), .table, "matti ritva elina jukka aune paavo sirkka", "mokki", 1),
        r(1990, .year, .graduation, "aleksi kaarina heikki", "jyvaskyla", 1),
        r(1991, .about, .beach, "elina jukka", "hanko", 1),
        r(1992, .decade, .table, "aune paavo ritva matti elina jukka", "mokki", 1),
        r(1993, .year, .christmas, "toivo anneli matti ritva elina jukka liisa", "helsinki", 1),
        r(1994, .unknown, .car, "jukka matti", "helsinki", 0),
        r(1997, .day(5, 31), .graduation, "elina matti ritva jukka", "helsinki", 3, "Elina's white cap", "Elinan lakkiaiset"),
        r(1996, .year, .winter, "jukka elina", "helsinki", 1),
        r(1998, .about, .lake, "mikko elina paavo", "mokki", 2, "Mikko's first summer at the cottage", "Mikon ensimmäinen mökkikesä"),
        r(1999, .unknown, .group, "anneli matti liisa ritva elina jukka", "tampere", 1, "After Toivo's funeral", "Toivon hautajaisten jälkeen"),
        r(1995, .decade, .sauna, "matti jukka heikki", "mokki", 0),
        r(1997, .year, .town, "onerva tarja", "vaasa", 1),
        r(1993, .about, .beach, "sisko mauri tarja", "vaasa", 1),
        r(2001, .day(6, 23), .table, "aune paavo ritva matti elina mikko jukka", "mokki", 1),
        r(2005, .day(7, 9), .wedding, "elina mikko matti ritva jukka", "helsinki", 2, "Elina and Mikko's wedding", "Elinan ja Mikon häät"),
        r(2006, .day(10, 1), .baby, "elina venla", "helsinki", 1, "Venla", "Venla"),
        r(2007, .day(8, 12), .group, "aune ritva matti elina jukka venla sirkka", "savonlinna", 2),
        r(2009, .year, .beach, "elina venla mikko", "hanko", 1),
        r(2010, .day(6, 5), .wedding, "petra jukka matti ritva", "turku", 1, "Jukka and Petra", "Jukka ja Petra"),
        r(2012, .about, .christmas, "matti ritva elina mikko venla oskari jukka petra elias", "helsinki", 1),
        r(2014, .year, .lake, "oskari venla matti", "mokki", 1),
        r(2016, .month(3), .winter, "venla oskari aino", "helsinki", 1),
        r(2017, .unknown, .table, "aleksi noora iiris", "oulu", 0),
        r(2019, .day(7, 6), .group, "matti ritva liisa kaarina sanni elina mikko jukka petra venla oskari aino elias", "puumala", 3,
          "The family reunion", "Sukukokous"),
        r(2021, .year, .sauna, "mikko oskari jukka elias", "mokki", 1),
        r(2025, .day(5, 31), .graduation, "venla elina mikko oskari aino", "helsinki", 2, "Venla's white cap", "Venlan lakkiaiset"),
        r(2024, .year, .studio, "sirkka", "savonlinna", 2, "Sirkka at ninety", "Sirkka 90 vuotta"),
    ]

    /// The one photograph whose teller asked not to be named.
    private static let hiddenTellerRow = 133

    /// Kept colourings: the row, and the member who said yes.
    private static let colourings: [(row: Int, by: String)] = [(24, "matti"), (35, "liisa"), (16, "elina")]

    /// Faces on person cards: the person, and the photograph their disc is cut from.
    private static let portraits: [(person: String, row: Int)] = [
        ("aapo", 1), ("lyyli", 2), ("vaino", 9), ("hilja", 9), ("kerttu", 7), ("sulo", 12), ("oiva", 13),
        ("anneli", 28), ("toivo", 35), ("eino", 41), ("helvi", 41), ("aune", 42), ("paavo", 42), ("onni", 58),
        ("otto", 66), ("helmi", 66), ("reino", 72), ("matti", 78), ("kaarina", 90), ("heikki", 90),
        ("ritva", 94), ("liisa", 101), ("elina", 130), ("mikko", 138), ("jukka", 142), ("petra", 142),
        ("venla", 149), ("sirkka", 150),
    ]

    // MARK: - What people say about a photograph

    /// A sentence somebody might say about a kind of picture. The slots are
    /// filled from the photograph: `{A}`, `{B}` and `{C}` are people in it,
    /// `{W}` and `{H}` a bride and a groom, `{P}` where it was. A line whose
    /// slot the picture cannot fill, or would fill with the teller's own
    /// name, is not said.
    private struct Line {
        let en: String
        let fi: String
        var from = 0
        var to = 9999
        /// Said in the first person, by somebody who was old enough to be there.
        var witness = false
    }

    private static let lines: [LargeArchivePictures.Scene: [Line]] = [
        .studio: [
            Line(en: "{A} went to the photographer in town for this. It cost a week's wages, so nobody smiled.",
                 fi: "{A} kävi tätä varten kaupungin valokuvaamossa. Kuva maksoi viikon palkan, joten kukaan ei hymyillyt.", to: 1960),
            Line(en: "This is the only picture of {A} from those years. The collar was borrowed.",
                 fi: "Tämä on ainoa kuva noilta vuosilta, jossa on {A}. Kaulus oli lainattu.", to: 1960),
            Line(en: "{A} kept this picture in the Bible, at the Psalms.",
                 fi: "{A} piti tätä kuvaa Raamatun välissä Psalmien kohdalla.", to: 1960),
            Line(en: "Look at the hands. {A} never knew what to do with them in front of a camera.",
                 fi: "Katso käsiä. {A} ei koskaan tiennyt, mitä niillä tehdä kameran edessä."),
            Line(en: "The photographer had a painted forest behind the chair, and half the town has the same forest behind them.",
                 fi: "Valokuvaajalla oli tuolin takana maalattu metsä, ja puolen kaupungin kuvissa on sama metsä.", to: 1935),
            Line(en: "{A} sent this one to the relatives so they would know everybody was well.",
                 fi: "{A} lähetti tämän sukulaisille, jotta he tietäisivät kaikkien voivan hyvin."),
            Line(en: "{A} hated having this taken and loved the picture afterwards.",
                 fi: "{A} inhosi kuvattavana olemista mutta rakasti kuvaa jälkeenpäin."),
        ],
        .couple: [
            Line(en: "{A} and {B} had been married a few years here.",
                 fi: "{A} ja {B} olivat olleet tässä naimisissa muutaman vuoden."),
            Line(en: "{B} always said {A} was the one who asked, and {A} always said it was the other way round.",
                 fi: "{B} sanoi aina, että {A} kosi, ja {A} sanoi aina, että asia oli toisin päin."),
            Line(en: "They met at a dance {P}, and {A} walked twenty kilometres home afterwards.",
                 fi: "He tapasivat tansseissa {P}, ja {A} käveli sen jälkeen kaksikymmentä kilometriä kotiin.", to: 1950),
            Line(en: "This hung above the sofa for fifty years.",
                 fi: "Tämä kuva riippui sohvan yläpuolella viisikymmentä vuotta."),
        ],
        .wedding: [
            Line(en: "{W} and {H} were married {P}. The coffee ran out before the dancing started.",
                 fi: "{W} ja {H} vihittiin {P}. Kahvi loppui ennen kuin tanssit alkoivat."),
            Line(en: "{C} baked the wedding cake and would not let anybody near it.",
                 fi: "{C} leipoi hääkakun eikä päästänyt ketään sen lähelle."),
            Line(en: "It rained all morning, and {W} took it as a good sign.",
                 fi: "Koko aamupäivän satoi, ja {W} piti sitä hyvänä enteenä."),
            Line(en: "{W} wore her mother's shoes, half a size too small.",
                 fi: "{W} käytti äitinsä kenkiä, jotka olivat puoli numeroa liian pienet."),
            Line(en: "{H} forgot the ring at home, and a cousin cycled back for it.",
                 fi: "{H} unohti sormuksen kotiin, ja serkku pyöräili hakemaan sen."),
        ],
        .group: [
            Line(en: "Everybody who lived in the house is here. Count them: one bed for every two.",
                 fi: "Kaikki talossa asuneet ovat tässä. Laske: yksi sänky jokaista kahta kohden.", to: 1950),
            Line(en: "{A} made everybody stand still so long that {C} started crying.",
                 fi: "{A} pani kaikki seisomaan paikallaan niin kauan, että {C} alkoi itkeä."),
            Line(en: "The whole family together for once {P}. Somebody always had to leave early, and it was always the same person.",
                 fi: "Koko perhe kerrankin koolla {P}. Jonkun piti aina lähteä aikaisin, ja se oli aina sama ihminen."),
            Line(en: "{B} is the one squinting. The sun was right in everybody's eyes.",
                 fi: "{B} on se, joka siristää silmiään. Aurinko paistoi kaikkia suoraan silmiin."),
            Line(en: "{A} insisted on a photograph every time the family was together.",
                 fi: "{A} vaati valokuvaa aina, kun perhe oli koolla."),
        ],
        .haying: [
            Line(en: "Haymaking {P}. Everybody worked, even {C}.",
                 fi: "Heinäntekoa {P}. Kaikki tekivät töitä, jopa {C}."),
            Line(en: "{A} put up the drying poles, and nobody else was allowed to touch them.",
                 fi: "{A} pystytti seipäät, eikä kukaan muu saanut koskea niihin."),
            Line(en: "{B} carried the coffee out in a milk can.",
                 fi: "{B} kantoi kahvit pellolle maitotonkassa."),
            Line(en: "My hands still remember the rake.",
                 fi: "Käteni muistavat haravan vieläkin.", witness: true),
        ],
        .farm: [
            Line(en: "The farm {P}. The horse was called Pollu, and it knew the way home better than anyone.",
                 fi: "Tila {P}. Hevosen nimi oli Pollu, ja se osasi kotiin paremmin kuin kukaan.", to: 1960),
            Line(en: "{B} had the house painted red the summer this was taken.",
                 fi: "{B} maalautti talon punaiseksi sinä kesänä, kun tämä otettiin."),
            Line(en: "That is the yard where we played until it got dark.",
                 fi: "Tuossa on piha, jolla leikimme pimeään asti.", witness: true),
            Line(en: "{A} came back from town with news, and everybody came out to hear it.",
                 fi: "{A} palasi kaupungista uutisten kanssa, ja kaikki tulivat pihalle kuulemaan."),
        ],
        .christmas: [
            Line(en: "Real candles on the tree, and a bucket of water beside it just in case.",
                 fi: "Kuusessa oli oikeat kynttilät ja vieressä ämpärillinen vettä varmuuden vuoksi.", to: 1960),
            Line(en: "{C} got a wooden horse that year, and it is still in the attic.",
                 fi: "{C} sai sinä vuonna puuhevosen, ja se on yhä vintillä.", to: 1970),
            Line(en: "Rice porridge, and whoever found the almond got to make a wish. It was always {B}.",
                 fi: "Riisipuuroa, ja joka löysi mantelin, sai toivoa jotakin. Se oli aina {B}."),
            Line(en: "{A} read the Christmas Gospel before anybody was allowed to eat.",
                 fi: "{A} luki jouluevankeliumin ennen kuin kukaan sai syödä."),
            Line(en: "Christmas {P}. Everybody got socks, and everybody pretended to be surprised.",
                 fi: "Joulu {P}. Kaikki saivat sukat, ja kaikki esittivät yllättyvänsä."),
        ],
        .car: [
            Line(en: "{A} was so proud of this car that nobody else was allowed to close its doors.",
                 fi: "{A} oli niin ylpeä tästä autosta, ettei kukaan muu saanut sulkea sen ovia."),
            Line(en: "Every summer in this car: four in the back seat and the dog on somebody's lap.",
                 fi: "Joka kesä tällä autolla: neljä takapenkillä ja koira jonkun sylissä.", witness: true),
            Line(en: "{B} learned to drive at forty and never let anyone forget it.",
                 fi: "{B} oppi ajamaan neljäkymppisenä eikä antanut kenenkään unohtaa sitä."),
            Line(en: "It broke down on the way to the cottage, and {A} fixed it with a nylon stocking.",
                 fi: "Auto hajosi matkalla mökille, ja {A} korjasi sen nailonsukalla."),
        ],
        .soldiers: [
            Line(en: "{A} and {B} were called up the same week.",
                 fi: "{A} ja {B} kutsuttiin palvelukseen samalla viikolla."),
            Line(en: "{A} sent this home. On the back it says: all well, send socks.",
                 fi: "{A} lähetti tämän kotiin. Takana lukee: kaikki hyvin, lähettäkää sukkia."),
            Line(en: "{B} never said a word about those years, not even to his wife.",
                 fi: "{B} ei puhunut noista vuosista sanaakaan, ei edes vaimolleen.", to: 1950),
            Line(en: "Look how young they are. {A} had hardly started shaving.",
                 fi: "Katso, miten nuoria he ovat. {A} oli tuskin alkanut ajaa partaansa."),
        ],
        .graduation: [
            Line(en: "The graduation party. {B} cried at the gate.",
                 fi: "Ylioppilasjuhlat. {B} itki portilla."),
            Line(en: "{A} studied every night at the kitchen table, and here is the cap to show for it.",
                 fi: "{A} luki joka ilta keittiön pöydän ääressä, ja tässä on lakki todisteena."),
            Line(en: "There were lilacs everywhere, and {A} kept a jar of them on the kitchen table for a week.",
                 fi: "Syreenit kukkivat kaikkialla, ja {A} piti niitä purkissa keittiön pöydällä viikon."),
        ],
        .lake: [
            Line(en: "Rowing {P}. {A} rowed and {B} complained about the oars.",
                 fi: "Soutelemassa {P}. {A} souti ja {B} valitti airoista."),
            Line(en: "The boat leaked, and somebody had to bail the whole way. That was always {C}.",
                 fi: "Vene vuoti, ja jonkun piti äyskäröidä koko matka. Se oli aina {C}."),
            Line(en: "We caught nothing that day, and {A} said it was the best fishing trip of the summer.",
                 fi: "Emme saaneet sinä päivänä mitään, ja {A} sanoi sitä kesän parhaaksi kalareissuksi.", witness: true),
            Line(en: "The lake was so still you could hear the neighbours talking on the other shore.",
                 fi: "Järvi oli niin tyyni, että naapurien puheen kuuli vastarannalle asti."),
        ],
        .sauna: [
            Line(en: "The sauna {P}. {A} heated it every Saturday, whatever the weather.",
                 fi: "Sauna {P}. {A} lämmitti sen joka lauantai säällä kuin säällä."),
            Line(en: "{B} always went in first and came out last.",
                 fi: "{B} meni aina ensimmäisenä sisään ja tuli viimeisenä ulos."),
            Line(en: "We swam off the jetty afterwards, even in October. {A} called it medicine.",
                 fi: "Saunan jälkeen uimme laiturilta, lokakuussakin. {A} sanoi sitä lääkkeeksi.", witness: true),
            Line(en: "{A} built this sauna with the neighbours, one log at a time.",
                 fi: "{A} rakensi tämän saunan naapurien kanssa hirsi kerrallaan.", to: 1960),
        ],
        .winter: [
            Line(en: "Skiing {P}. {A} waxed the skis the night before and would not say what with.",
                 fi: "Hiihtämässä {P}. {A} voiteli sukset edellisenä iltana eikä kertonut, millä."),
            Line(en: "It was so cold that the milk froze in the can. {B} went to school anyway.",
                 fi: "Oli niin kylmä, että maito jäätyi tonkkaan. {B} meni silti kouluun.", to: 1965),
            Line(en: "{A} and {B} skied to the village shop and back before breakfast.",
                 fi: "{A} ja {B} hiihtivät kyläkauppaan ja takaisin ennen aamiaista."),
            Line(en: "That was the winter we dug a tunnel to the woodshed.",
                 fi: "Sinä talvena kaivoimme tunnelin puuliiteriin.", witness: true),
        ],
        .beach: [
            Line(en: "Summer {P}. {A} swam out to the rock and back every morning.",
                 fi: "Kesä {P}. {A} ui joka aamu kivelle ja takaisin."),
            Line(en: "The water was freezing, and {B} went in anyway, just to show us.",
                 fi: "Vesi oli jääkylmää, ja {B} meni silti uimaan, ihan vain näyttääkseen."),
            Line(en: "There was sand in the sandwiches, and nobody minded.",
                 fi: "Voileivissä oli hiekkaa, eikä kukaan välittänyt."),
            Line(en: "{C} got so sunburnt that day that {A} covered the burn in soured milk.",
                 fi: "{C} paloi sinä päivänä niin pahasti, että {A} hoiti palovamman piimällä.", to: 1980),
        ],
        .school: [
            Line(en: "The school photograph. {A} is in there somewhere; the family never agreed which one.",
                 fi: "Koulukuva. {A} on siinä jossakin, mutta suvussa ei koskaan sovittu, kuka heistä."),
            Line(en: "{A} walked four kilometres to school with a warm potato in each pocket.",
                 fi: "{A} käveli kouluun neljä kilometriä lämmin peruna kummassakin taskussa.", to: 1960),
            Line(en: "They learned the times tables as songs, and {A} could still sing them decades later.",
                 fi: "Kertotaulut opeteltiin lauluina, ja {A} osasi laulaa ne vielä vuosikymmenten päästä."),
            Line(en: "{B} was the teacher. There was a birch switch on the desk, and it was never once used.",
                 fi: "{B} oli opettaja. Pöydällä oli koivunvitsa, eikä sitä käytetty kertaakaan.", to: 1960),
        ],
        .town: [
            Line(en: "A day {P}. {A} bought coffee, sugar and a newspaper, and nothing else.",
                 fi: "Kaupunkipäivä {P}. {A} osti kahvia, sokeria ja sanomalehden eikä mitään muuta."),
            Line(en: "{A} loved the city. {B} counted the hours until the train home.",
                 fi: "{A} rakasti kaupunkia. {B} laski tunteja kotijunaan."),
            Line(en: "There was a street photographer who sold the pictures by post.",
                 fi: "Kadulla oli valokuvaaja, joka myi kuvat postitse.", to: 1970),
            Line(en: "The street is still there, but the shop on the corner is gone.",
                 fi: "Katu on yhä paikallaan, mutta kulman kauppa on poissa."),
        ],
        .table: [
            Line(en: "Coffee at the table {P}. {A} baked the pulla that morning.",
                 fi: "Kahvipöydässä {P}. {A} leipoi pullat samana aamuna."),
            Line(en: "{B} laughed so hard the cups rattled.",
                 fi: "{B} nauroi niin, että kupit helisivät."),
            Line(en: "Seven kinds of cookies, because {A} would not serve six.",
                 fi: "Seitsemää sorttia pikkuleipiä, koska {A} ei suostunut tarjoamaan kuutta."),
            Line(en: "Every decision in the family was made at this table, usually over the third cup.",
                 fi: "Kaikki suvun päätökset tehtiin tämän pöydän ääressä, yleensä kolmannen kupin kohdalla."),
        ],
        .baby: [
            Line(en: "{A} was a few weeks old here. {B} said the baby never slept a whole night that year.",
                 fi: "{A} oli tässä muutaman viikon ikäinen. {B} sanoi, ettei vauva nukkunut sinä vuonna yhtään kokonaista yötä."),
            Line(en: "The pram came from a cousin, and three more babies rode in it after this one.",
                 fi: "Vaunut saatiin serkulta, ja niissä kulki tämän jälkeen vielä kolme vauvaa."),
            Line(en: "{A} was christened at home, in front of the window, because the church was too far.",
                 fi: "{A} kastettiin kotona ikkunan edessä, koska kirkko oli liian kaukana.", to: 1960),
            Line(en: "Look at those cheeks. {B} knitted everything the baby is wearing.",
                 fi: "Katso noita poskia. {B} neuloi kaiken, mitä vauvalla on päällään."),
        ],
    ]

    /// A graduation under seventeen is a confirmation.
    private static let confirmationLines: [Line] = [
        Line(en: "Confirmation day. {A} had learned the whole catechism by heart and forgot half of it at the altar.",
             fi: "Rippijuhla. {A} oli opetellut koko katekismuksen ulkoa ja unohti puolet siitä alttarilla."),
        Line(en: "Confirmation camp was the first summer {A} spent away from home.",
             fi: "Rippileiri oli ensimmäinen kesä, jonka {A} vietti poissa kotoa."),
        Line(en: "{B} bought the cake from the bakery, which had never happened before.",
             fi: "{B} osti kakun leipomosta, mitä ei ollut koskaan ennen tapahtunut."),
    ]

    /// What anybody might say about any picture.
    private static let anyLines: [Line] = [
        Line(en: "I remember this picture from the album at home. It was always on the first page.",
             fi: "Muistan tämän kuvan kodin albumista. Se oli aina ensimmäisellä sivulla."),
        Line(en: "Nobody remembers who took this, but everybody remembers the day.",
             fi: "Kukaan ei muista, kuka tämän otti, mutta päivän muistavat kaikki."),
        Line(en: "{A} always said this was the happiest day of that year.",
             fi: "{A} sanoi aina, että tämä oli sen vuoden onnellisin päivä."),
    ]

    /// A sentence about the years a picture is from, added to some tellings.
    private static func era(_ year: Int) -> (en: String, fi: String) {
        switch year {
        case ..<1940: ("Those were hard years, and a photograph was a luxury.",
                       "Ne olivat kovia vuosia, ja valokuva oli ylellisyyttä.")
        case ..<1950: ("Everything was on ration cards then, even coffee.",
                       "Silloin kaikki oli kortilla, jopa kahvi.")
        case ..<1960: ("Everybody was building something in those years.",
                       "Niinä vuosina kaikki rakensivat jotakin.")
        case ..<1970: ("The radio was always on in the kitchen.",
                       "Keittiössä radio oli aina päällä.")
        case ..<1980: ("Every house had the same orange curtains.",
                       "Joka talossa oli samat oranssit verhot.")
        case ..<1990: ("A film had thirty-six pictures, so you thought before you pressed.",
                       "Filmillä oli kolmekymmentäkuusi kuvaa, joten ennen painamista mietittiin.")
        case ..<2000: ("Nobody knew then how much we would want these pictures later.",
                       "Kukaan ei silloin tiennyt, miten paljon näitä kuvia myöhemmin kaivattaisiin.")
        default: ("There are hundreds of pictures from that day, and this is the one everybody likes.",
                  "Siitä päivästä on satoja kuvia, ja tämä on se, josta kaikki pitävät.")
        }
    }

    // MARK: - Tellings written by hand

    private enum On {
        case row(Int)
        case subject(String)
    }

    /// A telling somebody wrote in their own words. `teller` is a person key:
    /// `elina` is this phone, `sirkka` tells through it, and the rest are the
    /// members in `phones`. `mentions` are keys of people, places and events.
    private struct Written {
        let on: On
        let teller: String
        let mentions: [String]
        let en: String
        let fi: String
        var id: String? = nil
        var voice = false
        var daysAgo: Double? = nil
    }

    private static func w(
        _ on: On, _ teller: String, _ mentions: String, _ en: String, _ fi: String,
        id: String? = nil, voice: Bool = false, daysAgo: Double? = nil
    ) -> Written {
        Written(on: on, teller: teller, mentions: mentions.split(separator: " ").map(String.init),
                en: en, fi: fi, id: id, voice: voice, daysAgo: daysAgo)
    }

    private static let written: [Written] = [
        // About photographs, before any generated telling of the same picture.
        w(.row(1), "matti", "aapo sortavala",
          "Aapo was my great-grandfather. This was taken at the photographer's in Sortavala, and it is the oldest picture we have.",
          "Aapo oli isoisäni isä. Tämä otettiin valokuvaamossa Sortavalassa, ja se on vanhin kuva, joka meillä on."),
        w(.row(6), "sirkka", "vaino selma riihiniemi",
          "Father told me about Selma, the maid at Riihiniemi, who raked faster than any of the boys. She is the girl on the right, I think.",
          "Isä kertoi Selmasta, Riihiniemen piiasta, joka haravoi nopeammin kuin kukaan pojista. Hän on luullakseni tuo oikeanpuoleinen tyttö.",
          voice: true),
        w(.row(9), "sirkka", "hilja ritva",
          "Mother's wedding dress was her own mother's, taken in at the waist. It is still in the trunk at Ritva's.",
          "Äidin hääpuku oli hänen oman äitinsä, vyötäröltä kavennettu. Se on yhä Ritvan luona arkussa."),
        w(.row(24), "sirkka", "sirkka koivula",
          "That is all of us at Koivula. I am the little one in front, and I would not stand still, so I am looking at the photographer's dog.",
          "Siinä olemme kaikki Koivulassa. Minä olen tuo pieni edessä, enkä pysynyt paikallani, joten katson valokuvaajan koiraa.",
          voice: true),
        w(.row(26), "matti", "toivo yrjo",
          "Dad and Yrjö from the neighbouring farm left together in October. Yrjö did not come back, and Dad kept this picture in his wallet for the rest of his life.",
          "Isä ja naapuritalon Yrjö lähtivät yhdessä lokakuussa. Yrjö ei palannut, ja isä kantoi tätä kuvaa lompakossaan koko loppuelämänsä."),
        w(.row(27), "liisa", "toivo ilmari",
          "The man on the right is Ilmari. He wrote to Dad every Christmas until the eighties.",
          "Oikeanpuoleinen mies on Ilmari. Hän kirjoitti isälle joka joulu aina 80-luvulle asti."),
        w(.row(29), "kaarina", "eino arvo kuopio",
          "Dad wrote that Arvo from Kuopio shared his tent and his tobacco. We never found out what became of him.",
          "Isä kirjoitti, että kuopiolainen Arvo jakoi hänen kanssaan teltan ja tupakat. Emme koskaan saaneet tietää, mitä hänelle tapahtui.",
          daysAgo: 3),
        w(.row(31), "kaarina", "kerttu karjala",
          "The day they left Karelia. Grandmother would not look back at the house, so in the picture she is looking at the horse.",
          "Päivä, jona he lähtivät Karjalasta. Mummo ei suostunut katsomaan taakseen taloa kohti, joten kuvassa hän katsoo hevosta.",
          voice: true),
        w(.row(34), "ritva", "aune tyyne helvi",
          "Mother and her best friend Tyyne swam across the bay that summer. Helvi rowed beside them, just in case.",
          "Äiti ja hänen paras ystävänsä Tyyne uivat sinä kesänä lahden yli. Helvi souti vieressä varmuuden vuoksi.",
          daysAgo: 2),
        w(.row(35), "liisa", "anneli toivo tampere",
          "Mum and Dad were married in Tampere in June 1948. Dad borrowed the suit from his brother.",
          "Äiti ja isä vihittiin Tampereella kesäkuussa 1948. Isä lainasi puvun veljeltään."),
        w(.row(41), "kaarina", "helvi eino kuopio",
          "Mum and Dad's wedding in Kuopio. The original print is in my drawer, and this is the copy I scanned.",
          "Äidin ja isän häät Kuopiossa. Alkuperäinen kuva on minun laatikossani, ja tämä on skannaamani kopio.",
          id: "original"),
        w(.row(45), "matti", "toivo helsinki",
          "Dad bought the tickets to the Olympics a year ahead. I was two and remember nothing, but he talked about it until the end.",
          "Isä osti liput olympialaisiin vuotta etukäteen. Olin kaksivuotias enkä muista mitään, mutta hän puhui niistä loppuun asti."),
        w(.row(51), "sirkka", "sirkka eemeli",
          "My wedding. Eemeli was fifty-two and I was twenty-two, and everybody had an opinion about it. We had twenty-five good years.",
          "Minun häät. Eemeli oli viisikymmentäkaksi ja minä kaksikymmentäkaksi, ja kaikilla oli asiasta mielipide. Meillä oli kaksikymmentäviisi hyvää vuotta.",
          voice: true),
        w(.row(57), "matti", "toivo vaino koivula",
          "The first car was a grey Volkswagen. Dad drove it into the yard at Koivula, and Grandfather walked round it three times without a word.",
          "Ensimmäinen auto oli harmaa Volkswagen. Isä ajoi sen Koivulan pihaan, ja vaari käveli sen ympäri kolme kertaa sanomatta sanaakaan.",
          id: "first-car"),
        w(.row(65), "ritva", "paavo eemeli mokki",
          "Dad and Uncle Eemeli built the cottage in two summers. The first night there was no door yet, so they hung a blanket.",
          "Isä ja Eemeli-setä rakensivat mökin kahdessa kesässä. Ensimmäisenä yönä ovea ei vielä ollut, joten he ripustivat oviaukkoon peiton.",
          id: "cottage-built"),
        w(.row(77), "ritva", "matti eeva",
          "Eeva from the neighbouring house followed Matti everywhere that summer, and he carried her home on his shoulders.",
          "Naapuritalon Eeva seurasi Mattia kaikkialle sinä kesänä, ja Matti kantoi hänet kotiin harteillaan."),
        w(.row(113), "elina", "elina helsinki",
          "My first school day at Käpylä school. I had a red satchel and new shoes that hurt.",
          "Ensimmäinen koulupäiväni Käpylän koulussa. Minulla oli punainen reppu ja uudet kengät, jotka hiersivät.",
          id: "school"),
        w(.row(113), "ritva", "elina",
          "The teacher was Mrs Lehtonen. Elina cried the first morning and did not want to leave on the last.",
          "Opettaja oli rouva Lehtonen. Elina itki ensimmäisenä aamuna eikä halunnut lähteä viimeisenä.",
          id: "teacher"),
        w(.row(132), "mikko", "mikko paavo mokki",
          "My first summer at the cottage. Paavo tested me by making me row to the village shop, and I passed.",
          "Ensimmäinen kesäni mökillä. Paavo pani minut koetukselle ja soututti minua kyläkauppaan, ja läpäisin kokeen."),
        w(.row(147), "jukka", "ritva puumala",
          "The reunion at Puumala. Mum organised it and made name tags for all fifty-three of us.",
          "Sukukokous Puumalassa. Äiti järjesti sen ja teki nimilaput meille kaikille viidellekymmenellekolmelle.",
          id: "reunion", daysAgo: 1),
        w(.row(150), "elina", "sirkka",
          "Sirkka at ninety, at her own kitchen table. She told stories for three hours and did not repeat one.",
          "Sirkka yhdeksänkymppisenä oman keittiönpöytänsä ääressä. Hän kertoi tarinoita kolme tuntia eikä toistanut yhtäkään."),

        // About people.
        w(.subject("hilja"), "sirkka", "hilja",
          "Mother sang hymns while she milked, and the cows gave more for it. That is what she said, anyway.",
          "Äiti lauloi virsiä lypsäessään, ja lehmät lypsivät sen ansiosta paremmin. Niin hän ainakin sanoi.", voice: true),
        w(.subject("vaino"), "sirkka", "vaino",
          "Father chopped wood every morning of his life, even the winter he turned seventy.",
          "Isä pilkkoi puita joka aamu koko ikänsä, vielä sinä talvena, kun täytti seitsemänkymmentä."),
        w(.subject("aapo"), "matti", "aapo sortavala",
          "Aapo came from Sortavala, and he was the first in the family who could write his name.",
          "Aapo tuli Sortavalasta, ja hän oli suvun ensimmäinen, joka osasi kirjoittaa nimensä."),
        w(.subject("hilma"), "sirkka", "hilma",
          "Hilma died young, and all that is left of her is a comb with three teeth missing.",
          "Hilma kuoli nuorena, ja hänestä on jäljellä vain kampa, josta puuttuu kolme piikkiä.", voice: true),
        w(.subject("lyyli"), "kaarina", "lyyli kerttu",
          "Lyyli was Kerttu's mother, and she was not afraid of anybody, not even the priest.",
          "Lyyli oli Kertun äiti, eikä hän pelännyt ketään, ei edes pappia."),
        w(.subject("toivo"), "matti", "toivo tampere",
          "Dad worked at Tampella for thirty-one years and never once came home late for dinner.",
          "Isä oli Tampellalla töissä kolmekymmentäyksi vuotta eikä tullut kertaakaan myöhässä päivälliselle."),
        w(.subject("anneli"), "liisa", "anneli tampere",
          "Mum taught first grade for forty years. Half of Tampere learned to read from her.",
          "Äiti opetti ekaluokkalaisia neljäkymmentä vuotta. Puolet Tampereesta oppi lukemaan häneltä."),
        w(.subject("aune"), "ritva", "aune",
          "Mother baked rye bread every Friday, and the whole street knew it by the smell.",
          "Äiti leipoi ruisleipää joka perjantai, ja koko katu tiesi sen tuoksusta."),
        w(.subject("paavo"), "ritva", "paavo mokki",
          "Dad built the cottage, the sauna and half the jetty, and he never drew a plan for any of them.",
          "Isä rakensi mökin, saunan ja puolet laiturista, eikä hän piirtänyt niistä yhdestäkään piirustuksia."),
        w(.subject("eino"), "kaarina", "eino",
          "Dad played the harmonica at every party, the same five songs, and nobody ever asked for a sixth.",
          "Isä soitti huuliharppua kaikissa juhlissa, samat viisi kappaletta, eikä kukaan koskaan pyytänyt kuudetta."),
        w(.subject("helvi"), "kaarina", "helvi viipuri",
          "Mum was born in Viipuri and spoke of the market square as if she had been there yesterday.",
          "Äiti syntyi Viipurissa ja puhui kauppatorista kuin olisi käynyt siellä eilen."),
        w(.subject("reino"), "matti", "reino tukholma",
          "Uncle Reino moved to Stockholm and sent a parcel every Christmas: coffee, chocolate and a letter nobody could read.",
          "Reino-setä muutti Tukholmaan ja lähetti joka joulu paketin: kahvia, suklaata ja kirjeen, josta kukaan ei saanut selvää."),
        w(.subject("onni"), "liisa", "onni",
          "Onni worked in the logging camps up north and came home twice a year with presents for everyone.",
          "Onni oli savotoilla pohjoisessa ja tuli kotiin kahdesti vuodessa lahjat kaikille mukanaan."),
        w(.subject("kerttu"), "kaarina", "kerttu viipuri",
          "Grandmother kept the key to the Viipuri house until she died. It opens nothing now.",
          "Mummo säilytti Viipurin talon avainta kuolemaansa asti. Nyt se ei avaa mitään."),
        w(.subject("heikki"), "kaarina", "heikki",
          "Heikki fixed every clock in the family except our own, which he said was haunted.",
          "Heikki korjasi suvun kaikki kellot paitsi meidän omamme, jossa hänen mukaansa kummitteli."),
        w(.subject("sirkka"), "elina", "sirkka koivula",
          "Sirkka is ninety-two and still knows the name of every cow Koivula ever had.",
          "Sirkka on yhdeksänkymmentäkaksi ja muistaa yhä jokaisen Koivulan lehmän nimen."),
        w(.subject("mauri"), "mikko", "mauri vaasa",
          "Uncle Mauri drove a taxi in Vaasa for thirty years and knew everybody's business.",
          "Mauri-eno ajoi taksia Vaasassa kolmekymmentä vuotta ja tiesi kaikkien asiat."),
        w(.subject("otto"), "mikko", "otto hanko",
          "Otto taught me to sail off Hanko, and he never raised his voice, even when I ran us aground.",
          "Otto opetti minut purjehtimaan Hangon edustalla, eikä hän korottanut ääntään silloinkaan, kun ajoin karille."),
        w(.subject("martta"), "sanni", "martta veikko",
          "Grandma Martta brought up my father on her own and never said a bad word about anybody.",
          "Martta-mummo kasvatti isäni yksin eikä sanonut kenestäkään pahaa sanaa."),
        w(.subject("yrjo"), "matti", "yrjo taipale winterwar toivo",
          "Yrjö fell at Taipale in the Winter War. Dad never talked about him, but he kept his letters.",
          "Yrjö kaatui Taipaleella talvisodassa. Isä ei koskaan puhunut hänestä, mutta säilytti hänen kirjeensä."),
        w(.subject("impi"), "sirkka", "impi savonlinna",
          "Aunt Impi had no children of her own, so she had all of us every summer in Savonlinna.",
          "Impi-tädillä ei ollut omia lapsia, joten hän otti meidät kaikki joka kesä luokseen Savonlinnaan.", voice: true),
        w(.subject("saima"), "liisa", "saima hellin anneli",
          "Saima was Mum's friend from school. Her mother Hellin was the teacher at the village school.",
          "Saima oli äidin koulukaveri. Hänen äitinsä Hellin oli kyläkoulun opettaja."),

        // About places.
        w(.subject("mokki"), "ritva", "mokki",
          "The cottage had no electricity until 1978. We read by the paraffin lamp and nobody minded.",
          "Mökillä ei ollut sähköjä ennen vuotta 1978. Luimme öljylampun valossa, eikä kukaan välittänyt."),
        w(.subject("mokki"), "elina", "mokki matti",
          "Every summer started on the cottage road, with the windows down and Dad counting the bends.",
          "Joka kesä alkoi mökkitiellä, ikkunat auki ja isä laskemassa mutkia."),
        w(.subject("koivula"), "sirkka", "koivula",
          "Koivula had twelve cows when I was a girl, and I knew each one by name.",
          "Koivulassa oli tyttönä ollessani kaksitoista lehmää, ja tunsin jokaisen nimeltä.", voice: true),
        w(.subject("koivula"), "matti", "koivula vaino",
          "I drove the tractor at Koivula when I was eleven. Grandfather pretended not to see.",
          "Ajoin Koivulassa traktoria yksitoistavuotiaana. Vaari teeskenteli, ettei nähnyt."),
        w(.subject("riihiniemi"), "sirkka", "riihiniemi vaino",
          "Riihiniemi is across the border now. Father said you could see Lake Ladoga from the hayloft.",
          "Riihiniemi on nyt rajan takana. Isä sanoi, että heinäladon parvelta näki Laatokalle."),
        w(.subject("viipuri"), "kaarina", "viipuri kerttu",
          "Grandmother's Viipuri was the round tower, the market and the smell of the harbour.",
          "Mummon Viipuri oli Pyöreä torni, tori ja sataman tuoksu."),
        w(.subject("tampere"), "liisa", "tampere",
          "We lived near Pyynikki, and every Sunday we walked up to the tower for doughnuts.",
          "Asuimme Pyynikin lähellä, ja joka sunnuntai kävelimme näkötornille munkeille."),
        w(.subject("tukholma"), "matti", "tukholma reino",
          "I visited Reino in Stockholm in 1971. He had a television, a car and a Swedish accent.",
          "Kävin Reinon luona Tukholmassa vuonna 1971. Hänellä oli televisio, auto ja ruotsalainen korostus."),
        w(.subject("hanko"), "mikko", "hanko",
          "Hanko was where the summers were longest. The sea was never warm, and we swam anyway.",
          "Hangossa kesät olivat pisimmät. Meri ei ollut koskaan lämmin, ja uimme silti."),
        w(.subject("makela"), "sirkka", "makela hilja",
          "Mother was born at the Mäkelä croft. Nobody knows any more where exactly it stood.",
          "Äiti syntyi Mäkelän torpalla. Kukaan ei enää tiedä, missä se tarkalleen oli."),
        w(.subject("rovaniemi"), "liisa", "rovaniemi onni",
          "Onni wrote from Rovaniemi that the sun did not set at all in June, and we did not believe him.",
          "Onni kirjoitti Rovaniemeltä, ettei aurinko laskenut kesäkuussa ollenkaan, emmekä uskoneet häntä."),
        w(.subject("savonlinna"), "ritva", "savonlinna",
          "The market in Savonlinna in July, with fried vendace and the castle behind it.",
          "Savonlinnan tori heinäkuussa, paistetut muikut ja linna taustalla."),

        // About events.
        w(.subject("wedding1918"), "sirkka", "vaino hilja",
          "They were married in the year of the civil war, and Mother said nobody danced.",
          "He menivät naimisiin sisällissodan vuonna, ja äiti sanoi, ettei kukaan tanssinut."),
        w(.subject("winterwar"), "matti", "toivo kannas",
          "Dad left for the Isthmus in December and came back in March, and he was never quite the same.",
          "Isä lähti Kannakselle joulukuussa ja palasi maaliskuussa, eikä hän ollut enää koskaan aivan entisensä."),
        w(.subject("evacuation"), "kaarina", "kerttu oiva",
          "They took a cow, the sewing machine and the Bible. Everything else stayed.",
          "He ottivat mukaan lehmän, ompelukoneen ja Raamatun. Kaikki muu jäi."),
        w(.subject("evacuation"), "kaarina", "helvi",
          "Mum walked for two weeks, and she was seventeen.",
          "Äiti käveli kaksi viikkoa, ja hän oli seitsemäntoista.", voice: true),
        w(.subject("olympics"), "matti", "toivo",
          "Dad kept the ticket stubs from the Olympics in his wallet next to his driving licence.",
          "Isä säilytti olympialaisten lippujen kannat lompakossaan ajokortin vieressä."),
        w(.subject("auction"), "sirkka", "vaino koivula",
          "At the auction a neighbour bought Father's plough for less than a sack of coffee.",
          "Huutokaupassa naapuri osti isän auran halvemmalla kuin säkillisen kahvia."),
        w(.subject("sweden"), "matti", "reino",
          "Reino left for Sweden with one suitcase and came back for every funeral.",
          "Reino lähti Ruotsiin yhden matkalaukun kanssa ja tuli takaisin jokaisiin hautajaisiin."),
        w(.subject("wedding1976"), "ritva", "matti",
          "It snowed on our wedding day, in June.",
          "Hääpäivänämme satoi lunta, kesäkuussa."),
        w(.subject("wedding1976"), "matti", "ritva",
          "The band knew one waltz, so we danced it five times.",
          "Orkesteri osasi yhden valssin, joten tanssimme sen viisi kertaa."),
        w(.subject("aune80"), "elina", "aune",
          "Grandmother Aune's eightieth. She made her own cake because she did not trust anybody else's.",
          "Aune-mummon kahdeksankymppiset. Hän leipoi kakkunsa itse, koska ei luottanut kenenkään muun kakkuun."),
        w(.subject("reunion"), "jukka", "sirkka",
          "Fifty-three people, and Sirkka knew who every one of them was.",
          "Viisikymmentäkolme ihmistä, ja Sirkka tiesi jokaisesta, kuka hän oli."),
        w(.subject("sold"), "liisa", "toivo koivula",
          "When Koivula was sold, Dad drove there one last time and sat in the car in the yard.",
          "Kun Koivula myytiin, isä ajoi sinne vielä kerran ja istui autossa pihalla."),
    ]

    // MARK: - Questions

    /// A question on a card. `asker` nil is the extraction's, with a level;
    /// otherwise a person key, and `to` the person key of the member it is
    /// aimed at, or nil for the whole family. `answer` is the id of the
    /// written telling that answered it.
    private struct Ask {
        let on: On
        let en: String
        let fi: String
        var level: Int? = nil
        var asker: String? = nil
        var to: String? = nil
        var answer: String? = nil
    }

    private static let asks: [Ask] = [
        Ask(on: .row(3), en: "Who is the smallest child in the picture?", fi: "Kuka on kuvan pienin lapsi?", level: 1),
        Ask(on: .row(9), en: "Where did they dance after the wedding?", fi: "Missä häiden jälkeen tanssittiin?", level: 2),
        Ask(on: .row(24), en: "What happened to the house at Koivula later?", fi: "Mitä Koivulan talolle myöhemmin tapahtui?", level: 3),
        Ask(on: .row(26), en: "What sort of person was Yrjö?", fi: "Millainen ihminen Yrjö oli?", level: 3),
        Ask(on: .row(31), en: "What was the farm in Karelia like?", fi: "Millainen tila Karjalassa oli?", level: 3),
        Ask(on: .row(45), en: "Which events did you see at the Olympics?", fi: "Mitä lajeja olympialaisissa nähtiin?", level: 1),
        Ask(on: .row(57), en: "What make was the first car?", fi: "Minkä merkkinen ensimmäinen auto oli?", level: 1, answer: "first-car"),
        Ask(on: .row(65), en: "Who built the cottage?", fi: "Kuka mökin rakensi?", level: 2, answer: "cottage-built"),
        Ask(on: .row(94), en: "What music did the band play at the wedding?", fi: "Mitä musiikkia häissä soitettiin?", level: 1),
        Ask(on: .subject("aapo"), en: "Where was Aapo born?", fi: "Missä Aapo syntyi?", level: 1),
        Ask(on: .subject("hilma"), en: "What else is remembered about Hilma?", fi: "Mitä muuta Hilmasta muistetaan?", level: 3),
        Ask(on: .subject("reino"), en: "Why did Reino move to Sweden?", fi: "Miksi Reino muutti Ruotsiin?", level: 3),
        Ask(on: .subject("riihiniemi"), en: "Is anything left of Riihiniemi today?", fi: "Onko Riihiniemestä jäljellä mitään?", level: 2),
        Ask(on: .subject("evacuation"), en: "Where did the family live the first winter after?", fi: "Missä perhe asui ensimmäisen talven?", level: 3),
        Ask(on: .row(113), en: "What was the teacher's name?", fi: "Mikä opettajan nimi oli?", level: 1, answer: "teacher"),
        Ask(on: .row(147), en: "Who organised the reunion?", fi: "Kuka sukukokouksen järjesti?", level: 1, answer: "reunion"),

        Ask(on: .row(89), en: "Grandpa, what was the army like in the seventies?", fi: "Vaari, millaista armeijassa oli 70-luvulla?",
            asker: "venla", to: "matti"),
        Ask(on: .row(65), en: "Mum, do you remember the first night at the cottage?", fi: "Äiti, muistatko ensimmäisen yön mökillä?",
            asker: "jukka", to: "ritva"),
        Ask(on: .row(16), en: "Does anyone know where Aapo's pocket watch went?", fi: "Tietääkö kukaan, minne Aapon taskukello joutui?",
            asker: "elina"),
        Ask(on: .row(113), en: "Elina, which school was this?", fi: "Elina, mikä koulu tämä oli?",
            asker: "liisa", to: "elina", answer: "school"),
        Ask(on: .row(41), en: "Who has the original of the wedding photo?", fi: "Kenellä on hääkuvan alkuperäinen?",
            asker: "liisa", answer: "original"),
        Ask(on: .subject("martta"), en: "Kaarina, did Martta ever talk about Veikko's father?", fi: "Kaarina, puhuiko Martta koskaan Veikon isästä?",
            asker: "sanni", to: "kaarina"),
        Ask(on: .row(115), en: "Matti, where did you drive the Volvo that summer?", fi: "Matti, minne ajoitte Volvolla sinä kesänä?",
            asker: "mikko", to: "matti"),
    ]

    // MARK: - Facts on person cards

    private struct Known {
        let person: String
        let kind: String
        var year: Int? = nil
        var told: Told = .year
        var place: String? = nil
        var en: String? = nil
        var fi: String? = nil
    }

    private static let known: [Known] = [
        Known(person: "aapo", kind: "birth", year: 1862),
        Known(person: "aapo", kind: "death", year: 1931),
        Known(person: "aapo", kind: "occupation", en: "Farmer", fi: "Maanviljelijä"),
        Known(person: "lyyli", kind: "birth", year: 1874),
        Known(person: "lyyli", kind: "death", year: 1950),
        Known(person: "vaino", kind: "birth", year: 1889, told: .day(3, 2), place: "riihiniemi"),
        Known(person: "vaino", kind: "death", year: 1965, place: "koivula"),
        Known(person: "vaino", kind: "occupation", en: "Farmer", fi: "Maanviljelijä"),
        Known(person: "hilja", kind: "birth", year: 1894, place: "makela"),
        Known(person: "hilja", kind: "other_name", en: "née Mäkelä", fi: "o.s. Mäkelä"),
        Known(person: "hilja", kind: "death", year: 1978),
        Known(person: "impi", kind: "death", year: 1970, place: "savonlinna"),
        Known(person: "kerttu", kind: "birth", year: 1902, place: "sortavala"),
        Known(person: "kerttu", kind: "residence", year: 1930, told: .decade, place: "viipuri"),
        Known(person: "kerttu", kind: "death", year: 1985, place: "lappeenranta"),
        Known(person: "eemeli", kind: "death", year: 1981, place: "savonlinna"),
        Known(person: "toivo", kind: "birth", year: 1920, told: .day(5, 14), place: "koivula"),
        Known(person: "toivo", kind: "occupation", en: "Machinist at Tampella", fi: "Koneistaja Tampellalla"),
        Known(person: "toivo", kind: "death", year: 1999, place: "tampere"),
        Known(person: "anneli", kind: "birth", year: 1926, place: "tampere"),
        Known(person: "anneli", kind: "occupation", en: "Teacher", fi: "Opettaja"),
        Known(person: "anneli", kind: "death", year: 2019),
        Known(person: "eino", kind: "birth", year: 1924, place: "koivula"),
        Known(person: "eino", kind: "death", year: 1994, place: "kuopio"),
        Known(person: "helvi", kind: "birth", year: 1927, place: "viipuri"),
        Known(person: "helvi", kind: "death", year: 2011, place: "kuopio"),
        Known(person: "aune", kind: "birth", year: 1927, place: "koivula"),
        Known(person: "aune", kind: "death", year: 2016, place: "savonlinna"),
        Known(person: "paavo", kind: "occupation", en: "Carpenter", fi: "Kirvesmies"),
        Known(person: "paavo", kind: "death", year: 2003, place: "savonlinna"),
        Known(person: "reino", kind: "birth", year: 1930, place: "koivula"),
        Known(person: "reino", kind: "residence", year: 1960, told: .decade, place: "tukholma"),
        Known(person: "reino", kind: "death", year: 1996, place: "tukholma"),
        Known(person: "sirkka", kind: "birth", year: 1934, told: .day(6, 3), place: "koivula"),
        Known(person: "sirkka", kind: "occupation", en: "Seamstress", fi: "Ompelija"),
        Known(person: "sirkka", kind: "residence", place: "savonlinna"),
        Known(person: "onni", kind: "occupation", en: "Lumberjack", fi: "Metsätyömies"),
        Known(person: "onni", kind: "death", year: 1990, place: "rovaniemi"),
        Known(person: "yrjo", kind: "birth", year: 1915),
        Known(person: "yrjo", kind: "death", year: 1940),
        Known(person: "yrjo", kind: "note", en: "Fell in the Winter War.", fi: "Kaatui talvisodassa."),
        Known(person: "matti", kind: "birth", year: 1950, told: .day(3, 12), place: "tampere"),
        Known(person: "matti", kind: "occupation", en: "Engineer", fi: "Insinööri"),
        Known(person: "ritva", kind: "birth", year: 1952, place: "savonlinna"),
        Known(person: "liisa", kind: "birth", year: 1953, place: "tampere"),
        Known(person: "heikki", kind: "death", year: 2020, place: "jyvaskyla"),
        Known(person: "mauri", kind: "occupation", en: "Taxi driver", fi: "Taksinkuljettaja"),
        Known(person: "mauri", kind: "death", year: 2015, place: "vaasa"),
        Known(person: "otto", kind: "death", year: 2012, place: "hanko"),
        Known(person: "elina", kind: "birth", year: 1978, told: .day(5, 4), place: "tampere"),
        Known(person: "jukka", kind: "birth", year: 1981, told: .month(9), place: "tampere"),
        Known(person: "venla", kind: "birth", year: 2006, told: .day(10, 1), place: "helsinki"),
    ]

    // MARK: - Who tells

    /// Everybody who tells: this phone's Elina, Sirkka through her phone, and
    /// the members with phones of their own.
    private static let tellers = ["elina", "sirkka", "matti", "ritva", "mikko", "jukka", "liisa", "kaarina", "sanni", "venla"]

    /// Whom each teller knows about, which decides who tells about a picture.
    private static let circles: [String: Set<String>] = [
        "sirkka": ["aapo", "lyyli", "hilma", "vaino", "hilja", "impi", "urho", "sulo", "toivo", "martta", "eino", "aune",
                   "reino", "sirkka", "eemeli", "selma", "kustaa", "alma", "hellin", "yrjo"],
        "matti": ["toivo", "anneli", "matti", "liisa", "vaino", "hilja", "ritva", "elina", "jukka", "lauri", "yrjo", "onni",
                  "reino", "ilmari", "aapo"],
        "liisa": ["toivo", "anneli", "matti", "liisa", "vaino", "hilja", "martta", "onni", "ilmari", "saima"],
        "ritva": ["aune", "paavo", "ritva", "matti", "elina", "jukka", "tyyne", "sirkka", "eemeli", "kerttu", "oiva"],
        "kaarina": ["eino", "helvi", "kaarina", "heikki", "aleksi", "kerttu", "oiva", "noora", "iiris", "lyyli", "paavo"],
        "sanni": ["martta", "veikko", "tuula", "sanni"],
        "mikko": ["mikko", "sisko", "mauri", "tarja", "onerva", "otto", "helmi", "rauha", "venla", "oskari", "aino"],
        "jukka": ["jukka", "petra", "elias", "matti", "ritva", "elina"],
        "venla": ["venla", "oskari", "aino", "elina", "mikko"],
        "elina": ["elina", "mikko", "venla", "oskari", "aino", "jukka", "matti", "ritva", "aune", "paavo", "sirkka", "jonne"],
    ]

    /// Places a teller has a reason to talk about.
    private static let haunts: [String: Set<String>] = [
        "ritva": ["mokki", "puumala", "savonlinna"],
        "matti": ["koivula", "tampere"],
        "kaarina": ["kuopio", "viipuri", "jyvaskyla"],
        "mikko": ["joensuu", "vaasa", "hanko"],
        "sanni": ["lahti"],
    ]

    /// The years a teller remembers best.
    private static func eraBonus(_ teller: String, _ year: Int) -> Double {
        switch teller {
        case "sirkka": year <= 1960 ? 2 : 0
        case "elina": year >= 1978 ? 2 : 0
        case "venla": year >= 2005 ? 2 : 0
        case "matti": (1945 ... 1990).contains(year) ? 1 : 0
        default: 0
        }
    }

    /// The same numbers on every launch, so that the same telling lands on
    /// the same photograph under the same name every time.
    private struct Dice {
        var state: UInt64
        init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
        mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
    }

    // MARK: - Dates

    /// Midnight in Helsinki, on the archive's own calendar, as every date in
    /// the archive is built (`DateHint.calendar`).
    private static func date(_ year: Int, _ month: Int = 1, _ day: Int = 1) -> Date {
        DateHint.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// A date as the app stores it, no sharper than it was told (rule 5).
    private static func hint(_ told: Told, _ year: Int) -> DateHint? {
        switch told {
        case let .day(month, day):
            let when = date(year, month, day)
            return DateHint(start: when, end: when, precision: .day)
        case let .month(month):
            let start = date(year, month)
            return DateHint(start: start, end: DateHint.calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start), precision: .month)
        case .year:
            return DateHint(start: date(year), end: date(year, 12, 31), precision: .year)
        case .about:
            // "Around 1955", as the years on either side at the precision of
            // a year: neither the date sheet nor the extraction has a word
            // for "about", and a span of years is how the extraction's
            // `start_year` and `end_year` are stored.
            return DateHint(start: date(year - 1), end: date(year + 1), precision: .year)
        case .decade:
            let decade = year / 10 * 10
            return DateHint(start: date(decade), end: date(decade + 9, 12, 31), precision: .decade)
        case .unknown:
            return DateHint(start: nil, end: nil, precision: .unknown)
        case .never:
            return nil
        case let .span(last):
            return DateHint(start: date(year), end: date(last, 12, 31), precision: .year)
        }
    }

    /// How the first telling of a picture says a date it is not sure of.
    private static func datePhrase(_ told: Told, _ year: Int) -> (en: String, fi: String)? {
        switch told {
        case .about: ("It must have been around \(year).", "Sen täytyi olla joskus vuoden \(year) tienoilla.")
        case .decade: ("Sometime in the \(year / 10 * 10)s, I think.", "Joskus \(year / 10 * 10)-luvulla, luulisin.")
        case .unknown: ("I do not know what year it was.", "En tiedä, minä vuonna tämä oli.")
        default: nil
        }
    }

    // MARK: - The archive

    private static func photoID(_ row: Int) -> String { "large-photo-" + String(format: "%03d", row) }
    private static func photoFile(_ row: Int) -> String { "photo-large1-" + String(format: "%03d", row) + ".jpg" }
    private static func colourFile(_ row: Int) -> String { "media-large1-colour-" + String(format: "%03d", row) + ".jpg" }

    private static func picture(_ number: Int) -> LargeArchivePictures.Print {
        let row = rows[number - 1]
        return LargeArchivePictures.Print(
            number: number, year: row.year, scene: row.scene,
            sitters: row.cast.map { key in
                let life = lives[key] ?? (born: row.year - 30, died: nil, female: false)
                return LargeArchivePictures.Sitter(age: max(0, row.year - life.born), female: life.female)
            }
        )
    }

    /// One telling on its way into the archive.
    private struct Draft {
        var id: String?
        var subjectID: String
        var teller: String
        var body: String
        var mentions: [String]
        var createdAt: Date
        var voice: Bool
        /// Its moment was given rather than drawn.
        var fixed = false
        /// Written by hand and answering a question: said after the tellings
        /// that raised it.
        var answers = false
        var generated = false
        /// The teller asked not to be named.
        var hidden = false
    }

    private static func onRow(_ item: Written, _ number: Int) -> Bool {
        if case let .row(n) = item.on { return n == number }
        return false
    }

    static func archive(me: String, now: Date = .now) -> Archive {
        let finnish = inFinnish
        func say(_ en: String, _ fi: String) -> String { finnish ? fi : en }
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        // The tellers' phones.
        func joined(_ teller: String) -> Double {
            phones.first { $0.card == teller }?.joined ?? myJoined
        }
        func author(_ teller: String) -> (id: String, name: String) {
            guard let phone = phones.first(where: { $0.card == teller }) else { return (me, myName) }
            return (phone.id, phone.name)
        }

        // People: the clan's cards in their own order, made over the first
        // months of the archive, with the heard ones added when named.
        let clan = ClanFixture.archive()
        var names: [String: String] = [:]
        for subject in clan.subjects {
            names[String(subject.id.dropFirst("clan-".count))] = subject.title
        }
        names["kaarina"] = "Kaarina"
        names["eeva"] = "Eeva"
        for (key, name) in heardPeople { names[key] = name }

        func key(_ id: String) -> String { String(id.dropFirst("clan-".count)) }
        let clanPeople = clan.subjects.filter { $0.id != personID("eeva") }
        let ordered = clanPeople.filter { !lastMade.contains(key($0.id)) }
            + lastMade.compactMap { made in clanPeople.first { key($0.id) == made } }
        var people: [String: Subject] = [:]
        var personOrder: [String] = []
        for (index, made) in ordered.enumerated() {
            var person = made
            person.createdAt = ago(535 - Double(index) * 2)
            people[key(person.id)] = person
            personOrder.append(key(person.id))
        }
        if var eeva = clan.subjects.first(where: { $0.id == personID("eeva") }) {
            eeva.confirmed = false
            eeva.createdAt = now
            people["eeva"] = eeva
            personOrder.append("eeva")
        }
        for (key, name) in heardPeople.sorted(by: { $0.key < $1.key }) {
            people[key] = Subject(id: personID(key), kind: .person, title: name, confirmed: false)
            personOrder.append(key)
        }

        // Places and events.
        var placeCards: [String: Subject] = [:]
        for (index, place) in places.enumerated() {
            var card = Subject(id: "large-place-" + place.key, kind: .place, title: say(place.en, place.fi))
            card.confirmed = !place.heard
            // A heard place is made by the telling that named it, below.
            card.createdAt = place.heard ? now : ago(530 - Double(index) * 3)
            if let point = place.point {
                var located = PlaceHint(latitude: point.0, longitude: point.1, precision: place.precision)
                if let by = place.placedBy {
                    let who = author(by)
                    located.confirmedByID = who.id
                    located.confirmedByName = who.name
                    located.confirmedAt = ago(400 - Double(index))
                }
                card.place = located
            }
            placeCards[place.key] = card
        }
        var eventCards: [String: Subject] = [:]
        for (index, event) in events.enumerated() {
            var card = Subject(id: "large-event-" + event.key, kind: .event, title: say(event.en, event.fi))
            card.dateHint = hint(event.told, event.year)
            card.createdAt = ago(500 - Double(index) * 5)
            eventCards[event.key] = card
        }
        func subjectID(_ key: String) -> String {
            if let place = placeCards[key] { return place.id }
            if let event = eventCards[key] { return event.id }
            return personID(key)
        }
        func created(_ key: String) -> Date {
            placeCards[key]?.createdAt ?? eventCards[key]?.createdAt ?? people[key]?.createdAt ?? ago(500)
        }

        // Photographs, scanned a decade's album at a time.
        var photos: [Subject] = []
        for (index, row) in rows.enumerated() {
            let number = index + 1
            let batch: Double = switch row.year {
            case ..<1940: 520
            case ..<1950: 470
            case ..<1960: 430
            case ..<1970: 380
            case ..<1980: 330
            case ..<1990: 260
            case ..<2000: 190
            default: 120
            }
            var photo = Subject(id: photoID(number), kind: .photo, title: row.en.map { say($0, row.fi ?? $0) } ?? "")
            photo.imageFilename = photoFile(number)
            photo.r2Key = photoID(number)
            photo.dateHint = hint(row.told, row.year)
            photo.createdAt = ago(batch).addingTimeInterval(Double(number) * 420)
            photos.append(photo)
        }

        // Tellings.
        var drafts: [Draft] = []
        var dice = Dice(1)
        var said: [String: Int] = [:]
        func moment(after start: Date, teller: String) -> Date {
            let earliest = max(start, ago(joined(teller))).addingTimeInterval(86_400)
            let latest = ago(6)
            guard earliest < latest else { return latest }
            return earliest.addingTimeInterval(dice.unit() * latest.timeIntervalSince(earliest))
        }
        func draft(_ written: Written, on subjectID: String, after start: Date) -> Draft {
            let fixed = written.daysAgo.map { ago($0) }
            return Draft(
                id: written.id, subjectID: subjectID, teller: written.teller, body: say(written.en, written.fi),
                mentions: written.mentions, createdAt: fixed ?? moment(after: start, teller: written.teller),
                voice: written.voice, fixed: fixed != nil,
                answers: written.id != nil && asks.contains { $0.answer == written.id }
            )
        }

        for (index, row) in rows.enumerated() {
            let number = index + 1
            let scanned = photos[index].createdAt
            var here = written.filter { onRow($0, number) }
                .map { draft($0, on: photoID(number), after: scanned) }

            // The people a line can name: confirmed, and as the scene casts them.
            let age: (String) -> Int = { row.year - (lives[$0]?.born ?? row.year) }
            let cast = row.cast.filter { heardPeople[$0] == nil && $0 != "eeva" }
            var slot: [String: String] = [:]
            switch row.scene {
            case .baby:
                slot["A"] = cast.first { age($0) <= 2 }
                slot["B"] = cast.first { age($0) > 2 }
            case .school:
                slot["A"] = cast.first { age($0) < 16 }
                slot["B"] = cast.first { age($0) >= 16 }
            default:
                slot["A"] = cast.first
                slot["B"] = cast.dropFirst().first
            }
            if row.scene == .wedding {
                slot["W"] = cast.prefix(2).first { lives[$0]?.female == true }
                slot["H"] = cast.prefix(2).first { lives[$0]?.female == false }
                slot["C"] = cast.dropFirst(2).first { lives[$0]?.female == true }
            } else if cast.count >= 3 {
                slot["C"] = cast.filter { $0 != slot["A"] && $0 != slot["B"] && age($0) < 14 }.min { age($0) < age($1) }
            }
            let confirmation = row.scene == .graduation && (row.cast.first.map { age($0) < 17 } ?? false)
            let offered = (confirmation ? confirmationLines : lines[row.scene] ?? []) + anyLines

            func fill(_ line: Line, by teller: String) -> (text: String, mentions: [String])? {
                guard row.year >= line.from, row.year <= line.to else { return nil }
                if line.witness, row.year - (lives[teller]?.born ?? row.year) < 5 { return nil }
                var text = finnish ? line.fi : line.en
                var mentions: [String] = []
                for name in ["A", "B", "C", "W", "H"] where text.contains("{\(name)}") {
                    guard let person = slot[name], person != teller else { return nil }
                    text = text.replacingOccurrences(of: "{\(name)}", with: names[person] ?? person)
                    if !mentions.contains(person) { mentions.append(person) }
                }
                if text.contains("{P}") {
                    guard let place = places.first(where: { $0.key == row.place }) else { return nil }
                    text = text.replacingOccurrences(of: "{P}", with: finnish ? place.inFi : place.inEn)
                    mentions.append(row.place)
                }
                return (text, mentions)
            }

            var told = Set(here.map(\.teller))
            var linesHere = Set<String>()
            while here.count < row.tellings {
                let ranked = tellers.filter { !told.contains($0) }.map { teller -> (String, Double) in
                    let circle = circles[teller] ?? []
                    var score = 3 * Double(row.cast.filter { circle.contains($0) }.count)
                    if haunts[teller]?.contains(row.place) == true { score += 2 }
                    score += eraBonus(teller, row.year)
                    var jitter = Dice(number &* 131 &+ (tellers.firstIndex(of: teller) ?? 0))
                    score += 1.5 * jitter.unit()
                    return (teller, score)
                }.sorted { $0.1 > $1.1 }
                var made: Draft?
                for (teller, _) in ranked {
                    let usable = offered.filter { !linesHere.contains($0.en) }.compactMap { line in
                        fill(line, by: teller).map { (line, $0) }
                    }
                    guard !usable.isEmpty else { continue }
                    let fewest = usable.map { said[$0.0.en, default: 0] }.min() ?? 0
                    let least = usable.filter { said[$0.0.en, default: 0] == fewest }
                    let (line, filled) = least[dice.int(least.count)]
                    said[line.en, default: 0] += 1
                    linesHere.insert(line.en)
                    var body = filled.text
                    if dice.unit() < 0.4 {
                        let when = era(row.year)
                        body += " " + say(when.en, when.fi)
                    }
                    made = Draft(
                        id: nil, subjectID: photoID(number), teller: teller, body: body, mentions: filled.mentions,
                        createdAt: moment(after: scanned, teller: teller),
                        voice: dice.unit() < (teller == "sirkka" ? 0.7 : 0.3), generated: true
                    )
                    break
                }
                guard let made else { break }
                here.append(made)
                told.insert(made.teller)
            }

            // Somebody said it first, and somebody answered last: the drawn
            // moments go to the generated tellings first, then to the
            // hand-written ones in the order they are listed, and to an
            // answer last — never before the teller's phone joined.
            let loose = here.indices.filter { !here[$0].fixed }
            let moments = loose.map { here[$0].createdAt }.sorted()
            let queue = loose.filter { here[$0].generated }
                + loose.filter { !here[$0].generated && !here[$0].answers }
                + loose.filter { here[$0].answers }
            for (slotIndex, draftIndex) in queue.enumerated() {
                let joinedAt = ago(joined(here[draftIndex].teller) - 1)
                here[draftIndex].createdAt = max(moments[slotIndex], joinedAt)
            }

            let byTime = here.indices.sorted { here[$0].createdAt < here[$1].createdAt }
            if number == hiddenTellerRow, let first = byTime.first { here[first].hidden = true }
            if let first = byTime.first, let event = eventOfRow[number] {
                here[first].mentions.append(event)
            }
            if let phrase = datePhrase(row.told, row.year),
               let first = byTime.first(where: { here[$0].generated }) {
                here[first].body += " " + say(phrase.en, phrase.fi)
            }
            drafts += here
        }

        for item in written {
            guard case let .subject(key) = item.on else { continue }
            drafts.append(draft(item, on: subjectID(key), after: created(key)))
        }

        // Into memories.
        var memories: [Memory] = []
        var counter = 0
        for item in drafts {
            counter += 1
            let who = author(item.teller)
            var memory = Memory(
                id: "large-memory-" + (item.id ?? String(format: "%03d", counter)),
                subjectID: item.subjectID, authorID: who.id, authorName: who.name, body: item.body,
                source: item.voice ? .voice : .typed
            )
            if item.voice {
                memory.rawTranscript = say("Well, um. ", "No tota. ") + item.body
            }
            memory.createdAt = item.createdAt
            memory.mentionedSubjectIDs = item.mentions.map(subjectID)
            if item.hidden {
                memory.tellerHidden = true
            } else if item.teller == "sirkka" {
                memory.tellerSubjectID = personID("sirkka")
            }
            memories.append(memory)

            // A name or a place nobody has confirmed is made by the telling
            // that first said it.
            for mention in item.mentions {
                if people[mention]?.confirmed == false, people[mention].map({ item.createdAt < $0.createdAt }) ?? false {
                    people[mention]?.createdAt = item.createdAt
                }
                if placeCards[mention]?.confirmed == false, placeCards[mention].map({ item.createdAt < $0.createdAt }) ?? false {
                    placeCards[mention]?.createdAt = item.createdAt
                }
            }
        }
        // A heard card starts at now, which the loop above only moves back.
        for key in people.keys where people[key]?.confirmed == false {
            if !memories.contains(where: { $0.mentionedSubjectIDs.contains(personID(key)) }) {
                people[key]?.createdAt = ago(300)
            }
        }
        for key in placeCards.keys where placeCards[key]?.confirmed == false {
            if !memories.contains(where: { $0.mentionedSubjectIDs.contains(subjectID(key)) }) {
                placeCards[key]?.createdAt = ago(300)
            }
        }

        // Questions.
        var questions: [FollowUpQuestion] = []
        for (index, ask) in asks.enumerated() {
            let onID: String
            switch ask.on {
            case let .row(number): onID = photoID(number)
            case let .subject(key): onID = subjectID(key)
            }
            let told = memories.filter { $0.subjectID == onID }.map(\.createdAt).sorted()
            let answer = ask.answer.flatMap { id in memories.first { $0.id == "large-memory-" + id } }
            var question = FollowUpQuestion(subjectID: onID, text: say(ask.en, ask.fi), storedLevel: ask.level)
            question.id = "large-question-" + String(index + 1)
            if let answer {
                question.answered = true
                question.answeredMemoryID = answer.id
                question.createdAt = answer.createdAt.addingTimeInterval(-2 * 86_400)
            } else if ask.asker == nil {
                question.createdAt = (told.first ?? ago(60)).addingTimeInterval(300)
            } else {
                let after = max(told.last ?? ago(60), ago(joined(ask.asker ?? "elina") - 1))
                question.createdAt = min(after.addingTimeInterval(86_400), ago(5)).addingTimeInterval(Double(index) * 60)
            }
            if let asker = ask.asker {
                let who = author(asker)
                question.authorID = who.id
                question.authorName = who.name
            }
            if let to = ask.to {
                let who = author(to)
                question.targetMemberID = who.id
                question.targetName = who.name
            }
            questions.append(question)
        }

        // Facts, faces and colourings.
        for (index, fact) in known.enumerated() {
            let entry = PersonFact(
                id: "large-fact-" + String(index + 1), kind: fact.kind,
                text: fact.en.map { say($0, fact.fi ?? $0) },
                date: fact.year.flatMap { hint(fact.told, $0) },
                placeSubjectID: fact.place.map(subjectID),
                updatedAt: ago(320 - Double(index) * 3)
            )
            let held = people[fact.person]?.facts ?? []
            people[fact.person]?.facts = held + [entry]
            people[fact.person]?.factsSetAt = entry.updatedAt
        }
        for (index, portrait) in portraits.enumerated() {
            guard let seat = rows[portrait.row - 1].cast.firstIndex(of: portrait.person),
                  let face = LargeArchivePictures.faces(of: picture(portrait.row))[seat]
            else { continue }
            people[portrait.person]?.portraitSubjectID = photoID(portrait.row)
            people[portrait.person]?.portraitFocusX = Double(face.x)
            people[portrait.person]?.portraitFocusY = Double(face.y)
            people[portrait.person]?.portraitSetAt = ago(250 - Double(index) * 4)
        }
        for (index, colouring) in colourings.enumerated() {
            let who = author(colouring.by)
            photos[colouring.row - 1].colourImageFilename = colourFile(colouring.row)
            photos[colouring.row - 1].colourR2Key = "large-colour-" + String(format: "%03d", colouring.row)
            photos[colouring.row - 1].colourConfirmedByID = who.id
            photos[colouring.row - 1].colourConfirmedByName = who.name
            photos[colouring.row - 1].colourConfirmedAt = ago(150 - Double(index) * 20)
        }

        // Relationships: the clan's, less the one entered twice and the one
        // entered backwards, and the friendships and the proposal the
        // tellings added.
        var relations: [Relation] = []
        var seen = Set<String>()
        for relation in clan.relations {
            let signature = "\(relation.fromSubjectID)>\(relation.toSubjectID)>\(relation.kind.rawValue)"
            guard seen.insert(signature).inserted,
                  !(relation.fromSubjectID == personID("onni") && relation.toSubjectID == personID("sulo"))
            else { continue }
            var copy = relation
            copy.id = "large-relation-" + String(relations.count + 1)
            copy.createdAt = ago(530 - Double(relations.count))
            if copy.deletedAt != nil { copy.deletedAt = ago(200) }
            relations.append(copy)
        }
        for (from, to) in [("toivo", "yrjo"), ("anneli", "saima"), ("matti", "lauri"), ("reino", "verneri")] {
            relations.append(Relation(
                id: "large-relation-" + String(relations.count + 1), fromSubjectID: personID(from),
                toSubjectID: personID(to), kind: .friendOf, confirmed: true, createdAt: ago(300 - Double(relations.count))
            ))
        }
        let heardAt = memories.filter { $0.body.contains("Hellin") }.map(\.createdAt).min() ?? ago(200)
        relations.append(Relation(
            id: "large-relation-" + String(relations.count + 1), fromSubjectID: personID("hellin"),
            toSubjectID: personID("saima"), kind: .parentOf, confirmed: false, createdAt: heardAt
        ))
        if let index = relations.firstIndex(where: { $0.toSubjectID == personID("eeva") }) {
            relations[index].createdAt = people["eeva"]?.createdAt ?? relations[index].createdAt
        }

        // The pictures, drawn once and kept.
        var jobs: [(file: String, number: Int, coloured: Bool)] = []
        for number in rows.indices.map({ $0 + 1 }) where !MediaStore.exists(photoFile(number)) {
            jobs.append((photoFile(number), number, false))
        }
        for colouring in colourings where !MediaStore.exists(colourFile(colouring.row)) {
            jobs.append((colourFile(colouring.row), colouring.row, true))
        }
        let tasks = jobs
        let prints = tasks.map { picture($0.number) }
        let started = Date()
        DispatchQueue.concurrentPerform(iterations: tasks.count) { index in
            autoreleasepool {
                guard let data = LargeArchivePictures.jpeg(of: prints[index], coloured: tasks[index].coloured) else { return }
                try? data.write(to: MediaStore.url(for: tasks[index].file), options: .atomic)
            }
        }

        let subjects = personOrder.compactMap { people[$0] }
            + places.compactMap { placeCards[$0.key] }
            + events.compactMap { eventCards[$0.key] }
            + photos
        return Archive(
            subjects: subjects,
            memories: memories,
            questions: questions,
            relations: relations,
            seen: memories.filter { $0.createdAt < ago(4) || $0.authorID == me }.map(\.id),
            drawn: jobs.count,
            drawing: Date().timeIntervalSince(started)
        )
    }
}
#endif
