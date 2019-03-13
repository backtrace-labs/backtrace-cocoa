import Foundation

protocol MultipartRequestType: RequestType {}

extension MultipartRequestType {
    
    func multipartUrlRequest(data: Data, attributes: Attributes, attachments: [Attachment]) throws -> URLRequest {
        var multipartRequest = try urlRequest()
        let boundary = generateBoundaryString()
        multipartRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let boundaryPrefix = "--\(boundary)\r\n"
        let body = NSMutableData()
        // attributes
        for attribute in attributes {
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(attribute.key)\"\r\n\r\n")
            body.appendString("\(attribute.value)\r\n")
        }
        // report file
        body.appendString(boundaryPrefix)
        body.appendString("Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n")
        body.appendString("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
        // attachments
        for attachment in attachments {
            body.appendString(boundaryPrefix)
            // swiftlint:disable line_length
            body.appendString("Content-Disposition: form-data; name=\"\(attachment.name)\"; filename=\"\(attachment.name)\"\r\n")
            // swiftlint:enable line_length
            body.appendString("Content-Type: \(attachment.mimeType)\r\n\r\n")
            body.append(attachment.data)
            body.appendString("\r\n")
        }
        body.appendString("\(boundaryPrefix)--")
        multipartRequest.httpBody = body as Data
        
        multipartRequest.setValue("\(body.length)", forHTTPHeaderField: "Content-Length")
        
        return multipartRequest
    }
    
    private func generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"
    }
}

private extension NSMutableData {
    
    func appendString(_ string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: false) else { return }
        append(data)
    }
}
