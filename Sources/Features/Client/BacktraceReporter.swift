import Foundation

final class BacktraceReporter {

#if os(macOS) || !targetEnvironment(macCatalyst)
    private(set) var memoryPressureSource: DispatchSourceMemoryPressure?
#endif

    private enum LifecycleState {
        case active
        case shuttingDown
        case shutDown
    }
    private let lifecycleCondition = NSCondition()
    private var lifecycleState = LifecycleState.active
    private let shutdownThreadKey = "io.backtrace.reporter.shutdown.\(UUID().uuidString)"
    private var oomWatcherEnabled = false

    let reporter: CrashReporting
    private(set) var api: BacktraceApi
    let submissionCoordinator: BacktraceSubmissionCoordinator<PersistentRepository<BacktraceReport>>
    let watcher: BacktraceWatcher<PersistentRepository<BacktraceReport>>
    private(set) var attributesProvider: SignalContext
    private(set) var backtraceOomWatcher: BacktraceOomWatcher
    private let oomMode: BacktraceOomMode
    let repository: PersistentRepository<BacktraceReport>

    init(reporter: CrashReporting,
         api: BacktraceApi,
         dbSettings: BacktraceDatabaseSettings,
         credentials: BacktraceCredentials,
         oomMode: BacktraceOomMode,
         urlSession: URLSession = URLSession(configuration: .ephemeral),
         networkAvailabilityCheck: (() -> Bool)? = nil) throws {
        // Retained for internal source compatibility while replay now deliberately shares the delegate-aware API (and therefore its URLSession and credentials) with live reports.
        _ = credentials
        _ = urlSession
        self.reporter = reporter
        self.api = api
        self.oomMode = oomMode
        let repository = try PersistentRepository<BacktraceReport>(settings: dbSettings)
        // Recover claims left by the previous process only once.
        // A second live client sharing the database must not rewind work currently owned by the first client.
        try repository.recoverStaleInFlightReportsOncePerProcess()
        self.repository = repository
        let submissionCoordinator = BacktraceSubmissionCoordinator(api: api,
                                                                    repository: repository,
                                                                    retryLimit: dbSettings.retryLimit)
        self.submissionCoordinator = submissionCoordinator
        self.watcher =
            BacktraceWatcher(settings: dbSettings,
                             submissionCoordinator: submissionCoordinator,
                             repository: repository,
                             networkAvailabilityCheck: networkAvailabilityCheck)
        let attributesProvider = AttributesProvider(reportHostName: dbSettings.reportHostName)
        self.attributesProvider = attributesProvider
        self.backtraceOomWatcher = BacktraceOomWatcher(
            repository: self.repository,
            crashReporter: self.reporter,
            attributes: attributesProvider,
            submissionCoordinator: submissionCoordinator,
            oomMode: oomMode)
        self.reporter.signalContext(&self.attributesProvider)
    }

    deinit {
        shutdown()
    }

    internal var isShutdown: Bool {
        lifecycleCondition.lock()
        defer { lifecycleCondition.unlock() }
        return lifecycleState != .active
    }
}

extension BacktraceReporter {

    func enableCrashReporter() throws {
        try reporter.enableCrashReporting()
        watcher.enable()
        // Replay rows that were already retryable before this launch first.
        // Scheduling newly discovered initial rows afterward prevents a transient first attempt from being picked up again by the same startup replay cycle.
        watcher.replayAsync()
        watcher.submitInitialAsync()
    }

