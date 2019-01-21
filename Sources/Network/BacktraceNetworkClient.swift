
import Foundation

class BacktraceNetworkClient {
    private let request: SendCrashRequest
    private let session: URLSession

    init(endpoint: URL, token: String, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
        self.request = SendCrashRequest(endpoint: endpoint, token: token)
    }
}

extension BacktraceNetworkClient: NetworkClientType {
    @discardableResult
    func send(_ report: Data) throws -> BacktraceResponse {
        let urlRequest = try self.request.urlRequest()
        Logger.debug("Sending crash report:\n\(urlRequest.debugDescription)")
        let response = session.sync(urlRequest, data: report)
        if let responseError = response.reponseError {
            throw HttpError.serverError(responseError)
        }
        guard let httpRespone = response.urlResponse, let responseData = response.responseData else {
            throw HttpError.unknownError
        }
        Logger.debug("Response: \n\(httpRespone.debugDescription)")
        return try BacktraceHtttpResponseDeserializer(httpResponse: httpRespone, responseData: responseData).response
    }
}
