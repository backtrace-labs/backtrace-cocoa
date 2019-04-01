import Foundation
import Backtrace_PLCrashReporter

final class CrashReporter {
    private let reporter: PLCrashReporter
    static private let crashName = "live_report"
    public init(config: PLCrashReporterConfig = PLCrashReporterConfig.defaultConfiguration()) {
        reporter = PLCrashReporter.init(configuration: config)
    }
}

extension CrashReporter: CrashReporting {
    func signalContext(_ mutableContext: inout SignalContext) {
        let rawMutablePointer = UnsafeMutableRawPointer(&mutableContext)
        let handler: @convention(c) (_ signalInfo: UnsafeMutablePointer<siginfo_t>?,
            _ uContext: UnsafeMutablePointer<ucontext_t>?,
            _ context: UnsafeMutableRawPointer?) -> Void = { signalInfoPointer, _, context in
                guard let attributesProvider = context?.assumingMemoryBound(to: SignalContext.self).pointee,
                    let signalInfo = signalInfoPointer?.pointee else {
                    return
                }
                BacktraceLogger.debug("Saving custom attributes:\n\(attributesProvider.description)")
                attributesProvider.set(faultMessage: "siginfo_t.si_signo: \(signalInfo.si_signo)")
                try? AttributesStorage.store(attributesProvider.allAttributes, fileName: CrashReporter.crashName)
        }
        var callbacks = PLCrashReporterCallbacks(version: 0, context: rawMutablePointer, handleSignal: handler)
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
        let attributes = (try? AttributesStorage.retrieve(fileName: CrashReporter.crashName)) ?? [:]
        // NOTE: - no attachments in crash reports
        return try BacktraceReport(report: reportData, attributes: attributes, attachmentPaths: [])
    }
    
    func hasPendingCrashes() -> Bool {
        return reporter.hasPendingCrashReport()
    }
    
    func purgePendingCrashReport() throws {
        try AttributesStorage.remove(fileName: CrashReporter.crashName)
        try reporter.purgePendingCrashReportAndReturnError()
    }
}
