// A phone without the family's key sends the family nothing.
//
// PLAN.md §10 lever 3 promises that the server stores what it cannot read, and
// `family-crypto-check.swift` proves that the seal holds. What it cannot prove
// is that the seal is applied — and until 26 Sep 2026 it was not, on one kind
// of phone: one that had lost the key. `SyncEngine` looked the key up on every
// round and, finding none, pushed the rows and uploaded the recordings exactly
// as they were. That was a decision rather than an accident (0efbc6a, 16 Aug
// 2026): a missing key was to mean no sealing rather than no syncing, so that a
// family created before lever 3 kept working. No such family exists on the
// server the app talks to — lever 3 landed eight days before the Worker first
// deployed, and PLAN.md §10 records that there was no production data to
// migrate — so the fallback protected nobody. And it had a road to it:
//
//   1. One Apple ID on two phones. The Keychain entries are synchronizable
//      (`Keychain.query` in Identity.swift), so with iCloud Keychain on, both
//      phones hold one identity and one family key — and Apple documents that
//      deleting a synchronizable item deletes every copy of it.
//   2. "Tyhjennä tämä laite" on one of them forgets the key
//      (`Session.renewIdentity`). The other phone loses it too. Its archive
//      and its outbox stay on disk, as they should.
//   3. If the family had anybody else, the wipe first left the family on the
//      server for the identity both phones share, so the other phone is
//      refused and asks for a new invitation — and `Session.rejoin` never took
//      the key back out of it. If the family had nobody else, nothing left the
//      server at all, and the other phone's identity, held in memory since
//      launch, still worked without any rejoin.
//   4. Either way, the next round pushed without a key: the family's words,
//      stored in D1 and R2 as they were said.
//
// This drives that road through the app's own rules — `SyncSeal`, the only way
// a round gets its key, and `FamilyKey.onRejoin` — with the Keychain as one
// value two phones share, which is what kSecAttrSynchronizable makes it. No
// simulator, no Worker, no network, and nothing here touches the real
// Keychain: Identity.swift is compiled for its rule, and none of its Keychain
// calls is made.
//
// The rules are only as good as their callers, and `SyncEngine` and `Session`
// need the whole app to compile. So the last section reads their source, the
// way `device-wipe-check.mjs` reads Session.swift: every push, upload and pull
// in the engine goes through the seal, the key is looked up nowhere else, and
// the rejoin adopts only after the server's answer.
//
//   swiftc -parse-as-library -o /tmp/keyless-sync-check \
//     scripts/keyless-sync-check.swift ios/Kinlore/Data/Identity.swift \
//     ios/Kinlore/Services/FamilyCrypto.swift \
//     ios/Kinlore/Data/MemoryStore+Sync.swift ios/Kinlore/Model/Models.swift

import CryptoKit
import Foundation

/// kSecAttrSynchronizable, as two phones on one Apple ID see it: one entry,
/// and a deletion on either phone is a deletion on both.
final class SharedKeychain {
    var familyKey: SymmetricKey?

    init(familyKey: SymmetricKey?) {
        self.familyKey = familyKey
    }
}

/// The phone that keeps its archive. What it sends and what it adopts are
/// decided by the app's own rules; only the Keychain and the network are
/// stood in for.
struct Phone {
    let keychain: SharedKeychain

    /// One round's push, as `SyncEngine.sync` makes it: what reaches the
    /// Worker, or nil when the round does not run.
    func round(_ payload: SyncPayload) -> SyncPayload? {
        SyncSeal(key: keychain.familyKey).map { $0.push(payload) }
    }

    /// A photograph or a voice, as `SyncEngine.uploadPendingMedia` sends it.
    func upload(_ bytes: Data) -> Data? {
        SyncSeal(key: keychain.familyKey).map { $0.upload(bytes) }
    }

    /// What a pull hands `MemoryStore.applyRemote`, or nil for nothing.
    func pull(_ reply: SyncPullReply) -> SyncPullReply? {
        SyncSeal(key: keychain.familyKey).map { $0.pull(reply) }
    }

