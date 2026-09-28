// Checks that a memory's text never names a relationship the teller did not.
//
// In a take for the demo film on 28 Sep 2026, the teller, a synthetic voice,
// answered "Who took this photograph?" with "Toivo did. He always had the
// camera.", and the memory the app saved read "Toivo, our dad, always had the
// camera." The prompt forbids exactly that, and nothing checked it: the
// extraction's text went into the archive as the model wrote it.
// `RemoteExtractionService.extract` now keeps her own words instead whenever
// the text names a relationship her telling did not, and `RelationWords`
// decides that. This holds the deciding.
//
// Every way of being wrong is silent. A relationship the table misses reads
// like her own sentence, on a card nobody is asked to confirm; a word the
// table misreads as a relative sends a good text back to the untidied
// transcript, and a transcript looks like a memory too. No build fails and no
// screenshot shows the difference.
//
// Costs nothing: no Worker, no key, no network, no model. Run it after
// touching RelationWords.swift.
//
//   swiftc -parse-as-library -o /tmp/relation-words-check \
//     scripts/relation-words-check.swift ios/Kinlore/Services/RelationWords.swift

import Foundation

@main
enum RelationWordsCheck {
    static func main() {
        var failures = 0

        func check(_ label: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            }
        }

        func unsaid(_ body: String, said: String) -> [String] {
            RelationWords.unsaid(in: body, said: said).sorted()
        }

        print("— the telling this was written for —")
        let answer = "Toivo did. He always had the camera."
        check("\"our dad\" in the text of an answer that never said it is caught",
              unsaid("Toivo, our dad, always had the camera.", said: answer) == ["father"],
              "\(unsaid("Toivo, our dad, always had the camera.", said: answer))")
        check("and the same text passes when she said it herself",
              unsaid("Toivo, our dad, always had the camera.",
                     said: "Our dad did. Toivo always had the camera.").isEmpty)
        check("the text the model should have written passes",
              unsaid("Toivo did. He always had the camera.", said: answer).isEmpty)
        check("and the same in Finnish",
              unsaid("Toivo, meidän isä, otti aina kuvat.",
                     said: "Toivo otti. Hänellä oli aina kamera.") == ["father"])

        print("— every relationship, added to a text that named none —")
        let added: [(String, String)] = [
            ("isälle", "father"), ("isiensä", "father"), ("äidin", "mother"), ("äideille", "mother"),
            ("isoisän", "grandfather"), ("papalle", "grandfather"), ("ukin", "grandfather"),
            ("vaarin", "grandfather"), ("isoäidille", "grandmother"), ("mummolle", "grandmother"),
            ("mummin", "grandmother"), ("veljensä", "brother"), ("veljiä", "brother"),
            ("siskolle", "sister"), ("sisarensa", "sister"), ("pojalle", "son"), ("poikia", "son"),
            ("pojille", "son"), ("tyttärensä", "daughter"), ("aviomiehensä", "husband"),
            ("vaimolleen", "wife"), ("puolisonsa", "spouse"), ("sedälle", "uncle"),
            ("enolle", "uncle"), ("tädin", "aunt"), ("tätejä", "aunt"), ("serkun", "cousin"),
            ("serkkuja", "cousin"), ("lapsenlapsille", "grandchild"),
            ("dad's", "father"), ("fathers", "father"), ("mum", "mother"), ("mother", "mother"),
            ("grandad", "grandfather"), ("grandpa", "grandfather"), ("granny", "grandmother"),
            ("grandmother's", "grandmother"), ("brothers", "brother"), ("sister", "sister"),
            ("son", "son"), ("daughters", "daughter"), ("husband", "husband"), ("wife", "wife"),
            ("uncle", "uncle"), ("auntie", "aunt"), ("cousin", "cousin"), ("grandson", "grandson"),
            ("granddaughter", "granddaughter"), ("grandchildren", "grandchild"),
            ("nephew", "nephew"), ("niece", "niece"),
        ]
        let missed = added.filter { word, relation in
            unsaid("Toivo, \(word), otti kuvan.", said: "Toivo otti kuvan.") != [relation]
        }
        check("each of \(added.count) forms is caught as the relationship it is",
              missed.isEmpty, "\(missed)")

