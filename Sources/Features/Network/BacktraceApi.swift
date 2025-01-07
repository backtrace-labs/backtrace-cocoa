import Foundation

final class BacktraceApi {
    weak var delegate: BacktraceClientDelegate?

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

    func send(_ report: BacktraceReport) async throws -> BacktraceResult {
        var report = report

        // check if can send
        guard backtraceRateLimiter.canSend else {
            await BacktraceLogger.debug("Limit reached for report: \(report)")
            let result = BacktraceResult(.limitReached, report: report)
            delegate?.didReachLimit?(result)
            return result
        }

        backtraceRateLimiter.addRecord()

        // modify report before sending
        await BacktraceLogger.debug("Will send report: \(report)")
        report = delegate?.willSend?(report) ?? report
        do {
            // create request
            var urlRequest = try await MultipartRequest(configuration: credentials.configuration,
                                                  report: report).request

            // modify request before sending
            urlRequest = delegate?.willSendRequest?(urlRequest) ?? urlRequest
            await BacktraceLogger.debug("Will send URL request: \(urlRequest)")

            // send request
            let httpResponse = try await networkClient.send(request: urlRequest)

            // get result
            await BacktraceLogger.debug("Received HTTP response: \(httpResponse)")
            let result = httpResponse.result(report: report)
            delegate?.serverDidRespond?(result)
            return result
        } catch {
            await BacktraceLogger.error("Connection for \(report) failed with error: \(error)")
            delegate?.connectionDidFail?(error)
            throw error
        }
    }
}

extension BacktraceApi: BacktraceMetricsApiProtocol {

    func sendMetrics<T: Payload>(_ payload: T, url: URL) async {
        let payload = payload

        do {
            // create request
            let urlRequest = try await MetricsRequest(url: url, payload: payload).request

            // send request
            await networkClient.sendMetricsAsync(request: urlRequest)
        } catch {
            await BacktraceLogger.error("Connection for \(payload) failed with error: \(error)")
        }

    }
}
