import Foundation

final class BacktraceApi {
    weak var delegate: BacktraceClientDelegate?

    private(set) var backtraceRateLimiter: BacktraceRateLimiter
    let networkClient: BacktraceNetworkClient
    let credentials: BacktraceCredentials
    private let lifecycleLock = NSLock()
    private var shutdownRequested = false

    init(credentials: BacktraceCredentials,
         session: URLSession = URLSession(configuration: .ephemeral),
         reportsPerMin: Int) {
        self.networkClient = BacktraceNetworkClient(urlSession: session)
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
        guard !isShutdown else {
            throw URLError(.cancelled)
        }
        var report = report

        // check if can send
        guard backtraceRateLimiter.acquire() else {
            BacktraceLogger.debug("Submission rate limit reached for report \(report.identifier)")
            let result = BacktraceResult(.limitReached,
                                         report: report,
                                         submissionDisposition: .rateLimited)
            guard !isShutdown else {
                throw URLError(.cancelled)
            }
            delegate?.didReachLimit?(result)
            return result
        }

        // modify report before sending
        BacktraceLogger.debug("Preparing report \(report.identifier) for submission")
        guard !isShutdown else {
            throw URLError(.cancelled)
        }
        report = delegate?.willSend?(report) ?? report
        guard !isShutdown else {
            throw URLError(.cancelled)
        }
        do {
            // create request
            var urlRequest = try MultipartRequest(configuration: credentials.configuration,
                                                  report: report).request

            // modify request before sending
            urlRequest = delegate?.willSendRequest?(urlRequest) ?? urlRequest
            guard !isShutdown else {
                throw URLError(.cancelled)
            }
            BacktraceLogger.debug("Submitting report \(report.identifier)")

            // send request
            guard !isShutdown else {
                throw URLError(.cancelled)
            }
            let httpResponse = try networkClient.send(request: urlRequest)

            // get result
            guard !isShutdown else {
                throw URLError(.cancelled)
            }
            BacktraceLogger.debug("Received HTTP \(httpResponse.statusCode) for report \(report.identifier)")
            let result = httpResponse.result(report: report)
            delegate?.serverDidRespond?(result)
            return result
        } catch {
            guard !isShutdown else {
                throw URLError(.cancelled)
            }
            BacktraceLogger.error("Submission for report \(report.identifier) failed")
            delegate?.connectionDidFail?(error)
            throw error
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
