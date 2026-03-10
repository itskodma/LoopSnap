import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GifExporter {
    /// Encodes `frames` as an animated GIF at `url`.
    /// - Parameter delaySeconds: time per frame in seconds (e.g. 1/15 ≈ 0.067).
    static func export(frames: [CGImage], delaySeconds: Double, to url: URL) throws {
        guard !frames.isEmpty else { return }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else { throw ExportError.destinationCreationFailed }

        // Loop forever.
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let frameProps: CFDictionary = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime:          delaySeconds,
                kCGImagePropertyGIFUnclampedDelayTime: delaySeconds
            ]
        ] as CFDictionary

        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProps)
        }
        guard CGImageDestinationFinalize(dest) else { throw ExportError.finalizeFailed }
    }

    enum ExportError: LocalizedError {
        case destinationCreationFailed, finalizeFailed
        var errorDescription: String? {
            switch self {
            case .destinationCreationFailed: "Could not create GIF file at the specified location."
            case .finalizeFailed:            "Failed to write GIF data to disk."
            }
        }
    }
}
