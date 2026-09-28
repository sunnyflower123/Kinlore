import Foundation

/// The relationships a memory's text names that the teller never said.
///
/// The extraction model tidies a telling into the text the family reads. In a
/// take for the demo film on 28 Sep 2026, it tidied the teller's answer, spoken
/// by a synthetic voice, "Toivo did. He always had the camera." into "Toivo,
/// our dad, always had the camera." Neither the answer nor the question it
/// answered, "Who took this photograph?", names a relative: the model supplied
/// one, and the memory then stated it in the teller's voice. Rule 4 makes
/// a relationship the AI infers a proposal until somebody confirms it, and a
/// sentence of her memory is the one place where nobody is asked to confirm
/// anything. The prompt forbids this twice already, as an invented relative and
/// as archive text in the memory, and it happened anyway. So the rule is held
/// here, in code that does not depend on a model reading it: a text that names
/// a relationship the telling did not is replaced by the telling's own words.
///
/// **A relationship, not a word.** Each entry is one relationship in both
/// languages. Finnish inflects (*isän*, *isälle*, *äidin*), and the Finnish
/// prompt tells the model to turn *faija* into *isä*, so an entry holds stems
/// and spoken forms, and any of them said in the telling covers the rest. Both
/// languages share an entry because the prompt follows the app's language
/// rather than the speaker's, so a Finnish telling can come back in English.
///
/// **A wrong reading costs tidiness, never truth.** A word the table misreads
/// either hides an added relationship behind one that was said, which is where
/// things stood before this existed, or sends a text that added nothing back to
/// the telling's own words, which the app already stores whenever extraction
/// fails. Nothing here can put a word into a memory.
///
/// **What it cannot see.** A relationship that was said and then moved onto
/// somebody else ("my dad and Toivo" becoming "Toivo, my dad") passes, because
/// the word was said. So does a relationship written with a word that is not in
/// the table: *mies* is a husband and every other man, so it is left out.
enum RelationWords {
    /// An entry ending in `*` is a stem and matches every word that begins
    /// with it. Any other entry matches only itself, which is why most English
    /// words are whole: *son*, *mom* and *mum* begin *song*, *moment* and
    /// *mumble*.
    static let relations: [String: [String]] = [
        "father": ["father*", "dad", "dads", "daddy", "papa", "isä*", "isi*", "iskä*", "faija*", "fatsi*"],
        "mother": [
            "mother*", "mom", "moms", "mommy", "momma", "mum", "mums", "mummy", "mama", "mamma*",
            "äiti*", "äidi*", "äite*", "äide*", "äiskä*", "äippä*", "mutsi*",
        ],
        "grandfather": [
            "grandfather*", "grandpa", "grandpas", "grandad*", "granddad*", "grampa", "gramps",
            "isois*", "ukki*", "uki*", "vaari*", "pappa*", "papa*", "faari*",
        ],
        "grandmother": [
            "grandmother*", "grandma*", "granny", "grannies", "gran", "nana", "gramma",
            "isoäi*", "mummo*", "mummi*", "mumma*", "mummu*", "mumme*",
        ],
        "brother": ["brother*", "veli*", "velje*", "velji*"],
        "sister": ["sister*", "sisko*", "sisar*"],
        "son": ["son", "sons", "poika*", "poja*", "poiki*", "poji*"],
        "daughter": ["daughter*", "tytär*", "tyttär*"],
        "husband": ["husband*", "aviomie*"],
        "wife": ["wife*", "wives", "vaimo*"],
        "spouse": ["spouse*", "puoliso*"],
        "uncle": ["uncle*", "setä*", "sedä*", "eno*"],
        "aunt": ["aunt*", "täti*", "tädi*", "täte*", "täde*"],
        "cousin": ["cousin*", "serkk*", "serku*"],
        "grandson": ["grandson*"],
        "granddaughter": ["granddaughter*"],
        "grandchild": ["grandchild*", "grandkid*", "lapsenlap*", "lastenlap*"],
        "nephew": ["nephew*"],
        "niece": ["niece*"],
    ]

    /// Words that begin like a stem above and are no relative: the master of a
    /// house (*isäntä*, *isännät*), and *enough* and *enormous*.
    static let lookalikes = ["isänt", "isänn", "enou", "enor"]

    /// The relationships `text` names, by the English names above.
    static func named(in text: String) -> Set<String> {
        let words = Set(
            text.lowercased()
                .split { !$0.isLetter }
                .filter { word in !lookalikes.contains { word.hasPrefix($0) } }
        )
        return Set(relations.compactMap { relation, entries in
            let found = words.contains { word in
                entries.contains { $0.hasSuffix("*") ? word.hasPrefix($0.dropLast()) : word == $0 }
            }
            return found ? relation : nil
        })
    }

    /// The relationships `body` names that `said` does not.
    static func unsaid(in body: String, said: String) -> Set<String> {
        named(in: body).subtracting(named(in: said))
    }
}
