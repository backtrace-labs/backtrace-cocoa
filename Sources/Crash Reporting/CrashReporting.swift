import Foundation
import Backtrace_PLCrashReporter

protocol CrashReporting {
    func generateLiveReport() throws -> BacktraceCrashReport
    func generateLiveReport(exception: NSException) throws -> BacktraceCrashReport
    func generateLiveReportDescription(reportData: Data) throws -> String
    func pendingCrashReport() throws -> BacktraceCrashReport
    func purgePendingCrashReport() throws
    func hasPendingCrashes() -> Bool
    func enableCrashReporting() throws
}

class CrashReporter: NSObject {
    private let reporter: PLCrashReporter

    public init(config: PLCrashReporterConfig = PLCrashReporterConfig.defaultConfiguration()) {
        reporter = PLCrashReporter.init(configuration: config)
    }
}

extension CrashReporter: CrashReporting {
    func generateLiveReport(exception: NSException) throws -> BacktraceCrashReport {
        let reportData = try reporter.generateLiveReport(with: exception)
        let report = try PLCrashReport(data: reportData)
        BacktraceLogger.debug("Live report: \n\(report.info)")
        return BacktraceCrashReport(report: reportData, hashValue: report.uuidRef?.hashValue)
    }

    func generateLiveReport() throws -> BacktraceCrashReport {
        let reportData = try reporter.generateLiveReportAndReturnError()
        let report = try PLCrashReport(data: reportData)
        BacktraceLogger.debug("Live report: \n\(report.info)")
        return BacktraceCrashReport(report: reportData, hashValue: report.uuidRef?.hashValue)
    }

    func enableCrashReporting() throws {
        try reporter.enableAndReturnError()
    }

    func pendingCrashReport() throws -> BacktraceCrashReport {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let report = try PLCrashReport(data: reportData)
        BacktraceLogger.debug("Pending crash: \n\(report.info)")
        return BacktraceCrashReport(report: reportData, hashValue: report.uuidRef?.hashValue)
    }

    func hasPendingCrashes() -> Bool {
        return reporter.hasPendingCrashReport()
    }

    func purgePendingCrashReport() throws {
        try reporter.purgePendingCrashReportAndReturnError()
    }

    func generateLiveReportDescription(reportData: Data) throws -> String {
        let report = try PLCrashReport(data: reportData)
        return report.info
    }
}
