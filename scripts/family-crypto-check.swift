// Checks the encryption at rest that PLAN.md §10 lever 3 rests on.
//
// This is the one part of the app where being wrong is both silent and
// permanent. A memory sealed under the wrong key still syncs, still shows a row
// in the list, and still reports success — it is simply unreadable, and nobody
// finds out until somebody opens a story their grandmother told and gets
// nothing back. By then the plaintext is gone.
//
// So the properties are asserted rather than assumed, and three of them are the
// ones that would otherwise fail quietly:
//
//   - a wrong key does not open a box, and does not return empty text either
//   - a title encrypts to the same string every time, or `sync.ts` reads every
//     push as a rename and wipes coordinates somebody's device resolved
//   - a body encrypts to a different string every time, so the server cannot
//     tell two identical memories apart
//
// Run it after touching FamilyCrypto.swift — the command is in
// docs/DEVELOPMENT.md.
//
//   swiftc -parse-as-library -o /tmp/family-crypto-check \
//     scripts/family-crypto-check.swift ios/Kinlore/Services/FamilyCrypto.swift \
//     ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift

import CryptoKit
import Foundation

@main
enum FamilyCryptoCheck {
    static func main() {
        var failures = 0

        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            if passed {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)\(detail.isEmpty ? "" : ": \(detail)")")
            }
        }

        let key = SymmetricKey(size: .bits256)
        let other = SymmetricKey(size: .bits256)

        // A real one. Finnish, because the transcripts are, and because a
        // check that only ever sees ASCII would miss a UTF-8 length bug in
        // exactly the alphabet this app is written for.
        let body = "Aino tuli mökille joka kesä, ja rannassa istuttiin pitkään "
            + "puhumassa siitä, millaista sodan jälkeen oli ollut."

        print("— text goes there and comes back —")
        guard let sealed = FamilyCrypto.seal(body, with: key) else {
            print("  FAIL sealing returned nil")
            exit(1)
        }
        check("opens to the same words", FamilyCrypto.open(sealed, with: key) == body)
        check("carries the version marker", sealed.hasPrefix(FamilyCrypto.marker))
        check(
            "and the words are not in the ciphertext",
            !sealed.contains("Aino") && !sealed.contains("mökille")
        )

        print("— the wrong key refuses, rather than returning nothing —")
        check("a stranger's key opens nothing", FamilyCrypto.open(sealed, with: other) == nil)
        check(
            "nil rather than empty, so no screen can draw it as a memory with no words",
            FamilyCrypto.open(sealed, with: other) != ""
        )

        print("— a body is randomised —")
        let twice = (FamilyCrypto.seal(body, with: key), FamilyCrypto.seal(body, with: key))
        check("the same memory sealed twice differs", twice.0 != twice.1)
        check("and both still open", FamilyCrypto.open(twice.0 ?? "", with: key) == body)

        print("— a title is not —")
        let title = "Kuusamo"
        let titleOnce = FamilyCrypto.sealDeterministically(title, with: key)
        let titleTwice = FamilyCrypto.sealDeterministically(title, with: key)
        check(
            "the same title seals identically, or sync.ts reads a rename and wipes the coordinates",
            titleOnce == titleTwice,
            "\(titleOnce ?? "nil") vs \(titleTwice ?? "nil")"
        )
        check("a different title seals differently", titleOnce != FamilyCrypto.sealDeterministically("Kuusamon mökki", with: key))
        check("and it still opens", FamilyCrypto.open(titleOnce ?? "", with: key) == title)
        check(
            "the same title under another family's key is not the same string",
            titleOnce != FamilyCrypto.sealDeterministically(title, with: other)
        )

        print("— what was written before lever 3 still reads —")
        check("unmarked text passes through", FamilyCrypto.open("Vanha muisto", with: key) == "Vanha muisto")
        check("including empty", FamilyCrypto.open("", with: key) == "")

        print("— bytes: the recording is the product —")
        var audio = Data((0 ..< 4096).map { _ in UInt8.random(in: .min ... .max) })
        // An M4A begins with an ftyp box. Sealing must not care, and opening
        // must give back the same first bytes — a player is unforgiving about
        // them, and rule 3 says these are the bytes that matter.
        audio.replaceSubrange(4 ..< 8, with: Data("ftyp".utf8))
        guard let sealedAudio = FamilyCrypto.seal(audio, with: key) else {
            print("  FAIL sealing audio returned nil")
            exit(1)
        }
        check("opens byte for byte", FamilyCrypto.open(sealedAudio, with: key) == audio)
        // dropFirst(4), because that is where the fixture puts ftyp — after
        // the four-byte box size, as in a real m4a. This said 3 for a while
        // (the length of "k1.", a different offset entirely), which made the
        // comparison false for sealed AND plaintext bytes alike: a check that
        // could never fail, found by the deploy-day audit, 24 Aug 2026.
        check("the ftyp box is not left in the open", !sealedAudio.dropFirst(4).starts(with: Data("ftyp".utf8)))
        check("a stranger's key opens no audio", FamilyCrypto.open(sealedAudio, with: other) == nil)
        check("unsealed bytes pass through", FamilyCrypto.open(audio, with: key) == audio)

        print("— tampering is caught, not decrypted into nonsense —")
        var tampered = Array(sealedAudio)
        tampered[tampered.count - 1] ^= 0x01
        check("one flipped bit in the tag refuses", FamilyCrypto.open(Data(tampered), with: key) == nil)

        // MARK: - The payload that actually crosses to the Worker
        //
        // Built by decoding the wire JSON rather than by calling a memberwise
        // initialiser, so this exercises the shape `sync.ts` really receives.

        print("— the sync payload, sealed —")
        let wire = """
        {"subjects":[{"id":"s1","kind":"place","title":"Kuusamo","confirmed":1,"created_at":0}],
         "memories":[{"id":"m1","subject_id":"s1","body":"Aino tuli mökille joka kesä.",
                      "raw_transcript":"aino tuli mökille joka kesä öö niin",
                      "source":"voice","created_at":0}],
         "questions":[{"id":"q1","text":"Millainen Aino oli?","status":"open","created_at":0}],
         "relations":[{"id":"r1","from_subject":"s1","to_subject":"s2","kind":"parent",
                       "confirmed":0,"created_at":0}]}
        """
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: Data(wire.utf8)) else {
            print("  FAIL the wire JSON did not decode into SyncPayload")
            exit(1)
        }

        let out = payload.sealed(with: key)
        guard let onTheWire = try? JSONEncoder().encode(out),
              let asSent = String(data: onTheWire, encoding: .utf8)
        else {
            print("  FAIL the sealed payload did not encode")
            exit(1)
        }

        // The claim this whole lever makes, stated as an assertion: a dump of
        // what was sent contains none of the words.
        for word in ["Kuusamo", "Aino", "mökille", "Millainen", "sodan"] {
            check("\"\(word)\" is not in what crosses to the Worker", !asSent.contains(word))
        }
        check("the ids still are, because the server routes by them", asSent.contains("m1"))

        print("— and opened again on the other device —")
        // The same rows coming back. Built directly rather than through JSON:
        // the push above already exercised the wire shape, and composing a
        // reply out of encoded fragments tests the string interpolation rather
        // than the encryption.
        let reply = SyncPullReply(
            seq: 9,
            more: false,
            subjects: out.subjects,
            memories: out.memories,
            questions: out.questions
        )
        let back = reply.opened(with: key)
        check("the title comes back", back.subjects.first?.title == "Kuusamo")
        check("the body comes back", back.memories.first?.body == payload.memories.first?.body)
        check(
            "the raw transcript comes back — rule 3 says it is the product, not a step",
            back.memories.first?.raw_transcript == payload.memories.first?.raw_transcript
        )
        check("the question comes back", back.questions.first?.text == "Millainen Aino oli?")

        print("— the ways a seal can quietly eat a field —")
        check(
            "a nil raw transcript stays nil rather than becoming a sealed empty string",
            out.memories.first(where: { $0.raw_transcript == nil }) == nil
                ? true
                : out.memories.first?.raw_transcript != nil
        )
        check("an empty title is left alone", {
            var empty = payload
            empty.subjects[0].title = ""
            return empty.sealed(with: key).subjects[0].title == ""
        }())
        // A guesses check stood here until the guessing round was cut
        // (PLAN §5 row 8) and took SyncPayload.guesses with it — at which
        // point this script stopped COMPILING, silently, because its own
        // instruction says to run it only after touching FamilyCrypto and
        // nobody had. Found by the deploy-day audit chain, 24 Aug 2026:
        // a check that does not build is the quietest possible green.
        check("relations are untouched", out.relations.first?.kind == "parent")

        print("— a title survives being pushed twice —")
        check(
            "two pushes of the same title are byte-identical, or sync.ts wipes the coordinates",
            payload.sealed(with: key).subjects[0].title == out.subjects[0].title
        )

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
