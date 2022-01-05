import Foundation

final class BacktraceApi {
    weak var delegate: BacktraceClientDelegate?

    weak var summedEventsDelegate: BacktraceMetricsDelegate?
    weak var uniqueEventsDelegate: BacktraceMetricsDelegate?

    private(set) var backtraceRateLimiter: BacktraceRateLimiter
    let networkClient: BacktraceNetworkClient
    let credentials: BacktraceCredentials

    init(credentials: BacktraceCredentials,
         session: URLSession = URLSession(configuration: .ephemeral),
         reportsPerMin: Int) {
        self.networkClient = BacktraceNetworkClient(urlSession: session)
        self.backtraceRateLimiter = BacktraceRateLimiter(timestamps: [], reportsPerMin: reportsPerMin)
        self.credentials = credentials
    }
}

extension BacktraceApi: BacktraceApiProtocol {

    func send(_ report: BacktraceReport) throws -> BacktraceResult {
        var report = report

        // check if can send
        guard backtraceRateLimiter.canSend else {
            BacktraceLogger.debug("Limit reached for report: \(report)")
            let result = BacktraceResult(.limitReached, report: report)
            delegate?.didReachLimit?(result)
            return result
        }

        backtraceRateLimiter.addRecord()

        // modify report before sending
        BacktraceLogger.debug("Will send report: \(report)")
        report = delegate?.willSend?(report) ?? report
        do {
            // create request
            var urlRequest = try MultipartRequest(configuration: credentials.configuration,
                                                  report: report).request

            // modify request before sending
            urlRequest = delegate?.willSendRequest?(urlRequest) ?? urlRequest
            BacktraceLogger.debug("Will send URL request: \(urlRequest)")

            // send request
            let httpResponse = try networkClient.send(request: urlRequest)

            // get result
            BacktraceLogger.debug("Received HTTP response: \(httpResponse)")
            let result = httpResponse.result(report: report)
            delegate?.serverDidRespond?(result)
            return result
        } catch {
            BacktraceLogger.error("Connection for \(report) failed with error: \(error)")
            delegate?.connectionDidFail?(error)
            throw error
        }
    }
}

extension BacktraceApi: BacktraceMetricsApiProtocol {

    func sendMetrics(_ payload: SummedEventsPayload, url: URL) throws -> BacktraceMetricsResult {
        try sendMetrics(payload, url: url, metricsDelegate: summedEventsDelegate)
    }

    func sendMetrics(_ payload: UniqueEventsPayload, url: URL) throws -> BacktraceMetricsResult {
        try sendMetrics(payload, url: url, metricsDelegate: uniqueEventsDelegate)
    }

    func sendMetrics<T: Payload>(_ payload: T, url: URL, metricsDelegate: BacktraceMetricsDelegate?)
        throws -> BacktraceMetricsResult {
        let payload = payload

        do {
            // create request
            var urlRequest = try MetricsRequest(url: url, payload: payload).request

            // modify request before sending
            urlRequest = metricsDelegate?.willSendRequest?(urlRequest) ?? urlRequest
            BacktraceLogger.debug("Will send URL request to metrics API: \(urlRequest)")

            // send request
            let httpResponse = try networkClient.sendMetrics(request: urlRequest)

            // get result
            BacktraceLogger.debug("Received HTTP response from metrics API: \(httpResponse)")
            let result = httpResponse.result()
            metricsDelegate?.serverDidRespond?(result)

            return result
        } catch {
            BacktraceLogger.error("Connection for \(payload) failed with error: \(error)")
            metricsDelegate?.connectionDidFail?(error)
            throw error
        }
    }
}
