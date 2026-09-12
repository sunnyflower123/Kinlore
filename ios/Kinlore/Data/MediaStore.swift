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

    /// The two shapes of name this store writes.
    ///
    /// Constants rather than literals at the two call sites, because
    /// `deleteAll` below matches on them: a prefix that drifted would leave
    /// that sweep silently finding nothing, which is the failure it exists to
    /// prevent. Sharing them makes the drift impossible instead of checkable.
    private static let photoPrefix = "photo-"
    private static let mediaPrefix = "media-"

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
        let filename = "\(photoPrefix)\(UUID().uuidString).jpg"
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
        let filename = "\(mediaPrefix)\(UUID().uuidString).\(ext)"
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

    /// Every file this store has ever written, whether or not a row still
    /// points at it. For "Tyhjennä tämä laite" and nothing else.
    ///
    /// `MemoryStore.wipe` used to delete media by walking the rows'
    /// `imageFilename` and `audioFilename`, which is every file the archive
    /// knows about and not every file on the disk. `FullCopy` writes the bytes
    /// first and records the filename in memory, flushing to disk once per ten
    /// files — so a phone killed mid-round leaves up to nine of the family's
    /// photographs and recordings referenced by nothing. A sweep by row could
    /// not see them, and they outlived a dialog that says the memories are
    /// gone. Found 11 Sep 2026 reading `FullCopy` against `wipe`.
    ///
    /// **Three prefixes, because there are three writers**, and this file is
    /// only two of them. A recording made on this phone keeps the name
    /// `AudioRecorder` gave it in the temporary directory — the move in
    /// `TellViewModel.persistAudio` does not rename it — so it is a
    /// `memory-` file and not a `media-` one. A sweep with the two local
    /// prefixes looked complete, deleted the imported photographs and the
    /// downloaded copies, and left behind every recording the family had
    /// made: the one kind of file rule 3 is actually about. Caught by
    /// reading the writers rather than by any check, which is the honest
    /// account of it.
    ///
    /// Matched by prefix rather than by extension: `kinlore-store.json` and
    /// `preview-store.json` live in the same directory and are their owner's
    /// to delete, not this sweep's.
    static func deleteAll() {
        let prefixes = [photoPrefix, mediaPrefix, AudioRecorder.orphanPrefix]
        let documents = URL.documentsDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: documents.path)
        else { return }
        for name in names where prefixes.contains(where: name.hasPrefix) {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
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
