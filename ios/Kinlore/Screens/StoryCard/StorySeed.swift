import Foundation

#if DEBUG
/// `-seed story`: the Finnish archive the story card's versions are
/// photographed on (phase A, 26 Sep 2026).
///
/// One photograph told about three times by three people — a decade the
/// tellers disagree on, a name nobody has confirmed, and a teller who never
/// saw the place — is the smallest archive that exercises every rule the
/// story has: a gap that stays a gap, a contradiction shown and not settled,
/// and a proposal that never becomes fact (rule 4). Beside it a person with
/// two tellings, a photograph with one, and a person who is only mentioned,
/// so the same view can be seen with a story, with a short one, and with
/// none.
///
/// The tellings are the ones `scripts/story-bench.mjs` measured the prompt
/// on, word for word: the stories on the jetty and the kitchen were produced
/// from exactly this text (26 Sep 2026, `google/gemini-3.6-flash`, the first
/// run's texts — see the note on each), and a card whose log and story
/// disagree would be photographing a lie. Written in the register the
/// extraction leaves behind — fillers gone, the spoken forms kept.
///
/// Phase B (ARCHITECTURE §27) gave the seed the three states of a story.
/// The jetty's is composed and current: its `composedFrom` names its three
/// tellings, so the card asks for nothing. The kitchen's was corrected by
/// hand after its first telling, and a second telling came after — so the
/// card holds a proposal under the story and asks for nothing either. Aino
/// has two tellings and no story, and the card composes one on appearance,
/// which under `-story stub` is the stub's sentence per telling. Kuopio has
/// nothing told and no story.
///
/// Since 28 Sep 2026 the story is the top of the one card (§27), so the
/// seed has a story on each kind of card: Toivo's and Puumala's were
/// composed by `scripts/story-bench.mjs` from exactly the tellings below,
/// on the shipped prompt. The caption's place line has a card in each of
/// its states: the jetty names Puumala, which has a point; the sauna names
/// Mäkelä, which is confirmed and has none; Aino's tellings name only
/// Kotasaari, which nobody has confirmed; and Eevertti's card, with nothing
/// told on it, and Puumala's own card have no line.
///
/// The third telling on the jetty has no author id, which the card reads as
/// this phone's own: it is how the log's own-memory actions (edit, move,
/// delete) get into a screenshot without a server to be somebody on.
///
/// Two more cards hold the state the plan does not answer by itself: a
/// telling taken back from under a story a person corrected. The sauna's
/// story was made of two tellings and Pekka's is gone, one still told; the
/// porch's was made of one and it is gone. The card says so and asks
/// (`StoryTakenBack`), and the taken-back tellings are in the seed with
/// `deletedAt` set, the way a deletion arrives from another phone.
extension MemoryStore {
    struct StorySeed {
        var subjects: [Subject]
        var memories: [Memory]
        var questions: [FollowUpQuestion]
    }

