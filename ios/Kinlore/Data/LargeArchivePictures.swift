#if DEBUG
import UIKit

/// The photographs of `-seed large`, drawn in code.
///
/// An album of a hundred and fifty copies of `demoPhotoData()` would hide the
/// one thing a larger archive is for, which is telling the pictures apart, and
/// every measurement of the grid would be of one decoded image cached a
/// hundred and fifty times. So each print is drawn from its own number, the
/// way its decade would have printed it: a sepia cabinet card, a deckle-edged
/// black-and-white print on a black album page, a faded square colour print, a
/// colour print, a phone picture. Nothing here is a photograph of a real
/// person and nothing is downloaded.
///
/// 2048 pixels on the long side, the size `MediaStore` keeps an imported
/// photograph at, so that the grid decodes files the size a family's are. A
/// drawing compresses better than a camera's picture, so the files are
/// smaller than real ones and the decoding cost measured on them is a floor.
enum LargeArchivePictures {
    enum Scene {
        case studio, couple, wedding, group, haying, lake, sauna, winter, christmas
        case farm, soldiers, car, graduation, beach, school, town, table, baby
    }

    /// Somebody the picture shows by name: how old they were, and whether
    /// the picture dresses them as a woman or a man.
    struct Sitter: Hashable {
        var age: Int
        var female: Bool
    }

    struct Print {
        var number: Int
        var year: Int
        var scene: Scene
        var sitters: [Sitter]
    }

    /// Where each sitter's face is, as fractions of the whole print — the
    /// coordinates `Subject.portraitFocusX/Y` are stored in, so a person's
    /// disc is cut around the head that was drawn for them.
    static func faces(of print: Print) -> [CGPoint?] {
        let size = size(of: print)
        let inner = inner(of: size, frame: frame(for: print.year))
        var faces = [CGPoint?](repeating: nil, count: print.sitters.count)
        for figure in layout(print) {
            guard let index = figure.sitter else { continue }
            let head = figure.head(in: inner)
            faces[index] = CGPoint(x: head.x / size.width, y: head.y / size.height)
        }
        return faces
    }

