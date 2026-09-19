// How often the app will ask again, and what it is willing to blame on the
// moment rather than on the recording.
//
// A quota never rejects a recording and neither does a lost network: the audio
// is kept and the transcription waits (ARCHITECTURE §7, §16). `DeferredMemory`
// is the half that comes back for it, and two decisions inside it are silent in
// both directions.
//
// `TranscriptionAttempts` is the tally. Too forgiving and audio that can never
// be transcribed — silence, or speech the hallucination guard refuses — costs
// the family paid minutes on every launch for as long as the memory exists.
// Too strict and a perfectly good recording is abandoned because a provider had
// a bad hour. Neither shows: the row reads "Ääni tallessa" either way, and
// `hasGivenUp` quietly decides what `RootView`, `GalleryScreen` and the
// catch-up itself do with it.
//
// `isAboutTheMoment` is the classifier that feeds it, and its own comment names
// the two failures: getting it wrong in one direction starves every memory
// behind a hopeless one, and in the other it abandons a good recording because
// the cottage had no signal for a week.
//
// Nothing ran either of them until 19 Sep 2026. `-defer once` drives one branch
// — the minutes running out — through two UI tests and `export-check.mjs`, and
// that branch is the one that already worked.
//
// TWO INSTRUMENTS, AND THEY ARE NOT THE SAME STRENGTH. The tally is EXECUTED:
// `TranscriptionAttempts` was carved into a file of its own so that it could
// be, because `DeferredMemory.swift` reaches `MemoryStore`, `MediaStore` and
// `MediaLoader`, all three of which import UIKit — a command-line build on this
// machine cannot compile them, and standing in for them would have meant
// measuring the stand-ins. The classifier and its wiring are READ: they stay in
// `DeferredMemory.swift`, so nothing here runs them, and what is pinned is the
// arms they answer for and which arm counts a failure. Both halves are honest
// about which they are, and a reader should not take the second for the first.
//
//   swiftc -parse-as-library -o /tmp/transcription-catchup-check \
//     scripts/transcription-catchup-check.swift \
//     ios/Kinlore/Services/TranscriptionAttempts.swift
//
// Costs nothing: no simulator, no network, no key, no minutes. Run it after
// touching TranscriptionAttempts.swift or the catch-up in DeferredMemory.swift.

import Foundation

@main
enum TranscriptionCatchUpCheck {
    static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    /// The return that belongs to one `case`, read up to the next one.
    static func armSays(_ arms: String, _ label: String, _ answer: String) -> Bool {
        guard let start = arms.range(of: label) else { return false }
        let rest = arms[start.upperBound...]
        let end = rest.range(of: "\n        case ")?.lowerBound ?? rest.endIndex
        return rest[..<end].contains(answer)
    }

