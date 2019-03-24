import Foundation
import XCTest
import Backtrace

typealias VoidClosure = () -> Void

//based on: https://medium.com/@johnsundell/mocking-in-swift-56a913ee7484
final class URLSessionMock: URLSession {
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    // Properties that enable us to set exactly what data or error
    // we want our mocked URLSession to return for any request.
    var response: MockResponse?
    
    override func dataTask(with request: URLRequest,
                           completionHandler: @escaping CompletionHandler) -> URLSessionDataTask {
        return URLSessionDataTaskMock { [weak self] in
            guard let self = self else { return }
            completionHandler(self.response?.data, self.response?.urlResponse, self.response?.error)
        }
    }
}

// We create a partial mock by subclassing the original class
final class URLSessionDataTaskMock: URLSessionDataTask {
    private let closure: () -> Void
    init(closure: @escaping () -> Void) {
        self.closure = closure
    }
    // We override the 'resume' method and simply call our closure
    // instead of actually resuming any task.
    override func resume() {
        closure()
    }
}

final class BacktraceClientDelegateMock: BacktraceClientDelegate {
    
    var willSendClosure: ((BacktraceReport) -> BacktraceReport)?
    var willSendRequestClosure: ((URLRequest) -> URLRequest)?
    var serverDidResponseClosure: ((BacktraceResult) -> Void)?
    var connectionDidFailClosure: ((Error) -> Void)?
    var didReachLimitClosure: ((BacktraceResult) -> Void)?
    
    func willSend(_ report: BacktraceReport) -> BacktraceReport {
        return willSendClosure?(report) ?? report
    }
    
    func willSendRequest(_ request: URLRequest) -> URLRequest {
        return willSendRequestClosure?(request) ?? request
    }
    
    func serverDidResponse(_ result: BacktraceResult) {
        serverDidResponseClosure?(result)
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
    
    init(url: URL) {
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
    
    init(url: URL) {
        urlResponse = HTTPURLResponse(url: url, statusCode: 403, httpVersion: "1.1", headerFields: nil)
        let body = ["error": ["code": 6, "message": "invalid token"]]
        data = try? JSONSerialization.data(withJSONObject: body)
        error = nil
    }
}

struct MockConnectionErrorResponse: MockResponse {
    let data: Data?
    let error: Error?
    let urlResponse: URLResponse?
    
    init(url: URL) {
        urlResponse = nil
        data = nil
        error = NSError(domain: "backtrace.connection.error", code: 100, userInfo: nil)
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
