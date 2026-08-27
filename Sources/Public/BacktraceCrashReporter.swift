import Foundation

#if BACKTRACE_UNITY_PREFIXED_PLCRASHREPORTER
import BTUnityCrashReporter
#else
import CrashReporter
#endif
import Darwin

private final class BacktraceCrashSignalContext {
    let attributesProvider: SignalContext

    init(attributesProvider: SignalContext) {
        self.attributesProvider = attributesProvider
    }
}

/// Loads optional crash-time sidecars without making them a prerequisite for crash ingestion.
struct BacktracePendingCrashMetadata {
    static let attributesErrorKey = "backtrace.pending.attributes.error"
    static let invalidAttributeValuesKey = "backtrace.pending.attributes.invalid_values"
    static let invalidBookmarksKey = "backtrace.pending.attachments.invalid_bookmarks"
    static let missingAttachmentsKey = "backtrace.pending.attachments.missing_files"
    static let sidecarPreservationErrorKey = "backtrace.pending.sidecars.preservation_error"
    static let deadLetterMissingSidecarsKey = "backtrace.pending.dead_letter.sidecars.missing"
    static let deadLetterSidecarCopyFailuresKey = "backtrace.pending.dead_letter.sidecars.copy_failures"

    let attributes: Attributes
    let attachmentPaths: [String]
    let rawSidecarPaths: [String]
    let diagnostics: Attributes

    static func load(fileName: String) -> BacktracePendingCrashMetadata {
        var attributes = Attributes()
        var diagnostics = Attributes()
        var rawSidecarPaths = [String]()

        do {
            let config = try AttributesStorage.AttributesConfig(fileName: fileName)
            if FileManager.default.fileExists(atPath: config.fileUrl.path) {
                rawSidecarPaths.append(config.fileUrl.path)
            }
            attributes = try AttributesStorage.retrieve(fileName: fileName)
        } catch FileError.fileNotExists {
            // A crash may occur before the first attributes sidecar is written.
        } catch {
            diagnostics[attributesErrorKey] = String(describing: type(of: error))
            BacktraceLogger.warning("Pending crash attributes could not be decoded; ingesting the crash without them.")
        }

        var attachmentPaths = [String]()
        do {
            let config = try AttachmentsStorage.AttachmentsConfig(fileName: fileName)
            if FileManager.default.fileExists(atPath: config.fileUrl.path) {
                rawSidecarPaths.append(config.fileUrl.path)
            }
            let dictionary = try ReportMetadataStorageImpl.retrieveFromFile(config: config)
            guard let bookmarks = dictionary as? Bookmarks else {
                throw AttachmentsStorageError.invalidDictionary
            }
            let recovery = AttachmentBookmarkHandlerImpl.recoverAttachmentUrls(bookmarks)
            var missingAttachmentCount = 0
            for attachment in recovery.attachments {
                if FileManager.default.fileExists(atPath: attachment.path) {
                    attachmentPaths.append(attachment.path)
                } else {
                    missingAttachmentCount += 1
                }
            }
            if recovery.invalidBookmarkCount > 0 {
                diagnostics[invalidBookmarksKey] = recovery.invalidBookmarkCount
            }
            if missingAttachmentCount > 0 {
                diagnostics[missingAttachmentsKey] = missingAttachmentCount
            }
        } catch FileError.fileNotExists {
            // Attachments are optional.
        } catch {
            diagnostics[invalidBookmarksKey] = -1
            BacktraceLogger.warning("Pending crash attachment bookmarks could not be decoded; ingesting the crash without them.")
        }

        attributes += diagnostics

        return BacktracePendingCrashMetadata(attributes: attributes,
                                             attachmentPaths: attachmentPaths,
                                             rawSidecarPaths: rawSidecarPaths,
                                             diagnostics: diagnostics)
    }
}

enum BacktracePendingCrashError: Error {
    case invalidPayload(data: Data, rawSidecarPaths: [String], diagnostics: Attributes, underlying: Error)
}

/// A wrapper around `PLCrashReporter`.
@objc public class BacktraceCrashReporter: NSObject {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    private var retainedSignalContext: BacktraceCrashSignalContext?
    private let installationStateLock = NSLock()
    private var installationWasAttempted = false

