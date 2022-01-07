import XCTest

import Nimble
import Quick
@testable import Backtrace

final class BacktraceApiTests: QuickSpec {
    // swiftlint:disable function_body_length
    override func spec() {
        describe("Backtrace API") {
            let crashReporter = BacktraceCrashReporter()
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

            context("given valid HTTP response") {
                it("sends report and calls delegate methods") {
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
                }
            }
            context("given no HTTP response") {
                it("sends report and calls delegate methods") {
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
                }
            }

            context("given connection error") {
                it("fails to send report and calls delegate methods") {
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
                }
            }

            context("given forbidden HTTP response") {
                it("fails to send crash report and calls delegate methods") {
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
                }
            }

            context("given too many reports to send") {
                it("fails and calls limit reached delegate methods") {
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
                }
            }

            context("given new instance") {
                let api = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 30)
                it("has no delegate attached") { expect(api.delegate).to(beNil()) }
                it("has empty timestamps list") { expect(api.backtraceRateLimiter.timestamps).to(beEmpty()) }

                context("provided with delegate object") {
                    it("has delegate object attached") {
                        let delegate = BacktraceClientDelegateMock()
                        api.delegate = delegate
                        expect(api.delegate).toNot(beNil())
                    }
                }
            }

            context("given new report") {
                throwingIt("can modify the report") {
                    let delegate = BacktraceClientDelegateMock()
                    let backtraceReport = try crashReporter.generateLiveReport(attributes: [:])
                    let attachmentPaths = ["path1", "path2"]
                    let header = (key: "foo", value: "bar")
                    urlSession.response = MockOkResponse()
                    backtraceApi.delegate = delegate

                    delegate.willSendClosure = { report in
                        report.attachmentPaths = attachmentPaths
                        return report
                    }

                    delegate.willSendRequestClosure = { request in
                        var request = request
                        request.addValue(header.key, forHTTPHeaderField: header.value)
                        return request
                    }

                    let result = try backtraceApi.send(backtraceReport)

                    expect { result.backtraceStatus }.to(equal(.ok))
                    expect { result.report?.attachmentPaths }.to(equal(attachmentPaths))
                }
            }
        }
    }
    // swiftlint:enable function_body_length
}
