import Foundation

// Carved out of `DeferredMemory.swift` on 19 Sep 2026 so that it can be run.
// Nothing about the decision changed, and it is still the tally the catch-up
// keeps — but the file it lived in reaches `MemoryStore`, `MediaStore` and
// `MediaLoader`, all three of which import UIKit, so a command-line build on
// this machine cannot compile it and `transcription-catchup-check.swift` would
// have had to measure a stand-in for every collaborator instead. Which is the
// move `budget.ts` made on the backend for the same reason, and for the same
// gain: a few dozen lines with no imports of their own can simply be executed.

/// How often this device has tried and failed to make text out of one
/// recording, and when it may try again.
///
/// Device-local, in `UserDefaults`, for the same reason the ladder's comfort is
/// (§12): it describes this phone's attempts rather than a fact about the
/// family's archive. A count that synced would let one phone's bad afternoon
/// slow every other phone down.
@MainActor
enum TranscriptionAttempts {
    /// Three attempts as soon as the app can make them, and after that the
    /// asking slows down rather than stopping.
    ///
    /// Every attempt uploads the whole recording and is paid for whether or not
    /// any words come back, so audio that cannot be transcribed — silence, or
    /// speech the hallucination guard refuses — would otherwise cost the family
    /// minutes on every launch for as long as the memory exists. Three is
    /// forgiving enough that a provider having a bad hour does not lose a
    /// transcript, and small enough that nothing is paid for indefinitely.
    ///
    /// Until 26 Sep 2026 the third failure was the last, and that was the wrong
    /// end of the bargain for the one failure the tally cannot tell from a
    /// refused recording: a Worker whose provider has run out of credit answers
    /// 502, exactly as the guard does, and three rounds of the catch-up inside
    /// that outage retired every memory told during it — for good, on a phone
    /// that keeps the audio for precisely this case. So the tally now sets a
    /// wait instead of an end; see `wait(afterFailure:)`.
    static let limit = 3

    /// The wait after the third failure. Each further failure doubles it, up
    /// to `longestWait`, so a recording that will never transcribe costs the
    /// family three attempts on the day it is told, four more in its first
    /// month and one a month after that — instead of three and nothing.
    static let firstWait: TimeInterval = 24 * 60 * 60
    /// A month, so that an outage of any length is survived at the price of one
    /// attempt a month per memory, and so that the doubling has a ceiling.
    static let longestWait: TimeInterval = 30 * 24 * 60 * 60

    private static let countKey = "transcription-failures"
    private static let whenKey = "transcription-last-failure"

    static func failures(for memoryID: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: countKey)?[memoryID] as? Int) ?? 0
    }

    /// When this device last failed on the recording. Absent for a tally
    /// written before 26 Sep 2026, which `isDue` reads as due at once: those
    /// are the recordings the old rule retired, and the next round picks them
    /// up first.
    static func lastFailure(for memoryID: String) -> Date? {
        guard let seconds = UserDefaults.standard.dictionary(forKey: whenKey)?[memoryID] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Asked `limit` times and refused `limit` times. The audio is still kept
    /// and still exported, and the asking goes on at `isDue`'s pace — what a
    /// row may no longer do is promise the text for later.
    static func hasFailedRepeatedly(on memoryID: String) -> Bool {
        failures(for: memoryID) >= limit
    }

    /// How long the app waits after the n-th failure before asking again:
    /// nothing before the third, a day after it, doubling with each one, and
    /// never more than `longestWait`.
    static func wait(afterFailure count: Int) -> TimeInterval {
        guard count >= limit else { return 0 }
        // Bounded before it is raised, so that a tally in the hundreds cannot
        // overflow its way back to zero.
        let doublings = min(count - limit, 10)
        return min(firstWait * pow(2, Double(doublings)), longestWait)
    }

    /// Whether the catch-up should upload this recording now.
    static func isDue(_ memoryID: String, now: Date = Date()) -> Bool {
        let count = failures(for: memoryID)
        guard count >= limit else { return true }
        guard let last = lastFailure(for: memoryID) else { return true }
        let since = now.timeIntervalSince(last)
        // A last failure in the future is a clock that has been set back. One
        // attempt now puts the record straight, rather than waiting it out.
        return since < 0 || since >= wait(afterFailure: count)
    }

    static func recordFailure(_ memoryID: String, at now: Date = Date()) {
        var counts = UserDefaults.standard.dictionary(forKey: countKey) ?? [:]
        counts[memoryID] = failures(for: memoryID) + 1
        UserDefaults.standard.set(counts, forKey: countKey)
        var whens = UserDefaults.standard.dictionary(forKey: whenKey) ?? [:]
        whens[memoryID] = now.timeIntervalSince1970
        UserDefaults.standard.set(whens, forKey: whenKey)
    }

    /// Written out twice rather than as a loop over the two keys, because
    /// `device-wipe-check.mjs` reads every `forKey:` in this file by name and
    /// holds `reset()` to clearing each one — a loop variable is a key it
    /// cannot find a reset for.
    static func clear(_ memoryID: String) {
        if var counts = UserDefaults.standard.dictionary(forKey: countKey), counts[memoryID] != nil {
            counts.removeValue(forKey: memoryID)
            UserDefaults.standard.set(counts, forKey: countKey)
        }
        if var whens = UserDefaults.standard.dictionary(forKey: whenKey), whens[memoryID] != nil {
            whens.removeValue(forKey: memoryID)
            UserDefaults.standard.set(whens, forKey: whenKey)
        }
    }

    /// Part of "Tyhjennä tämä laite", like the ladder's own reset: this counts
    /// attempts made by whoever holds the phone, and it leaves with them.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: whenKey)
    }
}