    /// The print as JPEG bytes. `coloured` draws the same picture in colour
    /// with the mark `ColourSheet` stamps into a kept colouring, for the few
    /// colourings the seed has somebody confirm.
    static func jpeg(of print: Print, coloured: Bool = false) -> Data? {
        let size = size(of: print)
        let frame = frame(for: print.year)
        let inner = inner(of: size, frame: frame)
        let ink = Ink(tone: coloured ? .colourised : tone(for: print.year))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            var dice = Dice(print.number &* 104_729 &+ 3)
            paper(frame, size: size, inner: inner, ink: ink, dice: &dice)
            cg.saveGState()
            if frame == .white {
                UIBezierPath(roundedRect: inner, cornerRadius: inner.width * 0.015).addClip()
            } else {
                cg.clip(to: inner)
            }
            let canvas = Canvas(cg: cg, r: inner, ink: ink)
            scene(print, on: canvas, dice: &dice)
            weather(canvas, tone: ink.tone, dice: &dice)
            cg.restoreGState()
            if frame == .deckle { corners(inner: inner, ink: ink) }
            if coloured { mark(size: size) }
        }
        return image.jpegData(compressionQuality: 0.85)
    }

    // MARK: - Print, paper and tone

    private enum Tone { case sepia, mono, faded, warm, vivid, colourised }
    private enum Frame { case mount, deckle, white, none }

    private static func tone(for year: Int) -> Tone {
        switch year {
        case ..<1936: .sepia
        case ..<1960: .mono
        case ..<1980: .faded
        case ..<2000: .warm
        default: .vivid
        }
    }

    private static func frame(for year: Int) -> Frame {
        switch year {
        case ..<1940: .mount
        case ..<1960: .deckle
        case ..<1980: .white
        default: .none
        }
    }

    private static func tall(_ print: Print) -> Bool {
        switch print.scene {
        case .studio: true
        case .couple: print.year < 1960
        case .graduation: print.sitters.count == 1
        default: false
        }
    }

    private static func size(of print: Print) -> CGSize {
        let tall = tall(print)
        switch print.year {
        case ..<1960: return tall ? CGSize(width: 1463, height: 2048) : CGSize(width: 2048, height: 1463)
        case ..<1980: return CGSize(width: 2048, height: 2048)
        case ..<2000: return tall ? CGSize(width: 1365, height: 2048) : CGSize(width: 2048, height: 1365)
        default: return tall ? CGSize(width: 1536, height: 2048) : CGSize(width: 2048, height: 1536)
        }
    }

    private static func inner(of size: CGSize, frame: Frame) -> CGRect {
        let w = size.width, h = size.height
        switch frame {
        case .mount:
            return CGRect(x: w * 0.08, y: h * 0.07, width: w * 0.84, height: h * 0.77)
        case .deckle:
            let side = min(w, h) * 0.085
            return CGRect(x: side, y: side, width: w - 2 * side, height: h - 2 * side)
        case .white:
            let side = min(w, h) * 0.055
            return CGRect(x: side, y: side, width: w - 2 * side, height: h - 2 * side)
        case .none:
            return CGRect(origin: .zero, size: size)
        }
    }

    private typealias RGB = (CGFloat, CGFloat, CGFloat)

    /// Every colour goes through the print's tone, so a scene is drawn once
    /// in the colours it had and comes out as its decade printed it.
    private struct Ink {
        let tone: Tone

        func colour(_ c: RGB, alpha: CGFloat = 1) -> UIColor {
            let (r, g, b) = c
            let l = 0.3 * r + 0.59 * g + 0.11 * b
            func mix(_ keep: CGFloat) -> RGB { (l + (r - l) * keep, l + (g - l) * keep, l + (b - l) * keep) }
            func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
            let out: RGB
            switch tone {
            case .sepia:
                let t = 0.1 + 0.8 * l
                out = (t * 1.08 + 0.04, t * 0.92 + 0.03, t * 0.72)
            case .mono:
                let t = 0.07 + 0.86 * l
                out = (t, t, t * 1.02)
            case .faded:
                let m = mix(0.62)
                out = (0.12 + 0.84 * m.0, 0.09 + 0.8 * m.1, 0.07 + 0.74 * m.2)
            case .warm:
                let m = mix(0.92)
                out = (m.0 * 1.02 + 0.03, m.1, m.2 * 0.93)
            case .vivid:
                out = c
            case .colourised:
                let m = mix(0.78)
                out = (m.0 * 1.02 + 0.02, m.1 + 0.01, m.2 * 0.95)
            }
            return UIColor(red: clamp(out.0), green: clamp(out.1), blue: clamp(out.2), alpha: alpha)
        }
    }

    /// A splitmix generator: the same number draws the same print on every
    /// phone and every launch, which `SystemRandomNumberGenerator` would not.
    private struct Dice {
        private var state: UInt64

        init(_ seed: Int) {
            state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }
        mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * unit() }
        mutating func int(_ below: Int) -> Int { Int(next() % UInt64(max(below, 1))) }
    }

    private struct Canvas {
        let cg: CGContext
        let r: CGRect
        let ink: Ink

        func x(_ f: CGFloat) -> CGFloat { r.minX + f * r.width }
        func y(_ f: CGFloat) -> CGFloat { r.minY + f * r.height }
        /// A length measured against the picture's height, so a circle stays round.
        func h(_ f: CGFloat) -> CGFloat { f * r.height }
        func point(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: x(fx), y: y(fy)) }

        func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: x(x0), y: y(y0), width: (x1 - x0) * r.width, height: (y1 - y0) * r.height)
        }

        func fill(_ rect: CGRect, _ c: RGB, alpha: CGFloat = 1) {
            ink.colour(c, alpha: alpha).setFill()
            cg.fill(rect)
        }

        func oval(_ rect: CGRect, _ c: RGB, alpha: CGFloat = 1) {
            ink.colour(c, alpha: alpha).setFill()
            cg.fillEllipse(in: rect)
        }

        func disc(_ centre: CGPoint, _ radius: CGFloat, _ c: RGB, alpha: CGFloat = 1) {
            oval(CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius), c, alpha: alpha)
        }

        func shape(_ points: [CGPoint], _ c: RGB, alpha: CGFloat = 1) {
            guard let first = points.first else { return }
            let path = UIBezierPath()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.close()
            ink.colour(c, alpha: alpha).setFill()
            path.fill()
        }

        func rounded(_ rect: CGRect, radius: CGFloat, _ c: RGB, alpha: CGFloat = 1) {
            ink.colour(c, alpha: alpha).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        }

        func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, _ c: RGB, alpha: CGFloat = 1) {
            let path = UIBezierPath()
            path.move(to: a)
            path.addLine(to: b)
            path.lineWidth = width
            path.lineCapStyle = .round
            ink.colour(c, alpha: alpha).setStroke()
            path.stroke()
        }

        func gradient(_ rect: CGRect, top: RGB, bottom: RGB) {
            let colours = [ink.colour(top).cgColor, ink.colour(bottom).cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]
            ) else { return }
            cg.saveGState()
            cg.clip(to: rect)
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.minY),
                end: CGPoint(x: rect.midX, y: rect.maxY),
                options: []
            )
            cg.restoreGState()
        }
    }

    /// The paper around the picture: a card mount before the war, a deckled
    /// print on a black album page after it, a white-bordered square print in
    /// the sixties and seventies, and nothing since.
    private static func paper(_ frame: Frame, size: CGSize, inner: CGRect, ink: Ink, dice: inout Dice) {
        let whole = CGRect(origin: .zero, size: size)
        let canvas = Canvas(cg: UIGraphicsGetCurrentContext()!, r: whole, ink: ink)
        switch frame {
        case .mount:
            canvas.gradient(whole, top: (0.86, 0.8, 0.68), bottom: (0.78, 0.72, 0.6))
            let rule = inner.insetBy(dx: -size.width * 0.012, dy: -size.width * 0.012)
            ink.colour((0.55, 0.47, 0.34)).setStroke()
            let path = UIBezierPath(rect: rule)
            path.lineWidth = max(2, size.width * 0.003)
            path.stroke()
            // The studio's name, pressed into the card under the picture.
            let imprint = CGRect(
                x: size.width * 0.34, y: inner.maxY + (size.height - inner.maxY) * 0.42,
                width: size.width * 0.32, height: size.height * 0.012
            )
            canvas.rounded(imprint, radius: imprint.height / 2, (0.5, 0.42, 0.3), alpha: 0.7)
        case .deckle:
            canvas.fill(whole, (0.1, 0.1, 0.1))
            let edge = inner.insetBy(dx: -min(size.width, size.height) * 0.045, dy: -min(size.width, size.height) * 0.045)
            let tooth = min(size.width, size.height) * 0.012
            var points: [CGPoint] = []
            func run(from a: CGPoint, to b: CGPoint, out: CGVector) {
                let steps = Int(hypot(b.x - a.x, b.y - a.y) / tooth)
                for step in 0 ..< max(steps, 1) {
                    let t = CGFloat(step) / CGFloat(max(steps, 1))
                    let bump: CGFloat = step % 2 == 0 ? 0 : tooth * 0.45
                    points.append(CGPoint(x: a.x + (b.x - a.x) * t + out.dx * bump, y: a.y + (b.y - a.y) * t + out.dy * bump))
                }
            }
            run(from: CGPoint(x: edge.minX, y: edge.minY), to: CGPoint(x: edge.maxX, y: edge.minY), out: CGVector(dx: 0, dy: -1))
            run(from: CGPoint(x: edge.maxX, y: edge.minY), to: CGPoint(x: edge.maxX, y: edge.maxY), out: CGVector(dx: 1, dy: 0))
            run(from: CGPoint(x: edge.maxX, y: edge.maxY), to: CGPoint(x: edge.minX, y: edge.maxY), out: CGVector(dx: 0, dy: 1))
            run(from: CGPoint(x: edge.minX, y: edge.maxY), to: CGPoint(x: edge.minX, y: edge.minY), out: CGVector(dx: -1, dy: 0))
            canvas.shape(points, (0.95, 0.94, 0.9))
        case .white:
            canvas.fill(whole, (0.96, 0.95, 0.92))
        case .none:
            break
        }
    }

    /// The paper corners that hold a print on an album page.
    private static func corners(inner: CGRect, ink: Ink) {
        let canvas = Canvas(cg: UIGraphicsGetCurrentContext()!, r: inner, ink: ink)
        let side = min(inner.width, inner.height) * 0.14
        let pad = min(inner.width, inner.height) * 0.07
        let outer = inner.insetBy(dx: -pad, dy: -pad)
        let colour: RGB = (0.16, 0.16, 0.16)
        canvas.shape([CGPoint(x: outer.minX, y: outer.minY), CGPoint(x: outer.minX + side, y: outer.minY),
                      CGPoint(x: outer.minX, y: outer.minY + side)], colour)
        canvas.shape([CGPoint(x: outer.maxX, y: outer.minY), CGPoint(x: outer.maxX - side, y: outer.minY),
                      CGPoint(x: outer.maxX, y: outer.minY + side)], colour)
        canvas.shape([CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: outer.minX + side, y: outer.maxY),
                      CGPoint(x: outer.minX, y: outer.maxY - side)], colour)
        canvas.shape([CGPoint(x: outer.maxX, y: outer.maxY), CGPoint(x: outer.maxX - side, y: outer.maxY),
                      CGPoint(x: outer.maxX, y: outer.maxY - side)], colour)
    }

    /// What the years did to the print: a darker edge, grain, a scratch.
    private static func weather(_ c: Canvas, tone: Tone, dice: inout Dice) {
        let strength: CGFloat
        switch tone {
        case .sepia: strength = 0.45
        case .mono: strength = 0.36
        case .faded: strength = 0.22
        case .warm: strength = 0.12
        case .vivid: strength = 0.04
        case .colourised: strength = 0.2
        }
        let colours = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: strength).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
            let centre = CGPoint(x: c.r.midX, y: c.r.midY)
            let reach = hypot(c.r.width, c.r.height) / 2
            c.cg.drawRadialGradient(
                gradient, startCenter: centre, startRadius: reach * 0.45,
                endCenter: centre, endRadius: reach, options: [.drawsAfterEndLocation]
            )
        }
        guard tone == .sepia || tone == .mono || tone == .faded else { return }
        let dots = Int(c.r.width * c.r.height / 700)
        let dark = CGMutablePath(), light = CGMutablePath()
        for index in 0 ..< dots {
            let dot = CGRect(
                x: c.r.minX + dice.unit() * c.r.width, y: c.r.minY + dice.unit() * c.r.height,
                width: 2, height: 2
            )
            if index % 2 == 0 { dark.addRect(dot) } else { light.addRect(dot) }
        }
        c.cg.addPath(dark)
        c.cg.setFillColor(UIColor(white: 0, alpha: 0.16).cgColor)
        c.cg.fillPath()
        c.cg.addPath(light)
        c.cg.setFillColor(UIColor(white: 1, alpha: 0.14).cgColor)
        c.cg.fillPath()
        guard tone != .faded else { return }
        for _ in 0 ..< 3 {
            let start = CGPoint(x: c.x(dice.unit()), y: c.y(dice.unit()))
            let end = CGPoint(x: start.x + c.h(dice.range(-0.2, 0.2)), y: start.y + c.h(dice.range(0.1, 0.4)))
            c.line(start, end, width: 1.5, (1, 1, 1), alpha: 0.35)
        }
    }

    /// The mark `ColourSheet` draws into a kept colouring (`ColourMark`):
    /// a paper disc in a black ring with a palette, bottom left, because a
    /// caption does not travel with a picture and the pixels do.
    private static func mark(size: CGSize) {
        let diameter = max(48, min(size.width, size.height) * 0.11)
        let inset = diameter * 0.3
        let disc = CGRect(x: inset, y: size.height - diameter - inset, width: diameter, height: diameter)
        let ring = UIBezierPath(ovalIn: disc)
        (UIColor(named: "Paper") ?? .white).setFill()
        ring.fill()
        ring.lineWidth = max(2, diameter * 0.06)
        UIColor.black.setStroke()
        ring.stroke()
        let glyph = UIImage(
            systemName: "paintpalette.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.46, weight: .semibold)
        )?.withTintColor(.black, renderingMode: .alwaysOriginal)
        glyph?.draw(in: CGRect(
            x: disc.midX - (glyph?.size.width ?? 0) / 2, y: disc.midY - (glyph?.size.height ?? 0) / 2,
            width: glyph?.size.width ?? 0, height: glyph?.size.height ?? 0
        ))
    }

    // MARK: - Where the people stand

    private enum Look { case man, woman, bride, groom, soldier, graduate, robe, swimmer, baby }

    private struct Figure {
        var x: CGFloat
        var foot: CGFloat
        var height: CGFloat
        var look: Look
        var age: Int
        var female: Bool
        var sitter: Int?
        var tint: Int

        var child: Bool { age < 14 }
        var headRadius: CGFloat { look == .baby ? height * 0.35 : height * (child ? 0.115 : 0.09) }

        func head(in r: CGRect) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + (foot - height + headRadius) * r.height)
        }
    }

    private static func stature(_ sitter: Sitter) -> CGFloat {
        if sitter.age >= 16 { return sitter.female ? 0.94 : 1 }
        return 0.36 + 0.042 * CGFloat(max(sitter.age, 0))
    }

    private static func plain(_ sitter: Sitter) -> Look { sitter.female ? .woman : .man }

    private static func row(
        _ indices: [Int], of print: Print, from x0: CGFloat, to x1: CGFloat,
        foot: CGFloat, height: CGFloat, look: (Sitter) -> Look = plain, dice: inout Dice
    ) -> [Figure] {
        guard !indices.isEmpty else { return [] }
        let step = indices.count == 1 ? 0 : (x1 - x0) / CGFloat(indices.count - 1)
        return indices.enumerated().map { place, index in
            let sitter = print.sitters[index]
            let x = indices.count == 1 ? (x0 + x1) / 2 : x0 + step * CGFloat(place)
            return Figure(
                x: x + dice.range(-0.008, 0.008), foot: foot + dice.range(-0.006, 0.006),
                height: height * stature(sitter) * dice.range(0.97, 1.03), look: look(sitter),
                age: sitter.age, female: sitter.female, sitter: index, tint: dice.int(12)
            )
        }
    }

    /// A family in front of something: one row up to five, and above that
    /// the tall at the back, a step up the picture, and the small in front.
    private static func crowd(
        _ indices: [Int], of print: Print, from x0: CGFloat, to x1: CGFloat,
        foot: CGFloat, height: CGFloat, dice: inout Dice
    ) -> [Figure] {
        guard indices.count > 5 else {
            return row(indices, of: print, from: x0, to: x1, foot: foot, height: height, dice: &dice)
        }
        let byHeight = indices.sorted { stature(print.sitters[$0]) > stature(print.sitters[$1]) }
        let backCount = (indices.count + 1) / 2
        let back = Array(byHeight.prefix(backCount)).sorted()
        let front = Array(byHeight.dropFirst(backCount)).sorted()
        return row(back, of: print, from: x0 + 0.05, to: x1 - 0.05, foot: foot - 0.08, height: height * 0.94, dice: &dice)
            + row(front, of: print, from: x0, to: x1, foot: foot, height: height, dice: &dice)
    }

    private static func layout(_ print: Print) -> [Figure] {
        var dice = Dice(print.number &* 7919 &+ 17)
        let all = Array(print.sitters.indices)
        switch print.scene {
        case .studio:
            // Framed to the chest, whoever it is: a photographer framed a
            // face, not a height.
            guard all.count > 1 else {
                let sitter = print.sitters[0]
                return [Figure(x: 0.5, foot: 1.18, height: 0.96, look: plain(sitter), age: sitter.age,
                               female: sitter.female, sitter: 0, tint: dice.int(12))]
            }
            return row(all, of: print, from: 0.33, to: 0.67, foot: 1.16, height: 0.9, dice: &dice)
        case .couple:
            return row(all, of: print, from: 0.34, to: 0.66, foot: 1.12, height: 0.9, dice: &dice)
        case .wedding:
            let couple = Array(all.prefix(2))
            let guests = Array(all.dropFirst(2))
            let left = guests.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let right = guests.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            return row(left, of: print, from: 0.06, to: 0.3, foot: 0.9, height: 0.56, dice: &dice)
                + row(right, of: print, from: 0.7, to: 0.94, foot: 0.9, height: 0.56, dice: &dice)
                + row(couple, of: print, from: 0.43, to: 0.57, foot: 0.97, height: 0.64,
                      look: { $0.female ? .bride : .groom }, dice: &dice)
        case .group:
            return crowd(all, of: print, from: 0.14, to: 0.86, foot: 0.95, height: 0.52, dice: &dice)
        case .farm:
            return crowd(all, of: print, from: 0.42, to: 0.9, foot: 0.95, height: 0.46, dice: &dice)
        case .christmas:
            return crowd(all, of: print, from: 0.42, to: 0.9, foot: 0.97, height: 0.55, dice: &dice)
        case .car:
            return crowd(all, of: print, from: 0.62, to: 0.92, foot: 0.95, height: 0.5, dice: &dice)
        case .table:
            return row(all, of: print, from: 0.2, to: 0.8, foot: 1.02, height: 0.64, dice: &dice)
        case .haying:
            return row(all, of: print, from: 0.12, to: 0.88, foot: 0.9, height: 0.42, dice: &dice)
                .map { figure in
                    var figure = figure
                    figure.foot += dice.range(-0.05, 0.03)
                    return figure
                }
        case .lake:
            return row(Array(all.prefix(3)), of: print, from: 0.47, to: 0.6, foot: 0.8, height: 0.3, dice: &dice)
                + row(Array(all.dropFirst(3)), of: print, from: 0.05, to: 0.21, foot: 0.86, height: 0.34, dice: &dice)
        case .sauna:
            return row(all, of: print, from: 0.52, to: 0.88, foot: 0.8, height: 0.3, dice: &dice)
        case .winter:
            return row(all, of: print, from: 0.2, to: 0.8, foot: 0.9, height: 0.46, dice: &dice)
        case .soldiers:
            return row(all, of: print, from: 0.3, to: 0.86, foot: 0.93, height: 0.55,
                       look: { $0.female ? .woman : .soldier }, dice: &dice)
        case .graduation:
            let first = print.sitters[0]
            let alone = all.count == 1
            var figures = [Figure(
                x: 0.5, foot: alone ? 1.12 : 1.02, height: alone ? 0.88 : 0.7,
                look: first.age < 17 ? .robe : .graduate, age: first.age, female: first.female,
                sitter: 0, tint: dice.int(12)
            )]
            let spots: [CGFloat] = [0.22, 0.78, 0.08, 0.92]
            for (place, index) in all.dropFirst().prefix(spots.count).enumerated() {
                let sitter = print.sitters[index]
                figures.append(Figure(
                    x: spots[place], foot: 1.02, height: 0.64 * stature(sitter), look: plain(sitter),
                    age: sitter.age, female: sitter.female, sitter: index, tint: dice.int(12)
                ))
            }
            return figures
        case .beach:
            return row(all, of: print, from: 0.18, to: 0.82, foot: 0.92, height: 0.42,
                       look: { _ in .swimmer }, dice: &dice)
        case .school:
            // A class: two rows of children the family never named, the named
            // ones among them, and a grown-up at the end of the row.
            let children = all.filter { print.sitters[$0].age < 16 }
            let grownUps = all.filter { print.sitters[$0].age >= 16 }
            var seats = Array(0 ..< 14)
            var named: [Int: Int] = [:]
            for child in children {
                let seat = seats.remove(at: dice.int(seats.count))
                named[seat] = child
            }
            var figures: [Figure] = []
            for seat in 0 ..< 14 {
                let back = seat < 7
                let x = 0.1 + CGFloat(seat % 7) * 0.12 + (back ? 0.03 : 0)
                let index = named[seat]
                let age = index.map { print.sitters[$0].age } ?? 9
                let female = index.map { print.sitters[$0].female } ?? (dice.int(2) == 0)
                figures.append(Figure(
                    x: x, foot: back ? 0.76 : 0.93, height: (back ? 0.4 : 0.38) * stature(Sitter(age: age, female: female)),
                    look: female ? .woman : .man, age: age, female: female, sitter: index, tint: dice.int(12)
                ))
            }
            if let teacher = grownUps.first {
                let sitter = print.sitters[teacher]
                figures.append(Figure(
                    x: 0.93, foot: 0.93, height: 0.56 * stature(sitter), look: plain(sitter),
                    age: sitter.age, female: sitter.female, sitter: teacher, tint: dice.int(12)
                ))
            }
            return figures
        case .town:
            var figures = row(all, of: print, from: 0.36, to: 0.64, foot: 0.95, height: 0.5, dice: &dice)
            for _ in 0 ..< 3 {
                let female = dice.int(2) == 0
                figures.append(Figure(
                    x: dice.range(0.05, 0.95), foot: 0.8, height: 0.2, look: female ? .woman : .man,
                    age: 40, female: female, sitter: nil, tint: dice.int(12)
                ))
            }
            return figures
        case .baby:
            let babies = all.filter { print.sitters[$0].age <= 2 }
            let others = all.filter { print.sitters[$0].age > 2 }
            var figures = row(others, of: print, from: 0.18, to: 0.46, foot: 0.94, height: 0.6, dice: &dice)
            for (place, index) in babies.prefix(1).enumerated() {
                figures.append(Figure(
                    x: 0.64 + CGFloat(place) * 0.04, foot: 0.655, height: 0.1, look: .baby,
                    age: 0, female: print.sitters[index].female, sitter: index, tint: dice.int(12)
                ))
            }
            return figures
        }
    }

    // MARK: - Scenes

    private static func scene(_ print: Print, on c: Canvas, dice: inout Dice) {
        switch print.scene {
        case .studio, .couple:
            backdrop(c, year: print.year)
        case .wedding:
            if print.year < 1945 {
                backdrop(c, year: print.year)
            } else {
                outdoors(c, horizon: 0.55, dice: &dice)
                church(c)
            }
        case .group:
            outdoors(c, horizon: 0.5, dice: &dice)
            house(c, x0: 0.1, x1: 0.9, base: 0.68, height: 0.36, wall: wall(print.year, dice: &dice), dice: &dice)
        case .farm:
            outdoors(c, horizon: 0.46, dice: &dice)
            barn(c, x0: 0.56, x1: 0.99, base: 0.6, height: 0.22)
            house(c, x0: 0.02, x1: 0.5, base: 0.62, height: 0.32, wall: (0.62, 0.2, 0.15), dice: &dice)
            horse(c, x: 0.2, foot: 0.93)
        case .christmas:
            interior(c, dice: &dice)
            christmasTree(c, x: 0.2, base: 0.98, height: 0.82, year: print.year, dice: &dice)
        case .car:
            outdoors(c, horizon: 0.5, dice: &dice)
            c.fill(c.box(0, 0.8, 1, 1), (0.5, 0.49, 0.46))
            car(c, year: print.year, dice: &dice)
        case .haying:
            field(c, dice: &dice)
        case .lake:
            lake(c, shore: 0.42, dice: &dice)
            c.fill(c.box(0, 0.86, 0.26, 0.9), (0.5, 0.42, 0.3))
        case .sauna:
            lake(c, shore: 0.4, dice: &dice)
            sauna(c, dice: &dice)
        case .winter:
            winter(c, dice: &dice)
        case .soldiers:
            camp(c, dice: &dice)
        case .graduation:
            courtyard(c, dice: &dice)
        case .beach:
            beach(c, dice: &dice)
        case .school:
            school(c, year: print.year)
        case .town:
            town(c, year: print.year, dice: &dice)
        case .table:
            outdoors(c, horizon: 0.5, dice: &dice)
            birch(c, x: 0.06, base: 0.72, height: 0.66, dice: &dice)
            birch(c, x: 0.94, base: 0.7, height: 0.6, dice: &dice)
        case .baby:
            outdoors(c, horizon: 0.5, dice: &dice)
            house(c, x0: 0.7, x1: 1.2, base: 0.66, height: 0.4, wall: wall(print.year, dice: &dice), dice: &dice)
            pram(c)
        }

        for figure in layout(print).sorted(by: { $0.foot < $1.foot }) {
            person(figure, on: c, year: print.year, scene: print.scene)
        }

        switch print.scene {
        case .lake: boat(c)
        case .table: table(c, guests: print.sitters.count, dice: &dice)
        case .winter: snowfall(c, dice: &dice)
        default: break
        }
    }

    private static func wall(_ year: Int, dice: inout Dice) -> RGB {
        let walls: [RGB] = [(0.62, 0.2, 0.15), (0.84, 0.72, 0.42), (0.92, 0.9, 0.84), (0.58, 0.64, 0.7), (0.5, 0.6, 0.44)]
        return year < 1950 ? walls[dice.int(2)] : walls[dice.int(walls.count)]
    }

    private static func backdrop(_ c: Canvas, year: Int) {
        c.gradient(c.r, top: (0.62, 0.58, 0.52), bottom: (0.4, 0.37, 0.33))
        let glow = [c.ink.colour((0.82, 0.78, 0.7), alpha: 0.7).cgColor, c.ink.colour((0.82, 0.78, 0.7), alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glow, locations: [0, 1]) {
            let centre = c.point(0.5, 0.36)
            c.cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                    endRadius: c.h(0.45), options: [])
        }
        guard year < 1935 else { return }
        // A painted studio: a drape at one side and a plant on a stand at the other.
        c.shape([c.point(0, 0), c.point(0.2, 0), c.point(0.12, 0.35), c.point(0.16, 0.7), c.point(0.08, 1), c.point(0, 1)],
                (0.3, 0.25, 0.21))
        c.fill(c.box(0.84, 0.62, 0.9, 1), (0.36, 0.3, 0.24))
        for leaf in 0 ..< 7 {
            let angle = CGFloat(leaf) * 0.45 - 1.4
            let from = c.point(0.87, 0.62)
            let to = CGPoint(x: from.x + cos(angle - .pi / 2) * c.h(0.16), y: from.y + sin(angle - .pi / 2) * c.h(0.16))
            c.line(from, to, width: c.h(0.018), (0.2, 0.32, 0.18))
        }
    }

    private static func outdoors(_ c: Canvas, horizon: CGFloat, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, horizon), top: (0.5, 0.68, 0.88), bottom: (0.86, 0.9, 0.93))
        for _ in 0 ..< 3 {
            let centre = c.point(dice.range(0.05, 0.95), dice.range(0.05, horizon * 0.6))
            for puff in 0 ..< 4 {
                c.disc(CGPoint(x: centre.x + c.h(CGFloat(puff) * 0.05), y: centre.y + c.h(dice.range(-0.015, 0.015))),
                       c.h(dice.range(0.035, 0.06)), (1, 1, 1), alpha: 0.55)
            }
        }
        forest(c, line: horizon, height: 0.12, colour: (0.16, 0.3, 0.2), snow: false, dice: &dice)
        c.gradient(c.box(0, horizon, 1, 1), top: (0.44, 0.6, 0.3), bottom: (0.3, 0.46, 0.22))
    }

    private static func forest(_ c: Canvas, line: CGFloat, height: CGFloat, colour: RGB, snow: Bool, dice: inout Dice) {
        var x: CGFloat = -0.02
        while x < 1.02 {
            spruce(c, x: x, base: line + 0.004, height: height * dice.range(0.6, 1.25), colour: colour, snow: snow)
            x += dice.range(0.018, 0.04)
        }
    }

    private static func spruce(_ c: Canvas, x: CGFloat, base: CGFloat, height: CGFloat, colour: RGB, snow: Bool) {
        let tall = c.h(height), centre = c.x(x), foot = c.y(base)
        c.fill(CGRect(x: centre - tall * 0.02, y: foot - tall * 0.1, width: tall * 0.04, height: tall * 0.1), (0.25, 0.18, 0.12))
        for tier in 0 ..< 3 {
            let apex = foot - tall + CGFloat(tier) * tall * 0.25
            let bottom = apex + tall * 0.45
            let half = tall * (0.12 + 0.08 * CGFloat(tier))
            c.shape([CGPoint(x: centre, y: apex), CGPoint(x: centre + half, y: bottom), CGPoint(x: centre - half, y: bottom)], colour)
            if snow {
                c.shape([CGPoint(x: centre, y: apex), CGPoint(x: centre + half * 0.45, y: apex + tall * 0.2),
                         CGPoint(x: centre - half * 0.45, y: apex + tall * 0.2)], (0.96, 0.97, 0.98))
            }
        }
    }

    private static func birch(_ c: Canvas, x: CGFloat, base: CGFloat, height: CGFloat, dice: inout Dice) {
        let tall = c.h(height), centre = c.x(x), foot = c.y(base)
        let trunk = CGRect(x: centre - tall * 0.02, y: foot - tall * 0.85, width: tall * 0.04, height: tall * 0.85)
        c.fill(trunk, (0.93, 0.92, 0.88))
        for _ in 0 ..< 8 {
            c.fill(CGRect(x: trunk.minX, y: trunk.minY + dice.unit() * trunk.height, width: trunk.width * dice.range(0.4, 1),
                          height: tall * 0.012), (0.15, 0.14, 0.13))
        }
        for _ in 0 ..< 6 {
            c.disc(CGPoint(x: centre + tall * dice.range(-0.2, 0.2), y: foot - tall * dice.range(0.72, 1)),
                   tall * dice.range(0.1, 0.17), (0.45, 0.62, 0.3), alpha: 0.9)
        }
    }

    private static func house(_ c: Canvas, x0: CGFloat, x1: CGFloat, base: CGFloat, height: CGFloat, wall: RGB, dice: inout Dice) {
        let roof = height * 0.34
        let top = base - height
        c.fill(c.box(x0, top + roof, x1, base), wall)
        c.shape([c.point(x0 - 0.02, top + roof), c.point((x0 + x1) / 2, top), c.point(x1 + 0.02, top + roof)], (0.24, 0.22, 0.22))
        c.fill(c.box(x1 - 0.12 * (x1 - x0), top + roof * 0.1, x1 - 0.08 * (x1 - x0), top + roof * 0.7), (0.45, 0.3, 0.25))
        c.fill(c.box(x0, top + roof, x0 + 0.012, base), (0.95, 0.94, 0.9))
        c.fill(c.box(x1 - 0.012, top + roof, x1, base), (0.95, 0.94, 0.9))
        let windows = max(2, Int((x1 - x0) / 0.14))
        for index in 0 ..< windows {
            let left = x0 + (x1 - x0) * (CGFloat(index) + 0.3) / CGFloat(windows)
            let width = (x1 - x0) * 0.4 / CGFloat(windows)
            let frame = c.box(left, top + roof + (height - roof) * 0.18, left + width, top + roof + (height - roof) * 0.62)
            c.fill(frame, (0.95, 0.94, 0.9))
            c.fill(frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.08), (0.2, 0.25, 0.3))
            c.fill(CGRect(x: frame.midX - frame.width * 0.04, y: frame.minY, width: frame.width * 0.08, height: frame.height),
                   (0.95, 0.94, 0.9))
        }
    }

    private static func barn(_ c: Canvas, x0: CGFloat, x1: CGFloat, base: CGFloat, height: CGFloat) {
        c.fill(c.box(x0, base - height * 0.7, x1, base), (0.46, 0.4, 0.34))
        c.shape([c.point(x0 - 0.01, base - height * 0.7), c.point((x0 + x1) / 2, base - height), c.point(x1 + 0.01, base - height * 0.7)],
                (0.3, 0.27, 0.25))
        c.fill(c.box((x0 + x1) / 2 - 0.05, base - height * 0.5, (x0 + x1) / 2 + 0.05, base), (0.3, 0.24, 0.18))
    }

    private static func horse(_ c: Canvas, x: CGFloat, foot: CGFloat) {
        let brown: RGB = (0.4, 0.26, 0.16)
        let body = c.box(x - 0.12, foot - 0.3, x + 0.08, foot - 0.16)
        for leg in [x - 0.1, x - 0.07, x + 0.03, x + 0.06] {
            c.fill(c.box(leg, foot - 0.2, leg + 0.018, foot), brown)
        }
        c.oval(body, brown)
        c.shape([c.point(x + 0.04, foot - 0.28), c.point(x + 0.12, foot - 0.42), c.point(x + 0.16, foot - 0.38),
                 c.point(x + 0.08, foot - 0.22)], brown)
        c.oval(c.box(x + 0.1, foot - 0.44, x + 0.19, foot - 0.36), brown)
        c.line(c.point(x - 0.12, foot - 0.26), c.point(x - 0.16, foot - 0.14), width: c.h(0.02), (0.2, 0.14, 0.1))
    }

    private static func interior(_ c: Canvas, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, 0.78), top: (0.8, 0.72, 0.56), bottom: (0.7, 0.62, 0.48))
        var stripe: CGFloat = 0
        while stripe < 1 {
            c.fill(c.box(stripe, 0, stripe + 0.006, 0.78), (0.55, 0.45, 0.32), alpha: 0.25)
            stripe += 0.045
        }
        c.gradient(c.box(0, 0.78, 1, 1), top: (0.52, 0.36, 0.22), bottom: (0.42, 0.28, 0.16))
        let window = c.box(0.66, 0.1, 0.9, 0.46)
        c.fill(window.insetBy(dx: -c.h(0.012), dy: -c.h(0.012)), (0.95, 0.94, 0.9))
        c.gradient(window, top: (0.08, 0.12, 0.26), bottom: (0.16, 0.2, 0.36))
        c.fill(CGRect(x: window.midX - c.h(0.006), y: window.minY, width: c.h(0.012), height: window.height), (0.95, 0.94, 0.9))
        c.fill(CGRect(x: window.minX, y: window.midY - c.h(0.006), width: window.width, height: c.h(0.012)), (0.95, 0.94, 0.9))
        for _ in 0 ..< 12 {
            c.disc(CGPoint(x: window.minX + dice.unit() * window.width, y: window.minY + dice.unit() * window.height),
                   c.h(0.004), (1, 1, 1), alpha: 0.8)
        }
    }

    private static func christmasTree(_ c: Canvas, x: CGFloat, base: CGFloat, height: CGFloat, year: Int, dice: inout Dice) {
        let tall = c.h(height), centre = c.x(x), foot = c.y(base)
        c.fill(CGRect(x: centre - tall * 0.03, y: foot - tall * 0.08, width: tall * 0.06, height: tall * 0.08), (0.35, 0.22, 0.12))
        for tier in 0 ..< 4 {
            let apex = foot - tall + CGFloat(tier) * tall * 0.2
            let half = tall * (0.1 + 0.07 * CGFloat(tier))
            c.shape([CGPoint(x: centre, y: apex), CGPoint(x: centre + half, y: apex + tall * 0.34),
                     CGPoint(x: centre - half, y: apex + tall * 0.34)], (0.12, 0.34, 0.18))
        }
        for _ in 0 ..< 28 {
            let depth = dice.range(0.08, 0.9)
            let reach = tall * (0.05 + 0.3 * depth)
            let light = CGPoint(x: centre + dice.range(-1, 1) * reach * 0.8, y: foot - tall + depth * tall * 0.9)
            c.disc(light, c.h(0.012), (1, 0.9, 0.55), alpha: 0.35)
            c.disc(light, c.h(0.005), (1, 0.96, 0.8))
        }
        if year >= 1950 {
            for _ in 0 ..< 10 {
                let depth = dice.range(0.15, 0.85)
                c.disc(CGPoint(x: centre + dice.range(-1, 1) * tall * (0.05 + 0.28 * depth), y: foot - tall + depth * tall * 0.9),
                       c.h(0.009), (0.82, 0.14, 0.14))
            }
        }
        c.disc(CGPoint(x: centre, y: foot - tall), c.h(0.018), (0.98, 0.84, 0.3))
    }

    private static func car(_ c: Canvas, year: Int, dice: inout Dice) {
        let paints: [RGB] = year < 1970
            ? [(0.55, 0.7, 0.82), (0.9, 0.88, 0.8), (0.72, 0.15, 0.15), (0.3, 0.34, 0.3)]
            : [(0.85, 0.5, 0.15), (0.3, 0.5, 0.3), (0.6, 0.45, 0.25), (0.82, 0.8, 0.74)]
        let paint = paints[dice.int(paints.count)]
        c.shape([c.point(0.15, 0.71), c.point(0.2, 0.585), c.point(0.42, 0.585), c.point(0.48, 0.71)], paint)
        c.shape([c.point(0.18, 0.7), c.point(0.215, 0.605), c.point(0.305, 0.605), c.point(0.305, 0.7)], (0.72, 0.8, 0.85))
        c.shape([c.point(0.32, 0.7), c.point(0.32, 0.605), c.point(0.405, 0.605), c.point(0.45, 0.7)], (0.72, 0.8, 0.85))
        c.rounded(c.box(0.05, 0.7, 0.56, 0.87), radius: c.h(0.035), paint)
        c.fill(c.box(0.05, 0.835, 0.56, 0.848), (0.82, 0.82, 0.8))
        c.disc(c.point(0.545, 0.77), c.h(0.018), (0.98, 0.95, 0.8))
        for wheel in [0.16, 0.45] as [CGFloat] {
            c.disc(c.point(wheel, 0.87), c.h(0.06), (0.08, 0.08, 0.08))
            c.disc(c.point(wheel, 0.87), c.h(0.025), (0.7, 0.7, 0.7))
        }
    }

    private static func field(_ c: Canvas, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, 0.42), top: (0.46, 0.66, 0.9), bottom: (0.86, 0.9, 0.92))
        forest(c, line: 0.42, height: 0.1, colour: (0.14, 0.28, 0.18), snow: false, dice: &dice)
        c.gradient(c.box(0, 0.42, 1, 1), top: (0.8, 0.72, 0.4), bottom: (0.68, 0.58, 0.3))
        var pole: CGFloat = 0.04
        while pole < 0.97 {
            c.fill(c.box(pole, 0.43, pole + 0.005, 0.64), (0.3, 0.22, 0.14))
            pole += 0.07
        }
        c.rounded(c.box(0.03, 0.47, 0.97, 0.61), radius: c.h(0.03), (0.6, 0.5, 0.28))
        for _ in 0 ..< 40 {
            let y = dice.range(0.48, 0.6)
            c.line(c.point(dice.range(0.04, 0.9), y), c.point(dice.range(0.05, 0.96), y), width: 2, (0.45, 0.36, 0.2), alpha: 0.5)
        }
        for _ in 0 ..< 160 {
            let base = c.point(dice.unit(), dice.range(0.63, 1))
            c.line(base, CGPoint(x: base.x + c.h(0.004), y: base.y - c.h(0.015)), width: 2, (0.55, 0.45, 0.22), alpha: 0.6)
        }
    }

    private static func lake(_ c: Canvas, shore: CGFloat, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, shore), top: (0.55, 0.7, 0.88), bottom: (0.88, 0.9, 0.9))
        forest(c, line: shore, height: 0.1, colour: (0.12, 0.24, 0.16), snow: false, dice: &dice)
        c.gradient(c.box(0, shore, 1, 1), top: (0.46, 0.58, 0.68), bottom: (0.2, 0.32, 0.45))
        for _ in 0 ..< 40 {
            let y = dice.range(shore + 0.02, 1)
            let x = dice.unit()
            c.line(c.point(x, y), c.point(x + dice.range(0.03, 0.12), y), width: 2, (0.85, 0.9, 0.95), alpha: 0.3)
        }
    }

    private static func boat(_ c: Canvas) {
        c.shape([c.point(0.37, 0.745), c.point(0.71, 0.745), c.point(0.66, 0.815), c.point(0.42, 0.815)], (0.36, 0.22, 0.12))
        c.fill(c.box(0.37, 0.742, 0.71, 0.752), (0.55, 0.38, 0.22))
        c.line(c.point(0.43, 0.76), c.point(0.3, 0.84), width: c.h(0.008), (0.5, 0.36, 0.22))
        c.line(c.point(0.65, 0.76), c.point(0.78, 0.84), width: c.h(0.008), (0.5, 0.36, 0.22))
    }

    private static func sauna(_ c: Canvas, dice: inout Dice) {
        c.shape([c.point(0, 0.5), c.point(0.36, 0.52), c.point(0.46, 0.7), c.point(0.4, 1), c.point(0, 1)], (0.36, 0.5, 0.26))
        c.fill(c.box(0.05, 0.47, 0.3, 0.66), (0.3, 0.2, 0.12))
        var log: CGFloat = 0.49
        while log < 0.66 {
            c.fill(c.box(0.05, log, 0.3, log + 0.004), (0.18, 0.12, 0.08))
            log += 0.025
        }
        c.shape([c.point(0.03, 0.48), c.point(0.175, 0.39), c.point(0.32, 0.48)], (0.2, 0.17, 0.16))
        c.fill(c.box(0.23, 0.37, 0.255, 0.44), (0.4, 0.38, 0.36))
        for puff in 0 ..< 5 {
            c.disc(c.point(0.245 + CGFloat(puff) * 0.02, 0.35 - CGFloat(puff) * 0.04), c.h(0.02 + CGFloat(puff) * 0.008),
                   (0.85, 0.85, 0.86), alpha: 0.5)
        }
        c.fill(c.box(0.09, 0.55, 0.14, 0.66), (0.12, 0.08, 0.05))
        c.fill(c.box(0.2, 0.53, 0.25, 0.57), (0.75, 0.8, 0.82))
        c.fill(c.box(0.36, 0.8, 0.98, 0.835), (0.56, 0.46, 0.32))
        for post in stride(from: 0.4 as CGFloat, to: 0.98, by: 0.09) {
            c.fill(c.box(post, 0.835, post + 0.008, 0.9), (0.3, 0.24, 0.16))
        }
        _ = dice.unit()
    }

    private static func winter(_ c: Canvas, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, 0.46), top: (0.74, 0.77, 0.82), bottom: (0.9, 0.9, 0.92))
        forest(c, line: 0.46, height: 0.16, colour: (0.14, 0.24, 0.19), snow: true, dice: &dice)
        c.gradient(c.box(0, 0.46, 1, 1), top: (0.97, 0.97, 0.98), bottom: (0.86, 0.89, 0.94))
        for _ in 0 ..< 6 {
            c.oval(c.box(dice.range(-0.1, 0.9), dice.range(0.5, 0.95), dice.range(0.2, 1.1), dice.range(0.52, 1)),
                   (0.82, 0.86, 0.92), alpha: 0.4)
        }
        for track in [0.3, 0.33] as [CGFloat] {
            c.line(c.point(track, 1), c.point(track + 0.3, 0.55), width: 3, (0.7, 0.72, 0.78), alpha: 0.7)
        }
    }

    private static func snowfall(_ c: Canvas, dice: inout Dice) {
        for _ in 0 ..< 140 {
            c.disc(c.point(dice.unit(), dice.unit()), c.h(dice.range(0.002, 0.005)), (1, 1, 1), alpha: 0.85)
        }
    }

    private static func camp(_ c: Canvas, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, 0.4), top: (0.72, 0.74, 0.76), bottom: (0.86, 0.86, 0.86))
        forest(c, line: 0.5, height: 0.3, colour: (0.1, 0.2, 0.14), snow: false, dice: &dice)
        forest(c, line: 0.64, height: 0.22, colour: (0.14, 0.26, 0.18), snow: false, dice: &dice)
        c.gradient(c.box(0, 0.63, 1, 1), top: (0.44, 0.42, 0.34), bottom: (0.34, 0.32, 0.26))
        c.shape([c.point(0.13, 0.52), c.point(0.27, 0.82), c.point(-0.01, 0.82)], (0.4, 0.42, 0.33))
        c.shape([c.point(0.13, 0.62), c.point(0.17, 0.82), c.point(0.09, 0.82)], (0.16, 0.16, 0.13))
    }

    private static func courtyard(_ c: Canvas, dice: inout Dice) {
        c.fill(c.box(0, 0, 1, 0.66), (0.86, 0.83, 0.76))
        for left in [0.3, 0.6] as [CGFloat] {
            let window = c.box(left, 0.12, left + 0.1, 0.36)
            c.fill(window, (0.95, 0.94, 0.9))
            c.fill(window.insetBy(dx: window.width * 0.12, dy: window.height * 0.06), (0.3, 0.34, 0.38))
        }
        c.gradient(c.box(0, 0.66, 1, 1), top: (0.62, 0.6, 0.56), bottom: (0.52, 0.5, 0.46))
        for side in [0.1, 0.9] as [CGFloat] {
            for _ in 0 ..< 14 {
                c.disc(c.point(side + dice.range(-0.1, 0.1), dice.range(0.34, 0.74)), c.h(dice.range(0.03, 0.06)), (0.3, 0.45, 0.25))
            }
            for _ in 0 ..< 10 {
                c.disc(c.point(side + dice.range(-0.09, 0.09), dice.range(0.36, 0.6)), c.h(dice.range(0.02, 0.035)), (0.62, 0.48, 0.72))
            }
        }
    }

    private static func beach(_ c: Canvas, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, 0.36), top: (0.4, 0.65, 0.9), bottom: (0.8, 0.9, 0.95))
        c.shape([c.point(0.62, 0.36), c.point(0.7, 0.33), c.point(0.8, 0.325), c.point(0.88, 0.36)], (0.2, 0.34, 0.24))
        c.gradient(c.box(0, 0.36, 1, 0.6), top: (0.2, 0.48, 0.7), bottom: (0.36, 0.62, 0.78))
        c.fill(c.box(0, 0.595, 1, 0.61), (1, 1, 1), alpha: 0.6)
        c.gradient(c.box(0, 0.6, 1, 1), top: (0.93, 0.86, 0.66), bottom: (0.87, 0.79, 0.58))
        let towel = c.box(0.05, 0.9, 0.3, 0.97)
        c.fill(towel, (0.9, 0.3, 0.3))
        c.fill(towel.insetBy(dx: 0, dy: towel.height * 0.35), (1, 1, 1))
        let ball = c.point(dice.range(0.7, 0.9), 0.93)
        c.disc(ball, c.h(0.035), (0.95, 0.85, 0.2))
        c.oval(CGRect(x: ball.x - c.h(0.012), y: ball.y - c.h(0.035), width: c.h(0.024), height: c.h(0.07)), (0.85, 0.15, 0.15))
    }

    private static func school(_ c: Canvas, year: Int) {
        c.fill(c.box(0, 0, 1, 0.66), year < 1950 ? (0.84, 0.74, 0.5) : (0.62, 0.3, 0.22))
        for row in 0 ..< 2 {
            for column in 0 ..< 6 {
                let left = 0.06 + CGFloat(column) * 0.16
                let top = 0.08 + CGFloat(row) * 0.26
                let window = c.box(left, top, left + 0.08, top + 0.18)
                c.fill(window, (0.95, 0.94, 0.9))
                c.fill(window.insetBy(dx: window.width * 0.12, dy: window.height * 0.06), (0.28, 0.32, 0.36))
            }
        }
        c.gradient(c.box(0, 0.66, 1, 1), top: (0.62, 0.57, 0.48), bottom: (0.54, 0.5, 0.42))
    }

    private static func town(_ c: Canvas, year: Int, dice: inout Dice) {
        c.gradient(c.box(0, 0, 1, 0.3), top: (0.66, 0.74, 0.84), bottom: (0.86, 0.88, 0.9))
        let facades: [RGB] = [(0.85, 0.75, 0.45), (0.85, 0.66, 0.6), (0.7, 0.7, 0.68), (0.9, 0.88, 0.84), (0.72, 0.56, 0.36)]
        var left: CGFloat = -0.02
        while left < 1 {
            let width = dice.range(0.16, 0.26)
            let top = dice.range(0.1, 0.3)
            c.fill(c.box(left, top, left + width, 0.8), facades[dice.int(facades.count)])
            c.fill(c.box(left, top, left + width, top + 0.02), (0.3, 0.28, 0.26))
            var floor = top + 0.06
            while floor < 0.62 {
                var column = left + 0.025
                while column < left + width - 0.04 {
                    c.fill(c.box(column, floor, column + 0.03, floor + 0.07), (0.3, 0.33, 0.36))
                    column += 0.055
                }
                floor += 0.12
            }
            c.fill(c.box(left + 0.01, 0.66, left + width - 0.01, 0.7), (0.2, 0.2, 0.22))
            left += width
        }
        c.gradient(c.box(0, 0.8, 1, 1), top: (0.52, 0.51, 0.48), bottom: (0.42, 0.41, 0.39))
        if year < 1960 {
            // Cobbles.
            for _ in 0 ..< 60 {
                let stone = c.point(dice.unit(), dice.range(0.82, 0.99))
                c.oval(CGRect(x: stone.x - c.h(0.008), y: stone.y - c.h(0.004), width: c.h(0.016), height: c.h(0.008)),
                       (0.62, 0.6, 0.56), alpha: 0.6)
            }
        }
    }

    private static func church(_ c: Canvas) {
        c.fill(c.box(0.24, 0.3, 0.76, 0.58), (0.93, 0.91, 0.86))
        c.shape([c.point(0.21, 0.31), c.point(0.5, 0.16), c.point(0.79, 0.31)], (0.3, 0.28, 0.28))
        c.fill(c.box(0.44, 0.06, 0.56, 0.3), (0.93, 0.91, 0.86))
        c.shape([c.point(0.42, 0.07), c.point(0.5, -0.02), c.point(0.58, 0.07)], (0.3, 0.28, 0.28))
        c.fill(c.box(0.465, 0.42, 0.535, 0.58), (0.42, 0.28, 0.18))
    }

    private static func pram(_ c: Canvas) {
        let body: RGB = (0.12, 0.14, 0.22)
        c.rounded(c.box(0.56, 0.6, 0.8, 0.76), radius: c.h(0.04), body)
        c.shape([c.point(0.56, 0.64), c.point(0.57, 0.55), c.point(0.62, 0.52), c.point(0.68, 0.53), c.point(0.69, 0.62)], body)
        c.line(c.point(0.79, 0.63), c.point(0.86, 0.5), width: c.h(0.01), (0.2, 0.2, 0.22))
        for wheel in [0.6, 0.76] as [CGFloat] {
            c.disc(c.point(wheel, 0.8), c.h(0.055), (0.12, 0.12, 0.12))
            c.disc(c.point(wheel, 0.8), c.h(0.035), (0.75, 0.75, 0.75))
            c.disc(c.point(wheel, 0.8), c.h(0.01), (0.12, 0.12, 0.12))
        }
    }

    private static func table(_ c: Canvas, guests: Int, dice: inout Dice) {
        c.fill(c.box(0.12, 0.72, 0.88, 0.97), (0.9, 0.9, 0.88))
        for fold in stride(from: 0.16 as CGFloat, to: 0.88, by: 0.09) {
            c.fill(c.box(fold, 0.73, fold + 0.004, 0.97), (0.78, 0.78, 0.76))
        }
        c.fill(c.box(0.1, 0.68, 0.9, 0.725), (0.97, 0.97, 0.95))
        let places = max(guests, 2)
        for place in 0 ..< places {
            let x = 0.2 + 0.6 * CGFloat(place) / CGFloat(max(places - 1, 1))
            c.oval(c.box(x - 0.03, 0.688, x + 0.03, 0.702), (0.98, 0.98, 0.98))
            c.fill(c.box(x - 0.012, 0.672, x + 0.012, 0.692), (0.98, 0.98, 0.98))
        }
        c.fill(c.box(0.46, 0.64, 0.54, 0.69), (0.5, 0.3, 0.18))
        c.fill(c.box(0.46, 0.635, 0.54, 0.648), (0.98, 0.96, 0.9))
        c.disc(c.point(0.5, 0.622), c.h(0.008), (0.85, 0.15, 0.2))
        _ = dice.unit()
    }

    // MARK: - People

    private static func clothes(year: Int, look: Look, female: Bool, tint: Int) -> RGB {
        switch look {
        case .bride, .robe: return (0.96, 0.96, 0.94)
        case .groom: return (0.1, 0.1, 0.12)
        case .soldier: return (0.38, 0.4, 0.3)
        case .graduate: return female ? (0.15, 0.15, 0.2) : (0.12, 0.12, 0.15)
        case .swimmer: return [(0.85, 0.2, 0.25), (0.15, 0.35, 0.75), (0.95, 0.75, 0.2), (0.2, 0.6, 0.4)][tint % 4]
        default: break
        }
        let palette: [RGB]
        switch year {
        case ..<1936:
            palette = female
                ? [(0.15, 0.14, 0.16), (0.32, 0.26, 0.22), (0.88, 0.86, 0.8), (0.22, 0.2, 0.25)]
                : [(0.14, 0.13, 0.12), (0.26, 0.23, 0.2), (0.3, 0.3, 0.32)]
        case ..<1960:
            palette = female
                ? [(0.55, 0.2, 0.2), (0.3, 0.4, 0.6), (0.85, 0.82, 0.74), (0.35, 0.5, 0.35)]
                : [(0.3, 0.3, 0.32), (0.2, 0.23, 0.35), (0.38, 0.32, 0.26)]
        case ..<1980:
            palette = [(0.82, 0.46, 0.16), (0.52, 0.38, 0.2), (0.76, 0.66, 0.22), (0.2, 0.5, 0.5), (0.58, 0.26, 0.36), (0.84, 0.78, 0.68)]
        case ..<2000:
            palette = [(0.12, 0.36, 0.8), (0.84, 0.16, 0.2), (0.95, 0.52, 0.7), (0.93, 0.93, 0.93), (0.2, 0.6, 0.36), (0.26, 0.32, 0.46)]
        default:
            palette = [(0.16, 0.16, 0.19), (0.9, 0.9, 0.9), (0.22, 0.42, 0.7), (0.8, 0.3, 0.26), (0.42, 0.6, 0.32), (0.95, 0.76, 0.22)]
        }
        return palette[tint % palette.count]
    }

    private static func hair(age: Int, tint: Int) -> RGB {
        if age >= 75 { return (0.9, 0.9, 0.88) }
        if age >= 58 { return (0.66, 0.65, 0.63) }
        let colours: [RGB] = [(0.82, 0.7, 0.45), (0.5, 0.36, 0.22), (0.28, 0.19, 0.12), (0.7, 0.55, 0.3), (0.2, 0.15, 0.1)]
        return colours[tint % colours.count]
    }

    private static func shade(_ c: RGB, _ by: CGFloat) -> RGB { (c.0 * by, c.1 * by, c.2 * by) }

    private static func person(_ f: Figure, on c: Canvas, year: Int, scene: Scene) {
        let tall = c.h(f.height)
        let centre = c.x(f.x)
        let foot = c.y(f.foot)
        let radius = c.h(f.headRadius)
        let head = CGPoint(x: centre, y: foot - tall + radius)
        let skins: [RGB] = [(0.94, 0.8, 0.69), (0.9, 0.74, 0.62), (0.96, 0.84, 0.74)]
        let skin = skins[f.tint % skins.count]
        if f.look == .baby {
            c.disc(head, radius, skin)
            c.shape([CGPoint(x: head.x - radius * 1.2, y: head.y + radius * 0.2), CGPoint(x: head.x - radius * 0.9, y: head.y - radius * 1.1),
                     CGPoint(x: head.x + radius * 0.9, y: head.y - radius * 1.1), CGPoint(x: head.x + radius * 1.2, y: head.y + radius * 0.2),
                     CGPoint(x: head.x + radius * 0.8, y: head.y - radius * 0.5), CGPoint(x: head.x - radius * 0.8, y: head.y - radius * 0.5)],
                    (0.96, 0.96, 0.94))
            return
        }
        let cloth = clothes(year: year, look: f.look, female: f.female, tint: f.tint)
        let sleeve = shade(cloth, 0.85)
        let shoulder = head.y + radius * 1.1
        let hip = foot - 0.46 * tall
        let width = tall * (f.child ? 0.28 : (f.female ? 0.3 : 0.34))
        let skirted = f.female || f.look == .robe || f.look == .bride

        if f.look == .bride {
            c.shape([CGPoint(x: head.x, y: head.y - radius), CGPoint(x: head.x + width * 0.75, y: hip),
                     CGPoint(x: head.x - width * 0.75, y: hip)], (1, 1, 1), alpha: 0.7)
        }

        // Legs, and what covers them.
        let long = f.look == .bride || f.look == .robe || (f.female && year < 1925)
        let hem = skirted ? (long ? foot - 0.02 * tall : foot - 0.2 * tall) : hip
        if skirted {
            for side in [-1, 1] as [CGFloat] {
                c.fill(CGRect(x: centre + side * 0.06 * tall - 0.025 * tall, y: hem - 2, width: 0.05 * tall, height: foot - hem),
                       f.look == .swimmer ? skin : (0.3, 0.26, 0.24))
            }
        } else {
            let trousers: RGB = f.look == .swimmer ? skin : (f.look == .soldier || f.look == .groom ? cloth : shade(cloth, 0.6))
            for side in [-1, 1] as [CGFloat] {
                c.fill(CGRect(x: centre + side * 0.075 * tall - 0.065 * tall, y: hip - 2, width: 0.13 * tall, height: foot - hip),
                       trousers)
            }
        }
        for side in [-1, 1] as [CGFloat] {
            c.oval(CGRect(x: centre + side * 0.07 * tall - 0.05 * tall, y: foot - 0.03 * tall, width: 0.1 * tall, height: 0.04 * tall),
                   (0.1, 0.08, 0.07))
        }

        // The body.
        if f.look == .swimmer {
            c.fill(CGRect(x: centre - width / 2, y: shoulder, width: width, height: hip - shoulder), skin)
            c.fill(CGRect(x: centre - width / 2, y: f.female ? shoulder + 0.05 * tall : hip - 0.1 * tall, width: width,
                          height: f.female ? hip - shoulder : 0.14 * tall), cloth)
        } else if skirted {
            c.shape([CGPoint(x: centre - width / 2, y: shoulder), CGPoint(x: centre + width / 2, y: shoulder),
                      CGPoint(x: centre + width * 0.78, y: hem), CGPoint(x: centre - width * 0.78, y: hem)], cloth)
        } else {
            c.rounded(CGRect(x: centre - width / 2, y: shoulder, width: width, height: hip - shoulder + 0.03 * tall),
                      radius: 0.05 * tall, cloth)
        }

        // Arms and hands.
        let arm = 0.075 * tall
        for side in [-1, 1] as [CGFloat] {
            let x = centre + side * (width / 2 + arm * 0.3)
            c.rounded(CGRect(x: x - arm / 2, y: shoulder + 0.01 * tall, width: arm, height: 0.36 * tall),
                      radius: arm / 2, f.look == .swimmer ? skin : sleeve)
            c.disc(CGPoint(x: x, y: shoulder + 0.37 * tall), 0.035 * tall, skin)
        }

        // Neck, head and hair.
        c.fill(CGRect(x: centre - 0.035 * tall, y: head.y + radius * 0.6, width: 0.07 * tall, height: shoulder - head.y - radius * 0.6 + 2),
               skin)
        c.disc(head, radius, skin)
        let hairColour = hair(age: f.age, tint: f.tint)
        if f.female && f.age < 50 && year >= 1960 {
            c.fill(CGRect(x: head.x - radius * 1.05, y: head.y - radius * 0.2, width: radius * 0.45, height: radius * 1.6), hairColour)
            c.fill(CGRect(x: head.x + radius * 0.6, y: head.y - radius * 0.2, width: radius * 0.45, height: radius * 1.6), hairColour)
        }
        let cap = UIBezierPath(arcCenter: CGPoint(x: head.x, y: head.y - radius * 0.08), radius: radius * 1.04,
                               startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: true)
        cap.close()
        c.ink.colour(hairColour).setFill()
        cap.fill()
        if f.female && (year < 1950 || f.age > 55) {
            c.disc(CGPoint(x: head.x, y: head.y - radius * 1.05), radius * 0.4, hairColour)
        }
        if radius > 14 {
            for side in [-1, 1] as [CGFloat] {
                c.disc(CGPoint(x: head.x + side * radius * 0.34, y: head.y + radius * 0.05), max(1.5, radius * 0.07),
                       (0.2, 0.15, 0.12), alpha: 0.55)
            }
        }

        // What marks the day.
        switch f.look {
        case .soldier:
            c.rounded(CGRect(x: head.x - radius * 1.02, y: head.y - radius * 1.1, width: radius * 2.04, height: radius * 0.6),
                      radius: radius * 0.2, cloth)
            c.fill(CGRect(x: centre - width / 2, y: hip - 0.03 * tall, width: width, height: 0.025 * tall), (0.18, 0.14, 0.1))
        case .graduate:
            c.fill(CGRect(x: head.x - radius * 1.02, y: head.y - radius * 0.98, width: radius * 2.04, height: radius * 0.3),
                   (0.08, 0.08, 0.08))
            c.oval(CGRect(x: head.x - radius * 1.1, y: head.y - radius * 1.5, width: radius * 2.2, height: radius * 0.66),
                   (0.98, 0.98, 0.97))
            c.disc(CGPoint(x: head.x, y: head.y - radius * 0.85), radius * 0.12, (0.85, 0.7, 0.3))
            bouquet(c, at: CGPoint(x: centre, y: shoulder + 0.3 * tall), size: 0.06 * tall)
        case .groom:
            c.shape([CGPoint(x: centre - width * 0.16, y: shoulder), CGPoint(x: centre + width * 0.16, y: shoulder),
                     CGPoint(x: centre, y: shoulder + 0.14 * tall)], (0.97, 0.97, 0.97))
        case .bride:
            bouquet(c, at: CGPoint(x: centre, y: shoulder + 0.34 * tall), size: 0.06 * tall)
        case .robe:
            c.fill(CGRect(x: centre - 0.006 * tall, y: shoulder + 0.05 * tall, width: 0.012 * tall, height: 0.07 * tall), (0.45, 0.3, 0.16))
            c.fill(CGRect(x: centre - 0.025 * tall, y: shoulder + 0.07 * tall, width: 0.05 * tall, height: 0.012 * tall), (0.45, 0.3, 0.16))
        default:
            break
        }

        switch scene {
        case .haying where !f.child:
            let hand = CGPoint(x: centre + width / 2 + arm * 0.3, y: shoulder + 0.37 * tall)
            let end = CGPoint(x: hand.x + 0.18 * tall, y: head.y - 0.25 * tall)
            c.line(hand, end, width: 0.018 * tall, (0.55, 0.42, 0.26))
            c.line(CGPoint(x: end.x - 0.07 * tall, y: end.y - 0.03 * tall), CGPoint(x: end.x + 0.07 * tall, y: end.y + 0.03 * tall),
                   width: 0.02 * tall, (0.45, 0.34, 0.2))
        case .winter:
            c.line(CGPoint(x: centre - 0.4 * tall, y: foot), CGPoint(x: centre + 0.4 * tall, y: foot), width: 0.025 * tall, (0.35, 0.22, 0.12))
            for side in [-1, 1] as [CGFloat] {
                let hand = CGPoint(x: centre + side * (width / 2 + arm * 0.3), y: shoulder + 0.37 * tall)
                c.line(hand, CGPoint(x: hand.x + side * 0.12 * tall, y: foot), width: 0.012 * tall, (0.25, 0.22, 0.2))
            }
        default:
            break
        }
    }

    private static func bouquet(_ c: Canvas, at point: CGPoint, size: CGFloat) {
        let colours: [RGB] = [(0.92, 0.3, 0.35), (0.98, 0.95, 0.9), (0.95, 0.75, 0.3), (0.9, 0.5, 0.6)]
        for index in 0 ..< 7 {
            let angle = CGFloat(index) * 0.9
            c.disc(CGPoint(x: point.x + cos(angle) * size * 0.6, y: point.y + sin(angle) * size * 0.45), size * 0.42,
                   colours[index % colours.count])
        }
    }
}
#endif
