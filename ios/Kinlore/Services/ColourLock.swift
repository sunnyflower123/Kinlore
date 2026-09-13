import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Colour from a model, brightness from the photograph.
///
/// A model asked to colour a photograph repaints all of it, and the brightness
/// it paints is its own: on the measured run (13 Sep 2026, `wrangler.jsonc`)
/// the chosen model moved the lightness of half the picture by more than three
/// and a half points in a hundred, and a twentieth of it by sixteen. So nothing
/// it drew is kept but the hue. The photograph goes into CIELAB, keeps its own
/// `L`, and takes only `a` and `b` from the reply — every edge, crease and face
/// is then the original's own pixels, and the colours are the one thing the
/// model contributed.
///
/// That holds only while the reply's shapes sit where the photograph's do. A
/// model that redraws — one measured candidate repainted the grandmother as
/// somebody else — would lay its colours a few pixels off every edge, so the
/// edges are compared first and a reply that moved them is refused rather than
/// laid on.
///
/// No UIKit, so `scripts/colour-lock-check.swift` compiles this file as it is.
enum ColourLock {
    /// The ratios the image model accepts. The same list as `ASPECT_RATIOS` in
    /// backend/src/colourise.ts, which drops anything else before it is sent.
    static let ratios: [(name: String, value: Double)] = [
        ("1:1", 1), ("1:4", 1.0 / 4), ("1:8", 1.0 / 8), ("2:3", 2.0 / 3), ("3:2", 3.0 / 2),
        ("3:4", 3.0 / 4), ("4:1", 4), ("4:3", 4.0 / 3), ("4:5", 4.0 / 5), ("5:4", 5.0 / 4),
        ("8:1", 8), ("9:16", 9.0 / 16), ("16:9", 16.0 / 9), ("21:9", 21.0 / 9),
    ]

    /// How a photograph is put in front of the model.
    ///
    /// A ratio the model does not accept is not stretched into one it does: the
    /// photograph is centred on a canvas of the nearest accepted ratio and the
    /// rest is neutral grey. A model handed a canvas of exactly the shape it was
    /// asked for has no reason to move anything, and the grey is cut away from
    /// the reply before anything else looks at it.
    struct Framing: Equatable {
        /// The ratio asked for, one of `ratios`.
        let aspect: String
        let canvasWidth: Int
        let canvasHeight: Int
        /// Where the photograph sits on the canvas, in canvas pixels. Centred,
        /// so it is the same rectangle whichever corner a pixel grid counts from.
        let photo: CGRect
    }

    /// Below this the reply is refused.
    ///
    /// Measured 13 Sep 2026 on one synthetic photograph, unshifted, at the same
    /// 256 pixels wide: the two models that kept the picture scored 0.964 and
    /// 0.971, the one that rescaled its frame by two per cent 0.683, and the one
    /// that redrew the picture 0.125. The line sits well clear of both groups.
    /// One photograph is not a sample, and a grainy print may score lower than
    /// a clean synthetic one — the first real family photographs are where to
    /// find out.
    static let minimumEdgeCorrelation = 0.85

    enum Outcome {
        /// The photograph at its own size, with the reply's colours and its
        /// own brightness.
        case kept(CGImage)
        /// The reply's shapes are not where the photograph's are, so nothing of
        /// it can be laid on. Zero when the reply was not even the canvas's shape.
        case moved(correlation: Double)
    }

    static func framing(width: Int, height: Int, longSide: Int = 1024) -> Framing {
        let ratio = Double(max(width, 1)) / Double(max(height, 1))
        let nearest = ratios.min { abs(log(ratio / $0.value)) < abs(log(ratio / $1.value)) } ?? ("1:1", 1)
        let canvasWidth = nearest.value >= 1 ? longSide : Int((Double(longSide) * nearest.value).rounded())
        let canvasHeight = nearest.value >= 1 ? Int((Double(longSide) / nearest.value).rounded()) : longSide
        let scale = min(Double(canvasWidth) / Double(max(width, 1)), Double(canvasHeight) / Double(max(height, 1)))
        let photoWidth = Double(width) * scale
        let photoHeight = Double(height) * scale
        return Framing(
            aspect: nearest.name,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            photo: CGRect(
                x: (Double(canvasWidth) - photoWidth) / 2,
                y: (Double(canvasHeight) - photoHeight) / 2,
                width: photoWidth,
                height: photoHeight
            )
        )
    }

