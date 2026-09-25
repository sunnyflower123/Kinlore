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
@Observable
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
        guard !isRunning, !isFixture else { return }
        isRunning = true
        defer { isRunning = false }

        var isFirst = true
        for subject in store.placesAwaitingCoordinates().prefix(limit) {
            if !isFirst { try? await Task.sleep(for: .milliseconds(400)) }
            isFirst = false
            await lookUp(subject, in: store)
        }
    }

    /// Looks one place up because a screen is waiting for that one.
    ///
    /// The sweep above runs at launch and on the return to the foreground,
    /// which are both the wrong moment for the place somebody confirmed a
    /// minute ago: the card was reachable from Albumi and the map under its
    /// name was not, until the app had been left and opened again. That looks
    /// exactly like a map that does not work. Opening the card now asks for
    /// the answer the card exists to show.
    ///
    /// Neither paced nor held back by a sweep in progress, and both on
    /// purpose: this is one request, and it is the only one anybody is
    /// looking at.
    func resolve(_ subject: Subject, in store: MemoryStore) async {
        guard !isFixture,
              subject.kind == .place,
              subject.confirmed,
              subject.place == nil,
              !subject.title.isEmpty
        else { return }
        await lookUp(subject, in: store)
    }

    /// One name, one lookup, one write. Both callers go through here so that
    /// `missed` means the same thing whichever of them asked.
    ///
    /// The write asks again whether the place still has no point, because
    /// the lookup is a network round trip and a person is faster than it:
    /// the card that asked for the answer also offers "Merkitse kartalle",
    /// and a point somebody put there while the gazetteer was thinking is
    /// their word, which a municipality's centre arriving a second later
    /// must not replace (§18). The same holds for a title corrected in the
    /// meantime, whose answer this no longer is.
    private func lookUp(_ subject: Subject, in store: MemoryStore) async {
        let key = subject.title.lowercased()
        guard !missed.contains(key) else { return }
        guard let place = await PlaceLookup.find(subject.title) else {
            missed.insert(key)
            return
        }
        guard let current = store.subject(id: subject.id),
              current.id == subject.id,
              current.place == nil,
              current.title == subject.title
        else { return }
        store.setPlace(subjectID: subject.id, place: place)
    }

    /// Whether the archive on this device is a fixture rather than a family's.
    ///
    /// A seeded archive's places are props: the demo family's "Puumala" is not
    /// a place anybody told us about. A UI test run launches the app dozens of
    /// times, and looking that name up on every one of them would put a
    /// network request inside a measurement that is supposed to be about
    /// contrast and tap targets.
    private var isFixture: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "seed") != nil
        #else
        false
        #endif
    }
}
