// swiftlint:disable force_try function_body_length

import XCTest
import Nimble
import Quick

@testable import Backtrace

class BacktraceOomWatcherTests: QuickSpec {

    override func spec() {
        describe("BacktraceOomWatcher") {
            var oomWatcher: BacktraceOomWatcher?
            let urlSession = URLSessionMock()
            let credentials =
                BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
            let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
            let crashReporter = BacktraceCrashReporter()
            let repository = try! PersistentRepository<BacktraceReport>(settings: BacktraceDatabaseSettings())
            let newFile = URL(fileURLWithPath: "newfile")

            throwingBeforeEach {
                let attributesProvider = AttributesProvider()

                try "".write(to: newFile, atomically: true, encoding: .utf8)
                attributesProvider.attachments.append(newFile)

                oomWatcher = BacktraceOomWatcher(repository: repository,
                                                 crashReporter: crashReporter,
                                                 attributes: attributesProvider,
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
                    expect { savedState?.memoryWarningReceived }.to(beFalse())
                    expect { BacktraceOomWatcher.reportAttributes }.to(beNil())
                    expect { BacktraceOomWatcher.reportAttachments }.to(beNil())
                }
                it("application state change results in updated state file") {

                    oomWatcher?.start()
                    oomWatcher?.appChangedState(BacktraceOomWatcher.ApplicationState.background)
                    let savedState = oomWatcher?.loadPreviousState()

                    expect { savedState?.state }.to(equal(BacktraceOomWatcher.ApplicationState.background))
                }
                it("low memory warning results in updated state file with resource and attributes") {
                    oomWatcher?.start()
                    oomWatcher?.handleLowMemoryWarning()
                    let savedState = oomWatcher?.loadPreviousState()

                    expect { savedState?.memoryWarningReceived }.to(beTrue())
                    expect { BacktraceOomWatcher.reportAttributes }.toNot(beNil())
                    expect { BacktraceOomWatcher.reportAttachments?.first?.path }.to(contain("newfile"))
                }
                it("calling handleLowMemory again within quiet times is noop") {

                    // Modify the quiet time so we can check if it re-saved the state after the quiet time expires
                    oomWatcher?.quietTimeInMillis = 100
                    oomWatcher?.attributesProvider.attachments.removeAll()

                    oomWatcher?.start()
                    oomWatcher?.handleLowMemoryWarning()

                    let shouldNotBeAddedFile = URL(fileURLWithPath: "should-not-be-added")
                    try "".write(to: shouldNotBeAddedFile, atomically: true, encoding: .utf8)

                    oomWatcher?.attributesProvider.attachments.append(shouldNotBeAddedFile)
                    oomWatcher?.attributesProvider.attributes["should-not"] = "be-added"

                    // All these should be NOOPs
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.handleLowMemoryWarning()

                    expect { BacktraceOomWatcher.reportAttachments }.to(beEmpty())
                    expect { BacktraceOomWatcher.reportAttributes?["should-not"] }.to(beNil())

                    // after sleeping for the quietTime interval, it should add new attachments and attributes
                    Thread.sleep(forTimeInterval: 0.1)

                    oomWatcher?.attributesProvider.attachments.removeAll()

                    let shouldBeAddedFile = URL(fileURLWithPath: "should-be-added")
                    try "".write(to: shouldBeAddedFile, atomically: true, encoding: .utf8)
                    oomWatcher?.attributesProvider.attachments.append(shouldBeAddedFile)
                    oomWatcher?.attributesProvider.attributes["should"] = "be-added"

                    oomWatcher?.handleLowMemoryWarning()
                    expect { BacktraceOomWatcher.reportAttachments?.first?.path }.to(contain("should-be-added"))
                    expect { BacktraceOomWatcher.reportAttributes?["should"] }.toNot(beNil())
                }
            }
            context("with sending mocks") {
                var calledWillSend = 0
                var delegate = BacktraceClientDelegateMock()

                beforeEach {
                    urlSession.response = MockOkResponse()
                    calledWillSend = 0
                    delegate = BacktraceClientDelegateMock()

                    delegate.willSendClosure = { report in
                        calledWillSend += 1
                        expect { report.attachmentPaths }.to(contain(newFile.path))
                        // Oom specific attributes
                        expect { report.attributes["error.message"] as? String }.to(equal("Out of memory detected."))
                        expect { report.attributes["error.type"] as? String }.to(equal("Low Memory"))
                        expect { report.attributes["state"] as? String }.to(equal("active"))
                        // Random "generic" attribute
                        expect { report.attributes["guid"] as? String }.toNot(beNil())
                        return report
                    }
                }

                it("results in oom report being sent when oom requirements met") {
                    oomWatcher?.start()

                    // may be true when running in XCode: override bc otherwise won't send the report
                    oomWatcher?.state.debugger = false

                    oomWatcher?.handleLowMemoryWarning()

                    backtraceApi.delegate = delegate
                    oomWatcher?.sendPendingOomReports()

                    expect { calledWillSend }.to(equal(1))
                 }
                 it("can handle missing attributes and attachments") {
                     urlSession.response = MockOkResponse()

                     oomWatcher?.start()

                     // may be true when running in XCode: override bc otherwise won't send the report
                     oomWatcher?.state.debugger = false

                     oomWatcher?.handleLowMemoryWarning()

                     BacktraceOomWatcher.reportAttributes = nil
                     BacktraceOomWatcher.reportAttachments = nil

                     let delegate = BacktraceClientDelegateMock()
                     delegate.willSendClosure = { report in
                         calledWillSend += 1

                         expect { report.attributes }.to(beEmpty())
                         expect { report.attachmentPaths }.to(beEmpty())

                         return report
                     }

                     backtraceApi.delegate = delegate
                     oomWatcher?.sendPendingOomReports()

                     expect { calledWillSend }.to(be(1))
                 }
                 it("results in oom report NOT being sent when oom requirements NOT met: no warning") {
                     // debugger attached: no report.
                     oomWatcher?.start()
                     oomWatcher?.state.debugger = true
                     oomWatcher?.state.memoryWarningReceived = false
                     oomWatcher?.handleLowMemoryWarning()

                     backtraceApi.delegate = delegate
                     oomWatcher?.sendPendingOomReports()

                     expect { calledWillSend }.to(be(0))
                 }
                it("results in oom report NOT being sent when oom requirements NOT met: no report") {
                    // no memory warning: no report.
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false

                    backtraceApi.delegate = delegate
                    oomWatcher?.sendPendingOomReports()

                    expect { calledWillSend }.to(be(0))
                }
                it("results in oom report NOT being sent when oom requirements NOT met: other app version") {
                    // app version different: no report.
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false
                    oomWatcher?.state.appVersion = "1.2.3"
                    oomWatcher?.handleLowMemoryWarning()

                    backtraceApi.delegate = delegate
                    oomWatcher?.sendPendingOomReports()

                    expect { calledWillSend }.to(be(0))
                }
                it("results in oom report NOT being sent when oom requirements NOT met: other OS version") {
                    // OS version different: no report.
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false
                    oomWatcher?.state.version = "1.2.3"
                    oomWatcher?.handleLowMemoryWarning()

                    backtraceApi.delegate = delegate
                    oomWatcher?.sendPendingOomReports()

                    expect { calledWillSend }.to(be(0))
                }
            }
        }
    }

}
