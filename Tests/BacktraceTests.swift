//
//  BacktraceTests.swift
//  Backtrace
//
//  Created by Marcin Karmelita on 17/12/2018.
//

import XCTest
@testable import Backtrace
import PLCrashReporter

class BacktraceTests: XCTestCase {

    func testPLCrashReporterDefaultConfigNeverFails() {
        XCTAssertNotNil(PLCrashReporterConfig.defaultConfiguration())
    }

    func testGeneratingLiveReportWithoutEnabledReporter() {
        let reporter = CrashReporter(config: PLCrashReporterConfig.defaultConfiguration())
        XCTAssertNoThrow(try reporter.generateLiveReport())
    }

    func testGeneratingLiveReport() {
        let reporter = CrashReporter(config: PLCrashReporterConfig.defaultConfiguration())
        XCTAssertNoThrow(try reporter.enableCrashReporting())
        XCTAssertNoThrow(try reporter.generateLiveReport())
    }
}
