// The README's table pictures as prints in a photo album.
//
// A screenshot taken with `--mask=black` has the phone's rounded corners drawn
// in black (readme-shots.sh says why the mask is on), and an album print has
// square corners. So the mask is painted out first. It is measured row by row
// in the two top corners, where the status bar puts plain paper beside it, and
// each pixel it covers takes the colour of the first clean pixel in its row.
// The bottom corners get the same shape mirrored rather than a measurement of
// their own, because what sits beside them can be dark and would be read as
// mask, and the run stops if they are not black where the top says they are.
//
// Then the print is scaled down, given a hairline, and held by four photo
// corners that reach a little past its edges, on a transparent ground so that
// either of GitHub's themes shows through. Corners and hairline are
// `--k-rule-strong` from docs/assets/kinlore.css: light paper corners read on
// white and on GitHub's dark page alike, where the app's ink would vanish.
//
//   xcrun swiftc -O -o /tmp/mount scripts/mount-prints.swift
//   /tmp/mount <in.png> <out.png> [<in.png> <out.png> …]
//
// readme-shots.sh runs it on the first three stills after taking them. A print
// is 480 px wide, about twice what a table column gives it on github.com.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 480            // the print, before the corners' reach
let reach = 4              // how far a photo corner reaches past the print's edge
let cornerLeg = 0.10       // a photo corner's leg, as a fraction of the print's width
let paper = CGColor(srgbRed: 0xC9 / 255.0, green: 0xB3 / 255.0, blue: 0x93 / 255.0, alpha: 1)

let args = CommandLine.arguments
guard args.count >= 3, args.count % 2 == 1 else {
    FileHandle.standardError.write("usage: mount <in.png> <out.png> [<in.png> <out.png> …]\n".data(using: .utf8)!)
    exit(2)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("mount-prints: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func mount(_ inPath: String, _ outPath: String) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
          let shot = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(inPath)") }
    let w = shot.width, h = shot.height
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // The screenshot in a buffer we can edit, top row first.
    let canvas = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                           space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    canvas.draw(shot, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = canvas.data!.assumingMemoryBound(to: UInt8.self)
    func offset(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
    func lightness(_ o: Int) -> Int { Int(px[o]) + Int(px[o + 1]) + Int(px[o + 2]) }
    func black(_ o: Int) -> Bool { px[o] <= 2 && px[o + 1] <= 2 && px[o + 2] <= 2 }

    // Row by row from the top, how far the mask reaches in from one side: its
    // solid black, then its anti-aliased edge up to where the row's paper
    // begins. The edge is a pixel or two wide except in the top row, where the
    // curve meets the edge of the screen and fades out over about 45 px on an
    // iPhone 16. A row never reaches further than the one above it.
    func measure(fromRight: Bool) -> [(solid: Int, covered: Int)] {
        var rows: [(solid: Int, covered: Int)] = []
        var previous = w / 4
        for y in 0..<(h / 4) {
            func at(_ i: Int) -> Int { offset(fromRight ? w - 1 - i : i, y) }
            var solid = 0
            while solid < previous && black(at(solid)) { solid += 1 }
            let clean = lightness(at(solid + 48))
            var covered = solid
            while covered < min(solid + 48, previous) && lightness(at(covered)) < clean - 6 { covered += 1 }
            if covered == 0 { break }
            rows.append((solid, covered))
            previous = covered
        }
        return rows
    }
    let mask = zip(measure(fromRight: false), measure(fromRight: true))
        .map { (solid: min($0.solid, $1.solid), covered: min($0.covered, $1.covered)) }

    var checked = 0, wrong = 0
    for (y, row) in mask.enumerated() {
        for x in 0..<row.solid {
            checked += 2
            if !black(offset(x, h - 1 - y)) { wrong += 1 }
            if !black(offset(w - 1 - x, h - 1 - y)) { wrong += 1 }
        }
    }
    if wrong * 100 > checked {
        fail("\(inPath): \(wrong) of \(checked) pixels in the bottom corners are not the mask the top corners measured")
    }

    for (flipX, flipY) in [(false, false), (true, false), (false, true), (true, true)] {
        for (y, row) in mask.enumerated() {
            let yy = flipY ? h - 1 - y : y
            func x(_ i: Int) -> Int { flipX ? w - 1 - i : i }
            let from = offset(x(row.covered + 2), yy)
            for i in 0..<row.covered {
                let o = offset(x(i), yy)
                px[o] = px[from]; px[o + 1] = px[from + 1]; px[o + 2] = px[from + 2]
            }
        }
    }
    let squared = canvas.makeImage()!

    let printW = CGFloat(width), printH = (CGFloat(h) * printW / CGFloat(w)).rounded()
    let r = CGFloat(reach)
    let out = CGContext(data: nil, width: width + 2 * reach, height: Int(printH) + 2 * reach, bitsPerComponent: 8,
                        bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    out.interpolationQuality = .high
    let frame = CGRect(x: r, y: r, width: printW, height: printH)
    out.draw(squared, in: frame)
    out.setStrokeColor(paper)
    out.setLineWidth(2)
    out.stroke(frame.insetBy(dx: 1, dy: 1))

    // A photo corner is a right triangle whose legs run along two edges of the
    // print and reach past them.
    let leg = (printW * CGFloat(cornerLeg)).rounded()
    out.setFillColor(paper)
    for (x, y, dx, dy) in [(frame.minX, frame.minY, 1, 1), (frame.maxX, frame.minY, -1, 1),
                           (frame.minX, frame.maxY, 1, -1), (frame.maxX, frame.maxY, -1, -1)]
        as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        out.move(to: CGPoint(x: x - dx * r, y: y - dy * r))
        out.addLine(to: CGPoint(x: x + dx * leg, y: y - dy * r))
        out.addLine(to: CGPoint(x: x - dx * r, y: y + dy * leg))
        out.closePath()
    }
    out.fillPath()

    guard let image = out.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                            UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot write \(outPath)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(outPath)") }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? 0
    let name = URL(fileURLWithPath: outPath).pathComponents.suffix(2).joined(separator: "/")
    print("  \(name)  (\(image.width) × \(image.height), \(bytes / 1024) KB, mask \(mask.first?.covered ?? 0) px deep)")
}

for i in stride(from: 1, to: args.count, by: 2) {
    mount(args[i], args[i + 1])
}
