//
//  BacktraceCrashLoopDetector.swift
//  Backtrace
//

import Foundation
import Backtrace_PLCrashReporter

@objc public class BacktraceCrashLoopDetector: NSObject {
        
    fileprivate struct StartUpEvent: Codable {
        var timestamp: Double
        var isSuccessful: Bool
    }
    
    @objc private static let plistKey = "CrashLoopDB"
    @objc private static let eventsForCrashLoopCount = 5

    @objc public static let shared = BacktraceCrashLoopDetector()

    fileprivate var startupEvents: [StartUpEvent] = []
    
    @objc override private init() {
        super.init()
    }
    
    @objc private func loadEvents() {
        
        // Cleanup old events - f.e, for multiple usages of detector
        startupEvents.removeAll()
        
        /*
         - Since detector's DB is relatively small, UserDefaults are a good option here,
         plus allows to avoid a headache with reading/writing to/from the custom file.

         - But we should consider shared computers as well:
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
    }
    
    @objc private func saveEvents() {
        let data = try? PropertyListEncoder().encode(startupEvents)
        UserDefaults.standard.set(data, forKey: BacktraceCrashLoopDetector.plistKey)
    }
    
    @objc private func addCurrentEvent() {
        var event = StartUpEvent(timestamp: Double(Date.timeIntervalSinceReferenceDate), isSuccessful: true)

        let plReporter = PLCrashReporter(configuration: PLCrashReporterConfig.defaultConfiguration())

        if plReporter?.hasPendingCrashReport() ?? false {
            event.isSuccessful = false
        }
//        event.isSuccessful = false
        startupEvents.append(event)
    }

    @objc private func badEventsCount() -> Int {
        
        var badEventsCount = 0
        for event in startupEvents {
            badEventsCount += (event.isSuccessful ? 0 : 1)
        }

        if startupEvents.count >= BacktraceCrashLoopDetector.eventsForCrashLoopCount {
            startupEvents.remove(at: 0)
        }
        
        return badEventsCount
    }
    
    @objc func detectCrashloop() -> Bool {

        loadEvents()
        addCurrentEvent()
        
        let count = badEventsCount()
        saveEvents()

        // true -> crash loop detected -> set safe mode
        // false -> crash loop NOT detected -> set normal mode
        return count >= BacktraceCrashLoopDetector.eventsForCrashLoopCount
    }
}
