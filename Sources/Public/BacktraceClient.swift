import Foundation
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
#endif

/// Provides the default implementation of `BacktraceClientProtocol` protocol.
@objc open class BacktraceClient: NSObject {

    /// Shared instance of BacktraceClient class. Should be created before sending any reports.
    @objc public static var shared: BacktraceClientProtocol?

    /// `BacktraceClient`'s configuration. Allows to configure `BacktraceClient` in a custom way.
    @objc public let configuration: BacktraceClientConfiguration

    /// Error-free metrics class instance
    @objc private let metricsInstance: BacktraceMetrics

#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
    /// Breadcrumbs class instance
    @objc private let breadcrumbsInstance: BacktraceBreadcrumbs = BacktraceBreadcrumbs()
#endif

#if os(iOS) && !targetEnvironment(macCatalyst)
    /// Session replay screenshot capture engine.
    private var screenshotCapture: BacktraceScreenshotCapture?

    /// Shake / screenshot detector for feedback form.
    private let shakeDetector = BacktraceShakeDetector()

    /// Periodic device vitals sampler.
    private var vitalsMonitor: BacktraceVitalsMonitor?

    /// Application log capture.
    private var logCapture: BacktraceLogCapture?
#endif

    private let reporter: BacktraceReporter
    private let dispatcher: Dispatching
    private let reportingPolicy: ReportingPolicy

    /// Initialize `BacktraceClient` with credentials. To learn more about credentials, see
    /// https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    /// and https://help.backtrace.io/troubleshooting/what-is-a-submission-token .
    ///
    /// - Parameter credentials: Credentials to register in Backtrace services.
    /// - Parameter crashReporter: Instance of the crash reporter to inject.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(credentials: BacktraceCredentials,
                                  crashReporter: BacktraceCrashReporter = BacktraceCrashReporter()) throws {
        try self.init(configuration: BacktraceClientConfiguration(credentials: credentials), crashReporter: crashReporter)
    }

    /// Initialize `BacktraceClient` with credentials. To learn more about credentials, see
    /// https://help.backtrace.io/troubleshooting/what-is-a-submission-url
    /// and https://help.backtrace.io/troubleshooting/what-is-a-submission-token .
    ///
    /// - Parameter credentials: Credentials to register in Backtrace services.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(credentials: BacktraceCredentials) throws {
        try self.init(configuration: BacktraceClientConfiguration(credentials: credentials),
                      crashReporter: BacktraceCrashReporter())
    }

    /// Initialize `BacktraceClient` with `BacktraceClientConfiguration` instance. Allows to configure `BacktraceClient`
    /// in a custom way.
    ///
    /// - Parameter configuration: `BacktraceClient`s configuration.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(configuration: BacktraceClientConfiguration) throws {
        let api = BacktraceApi(credentials: configuration.credentials,
                               reportsPerMin: configuration.reportsPerMin)
        let reporter = try BacktraceReporter(reporter: BacktraceCrashReporter(), api: api, dbSettings: configuration.dbSettings,
                                             credentials: configuration.credentials, oomMode: configuration.oomMode)
        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api)
    }

    /// Initialize `BacktraceClient` with `BacktraceClientConfiguration` instance. Allows to configure `BacktraceClient`
    /// in a custom way.
    ///
    /// - Parameter configuration: `BacktraceClient`s configuration.
    /// - Parameter crashReporter: Instance of the crash reporter to inject.
    /// - Throws: throws an error in case of failure.
    @objc public convenience init(configuration: BacktraceClientConfiguration, crashReporter: BacktraceCrashReporter) throws {
        let api = BacktraceApi(credentials: configuration.credentials,
                               reportsPerMin: configuration.reportsPerMin)
        let reporter = try BacktraceReporter(reporter: crashReporter, api: api, dbSettings: configuration.dbSettings,
                                             credentials: configuration.credentials, oomMode: configuration.oomMode)

        try self.init(configuration: configuration, debugger: DebuggerChecker.self, reporter: reporter,
                      dispatcher: Dispatcher(), api: api)
    }

    init(configuration: BacktraceClientConfiguration, debugger: DebuggerChecking.Type = DebuggerChecker.self,
         reporter: BacktraceReporter, dispatcher: Dispatching = Dispatcher(),
         api: BacktraceApi) throws {

        self.dispatcher = dispatcher
        self.reporter = reporter
        self.configuration = configuration
        self.reportingPolicy = ReportingPolicy(configuration: configuration, debuggerChecker: debugger)
        self.metricsInstance = BacktraceMetrics(api: api)

        super.init()
        try startCrashReporter()
    }
}

// MARK: - BacktraceClientProviding
extension BacktraceClient: BacktraceClientCustomizing {

