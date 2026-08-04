// Re-measures the place lookup against the claims in docs/ARCHITECTURE.md §18.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/geo-check scripts/geo-check.swift \
//     ios/Memorize/Services/PlaceLookup.swift && /tmp/geo-check
//
// §18 says three things that are not about this app at all: that a Finnish
// municipality resolves to itself, that Karelian places resolve across the
// border rather than being dragged into Finland, and that the lookup answers
// confidently wrong for a name that is both a region and a village. All three
// are claims about somebody else's gazetteer, and they can stop being true
// without a line of this repo changing — which is the failure mode a document
// has: it goes on being believed.
//
// It compiles the REAL ios/Memorize/Services/PlaceLookup.swift. The two types
// below are the minimum stubs that file needs, copied from Models.swift — the
// point is to exercise the shipping lookup, not a copy of it that can drift.
//
// NEEDS A NETWORK. Without one every lookup returns nil, which is reported as
// "unresolved" rather than quietly passing: a check that goes green offline
// would be worse than no check.
//
// It warns that `MKMapItem.placemark` is deprecated — in macOS 26, which is
// what this script is compiled for. The app builds for iOS 17 and does not
// warn. Do not "fix" it here; the replacement is iOS 26 only and the app's
// deployment target is nine versions below that.

import Foundation

enum GeoPrecision: String { case exact, town, region, unknown }

struct PlaceHint {
    var latitude: Double
    var longitude: Double
    var precision: GeoPrecision
}

/// One documented claim. `near` is checked at half a degree, which is loose
/// enough to survive a gazetteer nudging a municipality's centre and tight
/// enough that a different place fails.
struct Claim {
    let name: String
    let precision: GeoPrecision
    let near: (lat: Double, lon: Double)
    let says: String
}

let claims = [
    Claim(name: "Puumala", precision: .town, near: (61.52, 28.18),
          says: "a Finnish municipality resolves to itself"),
    Claim(name: "Sortavala", precision: .town, near: (61.70, 30.69),
          says: "Karelia resolves across the border, not into Finland"),
    Claim(name: "Viipuri", precision: .town, near: (60.71, 28.74),
          says: "the Finnish name of a city that is now Vyborg still finds it"),
    Claim(name: "Lappi", precision: .region, near: (66.51, 25.72),
          says: "a province comes back as a region, not as a pin"),
    Claim(name: "Mannerheimintie 1, Helsinki", precision: .exact, near: (60.17, 24.94),
          says: "a street address comes back exact"),
    // The warning, not the promise. If this one starts failing, the lookup has
    // got better and §18's second table needs rewriting — which is exactly what
    // a failure here is for.
    Claim(name: "Karjala", precision: .town, near: (60.84, 22.00),
          says: "an ambiguous name still resolves to a village, confidently and "
              + "with a single result, rather than to the region a grandmother means"),
]

@main
enum GeoCheck {
    static func main() async {
        var failures = 0
        var unresolved = 0

        for claim in claims {
            guard let hint = await PlaceLookup.find(claim.name) else {
                unresolved += 1
                print("  ??   \(claim.name): unresolved — no network, or the name is gone")
                continue
            }
            let off = max(abs(hint.latitude - claim.near.lat), abs(hint.longitude - claim.near.lon))
            let placed = off <= 0.5
            let precise = hint.precision == claim.precision
            let mark = placed && precise ? "ok  " : "FAIL"
            if !(placed && precise) { failures += 1 }
            print(String(
                format: "  %@ %@ → %.3f, %.3f %@ — %@",
                mark, claim.name, hint.latitude, hint.longitude,
                hint.precision.rawValue, claim.says
            ))
            if !placed { print("       expected near \(claim.near.lat), \(claim.near.lon)") }
            if !precise { print("       expected precision \(claim.precision.rawValue)") }
            // Paced, because MapKit throttles a burst and a throttled reply
            // looks exactly like "no such place".
            try? await Task.sleep(for: .milliseconds(400))
        }

        if unresolved > 0 {
            print("\n\(unresolved) unresolved. Check the network before believing this run.")
        }
        print(failures == 0 && unresolved == 0
            ? "\nall claims still hold"
            : "\n\(failures) failed — docs/ARCHITECTURE.md §18 needs rereading")
        exit(failures == 0 && unresolved == 0 ? 0 : 1)
    }
}
