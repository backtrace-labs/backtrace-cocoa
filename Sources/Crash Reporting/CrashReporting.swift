//
//  CrashReporting.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 15/12/2018.
//

import Foundation
import PLCrashReporter

protocol CrashReporting {
    func generateLiveReport() throws -> CrashModel
    func generateLiveReportDescription(reportData: Data) throws -> String
    func pendingCrashReport() throws -> CrashModel
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

    func generateLiveReport() throws -> CrashModel {
        let reportData = try reporter.generateLiveReportAndReturnError()
        let report = try PLCrashReport(data: reportData)
        Logger.debug("Live report: \n\(report.info)")
        return CrashModel(report: reportData, hashValue: report.uuidRef?.hashValue)
    }

    func enableCrashReporting() throws {
        try reporter.enableAndReturnError()
    }

    func pendingCrashReport() throws -> CrashModel {
        let reportData = try reporter.loadPendingCrashReportDataAndReturnError()
        let report = try PLCrashReport(data: reportData)
        Logger.debug("Pending crash: \n\(report.info)")
        return CrashModel(report: reportData, hashValue: report.uuidRef?.hashValue)
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
