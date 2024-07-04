import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceMetricsTests: QuickSpec {

    override func spec() {
        describe("Backtrace Metrics") {
            let urlSession = URLSessionMock()
            urlSession.response = MockOkResponse()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

            let summedEventName = "view-changed"
            let uniqueEventName = "guid"

            it("clears the summed event after enabling and sending") {
                let metrics = BacktraceMetrics(api: backtraceApi)
                metrics.enable(settings: BacktraceMetricsSettings())

                // Allow default events to be "sent" out
                expect { metrics.count }.toEventually(equal(1), timeout: .seconds(6), pollInterval: .milliseconds(500))
            }

            it("can add and store summed event") {
                let metrics = BacktraceMetrics(api: backtraceApi)
                metrics.enable(settings: BacktraceMetricsSettings())

                // Allow default events to be "sent" out
                expect { metrics.count }.toEventually(equal(1), timeout: .seconds(6), pollInterval: .milliseconds(500))

                metrics.addSummedEvent(name: summedEventName)
                expect { metrics.count }.to(equal(2))
            }

            it("can add and store unique event") {
                let metrics = BacktraceMetrics(api: backtraceApi)
                metrics.enable(settings: BacktraceMetricsSettings())

                // Allow default events to be "sent" out
                expect { metrics.count }.toEventually(equal(1), timeout: .seconds(6), pollInterval: .milliseconds(500))

                metrics.addUniqueEvent(name: uniqueEventName)
                expect { metrics.count }.to(equal(2))
            }
        }
    }
}