    /// `Session.rejoin` after the server has placed the invitation's code in
    /// this phone's own family, which is the only point at which it adopts.
    func rejoin(invitationKey: String?) -> FamilyKey.OnRejoin {
        let outcome = FamilyKey.onRejoin(invited: invitationKey, held: keychain.familyKey.map(shareable))
        if case .adopt(let shared) = outcome {
            keychain.familyKey = key(fromShareable: shared)
        }
        return outcome
    }
}

/// `FamilyKey.shareable()`: base64url with no padding, as an invitation
/// carries the key.
func shareable(_ key: SymmetricKey) -> String {
    key.withUnsafeBytes { Data($0) }.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// `FamilyKey.adopt`, minus the Keychain: 32 bytes or nothing.
func key(fromShareable shared: String) -> SymmetricKey? {
    var value = shared
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while value.count % 4 != 0 { value += "=" }
    guard let data = Data(base64Encoded: value), data.count == 32 else { return nil }
    return SymmetricKey(data: data)
}

/// A file of the app, found from where this one was compiled rather than
/// from the working directory. Empty if it is not there.
func source(_ path: String) -> String {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

@main
enum KeylessSyncCheck {
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

        // The wire shape `sync.ts` receives, decoded rather than built, and the
        // same words `family-crypto-check.swift` looks for.
        let wire = """
        {"subjects":[{"id":"s1","kind":"place","title":"Kuusamo","confirmed":1,"created_at":0}],
         "memories":[{"id":"m1","subject_id":"s1","body":"Aino tuli mökille joka kesä sodan jälkeen.",
                      "raw_transcript":"aino tuli mökille joka kesä öö sodan jälkeen",
                      "source":"voice","created_at":0}],
         "questions":[{"id":"q1","text":"Millainen Aino oli?","status":"open","created_at":0}],
         "relations":[]}
        """
        guard let payload = try? JSONDecoder().decode(SyncPayload.self, from: Data(wire.utf8)) else {
            print("  FAIL the wire JSON did not decode into SyncPayload")
            exit(1)
        }
        let words = ["Kuusamo", "Aino", "mökille", "Millainen", "sodan"]

        /// What a push puts on the wire, or nothing at all.
        func sent(_ push: SyncPayload?) -> String {
            guard let push, let json = try? JSONEncoder().encode(push) else { return "" }
            return String(decoding: json, as: UTF8.self)
        }

        // An M4A begins with an ftyp box, four bytes in.
        var audio = Data((0 ..< 2048).map { _ in UInt8.random(in: .min ... .max) })
        audio.replaceSubrange(4 ..< 8, with: Data("ftyp".utf8))
        func isRecorded(_ bytes: Data) -> Bool {
            bytes.dropFirst(4).starts(with: Data("ftyp".utf8))
        }

        print("— the words are there to be found —")
        // Without this, every "does not cross" below could pass on a fixture
        // that never carried the word.
        for word in words {
            check("\"\(word)\" is in the phone's own outbox", sent(payload).contains(word))
        }
        check("and the recording is as it was recorded", isRecorded(audio))

        // The founder made the key; this phone joined with it; the other phone
        // on the same Apple ID holds it through the shared Keychain.
        let familyKey = SymmetricKey(size: .bits256)
        let keychain = SharedKeychain(familyKey: familyKey)
        let phone = Phone(keychain: keychain)

        print("— with the key: sealed —")
        let sealed = phone.round(payload)
        check("the round runs", sealed != nil)
        for word in words {
            check("\"\(word)\" is not in what crosses to the Worker", !sent(sealed).contains(word))
        }
        check("the ids still are, because the server routes by them", sent(sealed).contains("m1"))
        check("the recording goes up sealed", phone.upload(audio).map { !isRecorded($0) } ?? false)

        print("— the other phone on the same Apple ID is emptied —")
        // `Session.renewIdentity` → `FamilyKey.forget()`, on every phone of the
        // account at once. This phone's archive and outbox stay where they are.
        keychain.familyKey = nil
        let keyless = phone.round(payload)
        check(
            "no round runs without the key",
            keyless == nil,
            "a push of \(sent(keyless).utf8.count) bytes went out"
        )
        for word in words {
            check("\"\(word)\" does not cross to the Worker from a phone without the key", !sent(keyless).contains(word))
        }
        check(
            "a recording is not uploaded as it was recorded",
            phone.upload(audio).map { !isRecorded($0) } ?? true,
            "the original audio went to R2 in the clear"
        )
        // Another member's rows, sealed. Taken in unopened they would be stored
        // as sealed strings — and stay that way after the key came back, since
        // the cursor would already have moved past them.
        guard let founder = SyncSeal(key: familyKey) else {
            print("  FAIL a key did not make a seal")
            exit(1)
        }
        let othersSealed = founder.push(payload)
        let reply = SyncPullReply(
            seq: 7,
            more: false,
            subjects: othersSealed.subjects,
            memories: othersSealed.memories,
            questions: othersSealed.questions
        )
        let takenIn = phone.pull(reply)
        check(
            "and nothing sealed is taken in unopened",
            takenIn == nil,
            "applyRemote would store \(takenIn?.memories.first?.body.prefix(12) ?? "")…"
        )

        print("— a new invitation brings the key back —")
        // `InviteShare.inviteText`: the code, `#`, and the family's key.
        let invitation = shareable(familyKey)
        let outcome = phone.rejoin(invitationKey: invitation)
        check("the rejoin takes the key out of the invitation", outcome == .adopt(invitation), "\(outcome)")
        let resumed = phone.round(payload)
        check("the round runs again", resumed != nil)
        for word in words {
            check("\"\(word)\" is not in what crosses after the rejoin", !sent(resumed).contains(word))
        }
        let body = resumed?.memories.first?.body ?? ""
        check(
            "sealed under the family's own key, which every other phone opens",
            body.hasPrefix(FamilyCrypto.marker)
                && FamilyCrypto.open(body, with: familyKey) == payload.memories.first?.body,
            body.isEmpty ? "nothing was sent" : String(body.prefix(24))
        )
        check("and the outbox still has everything it had", sent(payload).contains("Aino"))

        print("— the rules that were already right, still right —")
        let otherFamily = shareable(SymmetricKey(size: .bits256))
        check(
            "another family's key is refused before any request",
            FamilyKey.onRejoin(invited: otherFamily, held: invitation) == .elsewhere
        )
        check(
            "the family's own key changes nothing",
            FamilyKey.onRejoin(invited: invitation, held: invitation) == .keep
        )
        check(
            "an invitation with no key leaves this phone's key where it is",
            FamilyKey.onRejoin(invited: nil, held: invitation) == .keep
        )
        check(
            "and leaves a phone with none still sending nothing",
            FamilyKey.onRejoin(invited: nil, held: nil) == .keep && SyncSeal(key: nil) == nil
        )

        print("— and the app takes no other road —")
        let engine = source("ios/Kinlore/Services/SyncEngine.swift")
        func throughSeal(_ call: String, _ sealed: String) -> Bool {
            let all = occurrences(of: call, in: engine)
            return all > 0 && all == occurrences(of: sealed, in: engine)
        }
        check("SyncEngine.swift is there to be read", !engine.isEmpty)
        check(
            "the engine looks the key up in one place, to make its seal",
            occurrences(of: "FamilyKey.current()", in: engine) == 1
                && occurrences(of: "SyncSeal(key: FamilyKey.current())", in: engine) == 1
        )
        check("every push is sealed by it", throughSeal("client.push(", "client.push(seal.push("))
        check(
            "every photograph, colouring and recording is sealed by it",
            throughSeal("media.upload(data:", "media.upload(data: seal.upload(")
        )
        check(
            "and every pull is opened by it before the store takes it in",
            throughSeal("store.applyRemote(", "store.applyRemote(seal.pull(")
        )
        let session = source("ios/Kinlore/Data/Session.swift")
        let rejoin = session.range(of: "func rejoin(").map { start -> String in
            let rest = session[start.lowerBound...]
            return String(rest[..<(rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex)])
        } ?? ""
        let answered = rejoin.range(of: "result.familyID != currentID")?.lowerBound
        let adopted = rejoin.range(of: "case .adopt(")?.lowerBound
        check("the rejoin decides by FamilyKey.onRejoin", rejoin.contains("FamilyKey.onRejoin("))
        check(
            "and takes the key only after the server has placed the code in this family",
            answered != nil && adopted != nil && answered! < adopted!
        )

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
