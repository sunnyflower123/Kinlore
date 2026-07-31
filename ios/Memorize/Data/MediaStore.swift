import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Kuvatiedostojen tallennus levylle.
///
/// Korvautuu R2-lataukselle kun backend tulee, mutta rajapinta pysyy: näkymät
/// tuntevat vain tiedostonimen, eivät sitä missä kuva fyysisesti on.
enum MediaStore {
    /// Pisin sivu tallennettaessa. Vanhat skannatut valokuvat ovat usein
    /// valtavia, ja täysikokoisina ne täyttäisivät sekä levyn että myöhemmin
    /// R2:n. 2048 riittää katseluun ja tulevaan tulostukseen.
    private static let maxDimension = 2048

    private static let thumbnailDimension = 600

    static func url(for filename: String) -> URL {
        URL.documentsDirectory.appendingPathComponent(filename)
    }

    /// Tallentaa kuvan pienennettynä ja palauttaa tiedostonimen.
    ///
    /// Pienennys tehdään ImageIO:lla, joka lukee vain tarvittavat tavut sen
    /// sijaan että purkaisi koko kuvan muistiin. Kymmenen skannatun valokuvan
    /// tuonti kaataisi muuten sovelluksen vanhemmalla laitteella.
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

    static func loadImage(named filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    /// Ruudukkoa varten. Täysikokoisten kuvien lataaminen ruudukkoon nykii.
    static func loadThumbnail(named filename: String) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: filename)),
              let jpeg = downsample(data, to: thumbnailDimension)
        else { return nil }
        return UIImage(data: jpeg)
    }

    static func delete(filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    // MARK: - Pienennys

    private static func downsample(_ data: Data, to maxPixels: Int) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Vanhat kuvat ovat usein skannattuja ja käännettyjä. Ilman tätä
            // ne kääntyisivät väärin päin ruudukossa.
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
