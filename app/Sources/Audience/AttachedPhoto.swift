import Foundation
import ImageIO
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// A photo given to the assistant as a source: a page of a textbook, the board, a worksheet.
/// It is reduced and re-encoded as JPEG, so a large HEIC or PNG fits in the request.
struct AttachedPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let thumbnail: CGImage

    /// Long side sent to the assistants: enough to read a printed page, small enough for every service.
    private static let sentSize = 1600

    init(_ raw: Data) throws {
        guard let source = CGImageSourceCreateWithData(raw as CFData, nil),
              let image = Self.reduced(source, to: Self.sentSize),
              let preview = Self.reduced(source, to: 240) else {
            throw AudienceError.message("Cette image n’a pas pu être lue.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AudienceError.message("Cette image n’a pas pu être préparée.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AudienceError.message("Cette image n’a pas pu être préparée.") }
        jpeg = output as Data
        thumbnail = preview
    }

    /// The image upright, its long side at most `size` pixels.
    private static func reduced(_ source: CGImageSource, to size: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ] as CFDictionary)
    }
}
