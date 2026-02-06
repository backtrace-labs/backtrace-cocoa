import Foundation
import Testing
@testable import Backtrace

@Suite struct CrashReporterTests {

    @Test func hasNoPendingCrashes() throws {
        let crashReporter = BacktraceCrashReporter()
        #expect(crashReporter.hasPendingCrashes() == false)
        #expect(throws: (any Error).self) { try crashReporter.pendingCrashReport() }
        #expect(throws: (any Error).self) { try crashReporter.purgePendingCrashReport() }
    }

    @Test func generatesLiveReportOnDemand() throws {
        let crashReporter = BacktraceCrashReporter()
        #expect(throws: Never.self) { try crashReporter.generateLiveReport(attributes: [:]) }
    }

    @Test func generatesLiveReportOnDemandTenTimes() throws {
        let crashReporter = BacktraceCrashReporter()
        for _ in 0...10 {
            #expect(throws: Never.self) { try crashReporter.generateLiveReport(attributes: [:]) }
        }
    }

    @Test func generatedLiveReportWithoutException() throws {
        let crashReporter = BacktraceCrashReporter()
        let reportData = try crashReporter.generateLiveReport(exception: nil, attributes: [:])

        #expect(reportData.plCrashReport.exceptionInfo == nil)
    }

    @Test func generatedLiveReportContainsException() throws {
        let crashReporter = BacktraceCrashReporter()
        let exception = NSException(name: NSExceptionName.decimalNumberOverflowException, reason: "Test Spec")
        let reportData = try crashReporter.generateLiveReport(exception: exception, attributes: [:])

        #expect(reportData.plCrashReport.exceptionInfo.exceptionName == NSExceptionName.decimalNumberOverflowException.rawValue)
        #expect(reportData.plCrashReport.exceptionInfo.exceptionReason == "Test Spec")
    }
}
