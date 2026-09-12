import Foundation

/// What to put in front of somebody who has not been asked anything.
///
/// The Kerro tab used to open on *"Kerro mitä muistat"* and a button, which is
/// a blank page — the most reliable way there is to get nothing from anybody,
/// and especially from a person who does not believe they remember anything
/// worth saying. The app already knew this: the question ladder exists because
/// *answering* a question is easy and *telling something* is hard. But the
/// ladder only has questions once there is something to ask about, so on the
/// screen that matters most it had nothing and fell back to the blank button.
///
/// A photograph is a question that needs no writing. This picks the next one.
///
/// **It is a derivation, not a new surface.** The Tell screen has been able to
/// open on a subject since it was written — that is what `target` is, and it is
/// what makes the title *"Kerro tästä kuvasta"* and the starter *"Kuka tässä
/// kuvassa on?"* appear. All that was missing was somebody choosing the
/// subject when nobody had navigated to one. So this adds no screen, no tab and
/// no state: it answers one question, *which card*.
///
/// **The skips are device-local**, like the ladder's comfort and the seen list
/// in `NewFromFamily`, and for the same reason: *"she does not recognise this
/// one"* describes the person holding the phone, not the family. Her sister
/// should still be asked.
@MainActor
enum Deck {
    static let skippedKey = "deck.skipped"

    /// How many cards may be pushed aside before the deck stops offering them.
    ///
    /// This is the failure mode the whole idea has to be designed against, and
    /// it is a silent one: nothing crashes, she simply meets five photographs
    /// she does not recognise in a row and concludes that an app built to tell
    /// her she remembers a great deal has decided otherwise. The ladder already
    /// holds the same opinion in numbers — one strained answer costs a whole
    /// level, because for this user one wall costs more than a run of easy
    /// questions — and this is the same instinct with a smaller counter.
    ///
    /// Per session and never stored: tomorrow is a new day, and a phone that
    /// remembered her bad evening for ever would be the wrong kind of memory.
    static let patience = 3

    private static var skipsThisSession = 0

    /// The next thing worth asking about, or nil when there is nothing — which
    /// is a real answer and not a failure. The screen falls back to the blank
    /// button it has always had, and an archive with nothing left to ask about
    /// is an archive somebody has told a great deal into.
    ///
    /// Photographs, and nothing else. A photograph asks without a name in it —
    /// the picture does the remembering — and it is something a person in the
    /// family put here on purpose.
    ///
    /// **People were cards too until 12 Sep 2026**, ranked after the
    /// photographs, and a person's card is a name and a question: *"Kerro
    /// hänestä – Toivo"*, *"Kuka Toivo oli sinulle?"*. The names that reach
    /// this table arrive mostly from the extraction, unconfirmed, and the
    /// founder met exactly that on the second launch — a name nobody had
    /// vouched for, asked about as if it were somebody. Rule 4 says an
    /// unconfirmed name is never fact; the front screen asserting it as a
    /// subject was the same mistake one step earlier. What this costs is a
    /// deck that runs out sooner, and nil is a real answer here.
    static func next(in store: MemoryStore) -> Subject? {
        guard skipsThisSession < patience else { return nil }
        let skipped = Set(UserDefaults.standard.stringArray(forKey: skippedKey) ?? [])
        return store.subjects(of: .photo)
            .filter { store.isEmpty($0) }
            .first { !skipped.contains($0.id) }
    }

    /// *"En muista tätä."* Recorded rather than discarded: it is information,
    /// and the only thing worse than not asking is asking the same person the
    /// same unanswerable question every time they open the app.
    static func skip(_ subject: Subject) {
        skipsThisSession += 1
        var skipped = UserDefaults.standard.stringArray(forKey: skippedKey) ?? []
        guard !skipped.contains(subject.id) else { return }
        skipped.append(subject.id)
        UserDefaults.standard.set(skipped, forKey: skippedKey)
    }

    /// Part of emptying the device, beside the ladder's, the rhythm's and the
    /// seen list's — all of them records about the person holding the phone.
    static func reset() {
        skipsThisSession = 0
        UserDefaults.standard.removeObject(forKey: skippedKey)
    }
}
