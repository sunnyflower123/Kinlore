import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Storing media files on disk.
///
/// The interface hides where a file physically lives: views know only the
/// filename, and R2 download fills the same cache.
enum MediaStore {
    /// The longest side when saving. Old scanned photographs are often enormous,
    /// and at full size they would fill both the disk and R2. 2048 is enough for
    /// viewing and for eventual printing.
    private static let maxDimension = 2048

    private static let thumbnailDimension = 600

    static func url(for filename: String) -> URL {
        URL.documentsDirectory.appendingPathComponent(filename)
    }

    /// Saves a downscaled photo and returns the filename.
    ///
    /// Downscaling uses ImageIO, which reads only the bytes it needs instead of
    /// decoding the whole image into memory. Importing ten scanned photographs
    /// would otherwise crash the app on an older device.
    static func save(imageData: Data) -> String? {
        guard let downsized = downsample(imageData, to: maxDimension) else { return nil }
        let filename = "photo-\(UUID().uuidString).jpg"
        do {
            try downsized.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func exists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    /// Saves bytes verbatim. Used for media downloaded from R2 and for audio:
    /// audio must never be re-encoded, because the original recording is the
    /// product rather than an intermediate step.
    static func saveRaw(_ data: Data, extension ext: String) -> String? {
        let filename = "media-\(UUID().uuidString).\(ext)"
        do {
            try data.write(to: url(for: filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func loadImage(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    /// For the grid. Loading full-size images into a grid stutters.
    static func loadThumbnail(named filename: String) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: filename)),
              let jpeg = downsample(data, to: thumbnailDimension)
        else { return nil }
        return UIImage(data: jpeg)
    }

    static func delete(filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    // MARK: - Downscaling

    private static func downsample(_ data: Data, to maxPixels: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Old photos are often scanned and rotated. Without this they would
            // come out the wrong way round in the grid.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
