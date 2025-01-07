import Foundation
import CrashReporter
import Darwin

import Foundation
import CrashReporter
import Darwin

actor AttachmentManager {
    private var attachments: [URL] = []

    /// Updates the list of copied file attachments.
    func updateAttachments(with newAttachments: [URL]) {
        attachments = newAttachments
    }

    /// Retrieves the list of copied file attachments.
    func getAttachments() -> [URL] {
        return attachments
    }

    /// Deletes all copied file attachments.
    func deleteAttachments() async throws {
        let fileManager = FileManager.default
        for attachment in attachments {
            if fileManager.fileExists(atPath: attachment.path) {
                try fileManager.removeItem(atPath: attachment.path)
            }
        }
        attachments = []
    }
}

/// A wrapper around `PLCrashReporter`.
@objc public class BacktraceCrashReporter: NSObject {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    private let attachmentManager = AttachmentManager()

    /// Creates an instance of a crash reporter.
    /// - Parameter config: A `PLCrashReporterConfig` configuration to use.
    @objc public convenience init(config: PLCrashReporterConfig = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)) {
        self.init(reporter: PLCrashReporter(configuration: config))
    }

    /// Creates an instance of a crash reporter.
    /// - Parameter reporter: An instance of `PLCrashReporter` to use.
    @objc public init(reporter: PLCrashReporter) {
        self.reporter = reporter
        super.init()
        // Lazy Initialize `copiedFileAttachments` asynchronously
        loadCopiedFileAttachments()
    }
    
    /// Asynchronously loads copied file attachments using the AttachmentManager actor.
    private func loadCopiedFileAttachments() {
        Task {
            let attachments = await BacktraceCrashReporter.copyFileAttachmentsFromPendingCrashes()
            await attachmentManager.updateAttachments(with: attachments)
        }
    }

    /// Retrieves the list of copied file attachments.
    func getCopiedFileAttachments() async -> [URL] {
        return await attachmentManager.getAttachments()
    }
}

extension BacktraceCrashReporter: CrashReporting {
    func signalContext(_ mutableContext: inout SignalContext) {
        let handler: @convention(c) (_ signalInfo: UnsafeMutablePointer<siginfo_t>?,
                                     _ uContext: UnsafeMutablePointer<ucontext_t>?,
                                     _ context: UnsafeMutableRawPointer?) -> Void = { signalInfoPointer, _, context in
            BacktraceOomWatcher.clean()
            guard let attributesProvider = context?.assumingMemoryBound(to: SignalContext.self).pointee,
                  let signalInfo = signalInfoPointer?.pointee else {
                return
            }
            
            attributesProvider.set(faultMessage: "\(String(cString: strsignal(signalInfo.si_signo)))")
            
            // Offload the async storage calls to a Task
            Task {
                do {
                    try await AttributesStorage.store(attributesProvider.dynamicAttributes, fileName: BacktraceCrashReporter.crashName)
                    try await AttachmentsStorage.store(attributesProvider.allAttachments, fileName: BacktraceCrashReporter.crashName)
                } catch {
                    await BacktraceLogger.error("Failed to store crash attributes or attachments: \(error)")
                }
            }
            
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
    func pendingCrashReport() async throws -> BacktraceReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        
        let attributes = await (try? AttributesStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? [:]
        let attachmentPaths = await attachmentManager.getAttachments().map(\.path)
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: attachmentPaths)
    }
    
    func setCustomData(data: Data) {
        self.reporter.customData = data
    }

    // This function is called to copy stored file attachments
    // from pending crashes so that they are not overwritten by the
    // new app session
    static func copyFileAttachmentsFromPendingCrashes() async -> [URL] {
        guard let directoryUrl = try? AttachmentsStorage.AttachmentsConfig(fileName: "").directoryUrl else {
            await BacktraceLogger.error("Could not get cache directory URL")
            return [URL]()
        }
        let attachments = await (try? AttachmentsStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? []
        var copiedFileAttachments = [URL]()
        for attachment in attachments {
            let fileManager = FileManager.default
            let fileName = attachment.lastPathComponent
            let copiedAttachmentPath = directoryUrl.appendingPathComponent(fileName)
            do {
                if !fileManager.fileExists(atPath: attachment.path) {
                    await BacktraceLogger.error("File attachment from previous session does not exist")
                    continue
                }
                if fileManager.fileExists(atPath: copiedAttachmentPath.path) {
                    try fileManager.removeItem(atPath: copiedAttachmentPath.path)
                }
                try fileManager.copyItem(at: attachment, to: copiedAttachmentPath)
                copiedFileAttachments.append(copiedAttachmentPath)
            } catch {
                await BacktraceLogger.error("Could not copy bookmarked attachment file from previous session. Error: \(error)")
                continue
            }
        }
        return copiedFileAttachments
    }

    func hasPendingCrashes() -> Bool {
        return reporter.hasPendingCrashReport()
    }

    func purgePendingCrashReport() async throws {
        try await AttributesStorage.remove(fileName: BacktraceCrashReporter.crashName)
        try await AttachmentsStorage.remove(fileName: BacktraceCrashReporter.crashName)
        try await attachmentManager.deleteAttachments()
        try reporter.purgePendingCrashReportAndReturnError()
    }
}
