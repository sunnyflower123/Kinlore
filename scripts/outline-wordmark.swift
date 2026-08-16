// Converts the wordmark to an SVG path so the lockup does not depend on the
// fonts installed on the reader's machine.
//
// The lockup lives in the GitHub README, where most readers are not on a Mac.
// With a <text> element the name fell back to Georgia or a generic serif and
// the last letter clipped at the edge of the viewBox. An outline cannot clip
// and cannot be substituted.
//
// Charter is used rather than an Apple system font: Bitstream Charter's licence
// allows its letterforms to be used this way, whereas Apple's fonts are
// licensed for user interface mock-ups only.
//
// Run this again if the name ever changes. It was last run for Kinlore on
// 16 Aug 2026; the viewBox in the lockups is the bounding box's right edge
// plus a 20.78 margin, which is what the previous name used.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcrun swift scripts/outline-wordmark.swift Kinlore Charter 0.4 92 -1 178 132
//
// Arguments: <text> <family> <weight> <size> <kerning> <baseline-x> <baseline-y>
// Writes the path data to stdout and the resolved font and bounding box to
// stderr. Paste the result into the <path d="..."> of docs/logo/lockup*.svg.

import CoreText
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 8 else {
    FileHandle.standardError.write(
        "usage: outline-wordmark.swift <text> <family> <weight> <size> <kern> <x> <y>\n"
            .data(using: .utf8)!)
    exit(1)
}

let text = args[1]
let family = args[2]
let weight = CGFloat(Double(args[3])!)
let size = CGFloat(Double(args[4])!)
let kern = CGFloat(Double(args[5])!)
let baselineX = CGFloat(Double(args[6])!)
let baselineY = CGFloat(Double(args[7])!)

let descriptor = CTFontDescriptorCreateWithAttributes([
    kCTFontFamilyNameAttribute: family,
    kCTFontTraitsAttribute: [kCTFontWeightTrait: weight],
] as CFDictionary)
let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)

func note(_ line: String) {
    FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
}

// The descriptor matches by traits, so report what it actually resolved to.
note("font: \(CTFontCopyPostScriptName(font))")

let string = CFAttributedStringCreate(nil, text as CFString, [
    kCTFontAttributeName: font,
    kCTKernAttributeName: kern,
] as CFDictionary)!
let line = CTLineCreateWithAttributedString(string)
let runs = CTLineGetGlyphRuns(line) as! [CTRun]

func fmt(_ value: CGFloat) -> String {
    let rounded = (Double(value) * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
}

var d = ""
let combined = CGMutablePath()

for run in runs {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
    let runFont = (CTRunGetAttributes(run) as! [CFString: Any])[kCTFontAttributeName] as! CTFont

    for i in 0..<count {
        guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
        // Core Text is y-up and relative to the baseline; SVG is y-down.
        let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                          tx: baselineX + positions[i].x, ty: baselineY)
        combined.addPath(glyph, transform: transform)
        glyph.applyWithBlock { element in
            let e = element.pointee
            func point(_ k: Int) -> CGPoint { e.points[k].applying(transform) }
            switch e.type {
            case .moveToPoint:
                let a = point(0)
                d += "M\(fmt(a.x)) \(fmt(a.y))"
            case .addLineToPoint:
                let a = point(0)
                d += "L\(fmt(a.x)) \(fmt(a.y))"
            case .addQuadCurveToPoint:
                let a = point(0), b = point(1)
                d += "Q\(fmt(a.x)) \(fmt(a.y)) \(fmt(b.x)) \(fmt(b.y))"
            case .addCurveToPoint:
                let a = point(0), b = point(1), c = point(2)
                d += "C\(fmt(a.x)) \(fmt(a.y)) \(fmt(b.x)) \(fmt(b.y)) \(fmt(c.x)) \(fmt(c.y))"
            case .closeSubpath:
                d += "Z"
            @unknown default:
                break
            }
        }
    }
}

// The right edge decides the viewBox width: too narrow and the name clips again.
let box = combined.boundingBoxOfPath
note("bounding box: x \(fmt(box.minX))..\(fmt(box.maxX))  y \(fmt(box.minY))..\(fmt(box.maxY))")
print(d)
