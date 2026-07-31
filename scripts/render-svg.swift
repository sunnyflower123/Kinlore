// Rasterises an SVG to PNG while preserving transparency.
//
// Do not use `qlmanage -t` for this. Quick Look thumbnails composite onto
// white, so a transparent SVG silently becomes an opaque white square. That is
// how the tinted app icon shipped as a white block instead of a greyscale mark.
// (The white card behind the launch screen mark looked like the same bug and
// was not: that one was a stale launch snapshot, see docs/logo/README.md.)
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcrun swift scripts/render-svg.swift <in.svg> <out.png> <width> [height] [fill]
//
// `fill` replaces `currentColor` in the source, for marks that inherit their
// colour (docs/logo/mark-mono.svg). Height defaults to width.

import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(
        "usage: render-svg.swift <in.svg> <out.png> <width> [height] [fill]\n"
            .data(using: .utf8)!)
    exit(1)
}

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let width = Int(args[3])!
let height = args.count > 4 ? Int(args[4])! : width
let fill = args.count > 5 ? args[5] : nil

var source = input
if let fill {
    // NSImage has no way to supply a current colour, so substitute in the text.
    let text = try String(contentsOf: input, encoding: .utf8)
        .replacingOccurrences(of: "currentColor", with: fill)
    source = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("render-svg-\(getpid()).svg")
    try text.write(to: source, atomically: true, encoding: .utf8)
}

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("cannot read \(input.path)\n".data(using: .utf8)!)
    exit(1)
}

// The bitmap starts fully transparent; sourceOver keeps it that way outside the art.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("cannot allocate bitmap\n".data(using: .utf8)!)
    exit(1)
}
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
           from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("cannot encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: output)

if fill != nil { try? FileManager.default.removeItem(at: source) }

// Report the corner pixel so a lost alpha channel is caught here, not on device.
let corner = rep.colorAt(x: 1, y: 1)!
print("\(output.lastPathComponent) \(width)x\(height) corner alpha \(corner.alphaComponent)")
