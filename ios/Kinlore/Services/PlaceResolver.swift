import Foundation

/// Fills in the coordinates of the places a family has talked about.
///
/// The archive stores places the way they were told: a name somebody said out
/// loud, "Puumala", "Sortavala", "Kannus". This walks the confirmed ones nobody
/// has looked up and caches the point on the subject, so that the places in a
/// family's memories can one day be drawn on a map without anybody being asked
/// to pin anything. The lookup itself is `PlaceLookup`; what is here is the
/// part that touches the archive. Confirmed only: `placesAwaitingCoordinates`
/// says why.
///
/// See docs/ARCHITECTURE.md §18 — including what a stored point does NOT mean.
@MainActor
final class PlaceResolver {
    /// Names nothing recognised. Kept for the run rather than on disk: a miss
    /// says something about the gazetteer, not about the archive, and a village
    /// that has been renamed since 1944 must not cost a lookup on every sweep.
    /// Forgetting them at launch is deliberate — the last failure may have been
    /// the network.
    private var missed: Set<String> = []
    private var isRunning = false

    /// Looks up the places that do not have coordinates yet.
    ///
    /// Serial, paced and capped. MapKit throttles a caller that asks in a burst,
    /// and a throttled reply is indistinguishable from "no such place" — which
    /// would poison `missed` for names that are perfectly good. Nothing on
    /// screen is waiting for any of this, so slow is free.
    func resolvePending(in store: MemoryStore, limit: Int = 8) async {
        guard !isRunning else { return }
        #if DEBUG
        // A seeded archive is a fixture, and its places are props: the demo
        // family's "Puumala" is not a place anybody told us about. A UI test run
        // launches the app dozens of times, and looking that name up on every
        // one of them would put a network request inside a measurement that is
        // supposed to be about contrast and tap targets.
        if UserDefaults.standard.string(forKey: "seed") != nil { return }
        #endif
        isRunning = true
        defer { isRunning = false }

        var isFirst = true
        for subject in store.placesAwaitingCoordinates().prefix(limit) {
            let key = subject.title.lowercased()
            guard !missed.contains(key) else { continue }
            if !isFirst { try? await Task.sleep(for: .milliseconds(400)) }
            isFirst = false
            guard let place = await PlaceLookup.find(subject.title) else {
                missed.insert(key)
                continue
            }
            store.setPlace(subjectID: subject.id, place: place)
        }
    }
}
