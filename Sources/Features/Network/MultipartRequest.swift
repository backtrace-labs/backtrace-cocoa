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
        
        // temporary file to stream data
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        
        do {
            let fileCreated = FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
            if !fileCreated {
                throw HttpError.fileCreationFailed(tempURL)
            }
            
            let fileHandle = try FileHandle(forWritingTo: tempURL)
            defer {
                if #available(iOS 13.0, tvOS 13.0, macOS 11.0, *) {
                    try? fileHandle.close()
                } else {
                    fileHandle.closeFile()
                }
            }
            
            // attributes
            var attributesString = ""
            for attribute in report.attributes {
                attributesString += "--\(boundary)\r\n"
                attributesString += "Content-Disposition: form-data; name=\"\(attribute.key)\"\r\n\r\n"
                attributesString += "\(attribute.value)\r\n"
            }
            try writeToFile(fileHandle, attributesString)
            
            // report
            var reportString = "--\(boundary)\r\n"
            reportString += "Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n"
            reportString += "Content-Type: application/octet-stream\r\n\r\n"
            try writeToFile(fileHandle, reportString)
            fileHandle.write(report.reportData)
            try writeToFile(fileHandle, "\r\n")
            
            // attachments
            for attachmentPath in Set(report.attachmentPaths) {
                guard let attachment = Attachment(filePath: attachmentPath) else {
                    BacktraceLogger.error("Failed to create attachment for path: \(attachmentPath)")
                    continue
                }
                
                try writeToFile(fileHandle, "--\(boundary)\r\n")
                try writeToFile(fileHandle, "Content-Disposition: form-data; name=\"\(attachment.filename)\"; filename=\"\(attachment.filename)\"\r\n")
                try writeToFile(fileHandle, "Content-Type: \(attachment.mimeType)\r\n\r\n")
                fileHandle.write(attachment.data)
                try writeToFile(fileHandle, "\r\n")
            }
            
            // Final boundary
            try writeToFile(fileHandle, "--\(boundary)--\r\n")
            
            // Set Content-Length
            let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int ?? 0
            multipartRequest.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
            
            // Attach file stream to HTTP body
            multipartRequest.httpBodyStream = InputStream(url: tempURL)
            
        } catch {
            BacktraceLogger.error("Error during multipart form creation: \(error.localizedDescription)")
            throw HttpError.multipartFormError(error)
        }
        
        return multipartRequest
    }

    private static func generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"
    }
    
    private static func writeToFile(_ fileHandle: FileHandle, _ string: String) throws {
        if let data = string.data(using: .utf8) {
            fileHandle.write(data)
        } else {
            throw HttpError.fileWriteFailed
        }
    }
}

private extension NSMutableData {

    func appendString(_ string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: false) else { return }
        append(data)
    }
}
