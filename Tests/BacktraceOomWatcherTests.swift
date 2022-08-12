// swiftlint:disable force_try function_body_length

import XCTest
import Nimble
import Quick

@testable import Backtrace

class BacktraceOomWatcherTests: QuickSpec {

    override func spec() {
        describe("BacktraceOomWatcherTests") {
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let crashReporter = BacktraceCrashReporter()
            let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())
            let oomWatcher = BacktraceOomWatcher(repository: repository,
                                                 crashReporter: crashReporter,
                                                 attributes: AttributesProvider(),
                                                 backtraceApi: backtraceApi)

            beforeEach {
                BacktraceOomWatcher.clean()
                urlSession.response = MockConnectionErrorResponse()
            }

            afterEach {
                oomWatcher.stop()
            }

            context("when started") {
                it("it saves the state with properties set") {
                    oomWatcher.start()

                    let savedStateOpt = oomWatcher.loadSavedAppContext()

                    guard let savedState = savedStateOpt else {
                        fail("No saved state")
                        return
                    }

                    expect { savedState.state }.to(equal(.active))
                    expect { savedState.appVersion }.to(equal(BacktraceOomWatcher.getAppVersion()))
                    expect { savedState.version }.to(equal(ProcessInfo.processInfo.operatingSystemVersionString))
                    expect { savedState.debugger }.to(equal(DebuggerChecker.isAttached()))
                    expect { savedState.memoryWarningTimestamp }.to(beNil())
                    expect { savedState.memoryWarningReceived }.to(beFalse())
                    expect { savedState.attributes }.to(beNil())
                }
                it("application state change results in updated state file") {
                    oomWatcher.start()
                    oomWatcher.appChangedState(BacktraceOomWatcher.AppState.background)

                    let savedState = oomWatcher.loadSavedAppContext()
                    expect { savedState?.state }.to(equal(BacktraceOomWatcher.AppState.background))
                }
            }
            context("when started and low memory warnings happen") {
                it("results in updated state file with resource and attributes") {
                    oomWatcher.start()
                    oomWatcher.handleLowMemoryWarning()

                    let savedState = oomWatcher.loadSavedAppContext()
                    expect { savedState?.memoryWarningTimestamp }.toNot(beNil())
                    expect { savedState?.memoryWarningReceived }.to(beTrue())
                    expect { savedState?.attributes }.toNot(beNil())
                }
                it("results in oom report being sent when oom requirements met") {
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
                        expect { report.attributes["state"] as? String }.to(equal("background"))
                        expect { report.attributes["memory.warning.timestamp"] }.toNot(beNil())
                        // Random "generic" attribute
                        expect { report.attributes["guid"] as? String }.toNot(beNil())
                        return report
                    }

                    oomWatcher.start()

                    // may be true when running in XCode: override bc otherwise won't send the report
                    oomWatcher.appContext?.debugger = false

                    oomWatcher.appChangedState(.background)
                    oomWatcher.handleLowMemoryWarning()
                    oomWatcher.sendPendingOomReports()

                    expect { calledWillSend }.toEventually(equal(1))
                }
                it("can handle missing attributes") {
                    urlSession.response = MockOkResponse()

                    oomWatcher.start()

                    // may be true when running in XCode: override bc otherwise won't send the report
                    oomWatcher.appContext?.debugger = false

                    oomWatcher.handleLowMemoryWarning()

                    // cheat a little, modify the struct and re-save it
                    oomWatcher.appContext?.attributes = nil
                    oomWatcher.saveAppContext()

                    oomWatcher.sendPendingOomReports()
                }
                it("results in oom report NOT being sent when oom requirements NOT met") {
                    let delegate = BacktraceClientDelegateMock()
                    backtraceApi.delegate = delegate
                    urlSession.response = MockOkResponse()
                    var calledWillSend = 0

                    delegate.willSendClosure = { report in
                        calledWillSend += 1
                        return report
                    }

                    // debugger attached: no report.
                    oomWatcher.start()
                    oomWatcher.appContext?.debugger = true
                    oomWatcher.appContext?.memoryWarningReceived = false
                    oomWatcher.handleLowMemoryWarning()
                    oomWatcher.sendPendingOomReports()

                    // no memory warning: no report.
                    oomWatcher.stop()
                    oomWatcher.start()
                    oomWatcher.appContext?.debugger = false
                    oomWatcher.sendPendingOomReports()

                    // app version different: no report.
                    oomWatcher.stop()
                    oomWatcher.start()
                    oomWatcher.appContext?.debugger = false
                    oomWatcher.appContext?.appVersion = "1.2.3"
                    oomWatcher.handleLowMemoryWarning()
                    oomWatcher.sendPendingOomReports()

                    // OS version different: no report.
                    oomWatcher.stop()
                    oomWatcher.start()
                    oomWatcher.appContext?.debugger = false
                    oomWatcher.appContext?.version = "1.2.3"
                    oomWatcher.handleLowMemoryWarning()
                    oomWatcher.sendPendingOomReports()

                    expect { calledWillSend }.to(be(0))
                }
                it("calling start multiple times doesn't send a 'pending' report") {
                    // otherwise won't send the report
                    oomWatcher.appContext?.debugger = false

                    let delegate = BacktraceClientDelegateMock()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        fail("Not expected to call willSendClosure")
                        return report
                    }

                    oomWatcher.start()
                    oomWatcher.handleLowMemoryWarning()
                    oomWatcher.start()
                    oomWatcher.start()
                }
            }
        }
    }
}
