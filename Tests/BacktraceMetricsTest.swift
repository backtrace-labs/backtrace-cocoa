import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceMetricsTests: QuickSpec {

    override func spec() {
        describe("Backtrace Metrics") {
            let urlSession = URLSessionMock()
            urlSession.response = MockOkResponse()
            let credentials = BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)

            let summedEventName = "view-changed"
            let uniqueEventName = "guid"
            let applicationLaunchEventName = "Application Launches"
            
            var metrics: BacktraceMetrics?

            context("Events operation") {
                
                beforeEach {
                    metrics = BacktraceMetrics(api: backtraceApi)
                }
                
                it("clears the summed event after enabling") {
                    metrics?.enable(settings: BacktraceMetricsSettings())
                    
                    metrics?.clearSummedEvents()
                    
                    guard let summedEvents = metrics?.getSummedEvents() else { return }
                    
                    expect { summedEvents.count }.to(equal(0))
                }
                
                it("can add and store summed event") {
                    metrics?.enable(settings: BacktraceMetricsSettings())
                    
                    metrics?.clearSummedEvents()
                    
                    metrics?.addSummedEvent(name: summedEventName)
                    
                    guard let summedEvents = metrics?.getSummedEvents() as? [SummedEvent] else { return }
                    
                    let filteredEvents = summedEvents.filter { event in
                        return event.name == summedEventName
                    }
                    
                    expect {filteredEvents.count}.to(equal(1))
                }
                
                it("can add and store application launch event") {
                    
                    metrics?.enable(settings: BacktraceMetricsSettings())
                    
                    guard let summedEvents = metrics?.getSummedEvents() as? [SummedEvent] else { return }
                    
                    let filteredEvents = summedEvents.filter { event in
                        return event.name == applicationLaunchEventName
                    }
                    
                    expect {filteredEvents.count}.to(equal(1))
                }
                
                it("can add and store unique event") {
                    
                    metrics?.enable(settings: BacktraceMetricsSettings())
                    
                    guard let uniqueEvents = metrics?.getUniqueEvents() as? [UniqueEvent] else { return }
                    
                    let filteredEvents = uniqueEvents.filter { event in
                        return event.name.contains(uniqueEventName)
                    }
                    
                    expect {filteredEvents.count}.to(equal(1))
                }
            }
        }
    }
}
