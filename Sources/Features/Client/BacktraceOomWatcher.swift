import Foundation
#if os(iOS) || os(tvOS)
typealias Application = UIApplication
#elseif os(macOS)
typealias Application = NSApplication
#else
#error("Unsupported platform")
#endif

enum State {
    case running, stopped, starting, stopping
}

final class BacktraceOomWatcher {

    // Relaxed visibility for testing
    internal var appContext: AppContext?

    let lowMemoryFilePrefix = "_lowMemory"
    private(set) static var oomFilePath: URL? = getAppContextFilePath()

    private(set) var crashReporter: CrashReporting
    private(set) var attributesProvider: AttributesProvider
    private(set) var backtraceApi: BacktraceApi
    private(set) var state = State.stopped
    private let repository: PersistentRepository<BacktraceReport>

#if os(macOS)
    lazy private var memoryPressureSource: DispatchSourceMemoryPressure = {
        DispatchSource.makeMemoryPressureSource(eventMask: [.critical, .warning], queue: .global())
    }()
#endif

    init(
        repository: PersistentRepository<BacktraceReport>,
        crashReporter: CrashReporting,
        attributes: AttributesProvider,
        backtraceApi: BacktraceApi) {
        self.crashReporter = crashReporter
        self.attributesProvider = attributes
        self.backtraceApi = backtraceApi
        self.repository = repository
    }

    deinit {
        self.stop()
    }

    internal static func clean() {
        if let oomFilePath = BacktraceOomWatcher.oomFilePath,
           FileManager.default.fileExists(atPath: oomFilePath.path) {
            do {
                try FileManager.default.removeItem(at: oomFilePath)
            } catch {
                BacktraceLogger.error("Deleting \(oomFilePath.path) failed: \(error.localizedDescription).")
            }
        }
    }

    internal static func getAppVersion() -> String {
        if let appVersion = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String {
            return appVersion
        } else {
            return ""
        }
    }

    internal func start() {
        if state != State.stopped {
            BacktraceLogger.warning("BacktraceOomWatcher in state \(state), can't start. Ignoring call.")
            return
        }
        state = State.starting

        // set default state
        appContext = AppContext()

        // set status file url if the default (in the cache dir) didn't work
        if BacktraceOomWatcher.oomFilePath == nil {
            // database path will point out sqlite database path
            // oom status should exist in the same directory where database exists.
            BacktraceOomWatcher.oomFilePath = self.repository.url.deletingLastPathComponent().absoluteURL
                .appendingPathComponent("BacktraceOomState.plist")
        }

        self.sendPendingOomReports()
        // override previous application state after reading all information
        self.saveAppContext()
        self.enableObservers()
        self.state = State.running
    }

    internal func stop() {
        if state != State.running {
            BacktraceLogger.warning("BacktraceOomWatcher in state \(state), can't stop. Ignoring call.")
            return
        }
        state = State.stopping

        appContext = nil
        BacktraceOomWatcher.clean()
        // swiftlint:disable notification_center_detachment
        NotificationCenter.default.removeObserver(self)

        state = State.stopped
    }

