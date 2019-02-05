import Foundation

protocol MultipartRequestType: RequestType {}

extension MultipartRequestType {
    
    func multipartUrlRequest(data: Data) throws -> URLRequest {
        var multipartRequest = try urlRequest()
        let boundary = generateBoundaryString()
        multipartRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let boundaryPrefix = "--\(boundary)\r\n"
        let body = NSMutableData()
        body.appendString(boundaryPrefix)
        body.appendString("Content-Disposition: form-data; name=\"upload_file\"; filename=\"upload_file\"\r\n")
        body.appendString("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
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
