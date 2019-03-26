import Foundation

public typealias BacktraceClientProtocol = BacktraceReporting & BacktraceClientCustomizing & BacktraceLogging

public typealias Attributes = [String: Any]

/// Public BacktraceClient protocol.
@objc public protocol BacktraceClientCustomizing {
    
    /// Additional user attributes which are automatically added to each report.
    @objc var userAttributes: Attributes { get set }
    
    /// Delegates methods.
    @objc weak var delegate: BacktraceClientDelegate? { get set }
}

@objc public protocol BacktraceReporting {
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - error: Error which occurred
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report
    ///   - completion: Backtrace services response.
    @objc func send(error: Error,
                    attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - message: Custom message which will be sent alongsite report
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report
    ///   - completion: Backtrace services response.
    @objc func send(message: String,
                    attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report
    ///   - completion: Backtrace services response.
    @objc func send(attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))
    
    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - exception: instance of NSException
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report
    ///   - completion: Backtrace services response.
    @objc func send(exception: NSException?,
                    attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))
}

@objc public protocol BacktraceLogging {
    @objc var destinations: Set<BacktraceBaseDestination> { get set }
}
