import Foundation

/// Response from the session start API call.
struct BacktraceSessionStartResponse {
    let sessionToken: String?
    let endpointAddress: URL?
    let sessionUrl: String?
}

/// Handles all HTTP communication for session features.
///
/// Builds requests following the TF wire protocol and submits them via the shared
/// `BacktraceNetworkClient`. Targets the collector URL from `BacktraceSessionSettings`.
final class BacktraceSessionApi {

    private let settings: BacktraceSessionSettings
    private let networkClient: BacktraceNetworkClient
    private var endpointAddress: URL?

    /// Base URL for API calls. Defaults to TF collector, overridden by `collectorURL` setting
    /// or by the `endpointAddress` returned from session start.
    private var baseURL: URL {
        return endpointAddress ?? settings.collectorURL ?? defaultCollectorURL
    }

    private let defaultCollectorURL = URL(string: "https://api2.testfairy.com/services/")!

    init(settings: BacktraceSessionSettings, networkClient: BacktraceNetworkClient) {
        self.settings = settings
        self.networkClient = networkClient
    }

    /// Update the endpoint address (from server response).
    func updateEndpoint(_ url: URL) {
        self.endpointAddress = url
    }

    // MARK: - Start Session

    func startSession(sessionId: String,
                      startTime: Date,
                      settings: BacktraceSessionSettings,
                      completion: @escaping (Swift.Result<BacktraceSessionStartResponse, Swift.Error>) -> Void) {
        guard let appToken = settings.appToken else {
            completion(.failure(BacktraceSessionError.missingAppToken))
            return
        }

        var url = baseURL
        url.appendQueryItem(name: "method", value: "testfairy.session.startSession")

        let request = BacktraceSessionRequest.buildStartSessionRequest(
            url: url,
            appToken: appToken,
            startTime: startTime,
            sessionId: sessionId
        )

        sendAsync(request: request) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try BacktraceSessionRequest.parseStartSessionResponse(data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Send Events

    func sendEvents(_ compressedData: Data,
                    sessionToken: String?,
                    completion: @escaping (Swift.Result<Void, Swift.Error>) -> Void) {
        guard let token = sessionToken else {
            completion(.failure(BacktraceSessionError.noSessionToken))
            return
        }

        var url = baseURL
        url.appendQueryItem(name: "method", value: "testfairy.session.addEvents")
        url.appendQueryItem(name: "sessionToken", value: token)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.httpBody = compressedData
        request.timeoutInterval = 30

        sendAsync(request: request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Send Screenshot

    func sendScreenshot(_ imageData: Data,
                        sessionToken: String?,
                        seq: Int,
                        timestamp: TimeInterval,
                        activityName: String,
                        completion: @escaping (Swift.Result<Void, Swift.Error>) -> Void) {
        guard let token = sessionToken else {
            completion(.failure(BacktraceSessionError.noSessionToken))
            return
        }

        var url = baseURL
        url.appendQueryItem(name: "method", value: "testfairy.session.addScreenshot")
        url.appendQueryItem(name: "sessionToken", value: token)
        url.appendQueryItem(name: "seq", value: String(seq))
        url.appendQueryItem(name: "timestamp", value: String(timestamp))
        url.appendQueryItem(name: "activityName", value: activityName)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData
        request.timeoutInterval = 30

        sendAsync(request: request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Send Feedback

    func sendFeedback(_ multipartData: Data,
                      boundary: String,
                      sessionToken: String?,
                      completion: @escaping (Swift.Result<Void, Swift.Error>) -> Void) {
        let method: String
        if sessionToken != nil {
            method = "testfairy.session.addUserFeedback"
        } else {
            method = "testfairy.session.addAnonymousUserFeedback"
        }

        var url = baseURL
        url.appendQueryItem(name: "method", value: method)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartData
        request.timeoutInterval = 30

        sendAsync(request: request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Set User Data

    func setUserData(sessionToken: String?, identifier: String) {
        guard let token = sessionToken else { return }

        var url = baseURL
        url.appendQueryItem(name: "method", value: "testfairy.session.setUserData")

        let boundary = "BacktraceSessionBoundary"
        var body = Data()
        body.appendMultipartField(name: "sessionToken", value: token, boundary: boundary)

        let traits: [String: String] = ["correlationId": identifier]
        if let traitsJson = try? JSONSerialization.data(withJSONObject: traits) {
            body.appendMultipartField(name: "data", value: String(data: traitsJson, encoding: .utf8) ?? "", boundary: boundary)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 30

        sendAsync(request: request) { _ in }
    }

    // MARK: - Private

    private func sendAsync(request: URLRequest,
                           completion: @escaping (Swift.Result<Data, Swift.Error>) -> Void) {
        let task = networkClient.urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success(data ?? Data()))
        }
        task.resume()
    }
}

// MARK: - Session Errors

enum BacktraceSessionError: Error, LocalizedError {
    case missingAppToken
    case noSessionToken
    case invalidResponse
    case encodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingAppToken: return "Session app token is required but not set."
        case .noSessionToken: return "No session token available. Session may not have started."
        case .invalidResponse: return "Invalid response from session server."
        case .encodingError(let detail): return "Encoding error: \(detail)"
        }
    }
}

// MARK: - URL Helper

private extension URL {
    mutating func appendQueryItem(name: String, value: String) {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        if let newURL = components.url {
            self = newURL
        }
    }
}

// MARK: - Data Multipart Helper

extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        let field = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        if let data = field.data(using: .utf8) {
            append(data)
        }
    }
}
