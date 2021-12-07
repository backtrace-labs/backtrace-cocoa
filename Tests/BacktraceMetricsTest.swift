import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceMetricsTest: QuickSpec {
    
    override func spec() {
        describe("Backtrace Metrics") {
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            var backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        }
    }
}
