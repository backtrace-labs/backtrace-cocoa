import XCTest
@testable import Backtrace

class PerformanceTests: XCTestCase {

    func testPerformanceAllAttributes() {
        let attributesProvider = AttributesProvider()
        self.measure {
            _ = attributesProvider.allAttributes
        }
    }

    func testPerformanceAttachmentPaths() {
        let attributesProvider = AttributesProvider()
        self.measure {
            _ = attributesProvider.attachmentPaths
        }
    }

    func testPerformanceLiveReport() throws {
        let crashReporter = BacktraceCrashReporter()
        let attributesProvider = AttributesProvider()
        self.measure {
            _ = try? crashReporter.generateLiveReport(attributes: attributesProvider.allAttributes)
        }
    }
}
