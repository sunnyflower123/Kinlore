#if DEBUG
import Foundation

/// `-seed clan`: a family too big for the screen, with every connection the
/// drawing has ever had trouble with in it.
///
/// The other seeds are archives of four or five people, which is the family an
/// hour after the app is installed. The tree is drawn for the family a year
/// later, and nothing in this repository has ever drawn one: five discs prove
/// the arithmetic runs, not that the picture can be read. Everything this
/// fixture is for only happens at size — a generation wider than the screen, a
/// name under a name, a line that crosses a stranger.
///
/// **What is deliberately hard in it**, each case put here because it is a
/// thing a real family archive does and not because it is exotic:
///
/// * A second marriage, and half-siblings from it (Aapo, Hilma, Lyyli).
/// * A sibship of six, which is wider than any phone.
/// * A childless couple (Impi and Urho), who must still be drawn as a couple.
/// * A child with one parent entered and no other (Sulo and Onni).
/// * Two cousins married to each other (Eino and Helvi), which makes the
///   family a ring rather than a tree.
/// * A marriage across generations (Eemeli and Sirkka): Eemeli is a brother of
///   somebody a generation above his wife. Breadth-first generations cannot
///   hold both, so the layout keeps the rows and drops the line — this is here
///   to make that visible rather than to hide it.
/// * Siblings nobody has entered parents for (Sisko, Mauri and Tarja), the
///   case that draws a bar of its own.
/// * A family sharing nobody with the rest (the same three, and Otto and
///   Helmi), which is what a family archive looks like when two sides of it
///   are entered before anybody joins them.
/// * A contradiction — Onni entered as both the child and the parent of Sulo —
///   and the same relationship entered twice.
/// * A person and a relationship nobody has confirmed, which rule 4 says must
///   not be drawn at all.
/// * People related to nobody yet, below everything.
/// * A name long enough to test what a name does to the place it is in.
///
/// Launch it with a card of your own to see the rail's words counted from
/// somebody in the middle:
///
///     -seed clan -you clan-elina -people tree
enum ClanFixture {
    /// Whose phone this is in the fixture, four generations down from the top.
    static let you = "clan-elina"

    static func archive() -> (subjects: [Subject], relations: [Relation]) {
        var subjects: [Subject] = []
        // Oldest card first is how the tree decides where to start (see
        // `FamilyTreeView.people`), so the order here is the order below.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func person(_ id: String, _ name: String, confirmed: Bool = true) {
            subjects.append(
                Subject(
                    id: "clan-" + id,
                    kind: .person,
                    title: name,
                    confirmed: confirmed,
                    createdAt: start.addingTimeInterval(Double(subjects.count))
                )
            )
        }

        // Generation by generation, oldest first.
        person("aapo", "Aapo")
        person("hilma", "Hilma")
        person("lyyli", "Lyyli")

        person("vaino", "Väinö")
        person("hilja", "Hilja")
        person("impi", "Impi")
        person("urho", "Urho")
        person("sulo", "Sulo")
        person("kerttu", "Kerttu")
        person("oiva", "Oiva")
        person("eemeli", "Eemeli")

        person("toivo", "Toivo")
        person("anneli", "Anneli")
        person("martta", "Martta")
        person("eino", "Eino")
        person("aune", "Aune")
        person("reino", "Reino")
        person("sirkka", "Sirkka")
        person("onni", "Onni")
        person("helvi", "Helvi")
        person("paavo", "Paavo")

        person("matti", "Matti")
        person("liisa", "Liisa")
        person("veikko", "Veikko")
        person("tuula", "Tuula")
        person("kaarina", "Kaarina-Liisa Vuorenmaa-Heikkilä")
        person("heikki", "Heikki")
        person("ritva", "Ritva")

        person("elina", "Elina")
        person("mikko", "Mikko")
        person("jukka", "Jukka")
        person("petra", "Petra")
        person("sanni", "Sanni")
        person("aleksi", "Aleksi")
        person("noora", "Noora")

        person("venla", "Venla")
        person("oskari", "Oskari")
        person("aino", "Aino")
        person("elias", "Elias")
        person("iiris", "Iiris")

