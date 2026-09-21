import UIKit

/// The disc of a face, cut from a photograph around the point somebody tapped.
///
/// The photograph is never touched. What is cut is a copy for the disc, at the
/// size a screen draws it, and it is cut again from the original whenever the
/// point moves — so a person's card, the list and the tree show the same
/// square of the same picture, and `Subject.portraitFocusX/Y` is the whole of
/// what travels (ARCHITECTURE §25).
enum Portrait {
    /// How much of the photograph's shorter side the disc shows.
    ///
    /// Half, and it is a decision about the interaction rather than about the
    /// picture: one tap and no zoom is all an 80-year-old is asked for, so
    /// the square has to be right for the two photographs a family actually
    /// has. In a portrait of one person half the shorter side is the head
    /// and shoulders; in a row of six at a table a face is about a tenth of
    /// the width, and half the height shows it with the people either side,
    /// which is still recognisably them. A tighter square would need a second
    /// gesture to get right, and a looser one would show the table.
    static let fraction: CGFloat = 0.5

    /// The cut's own size in pixels. The tree's disc is 48 pt and the card's
    /// 56, both at 3x on the phones this runs on, so 240 leaves nothing to
    /// scale up.
    static let side: CGFloat = 240

    /// The square the disc shows, in the photograph's own points, around a
    /// point given as fractions of its width and height. Clamped inside the
    /// picture, so a tap near an edge slides the square in rather than
    /// showing the paper around the print.
    static func window(in size: CGSize, focusX: Double, focusY: Double) -> CGRect {
        let side = min(size.width, size.height) * fraction
        let x = min(max(size.width * focusX - side / 2, 0), size.width - side)
        let y = min(max(size.height * focusY - side / 2, 0), size.height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// That square, cut and scaled to `side` pixels.
    ///
    /// Drawn through `UIImage.draw` rather than `CGImage.cropping`, because
    /// the point was tapped on the picture as the phone shows it, and only
    /// the former honours the orientation a camera writes into a file. The
    /// pixels of a photograph shot upright on a phone held sideways are stored
    /// rotated, and a crop by pixel would cut the wrong corner of them.
    static func crop(_ image: UIImage, focusX: Double, focusY: Double, side: CGFloat = side) -> UIImage {
        let window = window(in: image.size, focusX: focusX, focusY: focusY)
        let scale = side / window.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(
                x: -window.minX * scale,
                y: -window.minY * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
    }
}

/// The cut faces, kept so a list of forty people decodes each photograph once
/// rather than once per row per scroll.
///
/// Keyed by the file and the point, because the same photograph can be two
/// people's face — the couple in one print — and moving the point is what
/// makes a new one. `NSCache` empties itself under memory pressure, and
/// everything in it can be cut again from the file.
enum PortraitCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    static func key(filename: String, focusX: Double, focusY: Double) -> String {
        "\(filename)|\(focusX)|\(focusY)"
    }

    static func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// The face for a photograph on this phone, cut from the 600 px thumbnail
    /// — enough for a 240 px disc, and a fifth of the bytes the full file
    /// would decode into. Nil only when the file cannot be read.
    static func face(filename: String, focusX: Double, focusY: Double) -> UIImage? {
        let key = key(filename: filename, focusX: focusX, focusY: focusY)
        if let hit = cached(key) { return hit }
        guard let thumbnail = MediaStore.loadThumbnail(named: filename) else { return nil }
        let face = Portrait.crop(thumbnail, focusX: focusX, focusY: focusY)
        cache.setObject(face, forKey: key as NSString)
        return face
    }
}