    /// The object that acts as the delegate object of the `BacktraceClient`.
    @objc public var delegate: BacktraceClientDelegate? {
        get {
            return reporter.delegate
        } set {
            reporter.delegate = newValue
        }
    }

    /// Additional attributes which are automatically added to each report.
    @objc public var attributes: Attributes {
        get {
            return reporter.attributes
        } set {
            reporter.attributes = newValue
        }
    }

    /// Additional file attachments which are automatically added to each report.
    @objc public var attachments: Attachments {
        get {
            return reporter.attachments
        } set {
            reporter.attachments = newValue
        }
    }
}

// MARK: - BacktraceReporting
extension BacktraceClient: BacktraceReporting {

    @objc public func send(error: Error,
                           attachmentPaths: [String] = [],
                           completion: @escaping ((BacktraceResult) -> Void)) {
        reportCrash(faultMessage: error.localizedDescription, attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(message: String,
                           attachmentPaths: [String] = [],
                           completion: @escaping ((BacktraceResult) -> Void)) {
        reportCrash(faultMessage: message, attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(exception: NSException?,
                           attachmentPaths: [String] = [],
                           completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        reportCrash(faultMessage: exception?.name.rawValue ?? "Unknown exception", exception: exception,
                    attachmentPaths: attachmentPaths, completion: completion)
    }

    @objc public func send(attachmentPaths: [String] = [],
                           completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        reportCrash(attachmentPaths: attachmentPaths, completion: completion)
    }

    private func reportCrash(faultMessage: String? = nil, exception: NSException? = nil, attachmentPaths: [String] = [],
                             completion: @escaping ((_ result: BacktraceResult) -> Void)) {
        guard reportingPolicy.allowsReporting else {
            completion(BacktraceResult(.debuggerAttached))
            return
        }

        guard let resource = try? reporter.generate(exception: exception,
                                                    attachmentPaths: attachmentPaths,
                                                    faultMessage: faultMessage) else {
            completion(BacktraceResult(.unknownError))
            return
        }

        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            completion(self.reporter.send(resource: resource))
        }, completion: {
            BacktraceLogger.debug("Finished sending an error report.")
        })
    }

    func startCrashReporter() throws {
        guard reportingPolicy.allowsReporting else {
            return
        }

        try reporter.enableCrashReporter()
        
        dispatcher.dispatch({ [weak self] in
            guard let self = self else { return }
            do {
                try self.reporter.handlePendingCrashes()
            } catch {
                BacktraceLogger.error(error)
            }
            }, completion: {
                BacktraceLogger.debug("Started error reporter.")
        })

        if self.configuration.oomMode != .none {
            dispatcher.dispatch({ [weak self] in
                guard let self = self else { return }
                self.reporter.enableOomWatcher()
                }, completion: {
                    BacktraceLogger.debug("Started OOM Watcher.")
            })
        }
    }
}

// MARK: - BacktraceLogging
extension BacktraceClient: BacktraceLogging {

    /// A collection of logging destinations.
    public var loggingDestinations: Set<BacktraceBaseDestination> {
        get {
            return BacktraceLogger.destinations
        }
        set {
            BacktraceLogger.destinations = newValue
        }
    }
}

// MARK: - BacktraceMetricsProtocol
extension BacktraceClient: BacktraceMetricsProtocol {
    /// Error-free metrics class instance
    @objc public var metrics: BacktraceMetrics {
        return self.metricsInstance
    }
}

// MARK: - BacktraceBreadcrumbProtocol
#if os(iOS) || os(OSX) || targetEnvironment(macCatalyst)
extension BacktraceClient: BacktraceBreadcrumbProtocol {
    @objc public var breadcrumbs: BacktraceBreadcrumbs {
        return self.breadcrumbsInstance
    }

    @objc public func enableBreadcrumbs() {
        breadcrumbsInstance.enableBreadcrumbs()
    }

    @objc public func enableBreadcrumbs(_ breadcrumbSettings: BacktraceBreadcrumbSettings) {
        breadcrumbsInstance.enableBreadcrumbs(breadcrumbSettings)
    }

    @objc public func addBreadcrumb(_ message: String,
                                    attributes: [String: String],
                                    type: BacktraceBreadcrumbType,
                                    level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, attributes: attributes, type: type, level: level)
    }

    @objc public func addBreadcrumb(_ message: String) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message)
    }

    @objc public func addBreadcrumb(_ message: String, attributes: [String: String]) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, attributes: attributes)
    }

    @objc public func addBreadcrumb(_ message: String, type: BacktraceBreadcrumbType, level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, type: type, level: level)
    }

    @objc public func addBreadcrumb(_ message: String, level: BacktraceBreadcrumbLevel) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, level: level)
    }

    @objc public func addBreadcrumb(_ message: String, type: BacktraceBreadcrumbType) -> Bool {
        return breadcrumbsInstance.addBreadcrumb(message, type: type)
    }

    @objc public func clearBreadcrumbs() -> Bool {
        return breadcrumbsInstance.clear()
    }
}
#endif