    /// Indicates that PLCrashReporter handler installation was entered for this instance.
    /// Native wrappers use this to distinguish retryable pre-enable initialization failures from a potentially partial process-wide handler installation.
    @objc public var handlerInstallationAttempted: Bool {
        installationStateLock.lock()
        defer { installationStateLock.unlock() }
        return installationWasAttempted
    }

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
    }
}

extension BacktraceCrashReporter: CrashReporting {
    func signalContext(_ mutableContext: inout SignalContext) {
        let handler: @convention(c) (_ signalInfo: UnsafeMutablePointer<siginfo_t>?,
            _ uContext: UnsafeMutablePointer<ucontext_t>?,
            _ context: UnsafeMutableRawPointer?) -> Void = { signalInfoPointer, _, context in
                BacktraceOomWatcher.clean()
                guard let context = context else { return }
                let signalContext = Unmanaged<BacktraceCrashSignalContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                let attributesProvider = signalContext.attributesProvider
                guard
                    let signalInfo = signalInfoPointer?.pointee else {
                    return
                }
            
                attributesProvider.set(faultMessage: "\(String(cString: strsignal(signalInfo.si_signo)))")

                try? AttributesStorage.store(attributesProvider.dynamicAttributes,
                                             fileName: BacktraceCrashReporter.crashName)
                try? AttachmentsStorage.store(attributesProvider.allAttachments,
                                              fileName: BacktraceCrashReporter.crashName)
        }

        let signalContext = BacktraceCrashSignalContext(attributesProvider: mutableContext)
        retainedSignalContext = signalContext
        let contextPointer = Unmanaged.passUnretained(signalContext).toOpaque()
        var callbacks = PLCrashReporterCallbacks(version: 0, context: contextPointer, handleSignal: handler)
        reporter.setCrash(&callbacks)
    }

    func generateLiveReport(exception: NSException? = nil,
                            attributes: Attributes,
                            attachmentPaths: [String] = []) throws -> BacktraceReport {
        
        return try generateLiveReport(exception: exception,
                                          thread: mach_thread_self(),
                                          attributes: attributes,
                                          attachmentPaths: attachmentPaths)
    }
    
    func generateLiveReport(exception: NSException? = nil,
                            thread: mach_port_t,
                            attributes: Attributes,
                            attachmentPaths: [String] = []) throws -> BacktraceReport {
        
        defer { mach_port_deallocate(mach_task_self_, thread) }
        let reportData = try reporter.generateLiveReport(withThread: thread, exception: exception)
        
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: attachmentPaths)
    }

    func enableCrashReporting() throws {
        installationStateLock.lock()
        installationWasAttempted = true
        installationStateLock.unlock()
        try reporter.enableAndReturnError()
    }

    // This function retrieves, constructs, and sends the pending crash report
    func pendingCrashReport() throws -> BacktraceReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let metadata = BacktracePendingCrashMetadata.load(fileName: BacktraceCrashReporter.crashName)
        do {
            let report = try BacktraceReport(pendingReport: reportData,
                                             attributes: metadata.attributes,
                                             attachmentPaths: metadata.attachmentPaths)
            report.pendingMetadataFilePaths = metadata.rawSidecarPaths
            return report
        } catch {
            throw BacktracePendingCrashError.invalidPayload(data: reportData,
                                                            rawSidecarPaths: metadata.rawSidecarPaths,
                                                            diagnostics: metadata.diagnostics,
                                                            underlying: error)
        }
    }
    
    func setCustomData(data: Data) {
        self.reporter.customData = data
    }

    func hasPendingCrashes() -> Bool {
        return reporter.hasPendingCrashReport()
    }

    func purgePendingCrashReport() throws {
        // Keep metadata available if PLCrashReporter itself cannot purge. A later launch can then repeat the deterministic repository upsert without losing attributes or attachment ownership evidence.
        try reporter.purgePendingCrashReportAndReturnError()

        do {
            try AttributesStorage.remove(fileName: BacktraceCrashReporter.crashName)
        } catch {
            BacktraceLogger.warning("Purged pending crash payload but could not remove its attributes sidecar.")
        }
        do {
            try AttachmentsStorage.remove(fileName: BacktraceCrashReporter.crashName)
        } catch {
            BacktraceLogger.warning("Purged pending crash payload but could not remove its attachment-bookmark sidecar.")
        }
    }
}
