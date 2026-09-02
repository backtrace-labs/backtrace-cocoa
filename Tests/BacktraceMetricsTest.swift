import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceMetricsTests: QuickSpec {

    // swiftlint:disable:next function_body_length
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

                    // Enabling metrics sends and clears startup summed events asynchronously.
                    // Wait for that work to finish before exercising a newly added event.
                    expect { metrics?.getSummedEvents().count }.toEventually(
                        equal(0),
                        timeout: .seconds(10),
                        pollInterval: .milliseconds(10)
                    )
                    
                    metrics?.addSummedEvent(name: summedEventName)
                    
                    guard let summedEvents = metrics?.getSummedEvents() as? [SummedEvent] else { return }
                    
                    let filteredEvents = summedEvents.filter { event in
                        return event.name == summedEventName
                    }
                    
                    expect {filteredEvents.count}.to(equal(1))
                }
                
                it("can add and store application launch event") {
                    // BacktraceMetrics.enable sends and clears this event asynchronously, so
                    // verify its creation at the container boundary without racing the sender.
                    let container = BacktraceMetricsContainer(settings: BacktraceMetricsSettings())
                    let summedEvents = container.getSummedEventsPayload().events
                    
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

                it("replaces and stops the previous startup sender when enabled again") {
                    let replacementMetrics = BacktraceMetrics(api: backtraceApi)

                    replacementMetrics.enable(settings: BacktraceMetricsSettings())
                    replacementMetrics.enable(settings: BacktraceMetricsSettings())
                    replacementMetrics.shutdownForNativeBridge()

                    expect(replacementMetrics.isShutdown).to(beTrue())
                    replacementMetrics.enable(settings: BacktraceMetricsSettings())
                    replacementMetrics.addUniqueEvent(name: "ignored-after-replacement-shutdown")
                    expect(replacementMetrics.count).to(equal(0))
                }

                it("cancels in-flight startup metrics and rejects future work after native shutdown") {
                    let session = HangingURLSession()
                    let api = BacktraceApi(credentials: credentials, session: session, reportsPerMin: 30)
                    let senderQueue = DispatchQueue(label: "backtrace.metrics.shutdown.tests",
                                                    qos: .userInitiated)
                    let shutdownMetrics = BacktraceMetrics(api: api,
                                                           senderQueue: senderQueue)
                    shutdownMetrics.enable(settings: BacktraceMetricsSettings())
                    senderQueue.sync {}

                    expect(session.requestCount).to(equal(2))
                    expect(session.startedCount).to(equal(2))

                    shutdownMetrics.shutdownForNativeBridge()
                    api.shutdown()

                    expect(session.cancellationCount).to(equal(2))
                    shutdownMetrics.addUniqueEvent(name: "ignored-after-shutdown")
                    shutdownMetrics.addSummedEvent(name: "ignored-after-shutdown")
                    expect(shutdownMetrics.isShutdown).to(beTrue())
                    expect(shutdownMetrics.count).to(equal(0))
                }
            }

            context("Logging") {
                it("does not expose malformed credential input") {
                    let sentinel = "sentinel-metrics-token-5c8e2a"
                    let invalidCredentials = BacktraceCredentials(submissionUrl: URL(string: sentinel)!)
                    let invalidApi = BacktraceApi(credentials: invalidCredentials,
                                                  session: urlSession,
                                                  reportsPerMin: 30)
                    let destination = CapturingBacktraceDestination()
                    let previousDestinations = BacktraceLogger.destinations
                    BacktraceLogger.setDestinations([destination])
                    defer { BacktraceLogger.setDestinations(previousDestinations) }

                    // Keep the facade alive until both queued startup events exercise the
                    // redacted error path; production BacktraceClient owns this lifetime.
                    let senderQueue = DispatchQueue(label: "backtrace.metrics.logging.tests",
                                                    qos: .userInitiated)
                    let invalidMetrics = BacktraceMetrics(api: invalidApi,
                                                          senderQueue: senderQueue)
                    invalidMetrics.enable(settings: BacktraceMetricsSettings())
                    senderQueue.sync {}

                    let messages = destination.messages
                    expect(messages.filter {
                        $0 == "Unable to prepare summed metrics submission"
                    }.count).to(equal(1))
                    expect(messages.filter {
                        $0 == "Unable to prepare unique metrics submission"
                    }.count).to(equal(1))
                    expect(messages.filter { $0.contains(sentinel) }).to(beEmpty())
                    invalidMetrics.shutdownForNativeBridge()
                }
            }
        }
    }
}
