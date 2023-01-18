//
//  BacktraceCrashLoopDetector.swift
//  Backtrace
//

import Foundation

@objc internal class BacktraceCrashLoopDetector: BacktraceCrashLoop {

    internal struct StartUpEvent: Codable {
        var uuid: String
        var timestamp: Double
        var crashesCount: Int
        
        func description() -> String {
            let string = """
                            New Crash Loop Event:\n
                            UUID: \(uuid)\n
                            Timestamp: \(timestamp)\n
                            Crashes Count: \(crashesCount)
                         """
            return string
        }
    }

    @objc private static let plistKey = "CrashLoopDetectorData"
    @objc internal static let consecutiveCrashesThreshold = 5
    @objc private(set) var consecutiveCrashesCount = 0

    @objc private var threshold = consecutiveCrashesThreshold
    
    internal var startupEvents: [StartUpEvent] = []


    @objc internal func updateThreshold(_ threshold: Int) {
        self.threshold = threshold == 0 ? BacktraceCrashLoopDetector.consecutiveCrashesThreshold : threshold
    }

    @objc internal func detectCrashloop() -> Bool {

        BacktraceCrashLoop.LogDebug("Starting Crash Loop Detection")
        
        loadEvents()
        addStartupEvent()
        saveEvents()

        consecutiveCrashesCount = consecutiveEventsCount()

        /*
            true -> crash loop detected -> set safe mode
            false -> crash loop NOT detected -> set normal mode
         */
        let result = consecutiveCrashesCount >= BacktraceCrashLoopDetector.consecutiveCrashesThreshold
        BacktraceCrashLoop.LogDebug("Finishing Crash Loop Detection: \(result)")
        return result
    }

    @objc private func loadEvents() {
        
        // Cleanup old events - f.e. for multiple usages of detector
        startupEvents.removeAll()
        
        /*
         - Since detector's DB is relatively small, UserDefaults are a good option here,
         plus they allow to avoid a headache with reading/writing to/from the custom file.

         - But we should consider shared computers as well - comment from UserDefaults docs:
            With the exception of managed devices in educational institutions,
            a user’s defaults are stored locally on a single device,
            and persisted for backup and restore.
            To synchronize preferences and other data across a user’s connected devices,
            use NSUbiquitousKeyValueStore instead.
         */
        guard let data = UserDefaults.standard.object(forKey: BacktraceCrashLoopDetector.plistKey) as? Data
        else { return }

        guard let array = try? PropertyListDecoder().decode([StartUpEvent].self, from: data)
        else { return }

        startupEvents.append(contentsOf: array)
        BacktraceCrashLoopDetector.LogDebug("Events Loaded: \(startupEvents.count)")
    }

    @objc internal func saveEvents() {
        let data = try? PropertyListEncoder().encode(startupEvents)
        UserDefaults.standard.set(data, forKey: BacktraceCrashLoopDetector.plistKey)
        BacktraceCrashLoopDetector.LogDebug("Events Saved: \(startupEvents.count)")
    }

    @objc internal func addStartupEvent() {
        
        let crashesCount = BacktraceCrashLoopCounter.crashesCount()
        let event = StartUpEvent(uuid: UUID().uuidString,
                                 timestamp: Double(Date.timeIntervalSinceReferenceDate),
                                 crashesCount: crashesCount)
        
        BacktraceCrashLoop.LogDebug(event.description())

        startupEvents.append(event)
        
        if startupEvents.count > BacktraceCrashLoopDetector.consecutiveCrashesThreshold {
            startupEvents.removeFirst()
        }

        BacktraceCrashLoop.LogDebug("Startup Event Added: \(startupEvents.count)")
    }

    @objc internal func clearStartupEvents() {
        startupEvents.removeAll()
        saveEvents()
        BacktraceCrashLoop.LogDebug("Startup Events Cleared: \(startupEvents.count)")
    }
    
    @objc internal func consecutiveEventsCount() -> Int {
        
        var count = 0
        var previousValue = 0
        for event in startupEvents {
            if event.crashesCount > previousValue {
                count += 1
            }
            previousValue = event.crashesCount
        }

        BacktraceCrashLoop.LogDebug("Consecutive Events Count: \(count)")
        return count
    }
    
    @objc internal func databaseDescription() -> String {
        var string = ""
        for event in startupEvents {
            string += event.description() + "\n"
        }
        return string
    }
}

// MARK: Deprecated methods
extension BacktraceCrashLoopDetector {

    @available(*, deprecated, message: "Temporarily not needed")
    @objc internal func reportFilePath() -> String {
        
        /*  Crash Loop Detector considers all other Backtrace modules as potentially dangerous.
            Thats why it formats path to PLCrashReporter's report file itself,
            for not to use PLCrashReporter's APIs at all
         */
        
        let bundleIDBT = Bundle.main.bundleIdentifier ?? ""
        let appIDPath = bundleIDBT.replacingOccurrences(of: "/", with: "_")

        let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let cacheDir = URL(fileURLWithPath: paths.isEmpty ? "" : paths[0])

        let bundleIDPLCR = "com.plausiblelabs.crashreporter.data"
        let crashReportDir = cacheDir.appendingPathComponent(bundleIDPLCR)
                                     .appendingPathComponent(appIDPath)

        let reportName = "live_report.plcrash"
        let reportFullPath = crashReportDir.appendingPathComponent(reportName)
                                           .absoluteString
                                           .replacingOccurrences(of: "file://", with: "")
        BacktraceCrashLoop.LogDebug("reportFullPath: \(reportFullPath)")
        return reportFullPath
    }

    @available(*, deprecated, message: "Temporarily not needed")
    @objc internal func hasCrashReport() -> Bool {
        let exists = FileManager.default.fileExists(atPath: reportFilePath())
        return exists
    }

    @available(*, deprecated, message: "Temporarily not needed")
    @objc internal func deleteCrashReport() {
        let path = reportFilePath()
        let fileURL = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: fileURL)
        saveEvents()
    }
}
