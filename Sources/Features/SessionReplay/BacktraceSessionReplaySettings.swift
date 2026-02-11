import Foundation

/// Configuration settings for session replay feature.
@objc public class BacktraceSessionReplaySettings: NSObject {

    /// Capture interval in seconds. Default: 1.0 (1 fps).
    @objc public var captureIntervalSeconds: TimeInterval = 1.0

    /// JPEG compression quality (0.0–1.0). Default: 0.5.
    @objc public var jpegQuality: CGFloat = 0.5

    /// Maximum number of frames to keep in the ring buffer. Default: 60.
    @objc public var maxFrameCount: Int = 60

    /// Maximum disk storage in bytes for replay frames. Default: 20 MB.
    @objc public var maxStorageBytes: Int = 20 * 1024 * 1024

    /// Number of most-recent frames to attach to each error report. Default: 30.
    @objc public var framesPerReport: Int = 30

    /// Enable adaptive frame rate that reduces fps under high CPU or low battery. Default: true.
    @objc public var adaptiveFrameRate: Bool = true

    /// Enable session replay. Default: false.
    @objc public var enabled: Bool = false
}
