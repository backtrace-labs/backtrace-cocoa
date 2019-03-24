import XCTest

import Nimble
import Quick
@testable import Backtrace

final class CrashReporterTests: QuickSpec {
    
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            it("has no pending crashes", closure: {
                expect(crashReporter.hasPendingCrashes()).to(beFalse())
                expect { try crashReporter.pendingCrashReport() }.to(throwError())
                expect { try crashReporter.purgePendingCrashReport() }.to(throwError())
            })
        }
    }
}
