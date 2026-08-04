import Foundation
import MapKit

/// Turns a place's name into coordinates.
///
/// The archive stores places the way they were told: a name somebody said out
/// loud, "Puumala", "Sortavala", "Kannus". This looks that name up and caches
/// the point on the subject, so that the places in a family's memories can one
/// day be drawn on a map without anybody being asked to pin anything.
///
/// MapKit rather than a service of our own: no API key, no Worker round trip,
/// no quota to meter, and no location permission — looking a name up is not
/// asking where the phone is, so nothing is added to `Info.plist` and nothing is
/// asked of an 80-year-old.
///
/// **What leaves the device is the place name and nothing else.** Not the
/// memory, not the transcript, not who told it. That is the same boundary rule 7
/// draws around the Worker, applied to Apple's servers.
@MainActor
final class PlaceResolver {
    /// Roughly Finland plus the parts of Karelia this generation talks about.
    /// A bias, not a filter: a place outside it still resolves, it only loses to
    /// a nearer match of the same name. Without it "Puumala" is as likely to
    /// land in Indonesia as in Etelä-Savo.
    private static let searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 63.5, longitude: 27.0),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 24)
    )

    /// Names nothing recognised. Kept for the run rather than on disk: a miss
    /// says something about the gazetteer, not about the archive, and a village
    /// that has been renamed since 1944 must not cost a lookup on every sweep.
    /// Forgetting them at launch is deliberate — the last failure may have been
    /// the network.
    private var missed: Set<String> = []
    private var isRunning = false

    /// Looks up the places that do not have coordinates yet.
    ///
    /// Serial and capped. MapKit throttles a caller that asks in a burst, and
    /// the reply to a throttled request is indistinguishable from "no such
    /// place" — which would poison `missed` for names that are perfectly good.
    /// There is nothing waiting on the result, so slow is free.
    func resolvePending(in store: MemoryStore, limit: Int = 8) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        for subject in store.placesAwaitingCoordinates().prefix(limit) {
            let key = subject.title.lowercased()
            guard !missed.contains(key) else { continue }
            guard let place = await Self.lookUp(subject.title) else {
                missed.insert(key)
                continue
            }
            store.setPlace(subjectID: subject.id, place: place)
        }
    }

    private static func lookUp(_ name: String) async -> PlaceHint? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = searchRegion
        // Addresses, not points of interest: "Puumala" has to resolve to the
        // municipality, not to a hairdresser that happens to carry the name.
        request.resultTypes = .address

        guard let response = try? await MKLocalSearch(request: request).start(),
              let placemark = response.mapItems.first?.placemark,
              let coordinate = placemark.location?.coordinate
        else { return nil }

        return PlaceHint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            precision: precision(of: placemark)
        )
    }

    /// How much of the name the lookup actually pinned down.
    ///
    /// Read off what came back rather than assumed: the same query returns a
    /// street for one name and a whole province for another, and the difference
    /// is exactly what must not be flattened. A point with no locality above it
    /// is a region — "Lappi" is an answer, and it is not a pin.
    private static func precision(of placemark: CLPlacemark) -> GeoPrecision {
        if placemark.thoroughfare != nil { return .exact }
        if placemark.locality != nil || placemark.subLocality != nil { return .town }
        if placemark.administrativeArea != nil || placemark.country != nil { return .region }
        return .unknown
    }
}
