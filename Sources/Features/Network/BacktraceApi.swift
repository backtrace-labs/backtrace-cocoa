import Foundation

class BacktraceApi {
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
        // check if can send
        let currentTimestamp = Date().timeIntervalSince1970
        let sentCount = successfulSendTimestamps.filter { currentTimestamp - $0 < cacheInterval }.count
        guard sentCount < reportsPerMin else {
            return BacktraceResult(.limitReached, report: report)
        }
        // modify before sending
        let modifiedBeforeSendingReport = delegate?.willSend?(report) ?? report
        let attachments = modifiedBeforeSendingReport.attachmentPaths.compactMap(Attachment.init(filePath:))
        // create request
        let urlRequest = try request.multipartUrlRequest(data: modifiedBeforeSendingReport.reportData,
                                                         attributes: modifiedBeforeSendingReport.attributes,
                                                         attachments: attachments)
        BacktraceLogger.debug("Sending crash report:\n\(urlRequest)")
        // send report
        let response = session.sync(urlRequest)
        // check network error
        if let responseError = response.responseError {
            delegate?.connectionDidFail?(responseError)
            throw HttpError.connectionError(responseError)
        }
        guard let httpResponse = response.urlResponse, let responseData = response.responseData else {
            throw HttpError.unknownError
        }
        // check result
        BacktraceLogger.debug("HTTP response: \n\(httpResponse)\n\(String(describing: String(bytes: responseData, encoding: .utf8)))")
        let result = try BacktraceHttpResponseDeserializer(httpResponse: httpResponse, responseData: responseData)
            .result
        switch result {
        case .error(let error):
            delegate?.serverDidResponse?(error.result(report: modifiedBeforeSendingReport))
            return error.result(report: modifiedBeforeSendingReport)
        case .success(let response):
            // did send successfully
            successfulSendTimestamps.append(Date().timeIntervalSince1970)
            delegate?.serverDidResponse?(response.result(report: modifiedBeforeSendingReport))
            return response.result(report: modifiedBeforeSendingReport)
        }
    }
}
