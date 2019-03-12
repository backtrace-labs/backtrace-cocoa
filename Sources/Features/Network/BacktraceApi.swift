import Foundation

class BacktraceApi {
    private let request: SendReportRequest
    private let session: URLSession
    var successfulSendTimestamps: [TimeInterval] = []
    var reportsPerMin: Int
    weak var delegate: BacktraceClientDelegate?
    
    init(endpoint: URL, token: String, session: URLSession = URLSession(configuration: .ephemeral),
         reportsPerMin: Int) {
        self.session = session
        self.request = SendReportRequest(endpoint: endpoint, token: token)
        self.reportsPerMin = reportsPerMin
    }
}

extension BacktraceApi: BacktraceApiProtocol {
    func send(_ report: BacktraceReport) throws -> BacktraceResult {
        // check if can send
        let currentTimestamp = Date().timeIntervalSince1970
        let numberOfSendsInLastOneMinute = successfulSendTimestamps.filter { currentTimestamp - $0 < 60.0 }.count
        guard numberOfSendsInLastOneMinute < reportsPerMin else {
            return BacktraceResult.limitReached(report)
        }
        // modify before sending
        let modifiedBeforeSendingReport = self.delegate?.willSend?(report) ?? report
        let attachments = modifiedBeforeSendingReport.attachmentPaths.compactMap { Attachment(filePath: $0) }
        // create request
        let urlRequest = try self.request.multipartUrlRequest(data: modifiedBeforeSendingReport.reportData,
                                                              attributes: modifiedBeforeSendingReport.attributes,
                                                              attachments: attachments)
        BacktraceLogger.debug("Sending crash report:\n\(urlRequest.debugDescription)")
        // send report
        let response = session.sync(urlRequest)
        // check network error
        if let responseError = response.reponseError {
            self.delegate?.connectionDidFail?(responseError)
            throw HttpError.connectionError(responseError)
        }
        guard let httpResponse = response.urlResponse, let responseData = response.responseData else {
            throw HttpError.unknownError
        }
        BacktraceLogger.debug("Sent crash: \(modifiedBeforeSendingReport.plCrashReport.info)")
        BacktraceLogger.debug("Response: \n\(httpResponse.debugDescription)")
        // check result
        let result = try BacktraceHttpResponseDeserializer(httpResponse: httpResponse, responseData: responseData)
            .result
        switch result {
        case .error(let error):
            self.delegate?.serverDidResponse?(error.result(backtraceReport: modifiedBeforeSendingReport))
            return error.result(backtraceReport: modifiedBeforeSendingReport)
        case .success(let response):
            // did send successfully
            self.successfulSendTimestamps.append(Date().timeIntervalSince1970)
            self.delegate?.serverDidResponse?(response.result(backtraceReport: modifiedBeforeSendingReport))
            return response.result(backtraceReport: modifiedBeforeSendingReport)
        }
    }
}