    func handlePendingCrashes() throws {
        guard reporter.hasPendingCrashes() else {
            BacktraceLogger.debug("There are no pending crashes to ingest.")
            do {
                try repository.markAwaitingReportsReady()
            } catch {
                BacktraceLogger.warning("Could not reconcile pending report eligibility.")
            }
            return
        }
        BacktraceLogger.debug("There is a pending crash report to persist.")
        let resource: BacktraceReport
        do {
            resource = try reporter.pendingCrashReport()
        } catch let BacktracePendingCrashError.invalidPayload(data, rawSidecarPaths, diagnostics, underlying) {
            do {
                try repository.deadLetterPendingCrash(data: data,
                                                      rawSidecarPaths: rawSidecarPaths,
                                                      diagnostics: diagnostics,
                                                      failure: underlying)
                do {
                    try reporter.purgePendingCrashReport()
                    BacktraceLogger.warning("Moved a recurring invalid pending crash source to the dead-letter archive.")
                } catch {
                    BacktraceLogger.warning("Archived an invalid pending crash source but could not purge it.")
                }
            } catch {
                BacktraceLogger.warning("Could not archive an invalid pending crash source.")
            }
            return
        } catch {
            // Source read failures must not keep the current session from enabling crash capture.
            BacktraceLogger.warning("Could not read the pending crash source; crash capture will still be enabled.")
            return
        }

        try repository.markAwaitingReportsReady(except: resource.identifier)
        let saveOutcome = try repository.savePending(resource)
        BacktraceLogger.debug("Persisted pending crash report: \(resource.identifier)")

        do {
            try reporter.purgePendingCrashReport()
        } catch {
            // Persistence already succeeded, but the row remains ineligible until a later launch confirms that the deterministic PLCrashReporter source no longer exists.
            BacktraceLogger.warning("Persisted pending crash but could not purge its source.")
            return
        }

        if saveOutcome == .awaitingSourcePurge {
            do {
                try repository.promoteAfterSourcePurge(resource)
            } catch {
                // A later launch with no matching source promotes the row. Failing closed prevents duplicates.
                BacktraceLogger.warning("Purged a pending crash source but could not mark its row ready.")
            }
        }
    }
}

extension BacktraceReporter: BacktraceClientCustomizing {
    var delegate: BacktraceClientDelegate? {
        get {
            return api.delegate
        }
        set {
            api.delegate = newValue
        }
    }

    var attributes: Attributes {
        get {
            return attributesProvider.attributes
        } set {
            attributesProvider.attributes = newValue
            
            guard let attributeData = try? JSONSerialization.data(withJSONObject: attributesProvider.scopedAttributes) else {
                return
            }
            self.reporter.setCustomData(data: attributeData)
        
        }
    }

    var attachments: Attachments {
        get {
            return attributesProvider.attachments
        } set {
            attributesProvider.attachments = newValue
        }
    }
}

extension BacktraceReporter {
    func send(resource: BacktraceReport) -> BacktraceResult {
        guard !isShutdown else {
            return BacktraceResult(.unknownError, report: resource)
        }
        return submissionCoordinator.submit(resource, origin: .live).result
    }

    func send(exception: NSException? = nil, attachmentPaths: [String] = [],
              faultMessage: String? = nil) throws -> BacktraceResult {
        attributesProvider.set(faultMessage: faultMessage)
        let resource = try reporter.generateLiveReport(exception: exception,
                                                       attributes: attributesProvider.allAttributes,
                                                       attachmentPaths: attachmentPaths + attributesProvider.attachmentPaths)
        return send(resource: resource)
    }

    func generate(exception: NSException? = nil, attachmentPaths: [String] = [],
                  faultMessage: String? = nil) throws -> BacktraceReport {
        attributesProvider.set(faultMessage: faultMessage)
        let resource = try reporter.generateLiveReport(exception: exception,
                                                       attributes: attributesProvider.allAttributes,
                                                       attachmentPaths: attachmentPaths + attributesProvider.attachmentPaths)
        
        resource.attributes["error.type"] = "Exception"
        return resource
    }
}

#if (os(iOS) || os(tvOS))
import UIKit
typealias Application = UIApplication
#elseif os(macOS)
import AppKit
typealias Application = NSApplication
#else
#error("Unsupported platform")
#endif

//// Provides notification interfaces for BacktraceOOMWatcher and Breadcrumbs support
extension BacktraceReporter {

