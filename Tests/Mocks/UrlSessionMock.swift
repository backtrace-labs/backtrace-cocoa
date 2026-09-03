import Foundation
import XCTest
import Backtrace

typealias VoidClosure = () -> Void

// based on: https://medium.com/@johnsundell/mocking-in-swift-56a913ee7484
final class URLSessionMock: URLSession, @unchecked Sendable {
    // Properties that enable us to set exactly what data or error
    // we want our mocked URLSession to return for any request.
    var response: MockResponse?
    private let requestLock = NSLock()
    private var recordedRequestCount = 0

    var requestCount: Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedRequestCount
    }

    func resetRequestCount() {
        requestLock.lock()
        defer { requestLock.unlock() }
        recordedRequestCount = 0
    }

    override func dataTask(with request: URLRequest,
                           completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        requestLock.lock()
        recordedRequestCount += 1
        requestLock.unlock()
        return URLSessionDataTaskMock { [weak self] in
            guard let self = self else { return }
            completionHandler(self.response?.data, self.response?.urlResponse, self.response?.error)
        }
    }
}

// We create a partial mock by subclassing the original class
final class URLSessionDataTaskMock: URLSessionDataTask, @unchecked Sendable {
    private let closure: VoidClosure
    
    /// Test‑only initializer; suppresses the deprecated `super.init()`.
    @available(
        iOS, deprecated: 13.0,
        message: "Unit‑test stubbing only; do not use in production"
    )
    init(closure: @escaping VoidClosure) {
        self.closure = closure
        super.init()
    }
    
    // We override the 'resume' method and simply call our closure
    // instead of actually resuming any task.
    override func resume() {
        closure()
    }
}

/// Transport that never completes unless its task is cancelled. Used to prove that native
/// bridge shutdown does not wait indefinitely on URLSession.sync.
final class HangingURLSession: URLSession, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let cancelled = DispatchSemaphore(value: 0)
    private let requestLock = NSLock()
    private var recordedRequestCount = 0
    private var recordedStartedCount = 0
    private var recordedCancellationCount = 0

    var requestCount: Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedRequestCount
    }

    var startedCount: Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedStartedCount
    }

    var cancellationCount: Int {
        requestLock.lock()
        defer { requestLock.unlock() }
        return recordedCancellationCount
    }

    override func dataTask(with request: URLRequest,
                           completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        requestLock.lock()
        recordedRequestCount += 1
        requestLock.unlock()
        return HangingURLSessionDataTask(
            onStart: { [weak self] in
                self?.recordStart()
            },
            onCancellation: { [weak self] in
                self?.recordCancellation()
            },
            completionHandler: completionHandler
        )
    }

    private func recordStart() {
        requestLock.lock()
        recordedStartedCount += 1
        requestLock.unlock()
        started.signal()
    }

    private func recordCancellation() {
        requestLock.lock()
        recordedCancellationCount += 1
        requestLock.unlock()
        cancelled.signal()
    }
}

final class HangingURLSessionDataTask: URLSessionDataTask, @unchecked Sendable {
    private let onStart: () -> Void
    private let onCancellation: () -> Void
    private let completionHandler: (Data?, URLResponse?, Error?) -> Void
    private let lifecycleLock = NSLock()
    private var completionDelivered = false

    @available(
        iOS, deprecated: 13.0,
        message: "Unit-test stubbing only; do not use in production"
    )
    init(onStart: @escaping () -> Void,
         onCancellation: @escaping () -> Void,
         completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) {
        self.onStart = onStart
        self.onCancellation = onCancellation
        self.completionHandler = completionHandler
        super.init()
    }

    override func resume() {
        onStart()
    }

    override func cancel() {
        lifecycleLock.lock()
        guard !completionDelivered else {
            lifecycleLock.unlock()
            return
        }
        completionDelivered = true
        lifecycleLock.unlock()

        completionHandler(nil, nil, URLError(.cancelled))
        onCancellation()
    }
}

final class BacktraceClientDelegateSpy: BacktraceClientDelegate {

    var calledWillSend: Bool = false
    var calledWillSendRequest: Bool = false
    var calledServerDidRespond: Bool = false
    var calledConnectionDidFail: Bool = false
    var calledDidReachLimit: Bool = false

    func willSend(_ report: BacktraceReport) -> BacktraceReport {
        calledWillSend = true
        return report
    }

