#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import Foundation

/// Configuration for the vitals monitoring feature.
@objc public class BacktraceVitalsSettings: NSObject {

    /// Sample interval in seconds. Default: 5.0.
    @objc public var sampleIntervalSeconds: TimeInterval = 5.0

    /// Maximum file size for vitals data in bytes. Default: 1 MB.
    @objc public var maxFileSizeBytes: Int = 1 * 1024 * 1024

    /// Enable vitals monitoring. Default: false.
    @objc public var enabled: Bool = false
}

/// Periodically samples device vitals (CPU, memory, battery, disk, FPS) and writes
/// them to a JSON-lines file for attachment to error reports.
final class BacktraceVitalsMonitor {

    private let settings: BacktraceVitalsSettings
    private let vitalsFileURL: URL
    private var sampleTimer: DispatchSourceTimer?
    private let sampleQueue = DispatchQueue(label: "io.backtrace.vitals", qos: .utility)
    private var sampleCount: Int = 0
    private let startTime = Date()
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var currentFPS: Double = 0

    init(settings: BacktraceVitalsSettings, sessionId: String) {
        self.settings = settings

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let vitalsDir = cacheDir.appendingPathComponent("io.backtrace.vitals")
        try? FileManager.default.createDirectory(at: vitalsDir, withIntermediateDirectories: true)
        self.vitalsFileURL = vitalsDir.appendingPathComponent("vitals-\(sessionId).jsonl")

        // Create empty file
        FileManager.default.createFile(atPath: vitalsFileURL.path, contents: nil)

        setupNotifications()
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Start / Stop

    func start() {
        startFPSTracking()

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        let interval = settings.sampleIntervalSeconds
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.takeSample()
        }
        timer.resume()
        sampleTimer = timer

        BacktraceLogger.debug("Vitals monitoring started (interval: \(interval)s).")
    }

    func stop() {
        sampleTimer?.cancel()
        sampleTimer = nil
        stopFPSTracking()
        BacktraceLogger.debug("Vitals monitoring stopped.")
    }

    // MARK: - Report Integration

    /// Returns the vitals file URL for attachment to a report.
    var vitalsAttachmentURL: URL {
        return vitalsFileURL
    }

    /// Returns vitals metadata attributes for a report.
    func vitalsAttributes() -> [String: Any] {
        return [
            "vitals.sampleCount": sampleCount,
            "vitals.duration": Date().timeIntervalSince(startTime)
        ]
    }

    // MARK: - FPS Tracking

    private func startFPSTracking() {
        DispatchQueue.main.async { [weak self] in
            let link = CADisplayLink(target: self as Any, selector: #selector(self?.displayLinkTick(_:)))
            link.add(to: .main, forMode: .common)
            self?.displayLink = link
        }
    }

    private func stopFPSTracking() {
        DispatchQueue.main.async { [weak self] in
            self?.displayLink?.invalidate()
            self?.displayLink = nil
        }
    }

    @objc private func displayLinkTick(_ link: CADisplayLink) {
        if lastFrameTimestamp > 0 {
            let elapsed = link.timestamp - lastFrameTimestamp
            if elapsed > 0 {
                currentFPS = 1.0 / elapsed
            }
        }
        lastFrameTimestamp = link.timestamp
    }

    // MARK: - Sampling

    private func takeSample() {
        let timestamp = Date().timeIntervalSince1970

        let processMemory = try? MemoryInfo.Process()
        let systemMemory = try? MemoryInfo.System()

        let device = UIDevice.current
        let batteryLevel = device.isBatteryMonitoringEnabled ? device.batteryLevel : -1

        let diskAttributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory())
        let diskFree = diskAttributes?[.systemFreeSize] as? Int64 ?? 0
        let diskTotal = diskAttributes?[.systemSize] as? Int64 ?? 0

        let sample: [String: Any] = [
            "timestamp": timestamp,
            "cpu.user": (try? Processor())?.cpuTicks.user ?? 0,
            "cpu.sys": (try? Processor())?.cpuTicks.system ?? 0,
            "system.memory.used": systemMemory?.used ?? 0,
            "vm.rss.size": processMemory?.resident ?? 0,
            "battery.level": batteryLevel,
            "disk.free": diskFree,
            "disk.total": diskTotal,
            "fps": currentFPS
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: sample),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        jsonString += "\n"
        guard let lineData = jsonString.data(using: .utf8) else { return }

        // Append to file, enforce size limit
        if let handle = try? FileHandle(forWritingTo: vitalsFileURL) {
            handle.seekToEndOfFile()

            // Check file size before writing
            let currentSize = handle.offsetInFile
            if Int(currentSize) + lineData.count > settings.maxFileSizeBytes {
                // Truncate first half of file (simple eviction)
                handle.closeFile()
                truncateFirstHalf()
                if let newHandle = try? FileHandle(forWritingTo: vitalsFileURL) {
                    newHandle.seekToEndOfFile()
                    newHandle.write(lineData)
                    newHandle.closeFile()
                }
            } else {
                handle.write(lineData)
                handle.closeFile()
            }
        }

        sampleCount += 1
    }

    private func truncateFirstHalf() {
        guard let data = try? Data(contentsOf: vitalsFileURL) else { return }
        let midpoint = data.count / 2
        // Find the next newline after midpoint
        if let newlineIndex = data[midpoint...].firstIndex(of: UInt8(ascii: "\n")) {
            let remaining = data[(newlineIndex + 1)...]
            try? remaining.write(to: vitalsFileURL, options: .atomic)
        }
    }

    // MARK: - Notifications

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