    internal func enableOomWatcher() {
        guard oomMode != .none else { return }

        lifecycleCondition.lock()
        guard lifecycleState == .active, !oomWatcherEnabled else {
            lifecycleCondition.unlock()
            return
        }
        oomWatcherEnabled = true

        self.backtraceOomWatcher.start()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTermination),
                                               name: Application.willTerminateNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActiveNotification),
                                               name: Application.didBecomeActiveNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(willResignActiveNotification),
                                               name: Application.willResignActiveNotification,
                                               object: nil)

        #if (os(iOS) || os(tvOS))
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: Application.willEnterForegroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackgroundNotification),
                                               name: Application.didEnterBackgroundNotification,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleLowMemoryWarning),
                                               name: Application.didReceiveMemoryWarningNotification,
                                               object: nil)
        #endif

        #if os(macOS)
        let memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.critical, .warning],
            queue: .global())
        self.memoryPressureSource = memoryPressureSource
        memoryPressureSource.setEventHandler { [weak self] in
            // The source is configured only for warning/critical events. Do not read the
            // property that shutdown clears on another thread; the OOM watcher owns the gate.
            self?.handleLowMemoryWarning()
        }
        memoryPressureSource.resume()
        #endif

        lifecycleCondition.unlock()
    }

    @objc private func applicationWillEnterForeground() {
        self.backtraceOomWatcher.appChangedState(.active)
    }

    @objc private func didBecomeActiveNotification() {
        self.backtraceOomWatcher.appChangedState(.active)
    }

    @objc private func willResignActiveNotification() {
        self.backtraceOomWatcher.appChangedState(.inactive)
    }

    @objc private func didEnterBackgroundNotification() {
        self.backtraceOomWatcher.appChangedState(.background)
    }

    @objc private func handleTermination() {
        shutdown()
    }
    @objc private func handleLowMemoryWarning() {
        self.backtraceOomWatcher.handleLowMemoryWarning()
    }

    /// Stops all non-fatal background SDK activity while leaving the crash reporter and its process-wide callback context alive.
    /// Safe to call repeatedly.
    /// It does not wait on network transport, but a concurrent shutdown caller and currently admitted local repository transactions may drain before returning.
    internal func shutdown() {
        lifecycleCondition.lock()
        switch lifecycleState {
        case .active:
            lifecycleState = .shuttingDown
        case .shuttingDown:
            if Thread.current.threadDictionary[shutdownThreadKey] != nil {
                lifecycleCondition.unlock()
                return
            }
            while lifecycleState == .shuttingDown {
                lifecycleCondition.wait()
            }
            lifecycleCondition.unlock()
            return
        case .shutDown:
            lifecycleCondition.unlock()
            return
        }

        Thread.current.threadDictionary[shutdownThreadKey] = true

        NotificationCenter.default.removeObserver(self)
        #if os(macOS)
        let memoryPressureSource = self.memoryPressureSource
        self.memoryPressureSource = nil
        memoryPressureSource?.setEventHandler {}
        memoryPressureSource?.cancel()
        #endif
        lifecycleCondition.unlock()

        defer {
            Thread.current.threadDictionary.removeObject(forKey: shutdownThreadKey)
            lifecycleCondition.lock()
            lifecycleState = .shutDown
            lifecycleCondition.broadcast()
            lifecycleCondition.unlock()
        }

        // Stop producers and coordinator admission first.
        // Cancellation then releases unfinished transports, while submissions with a received response remain allowed to finalize repository state before repository maintenance is closed.
        watcher.prepareForShutdown()
        backtraceOomWatcher.prepareForShutdown()
        submissionCoordinator.prepareForShutdown()
        api.shutdown()
        watcher.finishShutdown()
        backtraceOomWatcher.finishShutdown()
        submissionCoordinator.finishShutdown { [repository] in
            repository.prepareForNativeBridgeShutdown()
            repository.finishNativeBridgeShutdown()
        }
    }
}
