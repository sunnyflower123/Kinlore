// The paper round a print, found without a photograph — checked on prints drawn here.
//
// `PrintBorder` cuts the album's picture of an old print out of its paper, and
// both ways of being wrong are silent. A border it misses leaves the card as it
// was; a picture it takes for paper loses a strip of somebody's face on a card
// that still looks like a photograph. So every print here is drawn, with its
// paper exactly where the drawing says, and the answer is measured against the
// drawing rather than against the detector's own idea of paper:
//
//   1. **Paper on four sides is cut away**, and none of it is left on the card:
//      deckled edge, stains, a print scanned a degree askew, cream paper in
//      colour, and a thumbnail twice the size, which is cut at the same place.
//   2. **Nothing else is paper.** A photograph with no border, paper on three
//      sides, a small print on a large sheet, a hairline, a print lying on a
//      dark table, a pale vignette, a bright sky, snow and a white page are
//      all left whole.
//
// The video's own prints are not in this repository. Measured on them on
// 28 Sep 2026, the five with a border were cut, and the two without and the
// six pictures of the design the album follows were left whole.
//
// Costs nothing: no simulator, no network.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/print-border-check scripts/print-border-check.swift \
//     ios/Kinlore/Services/PrintBorder.swift && /tmp/print-border-check

import CoreGraphics
import Foundation

@main
struct PrintBorderCheck {
    nonisolated(unsafe) static var failures = 0