    private func enableObservers() {
        // https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623111-applicationwillterminate
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

    internal static func getAppContextFilePath() -> URL? {
        // oom status file is available in application cache dir - the same dir
        // where we store attributes
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheDir.appendingPathComponent("BacktraceOomState.plist")
    }

    internal func sendPendingOomReports() {
        // Remove the state file regardless of what happens
        defer { BacktraceOomWatcher.clean() }

        // if oom state file doesn't exist it means that we deleted it to
        // prevent sending false oom crashes
        if let oomFilePath = BacktraceOomWatcher.oomFilePath, !FileManager.default.fileExists(atPath: oomFilePath.path) {
            return
        }

        guard let appContext = self.loadSavedAppContext() else {
            return
        }

        if !shouldReportOom(appState: appContext) {
            return
        }

        reportOom(appState: appContext)
    }

    private func shouldReportOom(appState: AppContext) -> Bool {
        // no low memory warning
        if !appState.memoryWarningReceived {
            return false
        }

        // check if debugger was enabled
        if appState.debugger {
            // detected debugger in previous session
            return false
        }
        // check system update
        if appState.version != ProcessInfo.processInfo.operatingSystemVersionString {
            // detected system update
            return false
        }

        // check application update
        if appState.appVersion != BacktraceOomWatcher.getAppVersion() {
            // detected app update
            return false
        }
        return true
    }

    private func reportOom(appState: AppContext) {
        guard let reportData = try? crashReporter.generateLiveReport(exception: nil,
                                                                     attributes: [:],
                                                                     attachmentPaths: []).reportData else {
            BacktraceLogger.warning("Could not create live_report for OomReport.")
            return
        }

        let reportAttributes: Attributes
        if let stateAttributes = appState.attributes,
           let attributes = try? JSONSerialization.jsonObject(with: stateAttributes, options: []) as? Attributes {
            reportAttributes = attributes ?? [:]
        } else {
            reportAttributes = [:]
        }

        // ok - we detected oom and we should report it
        guard let report = try? BacktraceReport(report: reportData, attributes: reportAttributes, attachmentPaths: [])
        else {
            return
        }
        do {
            _ = try backtraceApi.send(report)
        } catch {
            BacktraceLogger.error(error)
            try? self.repository.save(report)
        }
    }
}

extension BacktraceOomWatcher {
    /// Describes the current application's state
    enum AppState: String, Codable {
        /// The app is in the foreground and actively in use.
        case active
        /// The app is in an inactive state when it is in the foreground but receiving events.
        case inactive
        /// The app transitions into the background.
        case background
    }

    //// Describes the current application's information
    struct AppContext: Codable {
        var state: AppState = .active
        var debugger: Bool = DebuggerChecker.isAttached()
        var appVersion: String = BacktraceOomWatcher.getAppVersion()
        var version: String = ProcessInfo.processInfo.operatingSystemVersionString
        var attributes: Data?
        var memoryWarningReceived = false
        var memoryWarningTimestamp: Int?
    }
}

extension BacktraceOomWatcher {
    func appChangedState(_ newState: AppState) {
        appContext?.state = newState
        saveAppContext()
    }

    @objc private func handleTermination() {
        // application terminates correctly - for example: user decide to close app
        self.stop()
    }

    @objc private func applicationWillEnterForeground() {
        self.appChangedState(.active)
    }

    @objc private func didBecomeActiveNotification() {
        self.appChangedState(.active)
    }

    @objc private func willResignActiveNotification() {
        self.appChangedState(.inactive)
    }

    @objc private func didEnterBackgroundNotification() {
        self.appChangedState(.background)
    }

    @objc internal func handleLowMemoryWarning() {
        appContext?.memoryWarningReceived = true
        appContext?.memoryWarningTimestamp = Date().millisecondsSince1970

        var attributes = attributesProvider.allAttributes
        attributes["error.message"] = "Out of memory detected."
        attributes["error.type"] = "Low Memory"
        attributes["memory.warning.timestamp"] = appContext?.memoryWarningTimestamp
        attributes["state"] = appContext?.state.rawValue

        appContext?.attributes = try? JSONSerialization.data(withJSONObject: attributes)
        saveAppContext()
    }

    internal func loadSavedAppContext() -> AppContext? {
        let decoder = PropertyListDecoder()

        guard let destPath = BacktraceOomWatcher.oomFilePath,
              let data = try? Data(contentsOf: destPath),
              let previousAppState = try? decoder.decode(AppContext.self, from: data) else { return nil }
        return previousAppState
    }

    internal func saveAppContext() {
        let encoder = PropertyListEncoder()
        if let data = try? encoder.encode(self.appContext),
           let destPath = BacktraceOomWatcher.oomFilePath {
            if FileManager.default.fileExists(atPath: destPath.path) {
                try? data.write(to: destPath)
            } else {
                FileManager.default.createFile(atPath: destPath.path, contents: data, attributes: nil)
            }
        }
    }
}
