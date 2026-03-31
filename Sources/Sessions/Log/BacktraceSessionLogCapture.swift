import Foundation

/// Captures log messages and forwards them as session events.
final class BacktraceSessionLogCapture {

    private let logLevel: BacktraceSessionLogLevel
    private let captureConsole: Bool
    private weak var eventTracker: BacktraceSessionEventTracker?
    private let bundleName: String

    private var pipeReadSource: DispatchSourceRead?
    private var originalStderr: Int32 = -1

    init(logLevel: BacktraceSessionLogLevel,
         captureConsole: Bool,
         eventTracker: BacktraceSessionEventTracker) {
        self.logLevel = logLevel
        self.captureConsole = captureConsole
        self.eventTracker = eventTracker
        self.bundleName = Bundle.main.bundleIdentifier ?? "app"

        if captureConsole {
            startConsoleCapture()
        }
    }

    deinit {
        stopConsoleCapture()
    }

    // MARK: - Explicit Log API

    /// Log a message at the given level.
    func log(_ message: String, level: BacktraceSessionLogLevel, attributes: [String: String]? = nil) {
        guard level >= logLevel else { return }
        eventTracker?.addLogEvent(tag: bundleName, text: message, level: level)
    }

    // MARK: - Console Capture (Opt-in)

    private func startConsoleCapture() {
        let pipe = Pipe()
        originalStderr = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        let readFD = pipe.fileHandleForReading.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let data = pipe.fileHandleForReading.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            // Also write to original stderr so Xcode console still works
            if self.originalStderr >= 0 {
                data.withUnsafeBytes { ptr in
                    if let base = ptr.baseAddress {
                        write(self.originalStderr, base, data.count)
                    }
                }
            }

            // Parse each line as a log event
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            for line in lines {
                self.eventTracker?.addLogEvent(tag: self.bundleName, text: line, level: .info)
            }
        }
        source.resume()
        pipeReadSource = source
    }

    private func stopConsoleCapture() {
        pipeReadSource?.cancel()
        pipeReadSource = nil

        if originalStderr >= 0 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }
    }
}
