#if os(iOS)
import Foundation
import UIKit

/// Packages and submits feedback to the session API.
final class BacktraceFeedbackSubmission {

    private weak var sessionApi: BacktraceSessionApi?
    private let sessionToken: String?
    private let sessionId: String
    private let storage: BacktraceSessionStorage?

    init(sessionApi: BacktraceSessionApi?,
         sessionToken: String?,
         sessionId: String,
         storage: BacktraceSessionStorage?) {
        self.sessionApi = sessionApi
        self.sessionToken = sessionToken
        self.sessionId = sessionId
        self.storage = storage
    }

    /// Submit feedback with optional screenshot and custom fields.
    func submit(text: String,
                screenshot: UIImage?,
                email: String?,
                customFields: [String: String]?,
                completion: @escaping (Swift.Result<Void, Swift.Error>) -> Void) {

        let screenshotData = screenshot?.jpegData(compressionQuality: 1.0)

        let result = BacktraceSessionRequest.buildFeedbackRequest(
            sessionToken: sessionToken,
            appToken: nil, // TODO: pass through for anonymous feedback
            text: text,
            email: email,
            screenshot: screenshotData,
            customFields: customFields,
            sessionAttributes: nil
        )

        sessionApi?.sendFeedback(
            result.data,
            boundary: result.boundary,
            sessionToken: sessionToken
        ) { [weak self] sendResult in
            switch sendResult {
            case .success:
                completion(.success(()))
            case .failure(let error):
                // Persist for offline retry
                try? self?.storage?.save(type: .feedback, data: result.data)
                completion(.failure(error))
            }
        }
    }
}
#endif
