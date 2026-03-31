import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// JPEG compression quality for session screenshots.
/// Values match the TestFairy wire protocol for compatibility.
@objc public enum BacktraceScreenshotQuality: Int, Sendable {
    /// 0.70 JPEG quality — best visual fidelity, larger payloads.
    case high = 0
    /// 0.35 JPEG quality — balanced quality and size.
    case medium = 1
    /// 0.15 JPEG quality — smallest payloads, lower fidelity.
    case low = 2

    var compressionValue: CGFloat {
        switch self {
        case .high: return 0.70
        case .medium: return 0.35
        case .low: return 0.15
        }
    }
}
