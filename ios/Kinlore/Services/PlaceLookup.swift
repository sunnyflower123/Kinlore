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
/// **What leaves the device is the place name and nothing else** — or, from
/// the family's map, what somebody typed into its search. Not the memory, not
/// the transcript, not who told it, and never where the phone is. The same
/// boundary rule 7 draws around the Worker, applied to Apple's servers.
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

    /// One answer to a name somebody typed on the family's map
    /// (`PlaceSearchSheet`): what the row says, and the point with how much
    /// of it the answer pinned down.
    struct Found: Identifiable {
        let id = UUID()
        let name: String
        let detail: String?
        let hint: PlaceHint
    }

    /// Everything a typed name matches, best first, within the same bias as
    /// `find`. Nil when the search itself failed — no network, most often —
    /// which is a different answer from an empty list, and the sheet says
    /// which: "nothing by that name" and "the search did not get through"
    /// ask the person for different things.
    ///
    /// MapKit reports "nothing found" as an error of its own
    /// (`MKError.placemarkNotFound`) rather than as an empty answer, so that
    /// one error is read as the empty list and every other as a failure.
    /// An answer with no precision at all is left out: a row that places
    /// nothing is not an answer.
    static func search(_ query: String) async -> [Found]? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "placeSearch") {
        case "stub": return stubbedResults
        case "failing": return nil
        default: break
        }
        #endif
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = searchRegion
        request.resultTypes = .address

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch {
            return nil
        }
        return response.mapItems.compactMap { item in
            guard let coordinate = item.placemark.location?.coordinate else { return nil }
            let precision = precision(of: item.placemark)
            guard precision != .unknown else { return nil }
            let name = item.name ?? item.placemark.title ?? query
            let title = item.placemark.title
            return Found(
                name: name,
                detail: title == name ? nil : title,
                hint: PlaceHint(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    precision: precision
                )
            )
        }
    }

    #if DEBUG
    /// `-placeSearch stub`: three answers, one of each precision a search
    /// can give, whatever was typed — a real search needs a network and
    /// answers differently from one day to the next. `-placeSearch failing`
    /// is the search that did not get through.
    private static let stubbedResults = [
        Found(
            name: "Koivulantie 12", detail: "52200 Puumala",
            hint: PlaceHint(latitude: 61.5302, longitude: 28.1655, precision: .exact)
        ),
        Found(
            name: "Puumala", detail: "Etelä-Savo",
            hint: PlaceHint(latitude: 61.5236, longitude: 28.1811, precision: .town)
        ),
        Found(
            name: "Etelä-Savo", detail: "Suomi",
            hint: PlaceHint(latitude: 61.69, longitude: 27.27, precision: .region)
        ),
    ]
    #endif

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
