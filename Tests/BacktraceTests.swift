import Nimble
import Quick
@testable import Backtrace

final class BacktraceTests: QuickSpec {
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
        }
    }
}
