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
// `hasFailedRepeatedly` and `isDue` quietly decide what `RootView`,
// `GalleryScreen` and the catch-up itself do with it.
//
// Until 26 Sep 2026 the third failure was the last. A provider that has run out
// of credit answers the same 502 as the guard, on every attempt, for as long as
// the outage lasts, and three rounds of the catch-up inside one retired every
// memory told during it. So the tally now sets a wait instead of an end:
// nothing before the third failure, a day after it, doubling, never more than
// thirty days, timed from the last failure — and a tally the old rule left
// behind has no timestamp and is due at once. Every one of those numbers is
// silent when wrong. A wait that never ends is the old rule back, a wait that
// never grows is the money the rule exists to save, and a ceiling that
// overflows is either.
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
// arms they answer for, which arm counts a failure, and that the catch-up asks
// `isDue` and nothing that gives up for good. Both halves are honest about
// which they are, and a reader should not take the second for the first.
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
        typealias Attempts = TranscriptionAttempts
        let one = "memory-one"
        let two = "memory-two"
        let day: TimeInterval = 24 * 60 * 60
        // A fixed moment, so that nothing below depends on the clock it runs on.
        let told = Date(timeIntervalSince1970: 1_790_000_000)

        print("— how often the app asks again —")
        Attempts.reset()
        check("a recording nobody has failed on has no tally", Attempts.failures(for: one) == 0)
        check("and has not been refused repeatedly", !Attempts.hasFailedRepeatedly(on: one))
        check("and is due at once", Attempts.isDue(one, now: told))

        Attempts.recordFailure(one, at: told)
        check("one refusal counts once", Attempts.failures(for: one) == 1)
        check("and the app asks again at once", Attempts.isDue(one, now: told) && !Attempts.hasFailedRepeatedly(on: one))

        Attempts.recordFailure(one, at: told)
        check("two refusals count twice", Attempts.failures(for: one) == 2)
        check("and the app still asks again at once", Attempts.isDue(one, now: told) && !Attempts.hasFailedRepeatedly(on: one))

        Attempts.recordFailure(one, at: told)
        check("three refusals count three times", Attempts.failures(for: one) == 3)
        check("and the row may stop promising the text", Attempts.hasFailedRepeatedly(on: one))
        check(
            "and the app does not ask again on the spot",
            !Attempts.isDue(one, now: told),
            "the same silence would be paid for on every launch"
        )
        check("nor an hour short of a day later", !Attempts.isDue(one, now: told + day - 3600))
        check(
            "but a day later it does",
            Attempts.isDue(one, now: told + day),
            "a wait that never ends is the old rule back"
        )
        check("and the tally still reads three refusals", Attempts.hasFailedRepeatedly(on: one))

        let fourth = told + day
        Attempts.recordFailure(one, at: fourth)
        check("a fourth refusal doubles the wait: not due after a day", !Attempts.isDue(one, now: fourth + day))
        check(
            "but due after two",
            Attempts.isDue(one, now: fourth + 2 * day),
            "a wait that never grows is the money the tally exists to save"
        )

        // Each further refusal made the moment it is due, so that the schedule
        // is the one a phone would actually keep: four days, eight, sixteen,
        // and then the ceiling.
        var moment = fourth
        for (count, days) in [(5, 4.0), (6, 8.0), (7, 16.0), (8, 30.0), (9, 30.0), (12, 30.0)] {
            while Attempts.failures(for: one) < count {
                moment += Attempts.wait(afterFailure: Attempts.failures(for: one))
                Attempts.recordFailure(one, at: moment)
            }
            check(
                "after \(count) refusals the wait is \(Int(days)) days",
                !Attempts.isDue(one, now: moment + days * day - 60) && Attempts.isDue(one, now: moment + days * day),
                count == 8 ? "thirty days is the ceiling, not thirty-two" : ""
            )
        }

        print("\n— the wait itself —")
        check(
            "nothing before the third refusal",
            Attempts.wait(afterFailure: 0) == 0 && Attempts.wait(afterFailure: 1) == 0 && Attempts.wait(afterFailure: 2) == 0
        )
        check("a day after the third", Attempts.wait(afterFailure: 3) == day)
        check(
            "doubling with each one",
            Attempts.wait(afterFailure: 4) == 2 * day && Attempts.wait(afterFailure: 5) == 4 * day
                && Attempts.wait(afterFailure: 6) == 8 * day && Attempts.wait(afterFailure: 7) == 16 * day
        )
        check(
            "thirty days at most",
            Attempts.wait(afterFailure: 8) == 30 * day && Attempts.wait(afterFailure: 9) == 30 * day
                && Attempts.wait(afterFailure: 40) == 30 * day
        )
        check(
            "and a tally beyond counting cannot overflow its way back to zero",
            Attempts.wait(afterFailure: Int.max) == 30 * day
        )

        print("\n— what an older build left behind —")
        let old = "memory-retired-under-the-old-rule"
        var counts = UserDefaults.standard.dictionary(forKey: "transcription-failures") ?? [:]
        counts[old] = 3
        UserDefaults.standard.set(counts, forKey: "transcription-failures")
        check(
            "a tally of three with no timestamp reads as three refusals",
            Attempts.failures(for: old) == 3 && Attempts.hasFailedRepeatedly(on: old) && Attempts.lastFailure(for: old) == nil
        )
        check(
            "and is due at once",
            Attempts.isDue(old, now: told),
            "the memories told during the outage would stay retired"
        )
        Attempts.recordFailure(old, at: told)
        check(
            "and from its next refusal it waits like any other",
            !Attempts.isDue(old, now: told + day) && Attempts.isDue(old, now: told + 2 * day)
        )

        print("\n— a clock set back —")
        let ahead = "memory-last-failed-on-tomorrow"
        for _ in 0..<3 { Attempts.recordFailure(ahead, at: told + 10 * day) }
        check(
            "a last failure in the future is due now",
            Attempts.isDue(ahead, now: told),
            "a phone whose clock went back would wait the difference out"
        )

        print("\n— one recording's tally is its own —")
        Attempts.recordFailure(two, at: told)
        check(
            "another recording carries its own tally",
            Attempts.failures(for: two) == 1 && Attempts.failures(for: one) == 12
        )
        check("and has not been refused repeatedly", !Attempts.hasFailedRepeatedly(on: two))

        Attempts.clear(one)
        check("finishing a recording forgets its tally", Attempts.failures(for: one) == 0)
        check("and when it last failed", Attempts.lastFailure(for: one) == nil)
        check("and asks about it again at once", Attempts.isDue(one, now: told))
        check(
            "while the other's is untouched",
            Attempts.failures(for: two) == 1 && Attempts.lastFailure(for: two) == told
        )

        Attempts.clear("a recording this device has never failed on")
        check("clearing an unknown recording changes nothing", Attempts.failures(for: two) == 1)

        Attempts.reset()
        check(
            "emptying the device forgets every tally",
            Attempts.failures(for: two) == 0 && Attempts.failures(for: old) == 0 && Attempts.failures(for: ahead) == 0
        )
        check(
            "and every timestamp with it",
            UserDefaults.standard.dictionary(forKey: "transcription-last-failure") == nil
        )

        // The tally above is right on its own and would stay right with the
        // classifier's arms swapped — and swapped is exactly the defect the
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
            "a recording refused three times is skipped until its wait is over, before it is uploaded",
            source.contains("guard TranscriptionAttempts.isDue(memory.id) else { continue }"),
            "the tally is kept and not consulted"
        )
        check(
            "and nothing in the catch-up gives up on a recording for good",
            !source.contains("hasGivenUp"),
            "an outage of three rounds would retire every memory told during it"
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

        Attempts.reset()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
