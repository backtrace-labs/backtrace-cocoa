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
            guard let urlResponse = response.urlResponse, let responseData = response.responseData else {
                throw HttpError.unknownError
            }
            // check result
            let httpResponse = BacktraceHttpResponse(httpResponse: urlResponse, responseData: responseData)
            BacktraceLogger.debug("Received HTTP response: \(httpResponse)")
            if httpResponse.isSuccess {
                successfulSendTimestamps.append(Date().timeIntervalSince1970)
            }
            let result = httpResponse.result(report: report)
            delegate?.serverDidResponse?(result)
            return result
        } catch {
            BacktraceLogger.error("Connection for \(report) failed with error: \(error)")
            delegate?.connectionDidFail?(error)
            throw error
        }
    }
}
