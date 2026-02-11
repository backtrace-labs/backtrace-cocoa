import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
#endif

/// Type-alias of `BacktraceClient` type. Custom Backtrace client have to implement all of these protocols.
#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
public typealias BacktraceClientProtocol = BacktraceReporting & BacktraceClientCustomizing &
    BacktraceLogging & BacktraceMetricsProtocol & BacktraceBreadcrumbProtocol
#else
public typealias BacktraceClientProtocol = BacktraceReporting & BacktraceClientCustomizing &
    BacktraceLogging & BacktraceMetricsProtocol
#endif

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

public let buildVersion = Bundle.main.buildVersionNumber

public let defaultMetricsBaseUrlString = "https://events.backtrace.io/api/"

enum BacktraceUrlParsingError: Error {
    case invalidInput(String)
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// Provides session replay functionality to `BacktraceClient`.
@objc public protocol BacktraceSessionReplayProtocol {

    /// Enable session replay with default settings.
    @objc func enableSessionReplay()

    /// Enable session replay with custom settings.
    @objc func enableSessionReplay(_ settings: BacktraceSessionReplaySettings)

    /// Hide a view from session replay screenshots.
    @objc func hideView(_ view: UIView)

    /// Unhide a previously hidden view.
    @objc func unhideView(_ view: UIView)
}

/// Provides user feedback functionality to `BacktraceClient`.
@objc public protocol BacktraceFeedbackProtocol {

    /// Show the feedback form modally from the top-most view controller.
    @objc func showFeedbackForm()

    /// Set the trigger mode for the feedback form.
    @objc func setFeedbackTrigger(_ trigger: BacktraceFeedbackTrigger)
}

/// Provides log capture functionality to `BacktraceClient`.
@objc public protocol BacktraceLogCaptureProtocol {

    /// Enable log capture with default settings.
    @objc func enableLogCapture()

    /// Enable log capture with custom settings.
    @objc func enableLogCapture(_ settings: BacktraceLogCaptureSettings)

    /// Log a message at the given level.
    @objc func log(_ message: String, level: BacktraceLogLevel)
}

/// Provides vitals monitoring functionality to `BacktraceClient`.
@objc public protocol BacktraceVitalsProtocol {

    /// Enable vitals monitoring with default settings.
    @objc func enableVitalsMonitoring()

    /// Enable vitals monitoring with custom settings.
    @objc func enableVitalsMonitoring(_ settings: BacktraceVitalsSettings)
}
#endif

#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
/// Provides Breadcrumb adding functionality to `BacktraceClient`.
@objc public protocol BacktraceBreadcrumbProtocol {
    @objc var breadcrumbs: BacktraceBreadcrumbs { get }

    /// Enable breadcrumbs with default BradcrumbsSettings
    ///
    @objc func enableBreadcrumbs()

    /// Enable breadcrumbs
    ///
    /// - Parameters:
    ///   - breadcrumbSettings: bradcrumb settings.
    @objc func enableBreadcrumbs(_ breadcrumbSettings: BacktraceBreadcrumbSettings)

    /// Adds a breadcrumb to the breadcrumb trail. The breadcrumb plus attributes should not exceed 4kB, or it will be discarded.
    ///
    /// - Parameters:
    ///   - message: The message to add.
    ///   - attributes: The attributes to attach to the the breadcrumb
    ///   - type: The Breadcrumb type to add
    ///   - level: The breadcrumb severity level to add
    @objc func addBreadcrumb(_ message: String,
                             attributes: [String: String],
                             type: BacktraceBreadcrumbType,
                             level: BacktraceBreadcrumbLevel) -> Bool

    /// Adds a breadcrumb to the breadcrumb trail. The breadcrumb plus attributes should not exceed 4kB, or it will be discarded.
    ///
    /// - Parameters:
    ///   - message: The message to add.
    @objc func addBreadcrumb(_ message: String) -> Bool

    /// Adds a breadcrumb to the breadcrumb trail. The breadcrumb plus attributes should not exceed 4kB, or it will be discarded.
    ///
    /// - Parameters:
    ///   - message: The message to add.
    ///   - attributes: The attributes to attach to the the breadcrumb
    @objc func addBreadcrumb(_ message: String,
                             attributes: [String: String]) -> Bool

    /// Adds a breadcrumb to the breadcrumb trail. The breadcrumb plus attributes should not exceed 4kB, or it will be discarded.
    ///
    /// - Parameters:
    ///   - message: The message to add.
    ///   - type: The Breadcrumb type to add
    ///   - level: The breadcrumb severity level to add
    @objc func addBreadcrumb(_ message: String,
                             type: BacktraceBreadcrumbType,
                             level: BacktraceBreadcrumbLevel) -> Bool

    /// Adds a breadcrumb to the breadcrumb trail. The breadcrumb plus attributes should not exceed 4kB, or it will be discarded.
    ///
    /// - Parameters:
    ///   - message: The message to add.
    ///   - level: The breadcrumb severity level to add
    @objc func addBreadcrumb(_ message: String,
                             level: BacktraceBreadcrumbLevel) -> Bool

    /// Adds a breadcrumb to the breadcrumb trail. The breadcrumb plus attributes should not exceed 4kB, or it will be discarded.
    ///
    /// - Parameters:
    ///   - message: The message to add.
    ///   - type: The Breadcrumb type to add
    @objc func addBreadcrumb(_ message: String,
                             type: BacktraceBreadcrumbType) -> Bool

    /// Clear breadcrumbs
    ///
    @objc func clearBreadcrumbs() -> Bool
}
#endif
