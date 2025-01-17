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

        // output stream
        // TODO: bind input & output streams
        let outputStream = OutputStream.toMemory()
        outputStream.open()
        defer { outputStream.close() }

        let writeLock = DispatchQueue(label: "backtrace.multipartRequest.writeLock")

        do {
            // attributes
            var attributesString = ""
            for attribute in report.attributes {
                attributesString += "--\(boundary)\r\n"
                attributesString += "Content-Disposition: form-data; name=\"\(attribute.key)\"\r\n\r\n"
                attributesString += "\(attribute.value)\r\n"
            }
            try writeToStream(outputStream, attributesString, writeLock: writeLock)

            // report
            var reportString = "--\(boundary)\r\n"
            reportString += "Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n"
            reportString += "Content-Type: application/octet-stream\r\n\r\n"
            try writeToStream(outputStream, reportString, writeLock: writeLock)
            try writeLock.sync {
                let data = report.reportData
                let bytesWritten = data.withUnsafeBytes {
                    guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                        return -1
                    }
                    return outputStream.write(baseAddress, maxLength: data.count)
                }
                if bytesWritten < 0 {
                    throw HttpError.streamWriteFailed
                }
            }
            try writeToStream(outputStream, "\r\n", writeLock: writeLock)

            // attachments
            for attachmentPath in Set(report.attachmentPaths) {
                guard let attachment = Attachment(filePath: attachmentPath) else {
                    BacktraceLogger.error("Failed to create attachment for path: \(attachmentPath)")
                    continue
                }

                try writeToStream(outputStream, "--\(boundary)\r\n", writeLock: writeLock)
                try writeToStream(outputStream, "Content-Disposition: form-data; name=\"\(attachment.filename)\"; filename=\"\(attachment.filename)\"\r\n", writeLock: writeLock)
                try writeToStream(outputStream, "Content-Type: \(attachment.mimeType)\r\n\r\n", writeLock: writeLock)
                try writeLock.sync {
                    let data = attachment.data
                    let bytesWritten = data.withUnsafeBytes {
                        guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                            return -1
                        }
                        return outputStream.write(baseAddress, maxLength: data.count)
                    }
                    if bytesWritten < 0 {
                        throw HttpError.streamWriteFailed
                    }
                }
                try writeToStream(outputStream, "\r\n", writeLock: writeLock)
            }

            // Final boundary
            try writeToStream(outputStream, "--\(boundary)--\r\n", writeLock: writeLock)
            
            // Data from Output Stream
            guard let data = outputStream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
                throw HttpError.streamReadFailed
            }
            // Set Content-Length
            multipartRequest.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
            // Attach file stream to HTTP body
            multipartRequest.httpBodyStream = InputStream(data: data)
        } catch {
            BacktraceLogger.error("Error during multipart form creation: \(error.localizedDescription)")
            throw HttpError.multipartFormError(error)
        }

        return multipartRequest
    }

    private static func generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"
    }

    private static func writeToStream(_ stream: OutputStream, _ string: String, writeLock: DispatchQueue) throws {
        guard let data = string.data(using: .utf8) else {
            BacktraceLogger.error("Failed to convert string to UTF-8 data: \(string)")
            throw HttpError.fileWriteFailed
        }
        try writeLock.sync {
            let bytesWritten = data.withUnsafeBytes {
                guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }
                return stream.write(baseAddress, maxLength: data.count)
            }
            if bytesWritten < 0 {
                throw HttpError.streamWriteFailed
            }
        }
    }
}

private extension NSMutableData {

    func appendString(_ string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: false) else {
            BacktraceLogger.error("Failed to append string as UTF-8 data: \(string)")
            return
        }
        append(data)
    }
}