    /// The images are passed in rather than fetched here, because the film's
    /// photographs are read by a private helper in `MemoryStore.swift` and
    /// this file has no business making it less private.
    static func storySeed(
        jettyImage: String?, kitchenImage: String?, saunaImage: String?, porchImage: String?
    ) -> StorySeed {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DateHint.zone
        let fifties = DateHint(
            start: calendar.date(from: DateComponents(year: 1950, month: 1, day: 1)),
            end: nil,
            precision: .decade
        )

        var jetty = Subject(
            id: "demo-story-jetty", kind: .photo, title: "Mökin laituri",
            imageFilename: jettyImage, dateHint: fifties,
            createdAt: Date(timeIntervalSince1970: 1_749_800_000)
        )
        // The prompt's own text for the three tellings below, produced
        // before rules 2 and 5 of the prompt were amended the same morning:
        // it says *sillä* twice where its tellers only put two sentences
        // side by side. The second run, with the amended rules, kept the
        // register and still wrote both — so the causal-word rule is not
        // yet one the model follows, and the text stays as the six layouts
        // were photographed with it.
        jetty.story = Story(
            text: """
            Mummo kertoo, että kuvassa ollaan mökin rannassa Puumalassa. Aino oli Mummon vieressä ja Toivo otti kuvan, sillä Toivo oli aina se, joka otti kuvat. Mummo muistaa, että se oli joskus 50-luvulla, eikä muista tarkkaan. Mummon mukaan siellä oli aina niin hiljaista iltaisin. Aino taas muistaa, että kuva on otettu kesällä 1961, sinä kesänä kun Toivo sai uuden veneen. Aino on se pienempi tyttö laiturin päässä. Kahvipannu oli mukana niin kuin aina, ja rannassa istuttiin pitkään.

            Pekka kertoo Mummon kertoneen tästä laiturista aina, kun mentiin Puumalaan. Pekan mukaan Mummo sanoi, että laiturin lankut oli Eevertti tehnyt ja että ne narisivat joka askeleella. Pekka ei ole koskaan itse nähnyt sitä mökkiä, sillä se myytiin ennen kuin hän syntyi.
            """,
            composedFrom: ["demo-story-jetty-1", "demo-story-jetty-2", "demo-story-jetty-3"],
            composedAt: Date(timeIntervalSince1970: 1_789_900_000)
        )
        jetty.storySetAt = Date(timeIntervalSince1970: 1_789_900_000)
        var kitchen = Subject(
            id: "demo-story-kitchen", kind: .photo, title: "Keittiö Kuopiossa",
            imageFilename: kitchenImage,
            createdAt: Date(timeIntervalSince1970: 1_757_000_000)
        )
        // The prompt's text for the first telling, with *"ne oli"* tidied
        // into *"ne olivat"* by the first run, then corrected by hand: the
        // story a person read and saved. The proposal under it is what the
        // stub composer writes for the second telling — the model was not
        // run for it, and the seed says so rather than carrying a sentence
        // the prompt never produced.
        kitchen.story = Story(
            text: """
            Mummo kertoo, että heillä oli semmoinen puutalo Kuopiossa. Siinä oli iso keittiö ja siellä he aina istuivat. Naapurin isäntä tuli joka päivä käymään. Mummon mukaan ne oli hyviä aikoja.
            """,
            composedFrom: ["demo-story-kitchen-1"],
            composedAt: Date(timeIntervalSince1970: 1_757_100_000),
            editedAt: Date(timeIntervalSince1970: 1_757_200_000),
            proposal: StoryProposal(
                text: "Pekka kertoo, että siinä keittiössä oli iso puuhella, ja Mummo paistoi siinä lettuja joka sunnuntai.",
                from: ["demo-story-kitchen-2"],
                at: Date(timeIntervalSince1970: 1_790_200_000)
            )
        )
        kitchen.storySetAt = Date(timeIntervalSince1970: 1_790_200_000)
        var sauna = Subject(
            id: "demo-story-sauna", kind: .photo, title: "Rantasauna",
            imageFilename: saunaImage,
            createdAt: Date(timeIntervalSince1970: 1_758_500_000)
        )
        // The stub's two sentences, corrected by hand; then Pekka's telling
        // was taken back. The story still carries his words, which is the
        // point: nothing rewrites a person's story, and the card says what
        // is gone and asks.
        sauna.story = Story(
            text: """
            Mummo kertoo, että Mäkelän rantasauna lämmitettiin joka lauantai ja Toivo kantoi vedet järvestä. Pekan mukaan saunan ovi narisi niin, että sen kuuli laiturille asti.
            """,
            composedFrom: ["demo-story-sauna-1", "demo-story-sauna-2"],
            composedAt: Date(timeIntervalSince1970: 1_790_300_000),
            editedAt: Date(timeIntervalSince1970: 1_790_310_000)
        )
        sauna.storySetAt = Date(timeIntervalSince1970: 1_790_310_000)
        var porch = Subject(
            id: "demo-story-porch", kind: .photo, title: "Kuisti",
            imageFilename: porchImage,
            createdAt: Date(timeIntervalSince1970: 1_758_600_000)
        )
        // One telling, corrected by hand into a story, and then taken back:
        // there is nothing left to compose from, and the offer is to delete.
        porch.story = Story(
            text: "Mummo kertoo, että kuistilla juotiin kahvit joka ilta, kun oli lämmin.",
            composedFrom: ["demo-story-porch-1"],
            composedAt: Date(timeIntervalSince1970: 1_790_400_000),
            editedAt: Date(timeIntervalSince1970: 1_790_410_000)
        )
        porch.storySetAt = Date(timeIntervalSince1970: 1_790_410_000)
        let aino = Subject(id: "demo-story-aino", kind: .person, title: "Aino")
        var toivo = Subject(id: "demo-story-toivo", kind: .person, title: "Toivo")
        // The prompt's text for Toivo's two tellings, 28 Sep 2026, as it
        // came: one paragraph for two tellers, and Aino's *"meidät lapset"*
        // became *"lapset"*.
        toivo.story = Story(
            text: """
            Mummo kertoo, että Toivo oli hänen isoveljensä. Hänellä oli semmoinen vanha kamera, jonka hän oli saanut isältä, ja sillä hän kuvasi kaiken, mitä mökillä tehtiin. Puumalassa hän kalasti joka aamu ennen kuin muut heräsivät. Aino kertoo, että Toivo-eno vei lapset veneellä Puumalan selälle, ja hän lauloi soutaessaan aina samaa laulua. Laulun nimeä Aino ei muista.
            """,
            composedFrom: ["demo-story-toivo-1", "demo-story-toivo-2"],
            composedAt: Date(timeIntervalSince1970: 1_789_910_000)
        )
        toivo.storySetAt = Date(timeIntervalSince1970: 1_789_910_000)
        let eevertti = Subject(id: "demo-story-eevertti", kind: .person, title: "Eevertti", confirmed: false)
        var puumala = Subject(
            id: "demo-story-puumala", kind: .place, title: "Puumala",
            place: PlaceHint(latitude: 61.5236, longitude: 28.1806, precision: .town)
        )
        // The prompt's text for Puumala's two tellings, 28 Sep 2026.
        puumala.story = Story(
            text: """
            Mummo kertoo, että Puumalassa heillä oli se mökki järven rannassa. Sinne mentiin linja-autolla, ja viimeinen pätkä käveltiin metsätietä pitkin. Mökki myytiin sitten, kun isä kuoli.

            Pekka kertoo, että kävi Puumalassa kerran aikuisena ja yritti etsiä sen mökin, mutta ei löytänyt oikeaa rantaa.
            """,
            composedFrom: ["demo-story-puumala-1", "demo-story-puumala-2"],
            composedAt: Date(timeIntervalSince1970: 1_790_010_000)
        )
        puumala.storySetAt = Date(timeIntervalSince1970: 1_790_010_000)
        let kuopio = Subject(
            id: "demo-story-kuopio", kind: .place, title: "Kuopio",
            place: PlaceHint(latitude: 62.8924, longitude: 27.6770, precision: .town)
        )
        // A farm the gazetteer does not know: confirmed, and nowhere to be
        // drawn until somebody puts it on the map.
        let makela = Subject(id: "demo-story-makela", kind: .place, title: "Mäkelä")
        // A place heard in a telling and confirmed by nobody: never a point.
        let kotasaari = Subject(id: "demo-story-kotasaari", kind: .place, title: "Kotasaari", confirmed: false)

        let memories = [
            Memory(
                id: "demo-story-jetty-1", subjectID: jetty.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Siinä kuvassa ollaan sen mökin rannassa, se oli Puumalassa se mökki. "
                    + "Aino oli siinä minun vieressäni ja Toivo otti sen kuvan, se oli aina se "
                    + "joka otti kuvat. Se oli joskus 50-luvulla, en minä nyt muista tarkkaan. "
                    + "Siellä oli aina niin hiljaista iltaisin.",
                audioR2Key: "demo-audio-that-is-not-there", audioDuration: 42,
                source: .voice,
                createdAt: Date(timeIntervalSince1970: 1_749_891_600),
                mentionedSubjectIDs: [aino.id, toivo.id, puumala.id]
            ),
            Memory(
                id: "demo-story-jetty-2", subjectID: jetty.id,
                authorID: "demo-aino", authorName: "Aino",
                body: "Tämä on otettu kesällä 1961, sinä kesänä kun Toivo sai uuden veneen. "
                    + "Minä olen se pienempi tyttö laiturin päässä. Kahvipannu oli mukana niin "
                    + "kuin aina, ja rannassa istuttiin pitkään.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_754_125_200),
                mentionedSubjectIDs: [toivo.id]
            ),
            Memory(
                id: "demo-story-jetty-3", subjectID: jetty.id,
                authorID: nil, authorName: "Pekka",
                body: "Mummo kertoi tästä laiturista aina, kun mentiin Puumalaan. Hän sanoi, "
                    + "että laiturin lankut oli Eevertti tehnyt ja että ne narisivat joka "
                    + "askeleella. Minä en ole koskaan itse nähnyt sitä mökkiä, se myytiin "
                    + "ennen kuin synnyin.",
                audioR2Key: "demo-audio-that-is-not-there", audioDuration: 118,
                source: .voice,
                createdAt: Date(timeIntervalSince1970: 1_789_894_800),
                mentionedSubjectIDs: [puumala.id, eevertti.id]
            ),
            Memory(
                id: "demo-story-aino-1", subjectID: aino.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Aino oli minun siskoni lapsi, ja hän tuli mökille joka kesä. Ainon kanssa "
                    + "soudettiin Kotasaareen kalaan aamuvarhaisella. Aino oli aina se rohkein "
                    + "meistä, se meni ensimmäisenä uimaan vaikka vesi oli kylmää.",
                audioR2Key: "demo-audio-that-is-not-there", audioDuration: 65,
                source: .voice,
                createdAt: Date(timeIntervalSince1970: 1_753_002_000),
                mentionedSubjectIDs: [kotasaari.id]
            ),
            Memory(
                id: "demo-story-aino-2", subjectID: aino.id,
                authorID: "demo-pekka", authorName: "Pekka",
                body: "Aino-täti opetti minut soutamaan sinä kesänä kun olin kahdeksan. Hän "
                    + "sanoi, että airot pidetään vedessä eikä ilmassa. En muista, mikä vuosi "
                    + "se oli.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_790_067_600)
            ),
            Memory(
                id: "demo-story-kitchen-1", subjectID: kitchen.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Meillä oli semmoinen puutalo Kuopiossa, siinä oli iso keittiö ja siellä "
                    + "me aina istuttiin. Naapurin isäntä tuli joka päivä käymään. Ne oli hyviä "
                    + "aikoja.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_757_062_800),
                mentionedSubjectIDs: [kuopio.id]
            ),
            Memory(
                id: "demo-story-kitchen-2", subjectID: kitchen.id,
                authorID: "demo-pekka", authorName: "Pekka",
                body: "Siinä keittiössä oli iso puuhella, ja Mummo paistoi siinä lettuja joka sunnuntai.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_790_150_000)
            ),
            Memory(
                id: "demo-story-sauna-1", subjectID: sauna.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Mäkelän rantasauna lämmitettiin joka lauantai, ja Toivo kantoi vedet järvestä.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_790_280_000),
                mentionedSubjectIDs: [toivo.id, makela.id]
            ),
            Memory(
                id: "demo-story-sauna-2", subjectID: sauna.id,
                authorID: "demo-pekka", authorName: "Pekka",
                body: "Saunan ovi narisi niin, että sen kuuli laiturille asti.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_790_290_000),
                deletedAt: Date(timeIntervalSince1970: 1_790_320_000)
            ),
            Memory(
                id: "demo-story-porch-1", subjectID: porch.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Kuistilla juotiin kahvit joka ilta, kun oli lämmin.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_790_390_000),
                deletedAt: Date(timeIntervalSince1970: 1_790_420_000)
            ),
            Memory(
                id: "demo-story-toivo-1", subjectID: toivo.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Toivo oli minun isoveljeni. Hänellä oli semmoinen vanha kamera, jonka hän "
                    + "oli saanut isältä, ja sillä hän kuvasi kaiken, mitä mökillä tehtiin. "
                    + "Puumalassa hän kalasti joka aamu ennen kuin muut heräsivät.",
                audioR2Key: "demo-audio-that-is-not-there", audioDuration: 51,
                source: .voice,
                createdAt: Date(timeIntervalSince1970: 1_752_397_200),
                mentionedSubjectIDs: [puumala.id]
            ),
            Memory(
                id: "demo-story-toivo-2", subjectID: toivo.id,
                authorID: "demo-aino", authorName: "Aino",
                body: "Toivo-eno vei meidät lapset veneellä Puumalan selälle, ja hän lauloi "
                    + "soutaessaan aina samaa laulua. Laulun nimeä en muista.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_754_816_400),
                mentionedSubjectIDs: [puumala.id]
            ),
            Memory(
                id: "demo-story-puumala-1", subjectID: puumala.id,
                authorID: "demo-mummo", authorName: "Mummo",
                body: "Puumalassa meillä oli se mökki järven rannassa. Sinne mentiin "
                    + "linja-autolla, ja viimeinen pätkä käveltiin metsätietä pitkin. Mökki "
                    + "myytiin sitten, kun isä kuoli.",
                audioR2Key: "demo-audio-that-is-not-there", audioDuration: 38,
                source: .voice,
                createdAt: Date(timeIntervalSince1970: 1_750_496_400)
            ),
            Memory(
                id: "demo-story-puumala-2", subjectID: puumala.id,
                authorID: "demo-pekka", authorName: "Pekka",
                body: "Kävin Puumalassa kerran aikuisena ja yritin etsiä sen mökin, mutta en "
                    + "löytänyt oikeaa rantaa.",
                source: .typed,
                createdAt: Date(timeIntervalSince1970: 1_790_002_800)
            ),
        ]

        let questions = [
            FollowUpQuestion(
                id: "demo-story-question-1", subjectID: jetty.id,
                text: "Kuka muu oli laiturilla sinä päivänä?",
                createdAt: Date(timeIntervalSince1970: 1_790_326_800),
                authorID: "demo-pekka", authorName: "Pekka"
            ),
        ]

        UserDefaults.standard.set(memories.map(\.id), forKey: NewFromFamily.seenKey)
        return StorySeed(
            subjects: [jetty, kitchen, sauna, porch, aino, toivo, eevertti, puumala, kuopio, makela, kotasaari],
            memories: memories,
            questions: questions
        )
    }
}
#endif