        // The other side of the family, joined to the first by nobody.
        person("sisko", "Sisko")
        person("mauri", "Mauri")
        person("tarja", "Tarja")
        person("onerva", "Onerva")
        person("otto", "Otto")
        person("helmi", "Helmi")

        // Related to nobody yet: named while somebody talked, confirmed, and
        // never placed. Seven of them, so they fill a row of their own.
        person("kustaa", "Kustaa")
        person("alma", "Alma")
        person("yrjo", "Yrjö")
        person("saima", "Saima")
        person("lauri", "Lauri")
        person("hellin", "Hellin")
        person("verneri", "Verneri")

        // Proposed and not confirmed. Neither this card nor the line to it may
        // appear in the drawing (rule 4).
        person("epavarma", "Eeva", confirmed: false)

        var relations: [Relation] = []
        func link(_ from: String, _ to: String, _ kind: RelationKind, confirmed: Bool = true, deleted: Bool = false) {
            relations.append(
                Relation(
                    fromSubjectID: "clan-" + from,
                    toSubjectID: "clan-" + to,
                    kind: kind,
                    confirmed: confirmed,
                    createdAt: start.addingTimeInterval(Double(relations.count)),
                    deletedAt: deleted ? start : nil
                )
            )
        }
        func children(_ parents: [String], _ kids: [String]) {
            for parent in parents {
                for kid in kids { link(parent, kid, .parentOf) }
            }
        }

        link("aapo", "hilma", .spouseOf)
        // The second marriage. Aapo is in two couples; the row can only draw
        // him beside one of them.
        link("aapo", "lyyli", .spouseOf)
        children(["aapo", "hilma"], ["vaino", "impi", "sulo"])
        children(["aapo", "lyyli"], ["kerttu"])

        link("vaino", "hilja", .spouseOf)
        children(["vaino", "hilja"], ["toivo", "martta", "eino", "aune", "reino", "sirkka"])
        link("impi", "urho", .spouseOf)                       // no children
        children(["sulo"], ["onni"])                          // one parent only
        link("kerttu", "oiva", .spouseOf)
        children(["kerttu", "oiva"], ["helvi", "paavo"])
        link("oiva", "eemeli", .siblingOf)

        link("toivo", "anneli", .spouseOf)
        children(["toivo", "anneli"], ["matti", "liisa"])
        children(["martta"], ["veikko"])
        link("eino", "helvi", .spouseOf)                      // cousins
        children(["eino", "helvi"], ["kaarina"])
        link("aune", "paavo", .spouseOf)                      // cousins again
        children(["aune", "paavo"], ["ritva"])
        // A generation apart: Eemeli is a brother of Sirkka's parents-in-law's
        // generation, and married to her. The rows disagree and the line goes.
        link("eemeli", "sirkka", .spouseOf)
        // Entered twice, and then backwards. The first answer stands and the
        // second is dropped rather than turning the family upside down.
        children(["sulo"], ["onni"])
        link("onni", "sulo", .parentOf)

        link("matti", "ritva", .spouseOf)
        children(["matti", "ritva"], ["elina", "jukka"])
        link("veikko", "tuula", .spouseOf)
        children(["veikko", "tuula"], ["sanni"])
        link("kaarina", "heikki", .spouseOf)
        children(["kaarina", "heikki"], ["aleksi"])

        link("elina", "mikko", .spouseOf)
        children(["elina", "mikko"], ["venla", "oskari", "aino"])
        link("jukka", "petra", .spouseOf)
        children(["jukka", "petra"], ["elias"])
        link("aleksi", "noora", .spouseOf)
        children(["aleksi", "noora"], ["iiris"])

        // Three siblings and nobody's parents entered, and a child under one
        // of them: a family that is a family with no couple at the top of it.
        link("sisko", "mauri", .siblingOf)
        link("mauri", "tarja", .siblingOf)
        link("sisko", "tarja", .siblingOf)
        children(["sisko"], ["onerva"])
        link("otto", "helmi", .spouseOf)

        // Neither of these may be drawn: one is unconfirmed, the other was
        // taken back.
        link("matti", "epavarma", .parentOf, confirmed: false)
        link("liisa", "onerva", .spouseOf, deleted: true)

        return (subjects, relations)
    }
}
#endif
