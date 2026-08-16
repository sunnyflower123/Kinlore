// Assemble PNG frames into an animated GIF using ImageIO.
//
// No ffmpeg, gifski or ImageMagick on this machine, and none is needed: macOS
// ships an animated-GIF encoder in ImageIO. Frames are downscaled on the way in,
// because a simulator screenshot is 1206 points wide and a README GIF should not
// be a megabyte a frame.
//
//   swiftc -O -o /tmp/gif gif.swift
//   /tmp/gif <frames-dir> <out.gif> <width> <delay-seconds>

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 5,
      let width = Int(args[3]),
      let delay = Double(args[4]) else {
    FileHandle.standardError.write("usage: gif <frames-dir> <out.gif> <width> <delay>\n".data(using: .utf8)!)
    exit(2)
}

let dir = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])

let frames = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

guard !frames.isEmpty else {
    FileHandle.standardError.write("no PNG frames in \(dir.path)\n".data(using: .utf8)!)
    exit(1)
}

guard let dest = CGImageDestinationCreateWithURL(
    out as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    FileHandle.standardError.write("could not create \(out.path)\n".data(using: .utf8)!)
    exit(1)
}

// Loop forever.
CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)

let frameProps = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
] as CFDictionary

func downscale(_ image: CGImage, to targetWidth: Int) -> CGImage? {
    let scale = Double(targetWidth) / Double(image.width)
    let targetHeight = Int((Double(image.height) * scale).rounded())
    guard let ctx = CGContext(
        data: nil, width: targetWidth, height: targetHeight,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return ctx.makeImage()
}

var written = 0
for url in frames {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let small = downscale(image, to: width) else {
        FileHandle.standardError.write("skipped \(url.lastPathComponent)\n".data(using: .utf8)!)
        continue
    }
    CGImageDestinationAddImage(dest, small, frameProps)
    written += 1
}

guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("could not finalize \(out.path)\n".data(using: .utf8)!)
    exit(1)
}

let bytes = ((try? FileManager.default.attributesOfItem(atPath: out.path)[.size]) as? Int) ?? 0
print("\(written) frames, \(width)px wide, \(delay)s each → \(out.lastPathComponent) \(bytes / 1024) KB")
