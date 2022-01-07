import Foundation

/// Backtrace server API credentials.
@objc public class BacktraceCredentials: NSObject {

    let configuration: Configuration

    enum Configuration {
        case submissionUrl(URL)
        case endpoint(URL, token: String)
    }
    /// Produces Backtrace server API credentials.
    ///
    /// - Parameters:
    ///   - endpoint: Endpoint to Backtrace services.
    ///   See more: https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    ///   - token: Access token to Backtrace service.
    ///   See more: https://help.backtrace.io/troubleshooting/what-is-a-submission-token
    @objc public init(endpoint: URL, token: String) {
        self.configuration = .endpoint(endpoint, token: token)
    }

    /// Produces Backtrace server API credentials.
    ///
    /// - Parameters:
    ///   - submissionUrl: The submission URL containing authentication credentials.
    @objc public init(submissionUrl: URL) {
        self.configuration = .submissionUrl(submissionUrl)
    }
}

extension BacktraceCredentials {

    func getUniverseName() throws -> String {

        switch configuration {
        case .submissionUrl(let url):
            return try parseUniverseName(url)
        case .endpoint(let endpoint, _):
            return try parseUniverseName(endpoint)
        }
    }

    private func parseUniverseName(_ url: URL) throws -> String {
        let backtraceSubmitPath = "submit.backtrace.io"

        guard let host = url.host else {
            throw BacktraceUrlParsingError.invalidInput(url.debugDescription)
        }

        if host.contains(backtraceSubmitPath) {
            return url.pathComponents[1]
        } else {
            guard let universeSubstring = host.split(separator: ".").first else {
                throw BacktraceUrlParsingError.invalidInput(url.debugDescription)
            }

            return String(universeSubstring)
        }
    }

    func getSubmissionToken() throws -> String {
        switch configuration {
        case .submissionUrl(let url):
            let backtraceSubmitPath = "submit.backtrace.io"

            guard let host = url.host else {
                throw BacktraceUrlParsingError.invalidInput(url.debugDescription)
            }

            if host.contains(backtraceSubmitPath) {
                return url.pathComponents[2]
            } else {
                let tokenKey = "token"
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

                guard let token = components?.queryItems?.filter({$0.name == tokenKey}).first?.value else {
                    throw BacktraceUrlParsingError.invalidInput(url.debugDescription)
                }

                return token
            }
        case .endpoint(_, let token):
            return token
        }
    }
}
