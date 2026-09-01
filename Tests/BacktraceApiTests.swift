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
                urlSession.resetRequestCount()
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
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
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                }
            }

            context("given a thrown submission failure") {
                it("classifies permanent URL configuration errors separately from transient transport errors") {
                    let malformedUrl = URL(string: "https://yourteam.backtrace.io")!
                    expect(HttpError.malformedUrl(malformedUrl).backtraceSubmissionDisposition)
                        .to(equal(.permanentFailure))

                    for code in [URLError.Code.badURL,
                                 .unsupportedURL,
                                 .appTransportSecurityRequiresSecureConnection] {
                        let error = MockUrlErrorResponse(code).error!
                        expect(NetworkError.connectionError(error).backtraceSubmissionDisposition)
                            .to(equal(.permanentFailure), description: "URL error \(code.rawValue)")
                    }

                    let transportError = MockUrlErrorResponse(.timedOut).error!
                    expect(NetworkError.connectionError(transportError).backtraceSubmissionDisposition)
                        .to(equal(.retryable))
                    expect(HttpError.unknownError.backtraceSubmissionDisposition)
                        .to(equal(.retryable))
                }
            }

            context("given forbidden HTTP response") {
                it("classifies the response as a permanent rejection and calls delegate methods") {
                    urlSession.response = Mock403Response()
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    let result = try backtraceApi.send(report)

                    expect(result.backtraceStatus).to(equal(.serverError))
                    expect(result.submissionDisposition).to(equal(.permanentFailure))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(1))
                }
            }

            context("given retryable HTTP responses") {
                it("classifies transient status codes for retry") {
                    for statusCode in [408, 425, 429, 500, 503, 599] {
                        urlSession.response = MockHttpResponse(statusCode: statusCode)
                        let report = try crashReporter.generateLiveReport(attributes: [:])

                        expect(try backtraceApi.send(report).submissionDisposition)
                            .to(equal(.retryable), description: "HTTP \(statusCode)")
                    }
                }
            }

            context("given non-retryable HTTP responses") {
                it("classifies permanent status codes without retry") {
                    for statusCode in [400, 401, 403, 404, 405, 410, 413, 422] {
                        urlSession.response = MockHttpResponse(statusCode: statusCode)
                        let report = try crashReporter.generateLiveReport(attributes: [:])

                        expect(try backtraceApi.send(report).submissionDisposition)
                            .to(equal(.permanentFailure), description: "HTTP \(statusCode)")
                    }
                }
            }

            context("given an unlimited report rate") {
                it("sends without retaining rate-window timestamps") {
                    let backtraceApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 0)
                    backtraceApi.delegate = delegate
                    urlSession.response = MockOkResponse()
                    expect { try backtraceApi
                            .send(try crashReporter.generateLiveReport(attributes: [:])).backtraceStatus
                    }.to(equal(.ok))

                    expect { delegate.calledWillSend }.to(beTrue())
                    expect { delegate.calledWillSendRequest }.to(beTrue())
                    expect { delegate.calledServerDidRespond }.to(beTrue())
                    expect { delegate.calledConnectionDidFail }.to(beFalse())
                    expect { delegate.calledDidReachLimit }.to(beFalse())
                    expect { backtraceApi.backtraceRateLimiter.timestamps.count }.to(equal(0))
                }
            }

            context("given a full report-rate window") {
                it("does not open another request and calls the limit delegate") {
                    let limitedApi = BacktraceApi(credentials: credentials, session: urlSession, reportsPerMin: 1)
                    limitedApi.delegate = delegate
                    urlSession.response = MockOkResponse()

                    _ = try limitedApi.send(try crashReporter.generateLiveReport(attributes: [:]))
                    delegate.clear()
                    let result = try limitedApi.send(try crashReporter.generateLiveReport(attributes: [:]))

                    expect(result.backtraceStatus).to(equal(.limitReached))
                    expect(result.submissionDisposition).to(equal(.rateLimited))
                    expect(delegate.calledWillSend).to(beFalse())
                    expect(delegate.calledWillSendRequest).to(beFalse())
                    expect(delegate.calledServerDidRespond).to(beFalse())
                    expect(delegate.calledConnectionDidFail).to(beFalse())
                    expect(delegate.calledDidReachLimit).to(beTrue())
                    expect(urlSession.requestCount).to(equal(1))
                    expect(limitedApi.backtraceRateLimiter.timestamps.count).to(equal(1))
                }
            }

            context("when submission credentials contain a sentinel token") {
                throwingIt("never writes the token to SDK logs on success or transport failure") {
                    let token = "sentinel-backtrace-token-7a9d3b"
                    let endpoint = URL(string: "https://submit.backtrace.io/example")!
                    let tokenCredentials = BacktraceCredentials(endpoint: endpoint, token: token)
                    let tokenApi = BacktraceApi(credentials: tokenCredentials,
                                                session: urlSession,
                                                reportsPerMin: 30)
                    let destination = CapturingBacktraceDestination()
                    let previousDestinations = BacktraceLogger.destinations
                    BacktraceLogger.setDestinations([destination])
                    defer { BacktraceLogger.setDestinations(previousDestinations) }

                    urlSession.response = MockOkResponse(url: endpoint)
                    let success = try tokenApi.send(try crashReporter.generateLiveReport(attributes: [:]))

                    let failingUrl = URL(string: "https://submit.backtrace.io/example/post?token=\(token)")!
                    urlSession.response = MockConnectionErrorResponse(url: failingUrl)
                    expect {
                        try tokenApi.send(try crashReporter.generateLiveReport(attributes: [:]))
                    }.to(throwError())

                    expect(destination.messages.filter { $0.contains(token) }).to(beEmpty())
                    expect(success.message).toNot(contain(token))
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
                    let path1URL = URL(fileURLWithPath: "path1")
                    let path2URL = URL(fileURLWithPath: "path2")
                    
                    let path1data = Data(count: 1024)
                    let path2data = Data(count: 1024)
                    
                    try path1data.write(to: path1URL)
                    try path2data.write(to: path2URL)
                    
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

            context("when logging destinations change concurrently") {
                it("uses snapshots and never holds the storage lock across callbacks") {
                    let previousDestinations = BacktraceLogger.destinations
                    defer { BacktraceLogger.setDestinations(previousDestinations) }
                    let destination = CapturingBacktraceDestination()
                    let group = DispatchGroup()
                    let queue = DispatchQueue(label: "backtrace.logger.stress", attributes: .concurrent)

                    for index in 0..<500 {
                        group.enter()
                        queue.async {
                            BacktraceLogger.setDestinations(index.isMultiple(of: 2) ? [destination] : [])
                            BacktraceLogger.warning("concurrent logger message \(index)")
                            group.leave()
                        }
                    }

                    expect(group.wait(timeout: .now() + .seconds(5))).to(equal(.success))

                    let callback = ReentrantBacktraceDestination()
                    BacktraceLogger.setDestinations([callback])
                    queue.async {
                        BacktraceLogger.warning("reentrant logger callback")
                    }
                    expect(callback.invoked.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                }
            }

            context("when shutdown interrupts a stalled transport") {
                throwingIt("returns promptly, cancels the task, and suppresses late delegate callbacks") {
                    let session = HangingURLSession()
                    let api = BacktraceApi(credentials: credentials, session: session, reportsPerMin: 30)
                    let shutdownDelegate = BacktraceClientDelegateSpy()
                    api.delegate = shutdownDelegate
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    let sendQueue = DispatchQueue(label: "backtrace.api.shutdown.send",
                                                  qos: .userInitiated)
                    let shutdownQueue = DispatchQueue(label: "backtrace.api.shutdown.cancel",
                                                      qos: .userInitiated)
                    let sendClosureEntered = DispatchSemaphore(value: 0)
                    let sendFinished = DispatchSemaphore(value: 0)

                    sendQueue.async {
                        sendClosureEntered.signal()
                        defer { sendFinished.signal() }
                        _ = try? api.send(report)
                    }

                    guard sendClosureEntered.wait(timeout: .now() + .seconds(5)) == .success else {
                        api.shutdown()
                        fail("The send worker was not scheduled.")
                        return
                    }
                    guard session.started.wait(timeout: .now() + .seconds(10)) == .success else {
                        api.shutdown()
                        _ = sendFinished.wait(timeout: .now() + .seconds(10))
                        fail("The hanging transport did not enter resume().")
                        return
                    }

                    let shutdownReturned = DispatchSemaphore(value: 0)
                    shutdownQueue.async {
                        api.shutdown()
                        shutdownReturned.signal()
                    }

                    guard shutdownReturned.wait(timeout: .now() + .seconds(5)) == .success else {
                        api.shutdown()
                        _ = sendFinished.wait(timeout: .now() + .seconds(10))
                        fail("Shutdown did not return promptly.")
                        return
                    }
                    guard session.cancelled.wait(timeout: .now() + .seconds(5)) == .success else {
                        api.shutdown()
                        _ = sendFinished.wait(timeout: .now() + .seconds(10))
                        fail("Shutdown did not cancel the hanging transport.")
                        return
                    }
                    guard sendFinished.wait(timeout: .now() + .seconds(5)) == .success else {
                        api.shutdown()
                        fail("The send worker did not finish after transport cancellation.")
                        return
                    }

                    expect(api.isShutdown).to(beTrue())
                    expect(shutdownDelegate.calledConnectionDidFail).to(beFalse())
                    expect(shutdownDelegate.calledServerDidRespond).to(beFalse())
                    expect { try api.send(report) }.to(throwError())
                    expect(session.requestCount).to(equal(1))
                    expect(session.startedCount).to(equal(1))
                    expect(session.cancellationCount).to(equal(1))
                }
            }

            context("when shutdown begins after an HTTP response is received") {
                throwingIt("returns and reports the completed HTTP response") {
                    let responseReceived = DispatchSemaphore(value: 0)
                    let releaseResponse = DispatchSemaphore(value: 0)
                    urlSession.response = MockOkResponse()
                    let api = BacktraceApi(credentials: credentials,
                                           session: urlSession,
                                           reportsPerMin: 30,
                                           afterTransportCompletion: {
                                               responseReceived.signal()
                                               releaseResponse.wait()
                                           })
                    let responseDelegate = BacktraceClientDelegateSpy()
                    api.delegate = responseDelegate
                    let report = try crashReporter.generateLiveReport(attributes: [:])
                    let finished = DispatchSemaphore(value: 0)
                    var result: BacktraceResult?
                    DispatchQueue.global().async {
                        result = try? api.send(report)
                        finished.signal()
                    }

                    expect(responseReceived.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    api.shutdown()
                    releaseResponse.signal()

                    expect(finished.wait(timeout: .now() + .seconds(2))).to(equal(.success))
                    expect(result?.backtraceStatus).to(equal(.ok))
                    expect(responseDelegate.calledServerDidRespond).to(beTrue())
                    expect(responseDelegate.calledConnectionDidFail).to(beFalse())
                    expect(urlSession.requestCount).to(equal(1))
                }
            }
        }
    }
    // swiftlint:enable function_body_length
}

private final class ReentrantBacktraceDestination: BacktraceBaseDestination {
    let invoked = DispatchSemaphore(value: 0)

    init() {
        super.init(level: .debug)
    }

    override func log(level: BacktraceLogLevel,
                      msg: String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        BacktraceLogger.setDestinations([])
        invoked.signal()
    }
}

final class CapturingBacktraceDestination: BacktraceBaseDestination {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    init() {
        super.init(level: .debug)
    }

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedMessages
    }

    override func log(level: BacktraceLogLevel,
                      msg: String,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
        lock.lock()
        recordedMessages.append(msg)
        lock.unlock()
    }
}
