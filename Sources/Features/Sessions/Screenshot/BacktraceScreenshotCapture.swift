#if os(iOS)
import Foundation
import UIKit

/// Periodic and on-demand screenshot capture for session recording.
final class BacktraceScreenshotCapture {

    /// Current screen/activity name set by the consumer.
    var currentScreenName: String = "Unknown"

    private let interval: TimeInterval
    private let quality: BacktraceScreenshotQuality
    private let sensitiveViewManager: BacktraceSensitiveViewManager
    private weak var api: BacktraceSessionApi?
    private weak var eventTracker: BacktraceSessionEventTracker?

    private let queue = DispatchQueue(label: "io.backtrace.sessions.screenshots", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var sequenceNumber: Int = 0
    private var lastHash: UInt64 = 0
    private var isCapturing = false

    init(interval: TimeInterval,
         quality: BacktraceScreenshotQuality,
         sensitiveViewManager: BacktraceSensitiveViewManager,
         api: BacktraceSessionApi,
         eventTracker: BacktraceSessionEventTracker) {
        self.interval = interval
        self.quality = quality
        self.sensitiveViewManager = sensitiveViewManager
        self.api = api
        self.eventTracker = eventTracker
    }

    deinit {
        timer?.cancel()
    }

    // MARK: - Control

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.captureAndSend()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Capture

    /// Capture a screenshot immediately and return the image.
    /// Called on any thread; internally dispatches to main for UIKit rendering.
    func captureNow() -> UIImage? {
        var result: UIImage?
        if Thread.isMainThread {
            result = renderScreen()
        } else {
            DispatchQueue.main.sync {
                result = self.renderScreen()
            }
        }
        return result
    }

    /// Capture a screenshot and send it to the server.
    func captureAndSend() {
        guard !isCapturing else { return }
        isCapturing = true

        // Capture on main thread
        var image: UIImage?
        DispatchQueue.main.sync {
            image = self.renderScreen()
        }

        queue.async { [weak self] in
            guard let self = self, let image = image else {
                self?.isCapturing = false
                return
            }

            // Compress
            guard let data = image.jpegData(compressionQuality: self.quality.compressionValue) else {
                self.isCapturing = false
                return
            }

            // Duplicate detection via DJB2 hash
            let hash = self.djb2Hash(data)
            if hash == self.lastHash {
                self.isCapturing = false
                return
            }
            self.lastHash = hash

            // Submit
            let seq = self.sequenceNumber
            self.sequenceNumber += 1
            let timestamp = Date().timeIntervalSince1970
            let screenName = self.currentScreenName

            self.api?.sendScreenshot(
                data,
                sessionToken: self.eventTracker?.sessionToken,
                seq: seq,
                timestamp: timestamp,
                activityName: screenName
            ) { _ in }

            self.isCapturing = false
        }
    }

    // MARK: - Private: Rendering

    private func renderScreen() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }

        // Render at 50% scale for periodic captures to reduce CPU/memory
        let scale: CGFloat = 0.5
        let size = CGSize(
            width: window.bounds.width * scale,
            height: window.bounds.height * scale
        )

        // Apply sensitive view masking
        let overlays = sensitiveViewManager.addMaskOverlays(in: window)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            window.layer.render(in: ctx.cgContext)
        }

        // Remove mask overlays
        sensitiveViewManager.removeMaskOverlays(overlays)

        // Detect current screen name from top view controller
        if let topVC = topViewController(from: window.rootViewController) {
            currentScreenName = String(describing: type(of: topVC))
        }

        return image
    }

    private func topViewController(from vc: UIViewController?) -> UIViewController? {
        if let nav = vc as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = vc as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = vc?.presentedViewController {
            return topViewController(from: presented)
        }
        return vc
    }

    // MARK: - Private: Hash

    /// DJB2 hash on first 4KB + last 4KB for fast duplicate detection.
    private func djb2Hash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 5381
        let count = data.count
        let headSize = min(4096, count)
        let tailStart = max(0, count - 4096)

        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<headSize {
                hash = ((hash &<< 5) &+ hash) &+ UInt64(base[i])
            }
            if tailStart > headSize {
                for i in tailStart..<count {
                    hash = ((hash &<< 5) &+ hash) &+ UInt64(base[i])
                }
            }
        }
        return hash
    }
}
#endif