        print("— a relationship said in any form covers the others —")
        check("isän in the telling, isälle in the text",
              unsaid("Isälle mökki oli rakas.", said: "Isän kanssa mentiin mökille.").isEmpty)
        check("äidin in the telling, äidillä in the text",
              unsaid("Äidillä oli kamera Puumalassa.", said: "Äidin kamera jäi Puumalaan.").isEmpty)
        check("pojat in the telling, poikia in the text",
              unsaid("Poikia oli kolme.", said: "Pojat lähtivät kolmestaan.").isEmpty)
        check("mummon in the telling, mummola in the text",
              unsaid("Mummolassa oli sauna.", said: "Mummon talossa oli sauna.").isEmpty)
        check("a spoken word the prompt tidies: faija becoming isäni",
              unsaid("Isäni otti kuvat.", said: "Mun faija otti kuvat.").isEmpty)
        check("mutsi becoming äiti",
              unsaid("Äiti leipoi pullaa.", said: "Mutsi leipoi pullaa.").isEmpty)
        check("iskä and äiskä becoming isä and äiti",
              unsaid("Isä ja äiti tanssivat.", said: "Iskä ja äiskä tanssivat.").isEmpty)
        check("ukki becoming isoisä",
              unsaid("Isoisä korjasi veneen.", said: "Ukki korjas veneen.").isEmpty)
        check("a Finnish telling that came back in English",
              unsaid("Dad took the picture.", said: "Isä otti kuvan.").isEmpty)
        check("mum becoming mother",
              unsaid("Mother baked on Sundays.", said: "Mum baked on Sundays.").isEmpty)

        print("— words that begin like a relative and are not one —")
        let plain = "We sang a song for a moment, and she would mumble a sonnet. Poikkesimme mökille."
        check("song, moment, mumble, sonnet and poikkesimme name nobody",
              RelationWords.named(in: plain).isEmpty, "\(RelationWords.named(in: plain))")
        check("the master of the house is not a father",
              RelationWords.named(in: "Toivo oli talon isäntä, ja isännät tulivat.").isEmpty)
        check("and does not hide one the model added",
              unsaid("Toivo, meidän isä, oli talon isäntä.", said: "Toivo oli talon isäntä.") == ["father"])
        check("enough and enormous are no uncle, and do not hide one either",
              unsaid("It was enough. Our uncle's fish was enormous.",
                     said: "It was enough, and the fish was enormous.") == ["uncle"])

        print("— what the teller said stays hers —")
        check("a relationship she said and the text dropped is no business of this",
              unsaid("Toivo otti kuvan.", said: "Isä otti kuvan.").isEmpty)
        check("a grandmother the family calls Mummo keeps her name",
              unsaid("Mummo otti kuvan.", said: "Mummo otti kuvan.").isEmpty)
        check("a text that only lost the fillers is kept",
              unsaid("Toivo always had the camera.", said: "Um, Toivo, like, always had the camera.").isEmpty)

        print("— the letters —")
        check("capitals",
              unsaid("TOIVO, OUR DAD, HAD THE CAMERA.", said: answer) == ["father"]
                  && unsaid("isä otti kuvan", said: "ISÄ OTTI KUVAN").isEmpty)
        // "a" followed by a combining diaeresis, which is how some keyboards
        // and some pasted text spell ä. It is the same letter to Swift.
        check("an ä written as two code points",
              unsaid("Toivo, meidän isa\u{0308}, otti kuvan.", said: "Toivo otti kuvan.") == ["father"]
                  && unsaid("Isälle.", said: "Isa\u{0308}n kanssa.").isEmpty)

        print("— the table —")
        let entries = RelationWords.relations.values.flatMap { $0 }
        let upper = entries.filter { $0 != $0.lowercased() }
        check("every entry is lower case, since every word is", upper.isEmpty, "\(upper)")
        let short = entries.filter { $0.hasSuffix("*") && $0.count < 4 }
        check("no stem is shorter than three letters", short.isEmpty, "\(short)")
        let idle = RelationWords.lookalikes.filter { lookalike in
            !entries.contains { $0.hasSuffix("*") && lookalike.hasPrefix($0.dropLast()) }
        }
        check("every lookalike begins with a stem it is there to outrank", idle.isEmpty, "\(idle)")

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
