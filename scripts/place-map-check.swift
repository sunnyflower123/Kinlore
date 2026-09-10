// Checks what a place's map is allowed to draw.
//
// A place subject carries a point and how sure the gazetteer was about it
// (`PlaceHint`, `GeoPrecision`). `PlaceMapCard` turns that into a drawing, and
// every way of being wrong here is silent: a pin on one house inside a
// municipality looks exactly as confident as a pin on the right doorstep, and
// a place nobody could find, drawn at any span at all, is a map of somewhere
// the archive was never told about. Nothing about either fails a build, and
// neither shows up in a screenshot unless you already know the answer.
//
// That is rule 5 — uncertainty is stored, not rounded — on the one screen that
// turns it into a picture. Run it after touching `GeoPrecision` or
// `PlaceMapCard`. It needs no simulator, no network and no key.
//
//   swiftc -parse-as-library -o /tmp/place-map-check \
//     scripts/place-map-check.swift ios/Kinlore/Model/Models.swift

import Foundation

@main
enum PlaceMapCheck {
    static func main() {
        var failures = 0

        func check(_ label: String, _ ok: Bool) {
            if ok {
                print("  ok   \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)")
            }
        }

        print("— what may be drawn —")
        check(
            "a place nobody could find has no map at all",
            GeoPrecision.unknown.mapSpanMetres == nil
        )
        for precision in [GeoPrecision.exact, .town, .region] {
            check(
                "\(precision.rawValue) has a span",
                precision.mapSpanMetres != nil
            )
        }

        print("\n— only a point may be drawn as a point —")
        check("an exact answer earns the pin", GeoPrecision.exact.deservesAPin)
        check("a municipality does not", !GeoPrecision.town.deservesAPin)
        check("a region does not", !GeoPrecision.region.deservesAPin)
        check("and neither does an unknown", !GeoPrecision.unknown.deservesAPin)

        print("\n— the spans widen with the doubt —")
        let exact = GeoPrecision.exact.mapSpanMetres ?? 0
        let town = GeoPrecision.town.mapSpanMetres ?? 0
        let region = GeoPrecision.region.mapSpanMetres ?? 0
        check("a town is wider than an address", town > exact)
        check("a region is wider than a town", region > town)
        // A Finnish municipality is tens of kilometres across, and the circle
        // the view draws is a third of the span. Any narrower and the drawing
        // claims a neighbourhood out of an answer that named a parish.
        check("a town's circle is at least 4 km across", town / 3 >= 4_000)
        check("a region's circle is at least 20 km across", region / 3 >= 20_000)
        // And not so wide that "exact" stops meaning anything: at more than a
        // few kilometres a pin is decoration on a county.
        check("an exact answer stays under 3 km", exact <= 3_000)

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