    @MainActor
    static func main() {
        let one = "memory-one"
        let two = "memory-two"

        print("— how often the app asks again —")
        TranscriptionAttempts.reset()
        check("a recording nobody has failed on has no tally", TranscriptionAttempts.failures(for: one) == 0)
        check("and is still worth asking about", !TranscriptionAttempts.hasGivenUp(on: one))

        TranscriptionAttempts.recordFailure(one)
        check("one refusal counts once", TranscriptionAttempts.failures(for: one) == 1)
        check("and the app asks again", !TranscriptionAttempts.hasGivenUp(on: one))

        TranscriptionAttempts.recordFailure(one)
        check("two refusals count twice", TranscriptionAttempts.failures(for: one) == 2)
        check("and the app still asks again", !TranscriptionAttempts.hasGivenUp(on: one))

        TranscriptionAttempts.recordFailure(one)
        check("three refusals count three times", TranscriptionAttempts.failures(for: one) == 3)
        check("and then the app stops asking", TranscriptionAttempts.hasGivenUp(on: one))

        TranscriptionAttempts.recordFailure(two)
        check(
            "another recording carries its own tally",
            TranscriptionAttempts.failures(for: two) == 1 && TranscriptionAttempts.hasGivenUp(on: one)
        )
        check("and has not been given up on", !TranscriptionAttempts.hasGivenUp(on: two))

        TranscriptionAttempts.clear(one)
        check("finishing a recording forgets its tally", TranscriptionAttempts.failures(for: one) == 0)
        check("and asks about it again", !TranscriptionAttempts.hasGivenUp(on: one))
        check("while the other's is untouched", TranscriptionAttempts.failures(for: two) == 1)

        TranscriptionAttempts.clear("a recording this device has never failed on")
        check("clearing an unknown recording changes nothing", TranscriptionAttempts.failures(for: two) == 1)

        TranscriptionAttempts.reset()
        check("emptying the device forgets every tally", TranscriptionAttempts.failures(for: two) == 0)

        // The two above are each right on their own and would both stay right
        // with the arms swapped — and swapped is exactly the defect the
        // classifier's own comment describes. Nothing executable can see that
        // from outside `run()`, so the wiring is read.
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ios/Kinlore/Services/DeferredMemory.swift")
        guard let source = try? String(contentsOf: path, encoding: .utf8) else {
            print("  FAIL DeferredMemory.swift could not be read at \(path.path)")
            exit(1)
        }

        print("\n— the moment, or the recording —")
        guard let classifier = source.range(of: "static func isAboutTheMoment(_ error: Error) -> Bool {"),
              let classifierEnd = source.range(of: "\n    }\n", range: classifier.upperBound..<source.endIndex)
        else {
            print("  FAIL isAboutTheMoment is no longer shaped as this check reads it")
            exit(1)
        }
        let arms = String(source[classifier.upperBound..<classifierEnd.lowerBound])

        check(
            "a lost network is the moment",
            arms.contains("if error is URLError { return true }"),
            "a week at the cottage would give up on every recording made there"
        )
        check(
            "anything that is not the server's answer is the recording",
            arms.contains("guard let remote = error as? RemoteError else { return false }")
        )
        check("the month's minutes, spent, are the moment", armSays(arms, "case .quotaExceeded:", "return true"))
        check(
            "an unauthenticated device and knocking too often are the moment",
            armSays(arms, "case .badStatus(let code):", "return code == 401 || code == 429")
        )
        check("audio with no words in it is the recording", armSays(arms, "case .emptyResult:", "return false"))
        check(
            "and no arm is a default one",
            !arms.contains("default:"),
            "a case added to RemoteError would fall through it instead of failing to compile"
        )

        print("\n— and which arm counts —")
        check(
            "a recording already given up on is skipped before it is uploaded",
            source.contains("guard !TranscriptionAttempts.hasGivenUp(on: memory.id) else { continue }"),
            "the tally is kept and not consulted"
        )

        let guarded = "catch where Self.isAboutTheMoment(error) {"
        let plain = "} catch {"
        guard let momentStart = source.range(of: guarded),
              let plainStart = source.range(of: plain, range: momentStart.upperBound..<source.endIndex)
        else {
            print("  FAIL the two catch arms are no longer shaped as this check reads them")
            exit(1)
        }
        let momentArm = String(source[momentStart.upperBound..<plainStart.lowerBound])
        let recordingArm = String(source[plainStart.upperBound...].prefix(2000))

        check("a failure about the moment ends the round", momentArm.contains("break"))
        check(
            "and costs the recording nothing",
            !momentArm.contains("TranscriptionAttempts.recordFailure"),
            "a week without signal would give up on a good recording"
        )
        check(
            "a failure about the recording is counted",
            recordingArm.contains("TranscriptionAttempts.recordFailure"),
            "the same silence would be paid for on every launch"
        )
        check(
            "and the round goes on without it",
            recordingArm.contains("continue"),
            "one hopeless recording would starve every memory behind it"
        )

        TranscriptionAttempts.reset()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
