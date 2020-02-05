import Foundation

final class BacktraceApi {
    private let request: MultipartRequestType
    private let session: URLSession
    var successfulSendTimestamps: [TimeInterval] = []
    var reportsPerMin: Int
    weak var delegate: BacktraceClientDelegate?
    private let cacheInterval = 60.0
    
    init(urlRequest: MultipartRequestType, session: URLSession = URLSession(configuration: .ephemeral),
         reportsPerMin: Int) {
        self.session = session
        self.request = urlRequest
        self.reportsPerMin = reportsPerMin
    }
}

extension BacktraceApi: BacktraceApiProtocol {
    func send(_ report: BacktraceReport) throws -> BacktraceResult {
        do {
            var report = report
            // check if can send
            let currentTimestamp = Date().timeIntervalSince1970
            let sentCount = successfulSendTimestamps.filter { currentTimestamp - $0 < cacheInterval }.count
            guard sentCount < reportsPerMin else {
                BacktraceLogger.debug("Limit reached for report: \(report)")
                let result = BacktraceResult(.limitReached, report: report)
                delegate?.didReachLimit?(result)
                return result
            }
            // modify before sending
            BacktraceLogger.debug("Will send report: \(report)")
            report = delegate?.willSend?(report) ?? report
            let attachments = report.attachmentPaths.compactMap(Attachment.init(filePath:))
            // create request
            var urlRequest = try request.multipartUrlRequest(data: report.reportData,
                                                             attributes: report.attributes,
                                                             attachments: attachments)
            
            urlRequest = delegate?.willSendRequest?(urlRequest) ?? urlRequest
            BacktraceLogger.debug("Will send URL request: \(urlRequest)")
            // send report
            let response = session.sync(urlRequest)
            // check network error
            if let responseError = response.responseError {
                throw HttpError.connectionError(responseError)
            }
            guard let httpResponse = response.urlResponse, let responseData = response.responseData else {
                throw HttpError.unknownError
            }
            // check result
            let json = try? JSONSerialization.jsonObject(with: responseData, options: [.fragmentsAllowed])
            BacktraceLogger.debug(
                """
                Received HTTP response:
                \(httpResponse)
                \(String(describing: json ?? String(bytes: responseData, encoding: .utf8)))
                """)
            let result =
                try BacktraceHttpResponseDeserializer(httpResponse: httpResponse, responseData: responseData).result
            switch result {
            case .error(let error):
                BacktraceLogger.debug("Server responded with error response: \(error.result(report: report))")
                delegate?.serverDidResponse?(error.result(report: report))
                return error.result(report: report)
            case .success(let response):
                BacktraceLogger.debug("Server responded with successful response: \(response.result(report: report))")
                successfulSendTimestamps.append(Date().timeIntervalSince1970)
                delegate?.serverDidResponse?(response.result(report: report))
                return response.result(report: report)
            }
        } catch {
            BacktraceLogger.error("Connection for \(report) failed with error: \(error)")
            delegate?.connectionDidFail?(error)
            throw error
        }
    }
}
