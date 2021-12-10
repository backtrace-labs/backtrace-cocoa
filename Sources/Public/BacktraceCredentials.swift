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

    enum BacktraceUrlParsingError: Error {
        case InvalidInput(String)
    }
    
    // Using algorithm from backtrace-unity:
    // https://github.com/backtrace-labs/backtrace-unity/blob/553aab2b39c318ff96ebed4bc739bf2c87304649/Runtime/Model/BacktraceConfiguration.cs#L290
    func getUniverseName() throws -> String {
        
        switch configuration {
        case .submissionUrl(let url):
            return try parseUniverseName(url.absoluteString)
        case .endpoint(let endpoint, let token):
            return try parseUniverseName(endpoint.absoluteString)
        }
    }
    
    private func parseUniverseName(_ urlString: String) throws -> String {
        let backtraceSubmitUrl = "https://submit.backtrace.io/"
        
        if urlString.starts(with: backtraceSubmitUrl)
        {
            let universeIndexStart =
                urlString.index(urlString.startIndex, offsetBy: backtraceSubmitUrl.count)
            let substring = urlString[universeIndexStart...urlString.index(before: urlString.endIndex)]
            
            guard var universeIndexEnd = substring.firstIndex(of: "/") else {
                throw BacktraceUrlParsingError.InvalidInput(urlString)
            }
            universeIndexEnd = substring.index(before: universeIndexEnd)

            return String(urlString[universeIndexStart...universeIndexEnd])
        }
        else
        {
            let backtraceDomain = "backtrace.io"
            if !urlString.contains(backtraceDomain) {
                throw BacktraceUrlParsingError.InvalidInput(urlString)
            }

            let url = URL(string: urlString)
            guard let host = url?.host else {
                throw BacktraceUrlParsingError.InvalidInput(urlString)
            }
            
            guard var universeIndexEnd = host.firstIndex(of:".") else {
                throw BacktraceUrlParsingError.InvalidInput(urlString)
            }
            universeIndexEnd = host.index(before: universeIndexEnd)
            
            return String(host[host.startIndex...universeIndexEnd])
        }
    }
    
    // Using algorithm from backtrace-unity
    // https://github.com/backtrace-labs/backtrace-unity/blob/553aab2b39c318ff96ebed4bc739bf2c87304649/Runtime/Model/BacktraceConfiguration.cs#L320
    func getSubmissionToken() throws -> String {
        switch configuration {
        case .submissionUrl(let url):
            let tokenLength = 64;
            let tokenQueryParam = "token=";
            let urlString = url.absoluteString
            
            if urlString.contains("submit.backtrace.io") {
                guard var tokenEndIndex = urlString.lastIndex(of: "/") else {
                    throw BacktraceUrlParsingError.InvalidInput(urlString)
                }
                tokenEndIndex = urlString.index(before: tokenEndIndex)
                
                let tokenStartIndex = urlString.index(after: urlString.index(tokenEndIndex, offsetBy: -(tokenLength - 1)))
                
                return String(urlString[tokenStartIndex...tokenEndIndex])
            } else {
                guard let tokenQueryParamRange = urlString.range(of: tokenQueryParam) else {
                    throw BacktraceUrlParsingError.InvalidInput(urlString)
                }
                
                let tokenStartIndex = tokenQueryParamRange.upperBound
                print(urlString[tokenStartIndex...urlString.index(before: urlString.endIndex)])
                let tokenEndIndex = urlString.index(before: urlString.index(tokenStartIndex, offsetBy: tokenLength - 1))

                return String(urlString[tokenStartIndex...tokenEndIndex])
            }            
        case .endpoint(let endpoint, let token):
            return token
        }
    }
}
