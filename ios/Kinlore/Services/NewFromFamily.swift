import Foundation

/// What the family told while this phone was away.
///
/// The reading half of the app's promise, facing the other direction from
/// `SyncNote`: outgoing visibility says "did what I told get through", this
/// says "what came while I was not looking". PLAN §4.1 names the hole —
/// cutting the guessing round left nothing that gives a family a reason to
/// open a memory that is already written, and *"a family archive dies unread
/// more often than unrecorded"*. This is the smallest instrument that answers
/// it: a section that exists when there is something and does not when there
/// is not, and a landing that follows it. See docs/UX.md §6.
///
/// Seen-ness is a device-local list of telling ids, like the ladder's comfort
/// (§12) and the upsell rhythm — it describes the person holding the phone,
/// and what a family member has or has not read is not the family's data. It
/// is a list rather than a sync cursor because a `Memory` row carries no `seq`
/// on the device, and at this archive's scale — hundreds of rows, not
/// hundreds of thousands — a list is the simpler honest instrument.
///
/// **The first visit defines the baseline rather than showing everything.**
/// With no baseline there is nothing to be new *since*: a fresh joiner's
/// whole archive is new in a different sense, and the arrival state
/// (docs/UX.md §4.3) is what frames that. "Tyhjennä tämä laite" clears the
/// list with the rest of what this phone knows.
@MainActor
enum NewFromFamily {
    static let seenKey = "memories.seen"

    /// Tellings by other members this phone has not seen, newest first.
    ///
    /// "By other members" is exactly `authorID != me`, with nil excluded: a
    /// locally created memory has no author id until the server assigns one
    /// (`Models.swift`), and a telling made on this phone is not news to it.
    static func unseen(in store: MemoryStore, me: String) -> [Memory] {
        guard let seen = UserDefaults.standard.stringArray(forKey: seenKey).map(Set.init) else {
            return []
        }
        return store.told
            .filter { $0.authorID != nil && $0.authorID != me && !seen.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// A visit to Muistot is what marks everything seen — no per-row read
    /// state, no debt carried between rows. Also what creates the baseline on
    /// the first visit ever.
    ///
    /// Every telling's id goes in, own ones included: they are filtered out
    /// by authorship on the way back anyway, and a list that mirrors `told`
    /// is easier to reason about than one that mirrors a filter of it.
    static func markAllSeen(in store: MemoryStore) {
        UserDefaults.standard.set(store.told.map(\.id), forKey: seenKey)
    }

    /// Part of emptying the device, beside the ladder's and the rhythm's.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }
}
