#if os(iOS)
import Foundation
import UIKit

/// Compresses UIImage to JPEG with configurable quality.
final class BacktraceScreenshotCompressor {

    let quality: BacktraceScreenshotQuality

    init(quality: BacktraceScreenshotQuality) {
        self.quality = quality
    }

    /// Compress the image to JPEG data at the configured quality.
    func compress(_ image: UIImage) -> Data? {
        return image.jpegData(compressionQuality: quality.compressionValue)
    }
}
#endif
