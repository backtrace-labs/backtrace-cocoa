import Foundation
import Backtrace_PLCrashReporter

/// A wrapper around `PLCrashReporter`.
@objc public class BacktraceCrashReporter: NSObject {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    private var copiedFileAttachments = [URL]()
    
    /// Creates an instance of a crash reporter.
    /// - Parameter config: A `PLCrashReporterConfig` configuration to use.
    @objc public convenience init(config: PLCrashReporterConfig = PLCrashReporterConfig.defaultConfiguration()) {
        self.init(reporter: PLCrashReporter(configuration: config))
    }
    
    /// Creates an instance of a crash reporter.
    /// - Parameter reporter: An instance of `PLCrashReporter` to use.
    @objc public init(reporter: PLCrashReporter) {
        self.reporter = reporter
        super.init()
        self.copiedFileAttachments = copyFileAttachmentsFromPendingCrashes()
    }
}

extension BacktraceCrashReporter: CrashReporting {
    func signalContext(_ mutableContext: inout SignalContext) {
        let handler: @convention(c) (_ signalInfo: UnsafeMutablePointer<siginfo_t>?,
            _ uContext: UnsafeMutablePointer<ucontext_t>?,
            _ context: UnsafeMutableRawPointer?) -> Void = { signalInfoPointer, _, context in
                guard let attributesProvider = context?.assumingMemoryBound(to: SignalContext.self).pointee,
                    let signalInfo = signalInfoPointer?.pointee else {
                    return
                }
                attributesProvider.set(errorType: "Crash")
                attributesProvider.set(faultMessage: "siginfo_t.si_signo: \(signalInfo.si_signo)")
                BacktraceOomWatcher.clean()
                try? AttributesStorage.store(attributesProvider.allAttributes, fileName: BacktraceCrashReporter.crashName)
                try? AttachmentsStorage.store(attributesProvider.attachments, fileName: BacktraceCrashReporter.crashName)
        }
        
        var callbacks = withUnsafeMutableBytes(of: &mutableContext) { rawMutablePointer in
            PLCrashReporterCallbacks(version: 0, context: rawMutablePointer.baseAddress, handleSignal: handler)
        }
        reporter.setCrash(&callbacks)
    }
    
    func generateLiveReport(exception: NSException? = nil,
                            attributes: Attributes,
                            attachmentPaths: [String] = []) throws -> BacktraceReport {
        
        let reportData = try reporter.generateLiveReport(with: exception)
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: attachmentPaths)
    }

    func enableCrashReporting() throws {
        try reporter.enableAndReturnError()
    }
    
    // This function retrieves, constructs, and sends the pending crash report
    func pendingCrashReport() throws -> BacktraceReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let attributes = (try? AttributesStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? [:]
        let attachmentPaths = copiedFileAttachments.map {$0.path}
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: attachmentPaths)
    }
    
    // This function is called to copy stored file attachments
    // from pending crashes so that they are not overwritten by the
    // new app session
    func copyFileAttachmentsFromPendingCrashes() -> [URL] {
        guard let cacheDirectoryUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            BacktraceLogger.error("Could not get cache directory URL")
            return [URL]()
        }
        let attachments = (try? AttachmentsStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? [:]
        var copiedFileAttachments = [URL]()
        for attachment in attachments {
            let fileManager = FileManager()
            let copiedAttachmentPath = cacheDirectoryUrl.appendingPathComponent(attachment.key)
            do {
                if fileManager.fileExists(atPath: copiedAttachmentPath.path) {
                    try fileManager.removeItem(atPath: copiedAttachmentPath.path)
                }
                try fileManager.copyItem(at: attachment.value, to: copiedAttachmentPath)
                copiedFileAttachments.append(copiedAttachmentPath)
            } catch {
                print("Caught error: \(error)")
                BacktraceLogger.error("Could not copy bookmarked attachment file from previous session")
                continue
            }
        }
        return copiedFileAttachments
    }
        
    func hasPendingCrashes() -> Bool {
        return reporter.hasPendingCrashReport()
    }
    
    func purgePendingCrashReport() throws {
        try AttributesStorage.remove(fileName: BacktraceCrashReporter.crashName)
        try AttachmentsStorage.remove(fileName: BacktraceCrashReporter.crashName)
        try reporter.purgePendingCrashReportAndReturnError()
    }
}
