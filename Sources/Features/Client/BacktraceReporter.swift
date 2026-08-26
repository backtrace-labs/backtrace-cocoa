import Foundation

final class BacktraceReporter {

#if os(macOS) || !targetEnvironment(macCatalyst)
    lazy var memoryPressureSource: DispatchSourceMemoryPressure = {
        DispatchSource.makeMemoryPressureSource(eventMask: [.critical, .warning], queue: .global())
    }()
#endif

    let reporter: CrashReporting
    private(set) var api: BacktraceApi
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
         urlSession: URLSession = URLSession(configuration: .ephemeral)) throws {
        self.reporter = reporter
        self.api = api
        self.oomMode = oomMode
        let repository = try PersistentRepository<BacktraceReport>(settings: dbSettings)
        self.repository = repository
        self.watcher =
            BacktraceWatcher(settings: dbSettings,
                             networkClient: BacktraceNetworkClient(urlSession: urlSession),
                             credentials: credentials,
                             repository: repository)
        let attributesProvider = AttributesProvider(reportHostName: dbSettings.reportHostName)
        self.attributesProvider = attributesProvider
        self.backtraceOomWatcher = BacktraceOomWatcher(
            repository: self.repository,
            crashReporter: self.reporter,
            attributes: attributesProvider,
            backtraceApi: self.api,
            oomMode: oomMode)
        self.reporter.signalContext(&self.attributesProvider)
    }
}

extension BacktraceReporter {

    func enableCrashReporter() throws {
        try reporter.enableCrashReporting()
        watcher.enable()
        watcher.replayAsync()
    }

    func handlePendingCrashes() throws {
        guard reporter.hasPendingCrashes() else {
            BacktraceLogger.debug("There are no pending crashes to ingest.")
            return
        }
        BacktraceLogger.debug("There is a pending crash report to persist.")
        let resource = try reporter.pendingCrashReport()
        try repository.savePending(resource)
        BacktraceLogger.debug("Persisted pending crash report: \(resource.identifier)")

        do {
            try reporter.purgePendingCrashReport()
        } catch {
            // Persistence already succeeded. Leave the deterministic row available for replay and let a
            // later startup repeat the same identifier-based upsert if the source remains pending.
            BacktraceLogger.warning("Persisted pending crash but could not purge its source: \(error)")
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
        do {
            let result = try api.send(resource)
            if result.backtraceStatus != .ok {
                persistForRetry(result.report ?? resource)
            }
            return result
        } catch {
            BacktraceLogger.error(error)
            persistForRetry(resource)
            return BacktraceResult(error.backtraceStatus)
        }
    }

    private func persistForRetry(_ resource: BacktraceReport) {
        do {
            try repository.save(resource)
        } catch {
            BacktraceLogger.error("Unable to persist report \(resource.identifier) for retry: \(error)")
        }
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
        self.memoryPressureSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            if [.warning, .critical].contains(self.memoryPressureSource.mask) {
                self.handleLowMemoryWarning()
            }
            self.memoryPressureSource.resume()
        }
        #endif
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
        NotificationCenter.default.removeObserver(self)
        self.backtraceOomWatcher.handleTermination()
    }
    @objc private func handleLowMemoryWarning() {
        self.backtraceOomWatcher.handleLowMemoryWarning()
    }
}
