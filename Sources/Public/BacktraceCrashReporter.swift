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

/// Loads the crash-time sidecars as one pending-ingestion unit.
///
/// A missing sidecar is valid because a crash can occur before any attributes or attachments are registered.
/// Once a sidecar exists, however, every read, property-list parse, and bookmark decode must succeed.
/// Returning a partial value would allow the PLCrashReporter source to be purged while silently losing metadata that was present at crash time.
struct BacktracePendingCrashMetadata {
    let attributes: Attributes
    let attachmentPaths: [String]

    static func load(fileName: String) throws -> BacktracePendingCrashMetadata {
        let attributes: Attributes
        do {
            attributes = try AttributesStorage.retrieve(fileName: fileName)
        } catch FileError.fileNotExists {
            attributes = [:]
        }

        let attachmentPaths: [String]
        do {
            attachmentPaths = try AttachmentsStorage.retrieve(fileName: fileName).map(\.path)
        } catch FileError.fileNotExists {
            attachmentPaths = []
        }

        return BacktracePendingCrashMetadata(attributes: attributes,
                                             attachmentPaths: attachmentPaths)
    }
}

/// A wrapper around `PLCrashReporter`.
@objc public class BacktraceCrashReporter: NSObject {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    private var retainedSignalContext: BacktraceCrashSignalContext?

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
        try reporter.enableAndReturnError()
    }

    // This function retrieves, constructs, and sends the pending crash report
    func pendingCrashReport() throws -> BacktraceReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let metadata = try BacktracePendingCrashMetadata.load(fileName: BacktraceCrashReporter.crashName)
        return try BacktraceReport(pendingReport: reportData,
                                   attributes: metadata.attributes,
                                   attachmentPaths: metadata.attachmentPaths)
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
            BacktraceLogger.warning("Purged pending crash payload but could not remove its attributes: \(error)")
        }
        do {
            try AttachmentsStorage.remove(fileName: BacktraceCrashReporter.crashName)
        } catch {
            BacktraceLogger.warning("Purged pending crash payload but could not remove its attachment bookmarks: \(error)")
        }
    }
}
