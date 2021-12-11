import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceMetricsTests: QuickSpec {
    
    override func spec() {
        describe("Backtrace Metrics") {
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let metrics = BacktraceMetrics(api: backtraceApi)
            
            let summedEventName = "view-changed"

            it("can add and store summed event") {
                metrics.enable(settings: BacktraceMetricsSettings())
                expect { metrics.count }.to(be(0))
                
                metrics.addSummedEvent(name: summedEventName)
                expect { metrics.count }.to(be(1))
            }
        }
    }
}
