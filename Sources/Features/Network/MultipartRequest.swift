import Foundation

struct MultipartRequest {

    let request: URLRequest

    private enum Constants {
        static let submissionPath = "/post"
        static let queryItems = { token in ["format": "plcrash", "token": token] }
    }

    enum EncodingError: LocalizedError {
        case invalidHeaderParameter

        var errorDescription: String? {
            "A multipart field name or filename contains an invalid header character."
        }
    }

    init(configuration: BacktraceCredentials.Configuration, report: BacktraceReport) throws {
        let request: URLRequest
        switch configuration {
        case .submissionUrl(let url):
            request = MultipartRequest.form(submissionUrl: url)
        case .endpoint(let endpoint, let token):
            request = try MultipartRequest.formUrlRequest(endpoint: endpoint, token: token)
        }
        self.request = try MultipartRequest.writeReport(urlRequest: request, report: report)
    }
}

extension MultipartRequest {
    static func form(submissionUrl: URL) -> URLRequest {
        var urlRequest = URLRequest(url: submissionUrl)
        urlRequest.httpMethod = HttpMethod.post.rawValue
        return urlRequest
    }

    static func formUrlRequest(endpoint: URL, token: String) throws -> URLRequest {
        var urlComponents = URLComponents(string: endpoint.absoluteString + Constants.submissionPath)
        urlComponents?.queryItems = Constants.queryItems(token).map(URLQueryItem.init)

        guard let finalUrl = urlComponents?.url else {
            BacktraceLogger.error("Unable to construct the submission URL")
            throw HttpError.malformedUrl(endpoint)
        }
        var request = URLRequest(url: finalUrl)
        request.httpMethod = HttpMethod.post.rawValue
        return request
    }
}

extension MultipartRequest {

    static func writeReport(urlRequest: URLRequest, report: BacktraceReport) throws -> URLRequest {
        var multipartRequest = urlRequest
        let boundary = generateBoundaryString()
        multipartRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let boundaryPrefix = "--\(boundary)\r\n"
        let body = NSMutableData()
        // attributes
        for attribute in report.attributes {
            let name = try quotedHeaderParameter(attribute.key)
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(attribute.value)\r\n")
        }
        // report file
        body.appendString(boundaryPrefix)
        body.appendString("Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n")
        body.appendString("Content-Type: application/octet-stream\r\n\r\n")
        body.append(report.reportData)
        body.appendString("\r\n")

        // attachments
        for attachment in Set(report.attachmentPaths).compactMap(Attachment.init(filePath:)) {
            let filename = try quotedHeaderParameter(attachment.filename)
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(filename)\"; filename=\"\(filename)\"\r\n")
            body.appendString("Content-Type: \(attachment.mimeType)\r\n\r\n")
            body.append(attachment.data)
            body.appendString("\r\n")
        }
        body.appendString("--\(boundary)--\r\n")
        multipartRequest.httpBody = body as Data

        multipartRequest.setValue("\(body.length)", forHTTPHeaderField: "Content-Length")

        return multipartRequest
    }

    /// Quoted disposition parameters allow UTF-8 text and quoted pairs for the delimiter and escape character.
    /// Reject HTTP control octets instead of constructing a request with an invalid header.
    private static func quotedHeaderParameter(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw EncodingError.invalidHeaderParameter
        }
        return value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"
    }
}

private extension NSMutableData {

    func appendString(_ string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: false) else { return }
        append(data)
    }
}
