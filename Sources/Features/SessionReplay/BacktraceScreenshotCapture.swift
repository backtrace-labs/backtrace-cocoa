#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import Foundation

/// Captures periodic screenshots of the app's key window to produce a low-framerate session replay.
final class BacktraceScreenshotCapture {

    // MARK: - Types

    struct Frame {
        let timestamp: TimeInterval
        let fileURL: URL
    }

    // MARK: - Properties

    private let settings: BacktraceSessionReplaySettings
    private let storageDirectory: URL
    private var captureTimer: DispatchSourceTimer?
    private let captureQueue = DispatchQueue(label: "io.backtrace.sessionreplay.capture", qos: .utility)
    private var frames: [Frame] = []
    private var isCapturing = false
    private let sessionId: String

    /// Registry of views to mask before capture (weak references).
    private var hiddenViews = NSHashTable<UIView>.weakObjects()

    /// CSS selectors for WKWebView element hiding.
    private var hiddenWebViewSelectors: [String] = []

    // MARK: - Public API

    var currentFrames: [Frame] {
        return captureQueue.sync { frames }
    }

    init(settings: BacktraceSessionReplaySettings, sessionId: String) {
        self.settings = settings
        self.sessionId = sessionId

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.storageDirectory = cacheDir
            .appendingPathComponent("io.backtrace.sessionreplay")
            .appendingPathComponent(sessionId)

        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        setupNotifications()
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Start / Stop

    func start() {
        guard !isCapturing else { return }
        isCapturing = true

        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        let interval = settings.captureIntervalSeconds
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.captureFrame()
        }
        timer.resume()
        captureTimer = timer

        BacktraceLogger.debug("Session replay capture started (interval: \(interval)s).")
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false
        captureTimer?.cancel()
        captureTimer = nil
        BacktraceLogger.debug("Session replay capture stopped.")
    }

    // MARK: - View Masking

    func hideView(_ view: UIView) {
        hiddenViews.add(view)
    }

    func unhideView(_ view: UIView) {
        hiddenViews.remove(view)
    }

    func hideWebViewElements(_ cssSelector: String) {
        if !hiddenWebViewSelectors.contains(cssSelector) {
            hiddenWebViewSelectors.append(cssSelector)
        }
    }

    // MARK: - Frame Retrieval for Reports

    /// Returns the most recent `count` frame file URLs for attaching to a report.
    func recentFrameURLs(count: Int) -> [URL] {
        return captureQueue.sync {
            let slice = frames.suffix(count)
            return slice.map { $0.fileURL }
        }
    }

    /// Returns replay metadata attributes to include in a report.
    func replayAttributes() -> [String: Any] {
        return captureQueue.sync {
            guard !frames.isEmpty else { return [:] }
            return [
                "session.replay.frameCount": frames.count,
                "session.replay.startTimestamp": frames.first?.timestamp ?? 0,
                "session.replay.endTimestamp": frames.last?.timestamp ?? 0,
                "session.replay.fps": 1.0 / settings.captureIntervalSeconds
            ]
        }
    }

    // MARK: - Cleanup

    func clearStorage() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.frames.removeAll()
            try? FileManager.default.removeItem(at: self.storageDirectory)
            try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private

    private func captureFrame() {
        // Render must happen on main thread
        DispatchQueue.main.sync { [weak self] in
            guard let self = self else { return }
            guard let window = self.keyWindow() else { return }

            // Apply masks
            let maskOverlays = self.applyMasks(to: window)

            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }

            // Remove masks
            maskOverlays.forEach { $0.removeFromSuperview() }

            // Compress and store on capture queue
            self.captureQueue.async { [weak self] in
                guard let self = self else { return }
                guard let data = image.jpegData(compressionQuality: self.settings.jpegQuality) else { return }

                let timestamp = Date().timeIntervalSince1970
                let filename = String(format: "frame_%013.0f.jpg", timestamp * 1000)
                let fileURL = self.storageDirectory.appendingPathComponent(filename)

                do {
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    BacktraceLogger.error("Failed to write replay frame: \(error)")
                    return
                }

                let frame = Frame(timestamp: timestamp, fileURL: fileURL)
                self.frames.append(frame)
                self.enforceStorageLimits()
            }
        }
    }

    private func keyWindow() -> UIWindow? {
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }

    private func applyMasks(to window: UIWindow) -> [UIView] {
        var overlays: [UIView] = []
        for view in hiddenViews.allObjects {
            guard let superview = view.superview else { continue }
            let frameInWindow = superview.convert(view.frame, to: window)
            let overlay = UIView(frame: frameInWindow)
            overlay.backgroundColor = .black
            overlay.tag = 99_999 // Internal tag for identification
            window.addSubview(overlay)
            overlays.append(overlay)
        }
        return overlays
    }

    private func enforceStorageLimits() {
        // Enforce frame count limit
        while frames.count > settings.maxFrameCount {
            let removed = frames.removeFirst()
            try? FileManager.default.removeItem(at: removed.fileURL)
        }

        // Enforce storage size limit
        var totalSize = frames.compactMap { try? FileManager.default.attributesOfItem(atPath: $0.fileURL.path)[.size] as? Int }
            .reduce(0, +)

        while totalSize > settings.maxStorageBytes, !frames.isEmpty {
            let removed = frames.removeFirst()
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: removed.fileURL.path)[.size] as? Int) ?? 0
            try? FileManager.default.removeItem(at: removed.fileURL)
            totalSize -= fileSize
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func appDidEnterBackground() {
        stop()
    }

    @objc private func appWillEnterForeground() {
        if settings.enabled {
            start()
        }
    }
}
#endif
