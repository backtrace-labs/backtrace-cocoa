import Foundation
#if !os(macOS)
import UIKit
#else
import AppKit
#endif

final class BacktraceReporter {

    let reporter: CrashReporting
    private(set) var api: BacktraceApi
    private let watcher: BacktraceWatcher<PersistentRepository<BacktraceReport>>
    private(set) var attributesProvider: SignalContext
    private(set) var backtraceOomWatcher: BacktraceOomWatcher!
    let repository: PersistentRepository<BacktraceReport>

    #if os(macOS)
    lazy var memoryPressureSource: DispatchSourceMemoryPressure = {
        DispatchSource.makeMemoryPressureSource(eventMask: [.critical, .warning], queue: .global())
    }()
    #endif

    init(reporter: CrashReporting,
         api: BacktraceApi,
         dbSettings: BacktraceDatabaseSettings,
         credentials: BacktraceCredentials,
         urlSession: URLSession = URLSession(configuration: .ephemeral)) throws {
        self.reporter = reporter
        self.api = api
        self.watcher =
            BacktraceWatcher(settings: dbSettings,
                             networkClient: BacktraceNetworkClient(urlSession: urlSession),
                             credentials: credentials,
                             repository: try PersistentRepository<BacktraceReport>(settings: dbSettings))
        self.repository = try PersistentRepository<BacktraceReport>(settings: dbSettings)
        let attributesProvider = AttributesProvider(reportHostName: dbSettings.reportHostName)
        self.attributesProvider = attributesProvider
        if #available(iOS 15.3.1, *) {
            BacktraceLogger.debug("The OOM support is disabled for this version of iOS. Skipping OOM check.")
        }else{
            self.backtraceOomWatcher = BacktraceOomWatcher(
                repository: self.repository,
                crashReporter: self.reporter,
                attributes: attributesProvider,
                backtraceApi: self.api)
        }
        self.reporter.signalContext(&self.attributesProvider)
    }
}

extension BacktraceReporter {

    func enableCrashReporter() throws {
        try reporter.enableCrashReporting()
        watcher.enable()
    }

    func handlePendingCrashes() throws {
        // always try to remove pending crash report from disk
        defer { try? reporter.purgePendingCrashReport() }

        // try to send pending crash report
        guard reporter.hasPendingCrashes() else {
            BacktraceLogger.debug("There are no pending crash crashes to send.")
            return
        }
        BacktraceLogger.debug("There is a pending crash report to send.")
        let resource = try reporter.pendingCrashReport()
        _ = send(resource: resource)
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
            return try api.send(resource)
        } catch {
            BacktraceLogger.error(error)
            try? repository.save(resource)
            return BacktraceResult(error.backtraceStatus)
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
        attributesProvider.set(errorType: "Exception")
        let resource = try reporter.generateLiveReport(exception: exception,
                                                       attributes: attributesProvider.allAttributes,
                                                       attachmentPaths: attachmentPaths + attributesProvider.attachmentPaths)
        return resource
    }
}

#if os(iOS) || os(tvOS)
typealias Application = UIApplication
#elseif os(macOS)
typealias Application = NSApplication
#else
#error("Unsupported platform")
#endif

//// Provides notification interfaces for BacktraceOOMWatcher and Breadcrumbs support
extension BacktraceReporter {
    internal func enableOomWatcher() {
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

        #if os(iOS) || os(tvOS)
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
        self.backtraceOomWatcher.appChanedState(.active)
    }

    @objc private func didBecomeActiveNotification() {
        self.backtraceOomWatcher.appChanedState(.active)
    }

    @objc private func willResignActiveNotification() {
        self.backtraceOomWatcher.appChanedState(.inactive)
    }

    @objc private func didEnterBackgroundNotification() {
        self.backtraceOomWatcher.appChanedState(.background)
    }

    @objc private func handleTermination() {
        self.backtraceOomWatcher.handleTermination()
    }
    @objc private func handleLowMemoryWarning() {
        self.backtraceOomWatcher.handleLowMemoryWarning()
    }
}