    /// The canvas the model is sent: the photograph at `framing`'s size on
    /// neutral grey, as a JPEG.
    static func canvas(for photo: CGImage, framing: Framing) -> Data? {
        guard let context = rgbaContext(width: framing.canvasWidth, height: framing.canvasHeight) else {
            return nil
        }
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: framing.canvasWidth, height: framing.canvasHeight))
        context.interpolationQuality = .high
        context.draw(photo, in: framing.photo)
        guard let image = context.makeImage() else { return nil }
        return jpeg(image, quality: 0.85)
    }

    /// Cuts the photograph back out of the reply, compares the edges, and lays
    /// the reply's colours on the original. Nil only when there was no memory
    /// to draw into.
    static func lock(original: CGImage, reply: CGImage, framing: Framing) -> Outcome? {
        let replyRatio = Double(reply.width) / Double(max(reply.height, 1))
        let canvasRatio = Double(framing.canvasWidth) / Double(max(framing.canvasHeight, 1))
        guard abs(log(replyRatio / canvasRatio)) < 0.02 else { return .moved(correlation: 0) }

        // Rounded inwards, so no sliver of the grey comes back with the picture.
        let scaleX = Double(reply.width) / Double(framing.canvasWidth)
        let scaleY = Double(reply.height) / Double(framing.canvasHeight)
        let left = (framing.photo.minX * scaleX).rounded(.up)
        let top = (framing.photo.minY * scaleY).rounded(.up)
        let right = (framing.photo.maxX * scaleX).rounded(.down)
        let bottom = (framing.photo.maxY * scaleY).rounded(.down)
        guard right - left >= 16, bottom - top >= 16,
              let cut = reply.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
        else { return .moved(correlation: 0) }

        let correlation = edgeCorrelation(original, cut)
        guard correlation >= minimumEdgeCorrelation else { return .moved(correlation: correlation) }
        return laid(colourOf: cut, onto: original).map(Outcome.kept)
    }

    /// How closely the edges of one image lie on another's: the Pearson
    /// correlation of their Sobel edge maps at 256 pixels wide, unshifted, with
    /// a margin left out where the filter has no neighbours to read.
    static func edgeCorrelation(_ first: CGImage, _ second: CGImage) -> Double {
        let width = 256
        let height = max(1, Int((Double(first.height) * Double(width) / Double(max(first.width, 1))).rounded()))
        guard let a = lightness(of: first, width: width, height: height),
              let b = lightness(of: second, width: width, height: height)
        else { return 0 }
        let edgesA = sobel(a, width: width, height: height)
        let edgesB = sobel(b, width: width, height: height)

        let margin = 8
        var n = 0.0, sumA = 0.0, sumB = 0.0, sumAA = 0.0, sumBB = 0.0, sumAB = 0.0
        for y in stride(from: margin, to: height - margin, by: 1) {
            for x in stride(from: margin, to: width - margin, by: 1) {
                let u = edgesA[y * width + x], v = edgesB[y * width + x]
                n += 1
                sumA += u
                sumB += v
                sumAA += u * u
                sumBB += v * v
                sumAB += u * v
            }
        }
        guard n > 1 else { return 0 }
        let covariance = sumAB - sumA * sumB / n
        let varianceA = sumAA - sumA * sumA / n
        let varianceB = sumBB - sumB * sumB / n
        guard varianceA > 0, varianceB > 0 else { return 0 }
        return covariance / (varianceA * varianceB).squareRoot()
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.9) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - The arithmetic

    /// The original's brightness with the reply's hue, pixel by pixel, at the
    /// original's size. `a` and `b` are the differences between `f(X)`, `f(Y)`
    /// and `f(Z)`, so keeping the original's `L` and the reply's `a` and `b` is
    /// keeping the original's `f(Y)` and the reply's two differences.
    private static func laid(colourOf reply: CGImage, onto original: CGImage) -> CGImage? {
        let width = original.width, height = original.height
        guard let base = rgbaContext(width: width, height: height),
              let hue = rgbaContext(width: width, height: height)
        else { return nil }
        base.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
        hue.interpolationQuality = .high
        hue.draw(reply, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let target = base.data?.assumingMemoryBound(to: UInt8.self),
              let source = hue.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }

        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let (_, fy, _) = f(target[i], target[i + 1], target[i + 2])
            let (hx, hy, hz) = f(source[i], source[i + 1], source[i + 2])
            let (r, g, b) = encoded(fx: fy + (hx - hy), fy: fy, fz: fy - (hy - hz))
            target[i] = r
            target[i + 1] = g
            target[i + 2] = b
            target[i + 3] = 255
        }
        return base.makeImage()
    }

    /// CIELAB `L` of an image drawn at the given size.
    private static func lightness(of image: CGImage, width: Int, height: Int) -> [Double]? {
        guard let context = rgbaContext(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var values = [Double](repeating: 0, count: width * height)
        for index in 0 ..< width * height {
            let (_, fy, _) = f(pixels[index * 4], pixels[index * 4 + 1], pixels[index * 4 + 2])
            values[index] = 116 * fy - 16
        }
        return values
    }

    private static func sobel(_ values: [Double], width: Int, height: Int) -> [Double] {
        var edges = [Double](repeating: 0, count: width * height)
        guard width > 2, height > 2 else { return edges }
        for y in 1 ..< height - 1 {
            for x in 1 ..< width - 1 {
                func at(_ dx: Int, _ dy: Int) -> Double { values[(y + dy) * width + x + dx] }
                let gx = at(1, -1) + 2 * at(1, 0) + at(1, 1) - at(-1, -1) - 2 * at(-1, 0) - at(-1, 1)
                let gy = at(-1, 1) + 2 * at(0, 1) + at(1, 1) - at(-1, -1) - 2 * at(0, -1) - at(1, -1)
                edges[y * width + x] = (gx * gx + gy * gy).squareRoot()
            }
        }
        return edges
    }

    private static func rgbaContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    // sRGB (D65) ⇄ CIELAB, through two tables so that a 2048-pixel photograph
    // does not spend three `pow` calls on every pixel twice.
    private static let epsilon = 216.0 / 24389
    private static let kappa = 24389.0 / 27
    private static let whiteX = 0.95047
    private static let whiteZ = 1.08883

    private static let linear: [Double] = (0 ... 255).map { value in
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static let gamma: [UInt8] = (0 ... 4095).map { value in
        let c = Double(value) / 4095
        let e = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8((min(max(e, 0), 1) * 255).rounded())
    }

    @inline(__always)
    private static func f(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (Double, Double, Double) {
        let r = linear[Int(r8)], g = linear[Int(g8)], b = linear[Int(b8)]
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / whiteX
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / whiteZ
        return (lab(x), lab(y), lab(z))
    }

    @inline(__always)
    private static func lab(_ t: Double) -> Double {
        t > epsilon ? cbrt(t) : (kappa * t + 16) / 116
    }

    @inline(__always)
    private static func unlab(_ t: Double) -> Double {
        let cube = t * t * t
        return cube > epsilon ? cube : (116 * t - 16) / kappa
    }

    @inline(__always)
    private static func encoded(fx: Double, fy: Double, fz: Double) -> (UInt8, UInt8, UInt8) {
        let x = whiteX * unlab(fx), y = unlab(fy), z = whiteZ * unlab(fz)
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        @inline(__always) func channel(_ v: Double) -> UInt8 { gamma[Int((min(max(v, 0), 1) * 4095).rounded())] }
        return (channel(r), channel(g), channel(b))
    }
}
