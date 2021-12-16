import Foundation

final class BacktraceOomWatcher {

    private var state: ApplicationInfo

    let lowMemoryFilePrefix = "_lowMemory"
    private(set) static var oomFilePath: URL? = getStatusFilePath()

    private(set) var crashReporter: CrashReporting
    private(set) var attributesProvider: AttributesProvider
    private(set) var backtraceApi: BacktraceApi
    private let repository: PersistentRepository<BacktraceReport>

    init(
        repository: PersistentRepository<BacktraceReport>,
        crashReporter: CrashReporting,
        attributes: AttributesProvider,
        backtraceApi: BacktraceApi) {
        self.crashReporter = crashReporter
        self.attributesProvider = attributes
        self.backtraceApi = backtraceApi
        self.repository = repository

        // set default state
        state = ApplicationInfo()

        // set status file url
        if BacktraceOomWatcher.oomFilePath == nil {
            // database path will point out sqlite database path
            // oom status should exist in the same directory where database exists.
            BacktraceOomWatcher.oomFilePath = self.repository.url.deletingLastPathComponent().absoluteURL
                .appendingPathComponent("BacktraceOOMState.plist")
        }
    }

    internal static func clean() {
        if let oomFilePath = BacktraceOomWatcher.oomFilePath {
            // ignore errors or use do/catch block to handle errors more gracefully
            try? FileManager.default.removeItem(at: oomFilePath)
        }
    }

    internal static func getAppVersion() -> String {
        if let appVersion = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String {
            return appVersion
        } else {
            return ""
        }
    }

    public func start() {
        sendPendingOomReports()
        // override previous application state after reading all information
        saveState()
    }

    internal static func getStatusFilePath() -> URL? {
        // oom status file is available in application cache dir - the same dir
        // where we store attributes
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cacheDir.appendingPathComponent("BacktraceOomState.plist")
    }

    private func sendPendingOomReports() {
        // if oom state file doesn't exist it means that we deleted it to
        // prevent sending false oom crashes
        if let oomFilePath = BacktraceOomWatcher.oomFilePath, !FileManager.default.fileExists(atPath: oomFilePath.path) {
            return
        }

        guard let appState = self.loadPreviousState() else {
            return
        }

        if !shouldReportOom(appState: appState) {
            return
        }

        reportOom(appState: appState)
        BacktraceOomWatcher.clean()
    }

    private func shouldReportOom(appState: ApplicationInfo) -> Bool {
        // no low memory warning
        if appState.resource == nil {
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

    private func reportOom(appState: ApplicationInfo) {
        guard let reportData = appState.resource else {
            return
        }

        var reportAttributes: Attributes = [:]
        if let stateAttributes = appState.attributes,
           let attributes = try? JSONSerialization.jsonObject(with: stateAttributes, options: []) as? Attributes {
            reportAttributes = attributes ?? [:]
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
    enum ApplicationState: String, Codable {
        /// The app is in the foreground and actively in use.
        case active
        /// The app is in an inactive state when it is in the foreground but receiving events.
        case inactive
        /// The app transitions into the background.
        case background
    }

    //// Describes the current application's information
    struct ApplicationInfo: Codable {
        var state: ApplicationState = .active
        var debugger: Bool = DebuggerChecker.isAttached()
        var appVersion: String = BacktraceOomWatcher.getAppVersion()
        var version: String = ProcessInfo.processInfo.operatingSystemVersionString
        var attributes: Data?
        var resource: Data?
    }
}

extension BacktraceOomWatcher {
    func appChanedState(_ newState: ApplicationState) {
        self.state.state = newState
        saveState()
    }

    func handleTermination() {
        // application terminates correctly - for example: user decide to close app
        BacktraceOomWatcher.clean()
        NotificationCenter.default.removeObserver(self)
    }

    func handleLowMemoryWarning() {
        guard let resource = try? crashReporter.generateLiveReport(exception: nil,
                                                                   attributes: attributesProvider.allAttributes,
                                                                   attachmentPaths: []) else {
            return
        }
        self.state.resource = resource.reportData
        resource.attributes["error.message"] = "Out of memory detected."
        resource.attributes["error.type"] = "Low Memory"
        resource.attributes["state"] = state.state.rawValue

        self.state.attributes = try? JSONSerialization.data(withJSONObject: resource.attributes)
        saveState()
    }

    private func loadPreviousState() -> ApplicationInfo? {
        let decoder = PropertyListDecoder()

        guard let destPath = BacktraceOomWatcher.oomFilePath,
              let data = try? Data(contentsOf: destPath),
              let previousAppState = try? decoder.decode(ApplicationInfo.self, from: data) else { return nil }
        return previousAppState
    }

    private func saveState() {
        let encoder = PropertyListEncoder()
        if let data = try? encoder.encode(self.state),
           let destPath = BacktraceOomWatcher.oomFilePath {
            if FileManager.default.fileExists(atPath: destPath.path) {
                try? data.write(to: destPath)
            } else {
                FileManager.default.createFile(atPath: destPath.path, contents: data, attributes: nil)
            }

        }
    }
}
