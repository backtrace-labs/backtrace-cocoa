import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Manages session recording, event collection, log capture, screenshots, and feedback.
///
/// Access via `BacktraceClient.shared?.sessions`. Enable with `enableSessions()`.
@objc public class BacktraceSessions: NSObject {

    // MARK: - Public Properties

    /// Delegate for session lifecycle callbacks.
    @objc public weak var delegate: BacktraceSessionDelegate?

    /// The web dashboard URL for the current session, if available.
    @objc public private(set) var sessionURL: String?

    /// The session token returned by the server. Used for all subsequent API calls.
    @objc public private(set) var sessionToken: String?

    /// Whether the session is currently active (recording data).
    @objc public var isActive: Bool {
        return state == .active
    }

    // MARK: - Internal Properties

    private(set) var state: BacktraceSessionState = .idle
    let settings: BacktraceSessionSettings
    let sessionId: String = UUID().uuidString
    let startTime: Date = Date()

    private let queue = DispatchQueue(label: "io.backtrace.sessions", qos: .utility)

    private var sessionApi: BacktraceSessionApi?
    private var eventTracker: BacktraceSessionEventTracker?
    private var logCapture: BacktraceSessionLogCapture?
    private var storage: BacktraceSessionStorage?

    #if os(iOS)
    private var screenshotCapture: BacktraceScreenshotCapture?
    private var shakeDetector: BacktraceShakeDetector?
    private var sensitiveViewManager: BacktraceSensitiveViewManager?
    #endif

    private var metricsTimer: DispatchSourceTimer?
    private var lifecycleObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    init(settings: BacktraceSessionSettings) {
        self.settings = settings
        super.init()
    }

    deinit {
        removeLifecycleObservers()
    }

    // MARK: - Session Lifecycle

    /// Start the session. Called internally by `enableSessions()`.
    func start(networkClient: BacktraceNetworkClient) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.state.canTransitionToActive else {
                BacktraceLogger.debug("Session cannot start from state: \(self.state)")
                return
            }

            self.state = .active
            BacktraceLogger.debug("Session started: \(self.sessionId)")

            // Initialize subsystems
            self.initializeSubsystems(networkClient: networkClient)

            // Register lifecycle observers
            self.registerLifecycleObservers()

