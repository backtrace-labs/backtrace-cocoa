import Foundation
import CrashReporter


/// A wrapper around `PLCrashReporter`.
@objc public class BacktraceCrashReporter: NSObject {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    private let copiedFileAttachments: [URL]

    /// Creates an instance of a crash reporter.
    /// - Parameter config: A `PLCrashReporterConfig` configuration to use.
    @objc public convenience init(config: PLCrashReporterConfig = PLCrashReporterConfig.defaultConfiguration()) {
        self.init(reporter: PLCrashReporter(configuration: config))
    }

    /// Creates an instance of a crash reporter.
    /// - Parameter reporter: An instance of `PLCrashReporter` to use.
    @objc public init(reporter: PLCrashReporter) {
        self.reporter = reporter
        self.copiedFileAttachments = BacktraceCrashReporter.copyFileAttachmentsFromPendingCrashes()
        super.init()
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
        let reportData = try reporter.generateLiveReportAndReturnError()
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: attachmentPaths)
    }

    func enableCrashReporting() throws {
        try reporter.enableAndReturnError()
    }

    // This function retrieves, constructs, and sends the pending crash report
    func pendingCrashReport() throws -> BacktraceReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let attributes = (try? AttributesStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? [:]
        let attachmentPaths = copiedFileAttachments.map(\.path)
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: attachmentPaths)
    }

    // This function is called to copy stored file attachments
    // from pending crashes so that they are not overwritten by the
    // new app session
    static func copyFileAttachmentsFromPendingCrashes() -> [URL] {
        guard let directoryUrl = try? AttachmentsStorage.AttachmentsConfig(fileName: "").directoryUrl else {
            BacktraceLogger.error("Could not get cache directory URL")
            return [URL]()
        }
        let attachments = (try? AttachmentsStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? []
        var copiedFileAttachments = [URL]()
        for attachment in attachments {
            let fileManager = FileManager.default
            let fileName = attachment.lastPathComponent
            let copiedAttachmentPath = directoryUrl.appendingPathComponent(fileName)
            do {
                if !fileManager.fileExists(atPath: attachment.path) {
                    BacktraceLogger.error("File attachment from previous session does not exist")
                    continue
                }
                if fileManager.fileExists(atPath: copiedAttachmentPath.path) {
                    try fileManager.removeItem(atPath: copiedAttachmentPath.path)
                }
                try fileManager.copyItem(at: attachment, to: copiedAttachmentPath)
                copiedFileAttachments.append(copiedAttachmentPath)
            } catch {
                BacktraceLogger.error("Could not copy bookmarked attachment file from previous session. Error: \(error)")
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
        try deleteCopiedFileAttachments()
        try reporter.purgePendingCrashReportAndReturnError()
    }

    func deleteCopiedFileAttachments() throws {
        let fileManager = FileManager.default
        for attachment in copiedFileAttachments {
            if fileManager.fileExists(atPath: attachment.path) {
                try fileManager.removeItem(atPath: attachment.path)
            }
        }
    }
}