    static func check(_ what: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(what)")
        } else {
            failures += 1
            print("  FAIL \(what)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func main() {
        print("— paper on four sides is cut away —")
        let landscape = Print().drawn()
        let small = cut("a landscape print with a deckled edge", landscape)
        cut("a portrait print", Print(width: 400, height: 600, top: 0.06, left: 0.08, bottom: 0.10, right: 0.07).drawn())
        cut("a print cut straight, with no deckle", Print(deckle: false).drawn())
        cut("a print scanned a degree askew", Print(tilt: 1).drawn())
        cut("a colour print on cream paper", Print(colour: true).drawn())
        let large = cut("the same print at 1,200 pixels", Print(width: 1200, height: 800).drawn())
        if let small, let large {
            let apart = [
                abs(large.minX / 1200 - small.minX / 600), abs(large.maxX / 1200 - small.maxX / 600),
                abs(large.minY / 800 - small.minY / 400), abs(large.maxY / 800 - small.maxY / 400),
            ].max() ?? 1
            check(
                "and is cut at the same place",
                apart <= 0.005,
                String(format: "%.2f %% of a side apart", apart * 100)
            )
        }

        print("\n— nothing else is paper —")
        let photograph = Print(top: nil, left: nil, bottom: nil, right: nil).drawn().image
        whole("a photograph with no paper", photograph)
        whole("paper on three sides", Print(bottom: nil).drawn().image)
        whole("a small print on a large sheet", Print(top: 0.2, left: 0.2, bottom: 0.2, right: 0.2).drawn().image)
        whole("a hairline", Print(top: 0.005, left: 0.005, bottom: 0.005, right: 0.005, deckle: false).drawn().image)
        whole("a print lying on a dark table", Print(table: 0.04).drawn().image)
        // Light, but not paper-light all the way along: a studio portrait's
        // pale vignette is the photograph's own, on all four sides.
        whole("a portrait in a pale vignette", drawn(600, 400) { x, y in
            min(x, 599 - x, y, 399 - y) < 24 ? 200 + UInt8(noise(x, y, 6) % 41) : Print.photograph(x, y, 6)
        })
        whole("a bright sky", drawn(600, 400) { x, y in
            y < 40 ? 230 + UInt8(noise(x, y, 7) % 21) : Print.photograph(x, y, 7)
        })
        whole("snow", drawn(600, 400) { x, y in 180 + UInt8(noise(x, y, 8) % 76) })
        whole("a field of snow under a tree line", drawn(600, 400) { x, y in
            (160 ..< 240).contains(y) ? 40 + UInt8(noise(x / 4, y / 4, 9) % 60) : 225 + UInt8(noise(x, y, 9) % 31)
        })
        whole("a white page", drawn(600, 400) { x, y in 236 + UInt8(noise(x, y, 10) % 12) })

        print("\n— what the album is handed —")
        check("a photograph with no paper comes back as itself", PrintBorder.trimmed(photograph) === photograph)
        let trimmed = PrintBorder.trimmed(landscape.image)
        check(
            "a print comes back at the size of its picture",
            small.map { Int($0.width) == trimmed.width && Int($0.height) == trimmed.height } == true,
            "\(trimmed.width) × \(trimmed.height)"
        )

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// A print whose paper must go: some answer, no paper pixel inside it, and
    /// no more of the picture lost than the detector's margin and three pixels
    /// a side. Askew, the picture is a turned rectangle and its straight
    /// sides are the drawing's; only the first two conditions are asked.
    @discardableResult
    static func cut(_ what: String, _ drawing: Print.Drawing) -> CGRect? {
        let print = drawing.print
        guard let found = PrintBorder.picture(in: drawing.image) else {
            check(what, false, "left whole")
            return nil
        }
        var paper = 0
        for y in Int(found.minY) ..< Int(found.maxY) {
            for x in Int(found.minX) ..< Int(found.maxX) where drawing.kinds[y * print.width + x] != .picture {
                paper += 1
            }
        }
        let picture = print.picture
        let inset = (PrintBorder.margin * Double(max(print.width, print.height))).rounded(.up) + 3
        let lost = [
            found.minX - picture.minX, picture.maxX - found.maxX,
            found.minY - picture.minY, picture.maxY - found.maxY,
        ].max() ?? 0
        check(
            what,
            paper == 0 && (print.tilt != 0 || lost <= inset),
            "\(paper) pixels of paper left, \(Int(lost)) of the picture lost at the most"
        )
        return found
    }

    static func whole(_ what: String, _ image: CGImage) {
        let found = PrintBorder.picture(in: image)
        check(what, found == nil, found.map { "cut to \($0)" } ?? "")
    }

    /// A grey image drawn pixel by pixel, row 0 at the top — as RGB, because
    /// a phone's thumbnail is a colour JPEG even of a black-and-white print.
    static func drawn(_ width: Int, _ height: Int, _ luma: (Int, Int) -> UInt8) -> CGImage {
        image(width, height) { x, y in let v = luma(x, y); return (v, v, v) }
    }

    static func image(_ width: Int, _ height: Int, _ rgb: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let (r, g, b) = rgb(x, y)
                let i = (y * width + x) * 4
                bytes[i] = r
                bytes[i + 1] = g
                bytes[i + 2] = b
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

func clamped(_ value: Int) -> UInt8 { UInt8(max(0, min(255, value))) }

/// The same noise on every run and every machine.
func noise(_ x: Int, _ y: Int, _ seed: UInt64) -> UInt64 {
    var h = UInt64(truncatingIfNeeded: x) &* 0x9E37_79B9_7F4A_7C15
    h ^= UInt64(truncatingIfNeeded: y) &* 0xC2B2_AE3D_27D4_EB4F
    h ^= seed &* 0x1656_67B1_9E37_79F9
    h ^= h >> 33
    h = h &* 0xFF51_AFD7_ED55_8CCD
    h ^= h >> 33
    h = h &* 0xC4CE_B9FE_1A85_EC53
    return h ^ (h >> 33)
}

/// A print as a scanner or a phone's crop hands it over: white canvas at the
/// very edge, the dark line a deckled edge casts, paper, and the photograph
/// inside, each exactly where these numbers put it.
struct Print {
    enum Kind { case canvas, deckle, table, paper, picture }

    var width = 600
    var height = 400
    /// Paper on each side as a share of that side; nil where the picture runs
    /// to the edge.
    var top: Double? = 0.07
    var left: Double? = 0.05
    var bottom: Double? = 0.09
    var right: Double? = 0.06
    var deckle = true
    /// Degrees the picture is turned inside its paper.
    var tilt = 0.0
    var colour = false
    /// A dark table round the whole print, as a share of each side.
    var table = 0.0

    /// The picture before any tilt, in pixels from the top-left corner.
    var picture: CGRect {
        let w = Double(width), h = Double(height)
        let x0 = (left ?? 0) * w, y0 = (top ?? 0) * h
        return CGRect(x: x0, y: y0, width: w - (right ?? 0) * w - x0, height: h - (bottom ?? 0) * h - y0)
    }

    func kind(_ x: Int, _ y: Int) -> Kind {
        let tableX = Int(table * Double(width)), tableY = Int(table * Double(height))
        if min(x, width - 1 - x) < tableX || min(y, height - 1 - y) < tableY { return .table }
        if deckle {
            // Per side with paper: canvas to a jagged depth, then two dark
            // pixels, then paper. A side the picture runs to has neither.
            let sides: [(Double?, Int, Int, Int)] = [
                (left, x - tableX, y, width), (right, width - 1 - x - tableX, y, width),
                (top, y - tableY, x, height), (bottom, height - 1 - y - tableY, x, height),
            ]
            for (paper, depth, along, length) in sides where paper != nil {
                let canvas = max(1, length / 100) + Int(noise(along / 8, length, 3) % 3)
                if depth < canvas { return .canvas }
                if depth < canvas + 2 { return .deckle }
            }
        }
        let cx = Double(width) / 2, cy = Double(height) / 2, turn = -tilt * .pi / 180
        let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
        let u = cx + dx * cos(turn) - dy * sin(turn), v = cy + dx * sin(turn) + dy * cos(turn)
        return picture.contains(CGPoint(x: u, y: v)) ? .picture : .paper
    }

    /// Blocks of six pixels, most of them the mid-tones of a photograph and one
    /// in eight as light as paper, so that a line of picture is never all dark.
    static func photograph(_ x: Int, _ y: Int, _ seed: UInt64) -> UInt8 {
        let n = noise(x / 6, y / 6, seed)
        return n % 8 == 0 ? 215 + UInt8(n / 8 % 36) : 30 + UInt8(n / 8 % 170)
    }

    /// The print drawn once, with what each of its pixels is.
    struct Drawing {
        let print: Print
        let image: CGImage
        let kinds: [Kind]
    }

    func drawn() -> Drawing {
        var kinds: [Kind] = []
        kinds.reserveCapacity(width * height)
        for y in 0 ..< height {
            for x in 0 ..< width { kinds.append(kind(x, y)) }
        }
        let image = PrintBorderCheck.image(width, height) { x, y in
            let n = noise(x, y, 5)
            switch kinds[y * width + x] {
            case .canvas: return (254, 254, 254)
            case .deckle: let v = 140 + UInt8(n % 40); return (v, v, v)
            case .table: let v = 40 + UInt8(n % 30); return (v, v - 8, v - 16)
            case .paper:
                // One pixel in sixteen a stain, darker than paper-light.
                let v = n % 16 == 0 ? 190 + UInt8(n / 16 % 20) : 218 + UInt8(n / 16 % 25)
                return colour ? (min(255, v + 10), v, v - 20) : (v, v, v)
            case .picture:
                let v = Self.photograph(x, y, 1)
                guard colour else { return (v, v, v) }
                // Warm or cool by the block, about as light as the grey.
                let tint = Int(noise(x / 6, y / 6, 2) % 40) - 20
                return (clamped(Int(v) + tint), v, clamped(Int(v) - tint))
            }
        }
        return Drawing(print: self, image: image, kinds: kinds)
    }
}
