// swiftlint:disable force_try function_body_length

import XCTest
import Nimble
import Quick

@testable import Backtrace

extension BacktraceOomWatcher {
    /// BacktraceOomWatcher now performs all work asynchronously on its dedicated serial queue.
    /// The original unit‑tests assume that the start(), handleLowMemoryWarning() and appChangedState(_:) invocations finish synchronously, so their assertions run before the queue has persisted state or updated the static attributes/attachments.
    /// **test‑only**
    /// Blocks until all queued tasks have completed.
    func flushQueue() {
        queue.sync(flags: .barrier) { }
    }
}

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
                                                 backtraceApi: backtraceApi,
                                                 oomMode: .full)
                BacktraceOomWatcher.clean()

                urlSession.response = MockConnectionErrorResponse()
            }

            context("when enabled") {
                it("it saves the state with properties set") {
                    oomWatcher?.start()
                    oomWatcher?.flushQueue()
                    let savedState = oomWatcher?._loadPreviousState()

                    expect { savedState?.state }.to(equal(BacktraceOomWatcher.ApplicationState.active))
                    expect { savedState?.appVersion }.to(equal(BacktraceOomWatcher.appVersion()))
                    expect { savedState?.osVersion }.to(equal(ProcessInfo.processInfo.operatingSystemVersionString))
                    expect { savedState?.debugger }.to(equal(DebuggerChecker.isAttached()))
                    expect { savedState?.memoryWarningReceived }.to(beFalse())
                    expect { BacktraceOomWatcher.reportAttributes }.to(beNil())
                    expect { BacktraceOomWatcher.reportAttachments }.to(beNil())
                }
                it("application state change results in updated state file") {

                    oomWatcher?.start()
                    oomWatcher?.appChangedState(BacktraceOomWatcher.ApplicationState.background)
                    oomWatcher?.flushQueue()
                    let savedState = oomWatcher?._loadPreviousState()

                    expect { savedState?.state }.to(equal(BacktraceOomWatcher.ApplicationState.background))
                }
                it("low memory warning results in updated state file with resource and attributes") {
                    oomWatcher?.start()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.flushQueue()
                    let savedState = oomWatcher?._loadPreviousState()

                    expect { savedState?.memoryWarningReceived }.to(beTrue())
                    expect { BacktraceOomWatcher.reportAttributes }.toNot(beNil())
                    expect { BacktraceOomWatcher.reportAttachments?.first?.path }.to(contain("newfile"))
                }
                it("calling handleLowMemory again within quiet times is noop") {

                    // Modify the quiet time so we can check if it re-saved the state after the quiet time expires
                    oomWatcher?.quietTimeInMillis = 500
                    oomWatcher?.attributesProvider.attachments.removeAll()

                    oomWatcher?.start()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.flushQueue()

                    let shouldNotBeAddedFile = URL(fileURLWithPath: "should-not-be-added")
                    try "".write(to: shouldNotBeAddedFile, atomically: true, encoding: .utf8)

                    oomWatcher?.attributesProvider.attachments.append(shouldNotBeAddedFile)
                    oomWatcher?.attributesProvider.attributes["should-not"] = "be-added"

                    // All these should be NOOPs
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.handleLowMemoryWarning()
                    
                    oomWatcher?.flushQueue()

                    expect { BacktraceOomWatcher.reportAttachments }.to(beEmpty())
                    expect { BacktraceOomWatcher.reportAttributes?["should-not"] }.to(beNil())

                    // after sleeping for the quietTime interval, it should add new attachments and attributes
                    Thread.sleep(forTimeInterval: 0.5)

                    oomWatcher?.attributesProvider.attachments.removeAll()

                    let shouldBeAddedFile = URL(fileURLWithPath: "should-be-added")
                    try "".write(to: shouldBeAddedFile, atomically: true, encoding: .utf8)
                    oomWatcher?.attributesProvider.attachments.append(shouldBeAddedFile)
                    oomWatcher?.attributesProvider.attributes["should"] = "be-added"

                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.flushQueue()
                    expect { BacktraceOomWatcher.reportAttachments?.first?.path }.to(contain("should-be-added"))
                    expect { BacktraceOomWatcher.reportAttributes?["should"] }.toNot(beNil())
                }
            }
            
            context("when oomMode == .none") {
                it("does not create a state file or send reports") {
                    oomWatcher = BacktraceOomWatcher(repository: repository,
                                                     crashReporter: crashReporter,
                                                     attributes: AttributesProvider(),
                                                     backtraceApi: backtraceApi,
                                                     oomMode: .none)
                    
                    oomWatcher?.start()
                    oomWatcher?.flushQueue()
                    
                    expect(FileManager.default.fileExists(atPath: BacktraceOomWatcher.oomFileURL!.path)).to(beFalse())
                }
            }
            
            context("when oomMode == .light") {
                
                it("reports exactly once and off the main thread") {
                    urlSession.response = MockOkResponse()
                    var willSendCalls = 0
                    
                    let attrsProvider = AttributesProvider()
                    try "".write(to: newFile, atomically: true, encoding: .utf8)
                    attrsProvider.attachments.append(newFile)
                    
                    oomWatcher = BacktraceOomWatcher(repository: repository,
                                                     crashReporter: crashReporter,
                                                     attributes: attrsProvider,
                                                     backtraceApi: backtraceApi,
                                                     oomMode: .light)
                    
                    let delegate = BacktraceClientDelegateMock()
                    delegate.willSendClosure = { report in
                        willSendCalls += 1
                        return report
                    }
                    backtraceApi.delegate = delegate
                    
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false
                    oomWatcher?.handleLowMemoryWarning()
                    oomWatcher?.flushQueue()
                    oomWatcher?._sendPendingOomReports()
                    oomWatcher?.flushQueue()
                    
                    expect(willSendCalls).to(equal(1))
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
                        expect { report.attachmentPaths.count }.to(equal(1))
                        expect { report.attachmentPaths.first }.to(contain(newFile.path))
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
                    oomWatcher?.flushQueue()

                    backtraceApi.delegate = delegate
                    oomWatcher?._sendPendingOomReports()

                    expect { calledWillSend }.to(equal(1))
                 }
                
                 it("can handle missing attributes and attachments") {
                     urlSession.response = MockOkResponse()

                     oomWatcher?.start()

                     // may be true when running in XCode: override bc otherwise won't send the report
                     oomWatcher?.state.debugger = false

                     oomWatcher?.handleLowMemoryWarning()
                     oomWatcher?.flushQueue()

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
                     oomWatcher?._sendPendingOomReports()
                     
                     expect { calledWillSend }.to(equal(1))
                 }
                 it("results in oom report NOT being sent when oom requirements NOT met: no warning") {
                     // debugger attached: no report.
                     oomWatcher?.start()
                     oomWatcher?.state.debugger = true
                     oomWatcher?.state.memoryWarningReceived = false
                     oomWatcher?.handleLowMemoryWarning()

                     backtraceApi.delegate = delegate
                     oomWatcher?._sendPendingOomReports()

                     expect { calledWillSend }.to(equal(0))
                 }
                it("results in oom report NOT being sent when oom requirements NOT met: no report") {
                    // no memory warning: no report.
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false

                    backtraceApi.delegate = delegate
                    oomWatcher?._sendPendingOomReports()

                    expect { calledWillSend }.to(equal(0))
                }
                it("results in oom report NOT being sent when oom requirements NOT met: other app version") {
                    // app version different: no report.
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false
                    oomWatcher?.state.appVersion = "1.2.3"
                    oomWatcher?.handleLowMemoryWarning()

                    backtraceApi.delegate = delegate
                    oomWatcher?._sendPendingOomReports()

                    expect { calledWillSend }.to(equal(0))
                }
                it("results in oom report NOT being sent when oom requirements NOT met: other OS version") {
                    // OS version different: no report.
                    oomWatcher?.start()
                    oomWatcher?.state.debugger = false
                    oomWatcher?.state.osVersion = "1.2.3"
                    oomWatcher?.handleLowMemoryWarning()

                    backtraceApi.delegate = delegate
                    oomWatcher?._sendPendingOomReports()

                    expect { calledWillSend }.to(equal(0))
                }
            }
        }
    }

}
