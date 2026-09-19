import Foundation

// Carved out of `DeferredMemory.swift` on 19 Sep 2026 so that it can be run.
// Nothing about the decision changed, and it is still the tally the catch-up
// keeps — but the file it lived in reaches `MemoryStore`, `MediaStore` and
// `MediaLoader`, all three of which import UIKit, so a command-line build on
// this machine cannot compile it and `transcription-catchup-check.swift` would
// have had to measure a stand-in for every collaborator instead. Which is the
// move `budget.ts` made on the backend for the same reason, and for the same
// gain: forty-five lines with no imports of their own can simply be executed.

/// How often this device has tried and failed to make text out of one
/// recording.
///
/// Device-local, in `UserDefaults`, for the same reason the ladder's comfort is
/// (§12): it describes this phone's attempts rather than a fact about the
/// family's archive. A count that synced would let one phone's bad afternoon
/// stop another phone from ever trying.
@MainActor
enum TranscriptionAttempts {
    /// Three, and then the app stops asking about that recording.
    ///
    /// Every attempt uploads the whole recording and is paid for whether or not
    /// any words come back, so audio that cannot be transcribed — silence, or
    /// speech the hallucination guard refuses — would otherwise cost the family
    /// minutes on every launch for as long as the memory exists. Three is
    /// forgiving enough that a provider having a bad hour does not lose a
    /// transcript, and small enough that nothing is paid for indefinitely.
    static let limit = 3

    private static let key = "transcription-failures"

    static func failures(for memoryID: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: key)?[memoryID] as? Int) ?? 0
    }

    /// The app has stopped trying. The audio is still kept and still exported —
    /// giving up on the text is not giving up on the recording.
    static func hasGivenUp(on memoryID: String) -> Bool {
        failures(for: memoryID) >= limit
    }

    static func recordFailure(_ memoryID: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[memoryID] = failures(for: memoryID) + 1
        UserDefaults.standard.set(all, forKey: key)
    }

    static func clear(_ memoryID: String) {
        guard var all = UserDefaults.standard.dictionary(forKey: key),
              all[memoryID] != nil
        else { return }
        all.removeValue(forKey: memoryID)
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Part of "Tyhjennä tämä laite", like the ladder's own reset: this counts
    /// attempts made by whoever holds the phone, and it leaves with them.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
