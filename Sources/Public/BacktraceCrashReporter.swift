import Foundation
import Backtrace_PLCrashReporter

/// A wrapper around `PLCrashReporter`.
@objc public class BacktraceCrashReporter: NSObject {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    
    /// Creates an instance of a crash reporter.
    /// - Parameter config: A `PLCrashReporterConfig` configuration to use.
    @objc public convenience init(config: PLCrashReporterConfig = PLCrashReporterConfig.defaultConfiguration()) {
        self.init(reporter: PLCrashReporter(configuration: config))
    }
    
    /// Creates an instance of a crash reporter.
    /// - Parameter reporter: An instance of `PLCrashReporter` to use.
    @objc public init(reporter: PLCrashReporter) {
        self.reporter = reporter
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
    
    func pendingCrashReport() throws -> BacktraceReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let attributes = (try? AttributesStorage.retrieve(fileName: BacktraceCrashReporter.crashName)) ?? [:]
        // NOTE: - no attachments in crash reports
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: [])
    }
    
    func hasPendingCrashes() -> Bool {
        return reporter.hasPendingCrashReport()
    }
    
    func purgePendingCrashReport() throws {
        try AttributesStorage.remove(fileName: BacktraceCrashReporter.crashName)
        try reporter.purgePendingCrashReportAndReturnError()
    }
}
