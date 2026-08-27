import Foundation

/// A classified submission outcome delivered before any post-response delegate callback.
/// The durable submission coordinator uses this boundary to commit repository state before code can re-enter the SDK and request shutdown.
enum BacktraceSubmissionOutcome {
    case result(BacktraceResult)
    case failure(Error, report: BacktraceReport)
}

final class BacktraceApi {
    weak var delegate: BacktraceClientDelegate?

    private(set) var backtraceRateLimiter: BacktraceRateLimiter
    let networkClient: BacktraceNetworkClient
    let credentials: BacktraceCredentials
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false

    init(credentials: BacktraceCredentials,
         session: URLSession = URLSession(configuration: .ephemeral),
         reportsPerMin: Int,
         afterTransportCompletion: (() -> Void)? = nil) {
        self.networkClient = BacktraceNetworkClient(urlSession: session,
                                                    afterTransportCompletion: afterTransportCompletion)
        self.backtraceRateLimiter = BacktraceRateLimiter(reportsPerMin: reportsPerMin)
        self.credentials = credentials
    }

    internal var isShutdown: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return shutdownRequested
    }

    internal func shutdown() {
        lifecycleLock.lock()
        guard !shutdownRequested else {
            lifecycleLock.unlock()
            return
        }
        shutdownRequested = true
        lifecycleLock.unlock()
        networkClient.shutdown()
    }
}

extension BacktraceApi: BacktraceApiProtocol {

    func send(_ report: BacktraceReport) throws -> BacktraceResult {
        return try send(report, finalize: { _ in })
    }

    /// Runs one delegate-aware, rate-limited transport attempt.
    /// `finalize` is invoked exactly once after the outcome is classified and before:
    /// `serverDidRespond`, `connectionDidFail`, or `didReachLimit` is delivered.
    internal func send(_ originalReport: BacktraceReport,
                       finalize: (BacktraceSubmissionOutcome) -> Void) throws -> BacktraceResult {
        var report = originalReport

        func finishFailure(_ error: Error) throws -> Never {
            finalize(.failure(error, report: report))
            // Shutdown cancellation is an SDK lifecycle event, not a customer connection
            // failure. The public completion still receives an unknown/cancelled result.
            if !(isShutdown && error.isBacktraceCancellation) {
                BacktraceLogger.error("Submission for report \(report.identifier) failed")
                delegate?.connectionDidFail?(error)
            }
            throw error
        }

        guard !isShutdown else {
            try finishFailure(NetworkError.cancelled)
        }

        // check if can send
        guard backtraceRateLimiter.acquire() else {
            BacktraceLogger.debug("Submission rate limit reached for report \(report.identifier)")
            let result = BacktraceResult(.limitReached,
                                         report: report,
                                         submissionDisposition: .rateLimited)
            finalize(.result(result))
            delegate?.didReachLimit?(result)
            return result
        }

        // modify report before sending
        BacktraceLogger.debug("Preparing report \(report.identifier) for submission")
        guard !isShutdown else {
            try finishFailure(NetworkError.cancelled)
        }
        report = delegate?.willSend?(report) ?? report
        guard !isShutdown else {
            try finishFailure(NetworkError.cancelled)
        }
        do {
            // create request
            var urlRequest = try MultipartRequest(configuration: credentials.configuration,
                                                  report: report).request

            // modify request before sending
            urlRequest = delegate?.willSendRequest?(urlRequest) ?? urlRequest
            guard !isShutdown else {
                throw NetworkError.cancelled
            }
            BacktraceLogger.debug("Submitting report \(report.identifier)")

            // send request
            guard !isShutdown else {
                throw NetworkError.cancelled
            }
            let httpResponse = try networkClient.send(request: urlRequest)

            // A received HTTP response remains authoritative during shutdown.
            // Finalize the durable state before customer delegate code can call Disable reentrantly.
            BacktraceLogger.debug("Received HTTP \(httpResponse.statusCode) for report \(report.identifier)")
            let result = httpResponse.result(report: report)
            finalize(.result(result))
            delegate?.serverDidRespond?(result)
            return result
        } catch {
            try finishFailure(error)
        }
    }
}

extension BacktraceApi: BacktraceMetricsApiProtocol {

    func sendMetrics<T: Payload>(_ payload: T, url: URL) {
        guard !isShutdown else { return }
        let payload = payload

        do {
            // create request
            let urlRequest = try MetricsRequest(url: url, payload: payload).request

            // send request
            guard !isShutdown else { return }
            networkClient.sendMetrics(request: urlRequest)
        } catch {
            BacktraceLogger.error("Unable to create metrics request")
        }

    }
}
