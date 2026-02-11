#if os(iOS) && !targetEnvironment(macCatalyst)
import Foundation

/// Configuration for the log capture feature.
@objc public class BacktraceLogCaptureSettings: NSObject {

    /// Maximum log file size in bytes. Default: 512 KB.
    @objc public var maxFileSizeBytes: Int = 512 * 1024

    /// Minimum log level to capture. Default: .debug (capture everything).
    @objc public var minimumLevel: BacktraceLogLevel = .debug

    /// Enable NSLog capture via stderr redirection. Default: false.
    @objc public var captureNSLog: Bool = false

    /// Enable log capture feature. Default: false.
    @objc public var enabled: Bool = false
}

/// Captures application logs (both custom and NSLog) and stores them in a circular file
/// for attachment to error reports.
final class BacktraceLogCapture {

    private let settings: BacktraceLogCaptureSettings
    private let logFileURL: URL
    private let logQueue = DispatchQueue(label: "io.backtrace.logcapture", qos: .utility)
    private var lineCount: Int = 0
    private var stderrPipe: Pipe?
    private var originalStderrFd: Int32 = -1

    init(settings: BacktraceLogCaptureSettings, sessionId: String) {
        self.settings = settings

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logsDir = cacheDir.appendingPathComponent("io.backtrace.logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("session-\(sessionId).log")

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }

    deinit {
        stopNSLogCapture()
    }

    // MARK: - Start / Stop

    func start() {
        if settings.captureNSLog {
            startNSLogCapture()
        }
        BacktraceLogger.debug("Log capture started.")
    }

    func stop() {
        stopNSLogCapture()
        BacktraceLogger.debug("Log capture stopped.")
    }

    // MARK: - Public API

    /// Add a custom log entry.
    func log(_ message: String, level: BacktraceLogLevel) {
        guard level.rawValue >= settings.minimumLevel.rawValue else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let levelName = logLevelName(level)
        let line = "[\(timestamp)] [\(levelName)] \(message)\n"

        logQueue.async { [weak self] in
            self?.appendToFile(line)
        }
    }

    // MARK: - Report Integration

    var logAttachmentURL: URL {
        return logFileURL
    }

    func logAttributes() -> [String: Any] {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: logFileURL.path)[.size] as? Int) ?? 0
        return [
            "log.lineCount": lineCount,
            "log.sizeBytes": fileSize
        ]
    }

    // MARK: - NSLog Capture

    private func startNSLogCapture() {
        let pipe = Pipe()
        stderrPipe = pipe

        // Save original stderr
        originalStderrFd = dup(STDERR_FILENO)

        // Redirect stderr to our pipe
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Write to original stderr so logs still appear in console
            if let fd = self?.originalStderrFd, fd >= 0 {
                data.withUnsafeBytes { bytes in
                    if let ptr = bytes.baseAddress {
                        _ = write(fd, ptr, data.count)
                    }
                }
            }

            // Also capture to our log file
            if let logString = String(data: data, encoding: .utf8) {
                self?.logQueue.async {
                    self?.appendToFile(logString)
                }
            }
        }
    }

    private func stopNSLogCapture() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if originalStderrFd >= 0 {
            dup2(originalStderrFd, STDERR_FILENO)
            close(originalStderrFd)
            originalStderrFd = -1
        }

        stderrPipe = nil
    }

    // MARK: - File Operations

    private func appendToFile(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()

            let currentSize = handle.offsetInFile
            if Int(currentSize) + data.count > settings.maxFileSizeBytes {
                handle.closeFile()
                truncateFirstHalf()
                if let newHandle = try? FileHandle(forWritingTo: logFileURL) {
                    newHandle.seekToEndOfFile()
                    newHandle.write(data)
                    newHandle.closeFile()
                }
            } else {
                handle.write(data)
                handle.closeFile()
            }
        }

        lineCount += text.components(separatedBy: "\n").count - 1
    }

    private func truncateFirstHalf() {
        guard let data = try? Data(contentsOf: logFileURL) else { return }
        let midpoint = data.count / 2
        if let newlineIndex = data[midpoint...].firstIndex(of: UInt8(ascii: "\n")) {
            let remaining = data[(newlineIndex + 1)...]
            try? remaining.write(to: logFileURL, options: .atomic)
        }
    }

    private func logLevelName(_ level: BacktraceLogLevel) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .warning: return "WARN"
        case .info: return "INFO"
        case .error: return "ERROR"
        case .none: return "NONE"
        @unknown default: return "UNKNOWN"
        }
    }
}
#endif
