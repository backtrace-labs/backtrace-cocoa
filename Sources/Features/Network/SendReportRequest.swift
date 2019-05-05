import Foundation

struct SendReportRequest {

    private let endpoint: URL
    private let token: String

    init(endpoint: URL, token: String) {
        self.endpoint = endpoint
        self.token = token
    }
}

extension SendReportRequest: MultipartRequestType {
    var baseURL: URL {
        return endpoint
    }

    var path: String {
        return "/post"
    }

    var method: HttpMethod {
        return .post
    }

    var queryItems: [String: String] {
        return ["format": "plcrash",
                "token": token]
    }
}
