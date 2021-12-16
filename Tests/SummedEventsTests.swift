import XCTest

import Nimble
import Quick
@testable import Backtrace

final class SummedEventsTests: QuickSpec {

    override func spec() {
        describe("Backtrace metrics summed events") {
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            var backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let delegate = BacktraceMetricsDelegateSpy()

            var metrics = BacktraceMetrics(api: backtraceApi)

            beforeEach {
                delegate.clear()
                backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                metrics = BacktraceMetrics(api: backtraceApi)

                metrics.summedEventsDelegate = delegate
            }

            afterEach {
                MetricsInfo.disableMetrics()
            }

            it("sends summed events startup event") {
                urlSession.response = MockOkResponse()
                metrics.enable(settings: BacktraceMetricsSettings())

                expect { delegate.calledWillSendRequest }.to(beTrue())
                expect { delegate.calledServerDidRespond }.to(beTrue())
                expect { delegate.calledConnectionDidFail }.to(beFalse())
            }
        }
    }
}
