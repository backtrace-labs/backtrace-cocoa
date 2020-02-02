import Foundation

/// Type-alias of `BacktraceClient` type. Custom Backtrace client have to implement all of these protocols.
public typealias BacktraceClientProtocol = BacktraceReporting & BacktraceClientCustomizing & BacktraceLogging

/// Type-alias of passing attributes to library.
public typealias Attributes = [String: Any]

/// Protocol describes report customizing functionality of `BacktraceClient`.
@objc public protocol BacktraceClientCustomizing {
    
    /// Additional attributes which are automatically added to each report.
    @objc var attributes: Attributes { get set }
    
    /// The object that acts as the delegate of the `BacktraceClient`.
    @objc var delegate: BacktraceClientDelegate? { get set }
}

/// Protocol describes sending functionality of `BacktraceClient`.
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
    ///   - message: Custom message which will be sent alongside report
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

/// Protocol describes logging functionality of `BacktraceClient`.
@objc public protocol BacktraceLogging {
    
    /// Set of logging destinations.
    @objc var destinations: Set<BacktraceBaseDestination> { get set }
}
