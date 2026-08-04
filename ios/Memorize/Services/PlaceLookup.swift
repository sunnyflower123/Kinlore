import Foundation
import MapKit

/// A place name in, a point out. No archive around it.
///
/// Split from `PlaceResolver` on purpose: everything here is a claim about a
/// gazetteer rather than about this app, and claims about the outside world go
/// stale. `scripts/geo-check.swift` compiles THIS file and re-measures the table
/// in docs/ARCHITECTURE.md §18 against the shipping code, so the document can be
/// caught being wrong instead of being believed.
///
/// MapKit rather than a service of our own: no API key, no quota to meter, no
/// Worker round trip, and **no location permission** — looking a name up is not
/// asking where the phone is, so `Info.plist` gains nothing and the 80-year-old
/// is asked nothing.
///
/// **What leaves the device is the place name and nothing else.** Not the
/// memory, not the transcript, not who told it. The same boundary rule 7 draws
/// around the Worker, applied to Apple's servers.
enum PlaceLookup {
    /// Roughly Finland plus the parts of Karelia this generation talks about.
    /// A bias, not a filter: a place outside it still resolves, it only loses to
    /// a nearer match of the same name. Without it "Puumala" is as likely to
    /// land in Indonesia as in Etelä-Savo, and with it Sortavala and Viipuri
    /// still resolve where they actually are, across the border.
    static let searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 63.5, longitude: 27.0),
        span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 24)
    )

    static func find(_ name: String) async -> PlaceHint? {
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
    static func precision(of placemark: CLPlacemark) -> GeoPrecision {
        if placemark.thoroughfare != nil { return .exact }
        if placemark.locality != nil || placemark.subLocality != nil { return .town }
        if placemark.administrativeArea != nil || placemark.country != nil { return .region }
        return .unknown
    }
}