// MARK: - BacktraceSessionReplayProtocol
#if os(iOS) && !targetEnvironment(macCatalyst)
extension BacktraceClient: BacktraceSessionReplayProtocol {

    @objc public func enableSessionReplay() {
        enableSessionReplay(configuration.sessionReplaySettings)
    }

    @objc public func enableSessionReplay(_ settings: BacktraceSessionReplaySettings) {
        settings.enabled = true
        let capture = BacktraceScreenshotCapture(settings: settings, sessionId: ApplicationInfo.session)
        capture.start()
        screenshotCapture = capture
        BacktraceLogger.debug("Session replay enabled.")
    }

    @objc public func hideView(_ view: UIView) {
        screenshotCapture?.hideView(view)
    }

    @objc public func unhideView(_ view: UIView) {
        screenshotCapture?.unhideView(view)
    }
}

// MARK: - BacktraceFeedbackProtocol
extension BacktraceClient: BacktraceFeedbackProtocol {

    @objc public func showFeedbackForm() {
        let settings = configuration.feedbackSettings
        let screenshot = captureCurrentScreenshot()

        let controller = BacktraceFeedbackController(
            screenshot: screenshot,
            settings: settings,
            onSubmit: { [weak self] feedbackText, email, screenshot in
                self?.submitFeedbackReport(feedbackText: feedbackText, email: email, screenshot: screenshot)
            },
            onCancel: {
                BacktraceLogger.debug("Feedback form cancelled by user.")
            }
        )

        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .formSheet

        DispatchQueue.main.async {
            guard let topVC = self.topViewController() else { return }
            topVC.present(nav, animated: true)
        }
    }

    @objc public func setFeedbackTrigger(_ trigger: BacktraceFeedbackTrigger) {
        configuration.feedbackSettings.trigger = trigger
        if trigger != .none {
            shakeDetector.configure(
                trigger: trigger,
                debounceInterval: configuration.feedbackSettings.triggerDebounceSeconds
            ) { [weak self] in
                self?.showFeedbackForm()
            }
        } else {
            shakeDetector.teardown()
        }
    }

    private func captureCurrentScreenshot() -> UIImage? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func topViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              var topVC = window.rootViewController else { return nil }
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    private func submitFeedbackReport(feedbackText: String, email: String?, screenshot: UIImage?) {
        var attachmentPaths: [String] = []

        // Save screenshot to temp file if available
        if let screenshot = screenshot, let data = screenshot.jpegData(compressionQuality: 0.8) {
            let tempDir = FileManager.default.temporaryDirectory
            let screenshotURL = tempDir.appendingPathComponent("feedback_screenshot_\(UUID().uuidString).jpg")
            try? data.write(to: screenshotURL)
            attachmentPaths.append(screenshotURL.path)
        }

        // Build feedback message
        var message = "User Feedback: \(feedbackText)"
        if let email = email, !email.isEmpty {
            attributes["feedback.email"] = email
        }
        attributes["feedback.text"] = feedbackText

        send(message: message, attachmentPaths: attachmentPaths) { result in
            BacktraceLogger.debug("Feedback report sent: \(result.status)")
        }
    }
}

// MARK: - BacktraceLogCaptureProtocol
extension BacktraceClient: BacktraceLogCaptureProtocol {

    @objc public func enableLogCapture() {
        enableLogCapture(configuration.logCaptureSettings)
    }

    @objc public func enableLogCapture(_ settings: BacktraceLogCaptureSettings) {
        settings.enabled = true
        let capture = BacktraceLogCapture(settings: settings, sessionId: ApplicationInfo.session)
        capture.start()
        logCapture = capture
        BacktraceLogger.debug("Log capture enabled.")
    }

    @objc public func log(_ message: String, level: BacktraceLogLevel) {
        logCapture?.log(message, level: level)
    }
}

// MARK: - BacktraceVitalsProtocol
extension BacktraceClient: BacktraceVitalsProtocol {

    @objc public func enableVitalsMonitoring() {
        enableVitalsMonitoring(configuration.vitalsSettings)
    }

    @objc public func enableVitalsMonitoring(_ settings: BacktraceVitalsSettings) {
        settings.enabled = true
        let monitor = BacktraceVitalsMonitor(settings: settings, sessionId: ApplicationInfo.session)
        monitor.start()
        vitalsMonitor = monitor
        BacktraceLogger.debug("Vitals monitoring enabled.")
    }
}
#endif