            // Start session on server
            self.sessionApi?.startSession(
                sessionId: self.sessionId,
                startTime: self.startTime,
                settings: self.settings
            ) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    self.queue.async {
                        self.sessionToken = response.sessionToken
                        self.sessionURL = response.sessionUrl
                        self.eventTracker?.sessionToken = response.sessionToken
                        if let endpoint = response.endpointAddress {
                            self.sessionApi?.updateEndpoint(endpoint)
                        }
                    }
                    DispatchQueue.main.async {
                        self.delegate?.sessionDidStart?(sessionUrl: response.sessionUrl)
                    }
                case .failure(let error):
                    BacktraceLogger.error("Session start failed: \(error)")
                    DispatchQueue.main.async {
                        self.delegate?.sessionDidFailToStart?(error: error)
                    }
                }
            }
        }
    }

    /// Pause the session. Timers stop firing, buffers are flushed, no new data is collected.
    @objc public func pause() {
        queue.async { [weak self] in
            guard let self = self, self.state == .active else { return }
            self.state = .paused
            BacktraceLogger.debug("Session paused: \(self.sessionId)")

            self.eventTracker?.flush()
            self.stopTimers()

            self.eventTracker?.addMetaEvent(metaType: .appInBackground)
        }
    }

    /// Resume a paused session. Restarts timers and data collection.
    @objc public func resume() {
        queue.async { [weak self] in
            guard let self = self else { return }

            if self.state == .paused {
                self.state = .active
                BacktraceLogger.debug("Session resumed: \(self.sessionId)")
                self.startTimers()
                self.eventTracker?.addMetaEvent(metaType: .appInForeground)
            } else if self.state == .stopped {
                BacktraceLogger.debug("Session was stopped; cannot resume. Start a new session instead.")
            }
        }
    }

    /// Stop the session permanently. Flushes all buffers and releases resources.
    @objc public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.state == .active || self.state == .paused else { return }

            self.state = .stopped
            BacktraceLogger.debug("Session stopped: \(self.sessionId)")

            self.eventTracker?.addMetaEvent(metaType: .sessionStoppedProgrammatically)
            self.eventTracker?.flush()
            self.stopTimers()
            self.removeLifecycleObservers()

            #if os(iOS)
            self.screenshotCapture?.stop()
            self.shakeDetector?.disable()
            #endif

            DispatchQueue.main.async {
                self.delegate?.sessionDidStop?()
            }
        }
    }

    // MARK: - Logging

    /// Log a message to the session timeline.
    ///
    /// - Parameters:
    ///   - message: The log message text.
    ///   - level: Severity level. Default `.info`.
    ///   - attributes: Optional key-value pairs attached to this log entry.
    @objc public func log(_ message: String,
                          level: BacktraceSessionLogLevel = .info,
                          attributes: [String: String]? = nil) {
        guard state.isCollecting else { return }
        guard level >= settings.logLevel else { return }
        logCapture?.log(message, level: level, attributes: attributes)
    }

    // MARK: - User Identity & Attributes

    /// Set the user identifier for this session.
    ///
    /// - Parameter identifier: A user ID, email, or other identifier.
    @objc public func setUserIdentifier(_ identifier: String) {
        guard state == .active || state == .paused else { return }
        sessionApi?.setUserData(sessionToken: sessionToken, identifier: identifier)
        eventTracker?.addMetaEvent(metaType: .sessionAttribute, data: ["correlationId": identifier])
    }

    /// Set a custom session attribute.
    ///
    /// - Parameters:
    ///   - key: Attribute key (max 64 chars).
    ///   - value: Attribute value (max 1000 chars).
    @objc public func setAttribute(_ key: String, value: String) {
        guard state == .active || state == .paused else { return }
        guard key.count <= 64, value.count <= 1000 else {
            BacktraceLogger.warning("Session attribute key (max 64) or value (max 1000) too long. Ignored.")
            return
        }
        eventTracker?.addMetaEvent(metaType: .sessionAttribute, data: [key: value])
    }

    /// Add a named event/checkpoint to the session timeline.
    ///
    /// - Parameter name: The event name.
    @objc public func addEvent(_ name: String) {
        guard state.isCollecting else { return }
        eventTracker?.addCheckpointEvent(name: name)
    }

    // MARK: - Feedback (iOS only)

    #if os(iOS)
    /// Present the in-app feedback form.
    ///
    /// Captures a screenshot automatically and presents the feedback form modally.
    @objc public func showFeedbackForm() {
        guard state == .active || state == .paused else {
            BacktraceLogger.warning("Cannot show feedback form: session not active.")
            return
        }
        let screenshot = screenshotCapture?.captureNow()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let controller = BacktraceFeedbackController(
                screenshot: screenshot,
                options: self.settings.feedbackOptions ?? BacktraceFeedbackOptions(),
                submission: BacktraceFeedbackSubmission(
                    sessionApi: self.sessionApi,
                    sessionToken: self.sessionToken,
                    sessionId: self.sessionId,
                    storage: self.storage
                ),
                delegate: self.delegate
            )
            self.presentFeedbackController(controller)
        }
    }

    /// Send feedback programmatically without showing the form UI.
    ///
    /// - Parameter text: The feedback message.
    @objc public func sendFeedback(_ text: String) {
        guard state == .active || state == .paused else { return }
        let screenshot = screenshotCapture?.captureNow()
        let submission = BacktraceFeedbackSubmission(
            sessionApi: sessionApi,
            sessionToken: sessionToken,
            sessionId: sessionId,
            storage: storage
        )
        submission.submit(text: text, screenshot: screenshot, email: nil, customFields: nil) { [weak self] (result: Swift.Result<Void, Swift.Error>) in
            switch result {
            case .success:
                DispatchQueue.main.async { self?.delegate?.feedbackDidSubmit?() }
            case .failure(let error):
                DispatchQueue.main.async { self?.delegate?.feedbackDidFailToSubmit?(error: error) }
            }
        }
    }

    /// Hide a view from session screenshots. The view will be replaced with an opaque rectangle.
    ///
    /// - Parameter view: The view to hide.
    @objc public func hideView(_ view: UIView) {
        sensitiveViewManager?.hide(view)
    }

    /// Un-hide a previously hidden view.
    ///
    /// - Parameter view: The view to show again.
    @objc public func unhideView(_ view: UIView) {
        sensitiveViewManager?.show(view)
    }

    /// Manually capture a screenshot and add it to the session timeline.
    @objc public func captureScreenshot() {
        guard state.isCollecting else { return }
        screenshotCapture?.captureAndSend()
    }

    /// Set the current screen name for screenshots and feedback context.
    ///
    /// - Parameter name: The logical screen name (e.g., view controller name).
    @objc public func setScreenName(_ name: String) {
        screenshotCapture?.currentScreenName = name
    }
    #endif

    // MARK: - Private: Subsystem Initialization

    private func initializeSubsystems(networkClient: BacktraceNetworkClient) {
        let storage = BacktraceSessionStorage(maxSizeMB: settings.maxOfflineStorageMB)
        self.storage = storage

        let api = BacktraceSessionApi(
            settings: settings,
            networkClient: networkClient
        )
        self.sessionApi = api

        let eventTracker = BacktraceSessionEventTracker(
            bufferSize: settings.eventBufferSize,
            flushInterval: settings.eventFlushInterval,
            sessionId: sessionId,
            startTime: startTime,
            api: api,
            storage: storage
        )
        self.eventTracker = eventTracker

        let logCapture = BacktraceSessionLogCapture(
            logLevel: settings.logLevel,
            captureConsole: settings.captureConsoleOutput,
            eventTracker: eventTracker
        )
        self.logCapture = logCapture

        #if os(iOS)
        let sensitiveViewManager = BacktraceSensitiveViewManager()
        self.sensitiveViewManager = sensitiveViewManager

        if settings.screenshotInterval > 0 {
            let capture = BacktraceScreenshotCapture(
                interval: settings.screenshotInterval,
                quality: settings.screenshotQuality,
                sensitiveViewManager: sensitiveViewManager,
                api: api,
                eventTracker: eventTracker
            )
            self.screenshotCapture = capture
            capture.start()
        }

        if settings.shakeToReport {
            let detector = BacktraceShakeDetector()
            self.shakeDetector = detector
            detector.enable { [weak self] in
                self?.showFeedbackForm()
            }
        }
        #endif

        startTimers()
    }

    // MARK: - Private: Timers

    private func startTimers() {
        // Periodic metrics collection
        if settings.collectCPU || settings.collectMemory || settings.collectBattery {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + settings.metricsInterval,
                repeating: settings.metricsInterval
            )
            timer.setEventHandler { [weak self] in
                self?.collectMetrics()
            }
            timer.resume()
            metricsTimer = timer
        }

        // Resume screenshot capture if it was stopped
        #if os(iOS)
        screenshotCapture?.start()
        #endif
    }

    private func stopTimers() {
        metricsTimer?.cancel()
        metricsTimer = nil

        #if os(iOS)
        screenshotCapture?.stop()
        #endif
    }

    private func collectMetrics() {
        guard state.isCollecting else { return }
        eventTracker?.collectSystemMetrics(settings: settings)
    }

    // MARK: - Private: Lifecycle Observers

    private func registerLifecycleObservers() {
        #if os(iOS) || targetEnvironment(macCatalyst)
        let center = NotificationCenter.default

        let bgObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
        }

        let fgObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resume()
        }

        let termObserver = center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }

        lifecycleObservers = [bgObserver, fgObserver, termObserver]
        #elseif os(macOS)
        let center = NotificationCenter.default

        let bgObserver = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pause()
        }

        let fgObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resume()
        }

        let termObserver = center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }

        lifecycleObservers = [bgObserver, fgObserver, termObserver]
        #endif
    }

    private func removeLifecycleObservers() {
        let center = NotificationCenter.default
        for observer in lifecycleObservers {
            center.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
    }

    #if os(iOS)
    private func presentFeedbackController(_ controller: BacktraceFeedbackController) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            BacktraceLogger.warning("Could not find root view controller to present feedback form.")
            return
        }

        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .fullScreen
        presenter.present(nav, animated: true)
    }
    #endif
}
