// swiftlint:disable force_try function_body_length

import XCTest
import Nimble
import Quick

@testable import Backtrace

class BacktraceOomWatcherTests: QuickSpec {

    override func spec() {
        describe("BreadcrumbsLogManager") {
            var oomWatcher: BacktraceOomWatcher?
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let crashReporter = BacktraceCrashReporter()
            let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())

            throwingBeforeEach {
                oomWatcher = BacktraceOomWatcher(repository: repository,
                                                 crashReporter: crashReporter,
                                                 attributes: AttributesProvider(),
                                                 backtraceApi: backtraceApi)
                BacktraceOomWatcher.clean()

                urlSession.response = MockConnectionErrorResponse()
            }

            context("when enabled") {
                it("it saves the state with properties set") {
                    oomWatcher?.start()
                    let savedState = oomWatcher?.loadPreviousState()

                    expect { savedState?.state }.to(equal(BacktraceOomWatcher.ApplicationState.active))
                    expect { savedState?.appVersion }.to(equal(BacktraceOomWatcher.getAppVersion()))
                    expect { savedState?.version }.to(equal(ProcessInfo.processInfo.operatingSystemVersionString))
                    expect { savedState?.debugger }.to(equal(DebuggerChecker.isAttached()))
                    expect { savedState?.resource }.to(beNil())
                    expect { savedState?.attributes }.to(beNil())
                }
                it("application state change results in updated state file") {

                    oomWatcher?.start()
                    oomWatcher?.appChangedState(BacktraceOomWatcher.ApplicationState.background)
                    let savedState = oomWatcher?.loadPreviousState()

                    expect { savedState?.state }.to(equal(BacktraceOomWatcher.ApplicationState.background))
                }
                it("low memory warning results in updated state file with resource and attributes") {
                    // otherwise won't send the report
                    oomWatcher?.state.debugger = false

                    oomWatcher?.start()
                    oomWatcher?.handleLowMemoryWarning()
                    let savedState = oomWatcher?.loadPreviousState()

                    expect { savedState?.resource }.toNot(beNil())
                    expect { savedState?.attributes }.toNot(beNil())

                    let delegate = BacktraceClientDelegateMock()
                    backtraceApi.delegate = delegate
                    urlSession.response = MockOkResponse()
                    var calledWillSend = 0

                    delegate.willSendClosure = { report in
                        calledWillSend += 1
                        expect { report.attachmentPaths }.to(beEmpty())
                        // Oom specific attributes
                        expect { report.attributes["error.message"] as? String }.to(equal("Out of memory detected."))
                        expect { report.attributes["error.type"] as? String }.to(equal("Low Memory"))
                        expect { report.attributes["state"] as? String }.to(equal("active"))
                        // Random "generic" attribute
                        expect { report.attributes["guid"] as? String }.toNot(beNil())
                        return report
                    }

                    oomWatcher?.sendPendingOomReports()

                    expect { calledWillSend }.toEventually(equal(1))
                }
                it("calling start mulitple times doesn't send a 'pending' report") {
                    // otherwise won't send the report
                    oomWatcher?.state.debugger = false

                    let delegate = BacktraceClientDelegateMock()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        fail("Not expected to call willSendClosure")
                        return report
                    }

                    oomWatcher?.start()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.start()
                    oomWatcher?.start()
                }
            }
        }
    }

}
