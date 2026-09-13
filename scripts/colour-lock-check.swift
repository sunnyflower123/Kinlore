// Colour from a model, brightness from the photograph — checked without a model.
//
// `ColourLock` is the one thing standing between an image model's reply and a
// family's photograph, and all three of its promises fail silently:
//
//   1. **The photograph keeps its own brightness.** A lock that took the
//      reply's `L` along with its hue still produces a good-looking colour
//      photograph — with every face repainted by the model a little lighter or
//      darker, which is the change the lock exists to make impossible.
//   2. **A reply whose shapes moved is refused.** Laid on anyway it still looks
//      like a colour photograph, with the colours a few pixels off every edge.
//   3. **A ratio the model does not accept is framed, not stretched**, and the
//      frame is cut away again. Stretched, the model is asked to move every
//      edge, and the refusal above would spend a family's round on it.
//
// The model is replaced by what a well-behaved one does — the canvas, tinted
// and brightened, answered at the model's own size — and by the two ways the
// measured ones misbehaved: a picture shifted, and a frame rescaled. The
// measurements are an implementation of CIELAB of their own, with `pow` where
// ColourLock uses tables, so a mistake in its arithmetic cannot measure itself
// as correct.
//
// Costs nothing: no simulator, no network, no model.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
//     -parse-as-library -o /tmp/colour-lock-check scripts/colour-lock-check.swift \
//     ios/Kinlore/Services/ColourLock.swift && /tmp/colour-lock-check

import CoreGraphics
import Foundation

@main
struct ColourLockCheck {
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
        print("— a ratio the model does not accept is framed, not stretched —")
        do {
            let framing = ColourLock.framing(width: 900, height: 620)
            check("a 900 × 620 print goes on a 3:2 canvas", framing.aspect == "3:2", framing.aspect)
            check(
                "a canvas of that shape",
                framing.canvasWidth == 1024 && framing.canvasHeight == 683,
                "\(framing.canvasWidth) × \(framing.canvasHeight)"
            )
            let photo = framing.photo
            check(
                "the photograph keeps its own shape on it",
                abs(photo.width / photo.height - 900.0 / 620.0) < 0.005,
                "\(photo)"
            )
            check(
                "centred, with the grey at its sides",
                photo.minX > 10 && abs(photo.minX - (1024 - photo.maxX)) < 0.5 && abs(photo.height - 683) < 1,
                "\(photo)"
            )
            let four = ColourLock.framing(width: 1200, height: 900)
            check(
                "a 4:3 photograph fills a 4:3 canvas",
                four.aspect == "4:3" && four.photo.minX < 0.5 && four.photo.minY < 0.5,
                "\(four.aspect) \(four.photo)"
            )
            check("an upright one is upright", ColourLock.framing(width: 600, height: 900).aspect == "2:3")
            check("and a panorama finds the nearest there is", ColourLock.framing(width: 3000, height: 500).aspect == "8:1")
        }

        let original = print1950s(width: 900, height: 620)
        let framing = ColourLock.framing(width: original.width, height: original.height)
        guard let canvasData = ColourLock.canvas(for: original, framing: framing),
              let canvas = ColourLock.image(from: canvasData)
        else {
            check("the canvas can be drawn at all", false)
            exit(1)
        }
        do {
            check(
                "the canvas sent is the canvas planned",
                canvas.width == framing.canvasWidth && canvas.height == framing.canvasHeight,
                "\(canvas.width) × \(canvas.height)"
            )
            let side = pixel(canvas, x: 4, y: canvas.height / 2)
            check(
                "and what is not photograph is neutral grey",
                abs(Int(side.0) - 128) < 8 && abs(Int(side.1) - 128) < 8 && abs(Int(side.2) - 128) < 8,
                "\(side)"
            )
        }

        print("— the photograph keeps its own brightness —")
        do {
            // A model that kept every edge, answered at 1200 × 800, and — as
            // the measured ones did — painted the lightness brighter.
            let reply = modelReply(from: canvas, width: 1200, height: 800)
            guard case .kept(let coloured)? = ColourLock.lock(original: original, reply: reply, framing: framing) else {
                check("a reply that kept every edge is laid on", false)
                exit(1)
            }
            check("a reply that kept every edge is laid on", true)
            check(
                "at the photograph's own size",
                coloured.width == original.width && coloured.height == original.height,
                "\(coloured.width) × \(coloured.height)"
            )
            let (typical, worst, chroma) = compare(original, coloured)
            check(
                "with its own lightness, not the model's brighter one",
                typical <= 1.5 && worst <= 6,
                String(format: "99th percentile ΔL %.2f, largest %.2f", typical, worst)
            )
            check("and the colours are actually there", chroma > 8, String(format: "mean chroma %.1f", chroma))
        }

