import Foundation

struct MultipartRequest {

    let request: URLRequest

    private enum Constants {
        static let submissionPath = "/post"
        static let queryItems = { token in ["format": "plcrash", "token": token] }
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
            BacktraceLogger.error("Malformed URL: \(endpoint)")
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
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(attribute.key)\"\r\n\r\n")
            body.appendString("\(attribute.value)\r\n")
        }
        // report file
        body.appendString(boundaryPrefix)
        body.appendString("Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n")
        body.appendString("Content-Type: application/octet-stream\r\n\r\n")
        body.append(report.reportData)
        body.appendString("\r\n")
        // attachments
        for attachment in report.attachmentPaths.compactMap(Attachment.init(filePath:)) {
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(attachment.name)\"; filename=\"\(attachment.name)\"\r\n")
            body.appendString("Content-Type: \(attachment.mimeType)\r\n\r\n")
            body.append(attachment.data)
            body.appendString("\r\n")
        }
        body.appendString("\(boundaryPrefix)--")
        multipartRequest.httpBody = body as Data

        multipartRequest.setValue("\(body.length)", forHTTPHeaderField: "Content-Length")

        return multipartRequest
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
