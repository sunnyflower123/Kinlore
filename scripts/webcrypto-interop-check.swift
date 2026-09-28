// The browser half of PLAN.md §10 lever 3, measured rather than assumed.
//
// Lever 3 seals bodies, transcripts, subject titles and the R2 objects on the
// device with CryptoKit. Every argument for ever reading this archive anywhere
// other than an iPhone — a web page for an Android relative, the universal link
// ARCHITECTURE §4 wants, anything that is not a second native app — rests on one
// unmeasured claim: that a browser can open what CryptoKit sealed.
//
// That claim was written down as reasoning and believed for a while in both
// directions. It was used to argue a web surface is impossible (it is not), and
// it could equally have been assumed to work and discovered false after a
// weekend of design. Neither is acceptable for a claim this load-bearing, so it
// is a measurement now.
//
// This file is the CryptoKit half. It compiles against the shipping
// FamilyCrypto.swift rather than a copy, so what is measured is the code that
// runs on the phone.
//
//   emit    seals known material and prints it as JSON on stdout
//   verify  opens what the browser sealed, which is the return direction
//
// The properties that would fail silently, and are therefore asserted in the
// .mjs beside this file:
//
//   - the randomised seal opens, so a memory body can be read in a browser
//   - the deterministic seal opens, and the browser can REPRODUCE its nonce —
//     without that a web client that ever writes a title makes `sync.ts` read
//     every push as a rename and wipe coordinates a device had resolved
//   - sealed bytes survive byte for byte, because a photograph or a recording
//     that is quietly re-encoded is rule 3 broken without an error
//   - a value with no marker passes through, so pre-lever-3 data still reads
//   - a wrong key is refused rather than returning something
//
// The Finnish payloads are the input under test, not documentation: they carry
// ä and ö through the seal, and a NUL byte rides in the binary case. Translating
// them would test something else.
//
// Run it after touching FamilyCrypto.swift — the command is in
// docs/DEVELOPMENT.md.
//
//   swiftc -parse-as-library -o /tmp/webcrypto-interop-check \
//     scripts/webcrypto-interop-check.swift \
//     ios/Kinlore/Services/FamilyCrypto.swift

import CryptoKit
import Foundation

@main
enum WebCryptoInteropCheck {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { fail("usage: webcrypto-interop-check emit | verify <file>") }

        switch args[1] {
        case "emit":
            emit()
        case "verify":
            guard args.count > 2 else { fail("verify needs the file the .mjs wrote") }
            verify(path: args[2])
        default:
            fail("unknown mode \(args[1])")
        }
    }

    // MARK: - emit

    /// Seals known material under a fresh key and hands it to the browser half.
    static func emit() {
        let key = SymmetricKey(size: .bits256)
        let keyB64 = key.withUnsafeBytes { Data(Array($0)).base64EncodedString() }

        let body = "Mummo kertoi mökistä Puumalassa, joskus viisikymmentäluvulla. Isä souti."
        let title = "Isoäiti Aino"

        // Not text: every byte value, then UTF-8 with a NUL in it. A silent
        // re-encoding anywhere between here and the browser shows up as a hash
        // mismatch rather than as something that looks fine.
        var bytes = Data()
        for value in 0...255 { bytes.append(UInt8(value)) }
        bytes.append(contentsOf: Array("ääkkösiä ja \u{0000} nollatavu".utf8))

        guard let sealedBody = FamilyCrypto.seal(body, with: key),
              let titleA = FamilyCrypto.sealDeterministically(title, with: key),
              let titleB = FamilyCrypto.sealDeterministically(title, with: key),
              let sealedBytes = FamilyCrypto.seal(bytes, with: key)
        else { fail("CryptoKit could not seal — the check never got as far as the browser") }

        let out: [String: String] = [
            "key": keyB64,
            "body": body,
            "sealedBody": sealedBody,
            "title": title,
            "sealedTitleA": titleA,
            "sealedTitleB": titleB,
            "bytesSHA256": hex(SHA256.hash(data: bytes)),
            "bytesLength": String(bytes.count),
            "sealedBytesB64": sealedBytes.base64EncodedString(),
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else {
            fail("could not serialise the sealed material")
        }
        FileHandle.standardOutput.write(json)
    }

    // MARK: - verify

    /// Opens what the browser sealed. A read-only web surface does not need this
    /// direction; a web client that ever writes does, and it costs one function.
    static func verify(path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let keyData = obj["key"].flatMap({ Data(base64Encoded: $0) }),
              let sealedByBrowser = obj["sealedByBrowser"],
              let expected = obj["expected"],
              let sealedBytesByBrowser = obj["sealedBytesByBrowserB64"],
              let expectedBytesSHA = obj["expectedBytesSHA256"]
        else { fail("verify: \(path) is not the file the .mjs writes") }

        let key = SymmetricKey(data: keyData)
        var failures = 0

        if FamilyCrypto.open(sealedByBrowser, with: key) == expected {
            report(true, "CryptoKit opens the string WebCrypto sealed")
        } else {
            report(false, "CryptoKit opens the string WebCrypto sealed")
            failures += 1
        }

        if let raw = Data(base64Encoded: sealedBytesByBrowser),
           let opened = FamilyCrypto.open(raw, with: key),
           hex(SHA256.hash(data: opened)) == expectedBytesSHA {
            report(true, "CryptoKit opens the bytes WebCrypto sealed, SHA-256 matches")
        } else {
            report(false, "CryptoKit opens the bytes WebCrypto sealed, SHA-256 matches")
            failures += 1
        }

        print("")
        if failures == 0 {
            print("Both directions cross. Lever 3 is not what stands between this archive and a browser.")
        } else {
            print("\(failures) failed. A browser cannot write into this archive.")
        }
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - helpers

    static func report(_ ok: Bool, _ label: String) {
        print("  \(ok ? "PASS" : "FAIL")  \(label)")
    }

    static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(2)
    }
}
