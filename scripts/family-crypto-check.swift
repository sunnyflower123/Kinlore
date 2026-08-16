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
// Run it after touching FamilyCrypto.swift — the command is in CLAUDE.md.
//
//   swiftc -parse-as-library -o /tmp/family-crypto-check \
//     scripts/family-crypto-check.swift ios/Kinlore/Services/FamilyCrypto.swift

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
        check("the ftyp box is not left in the open", !sealedAudio.dropFirst(3).starts(with: Data("ftyp".utf8)))
        check("a stranger's key opens no audio", FamilyCrypto.open(sealedAudio, with: other) == nil)
        check("unsealed bytes pass through", FamilyCrypto.open(audio, with: key) == audio)

        print("— tampering is caught, not decrypted into nonsense —")
        var tampered = Array(sealedAudio)
        tampered[tampered.count - 1] ^= 0x01
        check("one flipped bit in the tag refuses", FamilyCrypto.open(Data(tampered), with: key) == nil)

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
