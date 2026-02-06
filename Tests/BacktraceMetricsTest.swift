import Foundation
import Testing
@testable import Backtrace

@Suite struct BacktraceMetricsTests {

    private func createMetrics() -> BacktraceMetrics {
        let urlSession = URLSessionMock()
        urlSession.response = MockOkResponse()
        let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
        return BacktraceMetrics(api: backtraceApi)
    }

    @Test func clearsSummedEventsAfterEnabling() {
        let metrics = createMetrics()
        metrics.enable(settings: BacktraceMetricsSettings())

        metrics.clearSummedEvents()

        let summedEvents = metrics.getSummedEvents()
        #expect(summedEvents.count == 0)
    }

    @Test func canAddAndStoreSummedEvent() {
        let summedEventName = "view-changed"
        let metrics = createMetrics()
        metrics.enable(settings: BacktraceMetricsSettings())

        metrics.clearSummedEvents()

        metrics.addSummedEvent(name: summedEventName)

        guard let summedEvents = metrics.getSummedEvents() as? [SummedEvent] else { return }

        let filteredEvents = summedEvents.filter { event in
            return event.name == summedEventName
        }

        #expect(filteredEvents.count == 1)
    }

    @Test func canAddAndStoreApplicationLaunchEvent() {
        let applicationLaunchEventName = "Application Launches"
        let metrics = createMetrics()
        metrics.enable(settings: BacktraceMetricsSettings())

        guard let summedEvents = metrics.getSummedEvents() as? [SummedEvent] else { return }

        let filteredEvents = summedEvents.filter { event in
            return event.name == applicationLaunchEventName
        }

        #expect(filteredEvents.count == 1)
    }

    @Test func canAddAndStoreUniqueEvent() {
        let uniqueEventName = "guid"
        let metrics = createMetrics()
        metrics.enable(settings: BacktraceMetricsSettings())

        guard let uniqueEvents = metrics.getUniqueEvents() as? [UniqueEvent] else { return }

        let filteredEvents = uniqueEvents.filter { event in
            return event.name.contains(uniqueEventName)
        }

        #expect(filteredEvents.count == 1)
    }
}
