import Nimble
import Quick
@testable import Backtrace

final class BacktraceTests: QuickSpec {
    // swiftlint:disable function_body_length
    override func spec() {
        describe("Crash reporter") {
            let crashReporter = CrashReporter()
            context("given valid configuration") {
                it("generates live report on demand", closure: {
                    expect { try crashReporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                })
                it("generate live report on demand 10 times", closure: {
                    for _ in 0...10 {
                        expect { try crashReporter.generateLiveReport(attributes: [:]) }.toNot(throwError())
                    }
                })
            }
            
            describe("Backtrace API") {
                
                let urlSession = URLSessionMock()
                let credentials =
                    BacktraceCredentials(endpoint: URL(string: "https://yourteam.backtrace.io")!, token: "")
                var backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                let delegate = BacktraceClientDelegateSpy()
                
                beforeEach {
                    delegate.clear()
                    backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                    backtraceApi.delegate = delegate
                }
                
                context("given valid HTTP response", closure: {
                    it("sends report and calls delegate methods", closure: {
                        urlSession.response = MockOkResponse()
                        expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:])).backtraceStatus
                        }.to(equal(BacktraceReportStatus.ok))
                        
                        expect { delegate.calledWillSend }.to(beTrue())
                        expect { delegate.calledWillSendRequest }.to(beTrue())
                        expect { delegate.calledServerDidRespond }.to(beTrue())
                        expect { delegate.calledConnectionDidFail }.to(beFalse())
                        expect { delegate.calledDidReachLimit }.to(beFalse())
                        expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    })
                })
                context("given no HTTP response", closure: {
                    it("sends report and calls delegate methods", closure: {
                        urlSession.response = MockNoResponse()
                        expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .to(throwError())
                        
                        expect { delegate.calledWillSend }.to(beTrue())
                        expect { delegate.calledWillSendRequest }.to(beTrue())
                        expect { delegate.calledConnectionDidFail }.to(beTrue())
                        expect { delegate.calledServerDidRespond }.to(beFalse())
                        expect { delegate.calledDidReachLimit }.to(beFalse())
                        expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    })
                })
                
                context("given connection error", closure: {
                    it("fails to send report and calls delegate methods", closure: {
                        urlSession.response =
                            MockConnectionErrorResponse()
                        expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:]))}
                            .to(throwError())
                        
                        expect { delegate.calledWillSend }.to(beTrue())
                        expect { delegate.calledWillSendRequest }.to(beTrue())
                        expect { delegate.calledConnectionDidFail }.to(beTrue())
                        expect { delegate.calledServerDidRespond }.to(beFalse())
                        expect { delegate.calledDidReachLimit }.to(beFalse())
                        expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    })
                })
                
                context("given forbidden HTTP response", closure: {
                    it("fails to send crash report and calls delegate methods", closure: {
                        urlSession.response = Mock403Response()
                        expect {
                            let report = try crashReporter.generateLiveReport(attributes: [:])
                            return try backtraceApi.send(report).backtraceStatus
                        }.to(equal(BacktraceReportStatus.serverError))
                        
                        expect { delegate.calledWillSend }.to(beTrue())
                        expect { delegate.calledWillSendRequest }.to(beTrue())
                        expect { delegate.calledServerDidRespond }.to(beTrue())
                        expect { delegate.calledConnectionDidFail }.to(beFalse())
                        expect { delegate.calledDidReachLimit }.to(beFalse())
                        expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(1))
                    })
                })
                
                context("given too many reports to send", closure: {
                    it("fails and calls limit reached delegate methods", closure: {
                        let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 0)
                        backtraceApi.delegate = delegate
                        urlSession.response = MockOkResponse()
                        expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:])).backtraceStatus
                        }.to(equal(.limitReached))
                        
                        expect { delegate.calledWillSend }.to(beFalse())
                        expect { delegate.calledWillSendRequest }.to(beFalse())
                        expect { delegate.calledServerDidRespond }.to(beFalse())
                        expect { delegate.calledConnectionDidFail }.to(beFalse())
                        expect { delegate.calledDidReachLimit }.to(beTrue())
                        expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(be(0))
                    })
                })
            }
        }
    }
    // swiftlint:enable function_body_length
}