        print("— a reply whose shapes moved is refused —")
        do {
            let shifted = modelReply(from: canvas, width: 1200, height: 800, shift: 0.03)
            if case .moved(let correlation)? = ColourLock.lock(original: original, reply: shifted, framing: framing) {
                check("a picture moved three per cent sideways", true)
                print(String(format: "       (edges correlated %.3f)", correlation))
            } else {
                check("a picture moved three per cent sideways", false, "it was laid on")
            }
            let rescaled = modelReply(from: canvas, width: 1200, height: 800, scale: 1.03)
            if case .moved? = ColourLock.lock(original: original, reply: rescaled, framing: framing) {
                check("a frame rescaled by three per cent", true)
            } else {
                check("a frame rescaled by three per cent", false, "it was laid on")
            }
            let square = modelReply(from: canvas, width: 1024, height: 1024)
            if case .moved(let correlation)? = ColourLock.lock(original: original, reply: square, framing: framing) {
                check("a reply of the wrong shape, before anything is compared", correlation == 0)
            } else {
                check("a reply of the wrong shape, before anything is compared", false, "it was laid on")
            }
        }

        print(failures == 0 ? "\nall checks passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - A photograph, and a model

    /// Something with edges worth keeping: blocks, a disc, thin lines and a
    /// soft gradient, in a warm grey, at a ratio no model accepts.
    static func print1950s(width: Int, height: Int) -> CGImage {
        let context = rgba(width: width, height: height)
        for row in 0 ..< height {
            let shade = 0.35 + 0.35 * Double(row) / Double(height)
            context.setFillColor(red: shade + 0.03, green: shade, blue: shade - 0.03, alpha: 1)
            context.fill(CGRect(x: 0, y: row, width: width, height: 1))
        }
        context.setFillColor(red: 0.21, green: 0.19, blue: 0.17, alpha: 1)
        context.fill(CGRect(x: 90, y: 120, width: 260, height: 330))
        context.setFillColor(red: 0.82, green: 0.8, blue: 0.77, alpha: 1)
        context.fill(CGRect(x: 520, y: 90, width: 180, height: 250))
        context.setFillColor(red: 0.55, green: 0.53, blue: 0.5, alpha: 1)
        context.fillEllipse(in: CGRect(x: 610, y: 360, width: 200, height: 200))
        context.setStrokeColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        context.setLineWidth(3)
        for line in 0 ..< 6 {
            context.move(to: CGPoint(x: 380 + line * 22, y: 40))
            context.addLine(to: CGPoint(x: 420 + line * 22, y: 580))
        }
        context.strokePath()
        return context.makeImage()!
    }

    /// What an image model answers: the canvas drawn at the model's size —
    /// shifted or rescaled when it misbehaves — tinted warm to the left and
    /// cool to the right, and painted brighter than it was.
    static func modelReply(from canvas: CGImage, width: Int, height: Int, shift: Double = 0, scale: Double = 1) -> CGImage {
        let context = rgba(width: width, height: height)
        context.interpolationQuality = .high
        let drawnWidth = Double(width) * scale
        let drawnHeight = Double(height) * scale
        context.draw(
            canvas,
            in: CGRect(
                x: (Double(width) - drawnWidth) / 2 + shift * Double(width),
                y: (Double(height) - drawnHeight) / 2,
                width: drawnWidth,
                height: drawnHeight
            )
        )
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = (y * width + x) * 4
                let warm = Double(x) / Double(width)
                func paint(_ value: UInt8, _ tint: Double) -> UInt8 {
                    UInt8(min(255, max(0, (Double(value) * 1.12 + 14) * tint)))
                }
                pixels[i] = paint(pixels[i], 1.25 - 0.4 * warm)
                pixels[i + 1] = paint(pixels[i + 1], 1.0)
                pixels[i + 2] = paint(pixels[i + 2], 0.8 + 0.4 * warm)
            }
        }
        return context.makeImage()!
    }

    // MARK: - Measuring, independently

    /// The 99th percentile and the largest CIELAB ΔL between two images of one
    /// size, and the mean chroma of the second.
    static func compare(_ first: CGImage, _ second: CGImage) -> (Double, Double, Double) {
        let a = rgba(width: first.width, height: first.height)
        a.draw(first, in: CGRect(x: 0, y: 0, width: first.width, height: first.height))
        let b = rgba(width: first.width, height: first.height)
        b.draw(second, in: CGRect(x: 0, y: 0, width: first.width, height: first.height))
        let pa = a.data!.assumingMemoryBound(to: UInt8.self)
        let pb = b.data!.assumingMemoryBound(to: UInt8.self)
        var differences: [Double] = []
        differences.reserveCapacity(first.width * first.height)
        var chroma = 0.0
        for index in 0 ..< first.width * first.height {
            let i = index * 4
            let one = lab(pa[i], pa[i + 1], pa[i + 2])
            let two = lab(pb[i], pb[i + 1], pb[i + 2])
            differences.append(abs(one.l - two.l))
            chroma += (two.a * two.a + two.b * two.b).squareRoot()
        }
        differences.sort()
        let typical = differences[min(differences.count - 1, differences.count * 99 / 100)]
        return (typical, differences.last ?? 0, chroma / Double(differences.count))
    }

    static func lab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (l: Double, a: Double, b: Double) {
        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func f(_ t: Double) -> Double {
            t > 216.0 / 24389 ? pow(t, 1.0 / 3) : (24389.0 / 27 * t + 16) / 116
        }
        let r = linear(r8), g = linear(g8), b = linear(b8)
        let fx = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047)
        let fy = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        let fz = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let context = rgba(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let p = context.data!.assumingMemoryBound(to: UInt8.self)
        let i = (y * image.width + x) * 4
        return (p[i], p[i + 1], p[i + 2])
    }

    static func rgba(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }
}
