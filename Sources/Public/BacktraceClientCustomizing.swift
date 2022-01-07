import Foundation

/// Type-alias of `BacktraceClient` type. Custom Backtrace client have to implement all of these protocols.
public typealias BacktraceClientProtocol = BacktraceReporting & BacktraceClientCustomizing &
    BacktraceLogging & BacktraceMetricsProtocol

/// Type-alias of passing attributes to library.
public typealias Attributes = [String: Any]

/// Type-alias of attributes which is decodable using standard Swift `Decodable` protocol
public typealias DecodableAttributes = [String: String]

/// Type-alias of passing file attachments to library.
public typealias Attachments = [URL]

/// Type-alias of storing file attachments on disk (as a bookmark)
/// Expected format: Filename, File URL bookmark
public typealias Bookmarks = [String: Data]

/// Provides customization functionality to `BacktraceClient`.
@objc public protocol BacktraceClientCustomizing {

    /// Additional attributes which are automatically added to each report.
    @objc var attributes: Attributes { get set }

    /// Additional file attachments which are automatically added to each report.
    @objc var attachments: Attachments { get set }

    /// The object that acts as the delegate object of the `BacktraceClient` instance.
    @objc var delegate: BacktraceClientDelegate? { get set }
}

/// Provides connectivity functionality to `BacktraceClient`.
@objc public protocol BacktraceReporting {

    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - error: An error to send.
    ///   - attachmentPaths: Array of paths to files that should be send alongside with the error report.
    ///   - completion: Backtrace services response.
    @objc func send(error: Error,
                    attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))

    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - message: Custom message which will be sent alongside the report.
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report.
    ///   - completion: Backtrace services response.
    @objc func send(message: String,
                    attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))

    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report.
    ///   - completion: Backtrace services response.
    @objc func send(attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))

    /// Automatically generates and sends a crash report to Backtrace services.
    /// The services response is returned in a completion block.
    ///
    /// - Parameters:
    ///   - exception: An exception to send.
    ///   - attachmentPaths: Array of paths to files that should be send alongside with crash report.
    ///   - completion: Backtrace services response.
    @objc func send(exception: NSException?,
                    attachmentPaths: [String],
                    completion: @escaping ((_ result: BacktraceResult) -> Void))
}

/// Provides logging functionality to `BacktraceClient`.
@objc public protocol BacktraceLogging {

    /// Set of logging destinations.
    @available(*, renamed: "destinations")
    @objc var loggingDestinations: Set<BacktraceBaseDestination> { get set }
}

/// Provides error-free metrics functionality to `BacktraceClient`
@objc public protocol BacktraceMetricsProtocol {
    @objc var metrics: BacktraceMetrics { get }
}

public let applicationName = Bundle.main.displayName

public let applicationVersion = Bundle.main.releaseVersionNumber

public let defaultMetricsBaseUrlString = "https://events.backtrace.io/api/"

enum BacktraceUrlParsingError: Error {
    case invalidInput(String)
}