    func willSendRequest(_ request: URLRequest) -> URLRequest {
        calledWillSendRequest = true
        return request
    }

    func serverDidRespond(_ result: BacktraceResult) {
        calledServerDidRespond = true
    }

    func connectionDidFail(_ error: Error) {
        calledConnectionDidFail = true
    }

    func didReachLimit(_ result: BacktraceResult) {
        calledDidReachLimit = true
    }

    func clear() {
        calledWillSend = false
        calledWillSendRequest = false
        calledServerDidRespond = false
        calledConnectionDidFail = false
        calledDidReachLimit = false
    }
}

final class BacktraceClientDelegateMock: BacktraceClientDelegate {

    var willSendClosure: ((BacktraceReport) -> BacktraceReport)?
    var willSendRequestClosure: ((URLRequest) -> URLRequest)?
    var serverDidRespondClosure: ((BacktraceResult) -> Void)?
    var connectionDidFailClosure: ((Error) -> Void)?
    var didReachLimitClosure: ((BacktraceResult) -> Void)?

    func willSend(_ report: BacktraceReport) -> BacktraceReport {
        return willSendClosure?(report) ?? report
    }

    func willSendRequest(_ request: URLRequest) -> URLRequest {
        return willSendRequestClosure?(request) ?? request
    }

    func serverDidRespond(_ result: BacktraceResult) {
        serverDidRespondClosure?(result)
    }

    func connectionDidFail(_ error: Error) {
        connectionDidFailClosure?(error)
    }

    func didReachLimit(_ result: BacktraceResult) {
        didReachLimitClosure?(result)
    }
}

protocol MockResponse {
    var data: Data? { get }
    var error: Error? { get }
    var urlResponse: URLResponse? { get }
}

struct MockOkResponse: MockResponse {
    let data: Data?
    let error: Error?
    let urlResponse: URLResponse?

    init(url: URL = URL(string: "https://yourteam.backtrace.io")!) {
        urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: nil)
        let body: [String: Any] = ["response": "ok",
                                   "_rxid": "04000000-4ca4-4002-0000-000000000000",
                                   "fingerprint": "7edeff2cd1c15068c918dcefe7db4301ee6314cee654ef44d8da941a4a75924e",
                                   "unique": false]
        data = try? JSONSerialization.data(withJSONObject: body)
        error = nil
    }
}

struct Mock403Response: MockResponse {
    let data: Data?
    let error: Error?
    let urlResponse: URLResponse?

    init(url: URL = URL(string: "https://yourteam.backtrace.io")!) {
        urlResponse = HTTPURLResponse(url: url, statusCode: 403, httpVersion: "1.1", headerFields: nil)
        let body = ["error": ["code": 6, "message": "invalid token"]]
        data = try? JSONSerialization.data(withJSONObject: body)
        error = nil
    }
}

struct MockHttpResponse: MockResponse {
    let data: Data?
    let error: Error? = nil
    let urlResponse: URLResponse?

    init(statusCode: Int, url: URL = URL(string: "https://yourteam.backtrace.io")!) {
        urlResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "1.1", headerFields: nil)
        data = try? JSONSerialization.data(withJSONObject: ["status": statusCode])
    }
}

struct MockConnectionErrorResponse: MockResponse {
    let data: Data?
    let error: Error?
    let urlResponse: URLResponse?

    init(url: URL = URL(string: "https://yourteam.backtrace.io")!) {
        urlResponse = nil
        data = nil
        error = NSError(domain: "backtrace.connection.error",
                        code: 100,
                        userInfo: [NSURLErrorFailingURLStringErrorKey: url.absoluteString])
    }
}

struct MockUrlErrorResponse: MockResponse {
    let data: Data? = nil
    let error: Error?
    let urlResponse: URLResponse? = nil

    init(_ code: URLError.Code,
         url: URL = URL(string: "https://yourteam.backtrace.io")!) {
        error = NSError(domain: NSURLErrorDomain,
                        code: code.rawValue,
                        userInfo: [NSURLErrorFailingURLStringErrorKey: url.absoluteString])
    }
}

struct MockNoResponse: MockResponse {
    let data: Data?
    let error: Error?
    let urlResponse: URLResponse?

    init() {
        urlResponse = nil
        data = nil
        error = nil
    }
}
