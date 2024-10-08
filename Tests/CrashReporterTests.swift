import XCTest

import Nimble
import Quick
@testable import Backtrace

final class CrashReporterTests: QuickSpec {

    override func spec() {
        describe("Crash reporter") {
            let crashReporter = BacktraceCrashReporter()

            it("has no pending crashes") {
                expect(crashReporter.hasPendingCrashes()).to(beFalse())
                expect { try crashReporter.pendingCrashReport() }.to(throwError())
                expect { try crashReporter.purgePendingCrashReport() }.to(throwError())
            }

            context("given valid configuration") {
                it("generates live report on demand") {
                    expect { try crashReporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                }
                
                it("generate live report on demand 10 times") {
                    for _ in 0...10 {
                        expect { try crashReporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                    }
                }
                
                it("generated live report without exception") {
                    let reportData = try crashReporter.generateLiveReport(exception: nil, attributes: [:])
                    
                    expect { reportData.plCrashReport.exceptionInfo }.to(beNil())
                }
                
                it("generated live report contains exception") {
                    let exception = NSException(name: NSExceptionName.decimalNumberOverflowException, reason: "Test Spec")
                    let reportData = try crashReporter.generateLiveReport(exception: exception, attributes: [:])
                    
                    expect { reportData.plCrashReport.exceptionInfo.exceptionName }.to(equal(NSExceptionName.decimalNumberOverflowException.rawValue))
                    expect { reportData.plCrashReport.exceptionInfo.exceptionReason }.to(equal("Test Spec"))
                }
            }
        }
    }
}
