import CoreGraphics

/// The paper round an old print, found so that the album can show the picture.
///
/// A print from the forties or fifties has a border of its own — a few
/// millimetres of white, cream or yellowed paper, often with a deckled edge —
/// and a scan or a photograph of the print keeps it. On a card in the album
/// that paper is the brightest thing on the screen. The video's five bordered
/// prints spend 7 to 18 per cent of their width on it, and on 28 Sep 2026 the
/// album read as a pile of scans beside the design the user had chosen, whose
/// pictures filled their cards.
///
/// Only the album's picture is cut. The photograph's own screen, the face
/// picker, the colouring and the export keep the whole print, paper and all:
/// the paper is part of the thing the family owns, and a date stamped on it is
/// sometimes the only one the print has.
///
/// A border is paper on all four sides, and nothing else is one. A bright sky,
/// a white wall or a field of snow reaches one or two edges of a photograph,
/// not all four with the picture starting a short, even way in from each, and
/// a print photographed lying on a table has the table round it rather than
/// paper. Either way the picture is left whole, which is what the album showed
/// before.
///
/// No UIKit, so `scripts/print-border-check.swift` compiles this file as it is.
enum PrintBorder {
    /// A pixel this light or lighter may be paper: 214 of 255. Measured
    /// 28 Sep 2026 on 600-pixel thumbnails of the video's prints, the
    /// yellowest paper averages 223 to 228 down a column, and the bright sky
    /// just inside it 208 to 210 along a row.
    static let paperLuma: UInt8 = 214

    /// A row or a column is paper when this share of it is paper-light. The
    /// yellowest paper's columns measure 0.86 to 0.97, stains and all.
    static let paperShare = 0.85

    /// And picture when less than this share is. That sky measures about a
    /// third, 0.32 to 0.38.
    static let pictureShare = 0.5

    /// The picture starts where this much of the side is picture, line after
    /// line: 3 per cent, 18 rows of a 600-pixel thumbnail. The dark line a
    /// deckled edge casts inside the paper is at most three on the video's
    /// prints, and the paper goes on past it.
    static let run = 0.03

    /// A border is 1 to 12 per cent of its side. The video's prints measure
    /// 3.5 to 9.4 per cent a side. Less than 1 is a light edge rather than
    /// paper, and more than 12 is a small print on a large sheet, or a
    /// photograph whose own light reaches its edges.
    static let narrowest = 0.01
    static let widest = 0.12

    /// At least this share of the lines before the picture are paper: 69 to
    /// 97 per cent on the video's prints. The rest are a deckle's shadow, and
    /// the wedge a print scanned askew leaves.
    static let mostlyPaper = 0.5

    /// Then a further 1 per cent in, so that neither the row where paper
    /// turns into picture nor that wedge is left as a pale edge on the card.
    static let margin = 0.01

    /// Where the picture is inside the print's paper, in the image's pixels
    /// counted from its top-left corner as `CGImage.cropping(to:)` counts
    /// them, or nil when the image has no border.
    static func picture(in image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width >= 32, height >= 32 else { return nil }
        // Grey, a byte a pixel: white, cream and yellowed paper are all
        // light, and lightness is all that tells paper from picture here.
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // The share of a line's pixels that are paper-light. Row 0 is the
        // top: a bitmap context keeps its first row of memory at the top of
        // what is drawn into it.
        func light(_ count: Int, _ pixel: (Int) -> UInt8) -> Double {
            var light = 0
            for i in 0 ..< count where pixel(i) >= paperLuma { light += 1 }
            return Double(light) / Double(count)
        }
        let row = { (y: Int) in light(width) { pixels[y * width + $0] } }
        let column = { (x: Int) in light(height) { pixels[$0 * width + x] } }

        guard let top = depth(of: height, row),
              let bottom = depth(of: height, { row(height - 1 - $0) }),
              let left = depth(of: width, column),
              let right = depth(of: width, { column(width - 1 - $0) })
        else { return nil }
        let insetX = Int((margin * Double(width)).rounded(.up))
        let insetY = Int((margin * Double(height)).rounded(.up))
        return CGRect(
            x: left + insetX,
            y: top + insetY,
            width: width - left - right - 2 * insetX,
            height: height - top - bottom - 2 * insetY
        )
    }

    /// The image cut to its picture, or the image itself when it has no border.
    static func trimmed(_ image: CGImage) -> CGImage {
        picture(in: image).flatMap { image.cropping(to: $0) } ?? image
    }

    /// How deep one side's paper goes, in lines from the edge, or nil when the
    /// side has no border. `share` is a line's paper-light share, line 0 the
    /// outermost.
    private static func depth(of length: Int, _ share: (Int) -> Double) -> Int? {
        let deepest = Int(widest * Double(length))
        let lines = max(3, Int(run * Double(length)))
        let shares = (0 ..< min(length, deepest + lines)).map(share)
        guard let edge = (0 ... deepest).first(where: { start in
            start + lines <= shares.count
                && shares[start ..< start + lines].allSatisfy { $0 < pictureShare }
        }), edge >= max(1, Int(narrowest * Double(length)))
        else { return nil }
        let paper = shares[..<edge].filter { $0 >= paperShare }.count
        return Double(paper) >= mostlyPaper * Double(edge) ? edge : nil
    }
}
