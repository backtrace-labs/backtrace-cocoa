//
//  BacktraceCrashLoopCounter.swift
//  Backtrace
//

import Foundation

@objc internal class BacktraceCrashLoopCounter: BacktraceCrashLoop {

    static private var counter = 0

    static internal func start() {
        checkFileExists()
        BacktraceCrashLoop.LogDebug("Cache Dir: \(cacheDir())")
        BacktraceCrashLoop.LogDebug("Crash Loop Counter File Path: \(filePath())")
        loadCounter()
    }

    static internal func loadCounter() {
        guard let contents = try? String(contentsOfFile: filePath())
        else {
            counter = 0
            return
        }
        counter = Int(contents) ?? 0
    }

    static internal func crashesCount() -> Int {
        return counter
    }

    static private func checkFileExists() {
        let path = filePath()
        /*
            We can use just 'createFile' to check if file exists, but, as per docs:
            "If a file already exists at path, this method overwrites the contents of that file
            if the current process has the appropriate privileges to do so."
            https://developer.apple.com/documentation/foundation/filemanager/1410695-createfile
         */
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
            // Write current counter
            reset()
        }
    }

    static internal func increment() {
        counter += 1
        saveCounter()
    }

    static internal func reset() {
        counter = 0
        saveCounter()
    }

    static private func saveCounter() {
        let contents = String(counter)
        try? contents.write(toFile: filePath(), atomically: true, encoding: .utf8)
    }

    static private func fileURL() -> URL {
        let cacheDir = cacheDir()
        let filePath = cacheDir.appendingPathComponent("BacktraceCrashLoopCounter.txt")
        return filePath
    }

    static private func filePath() -> String {
        let filePath = fileURL().absoluteString
                                .replacingOccurrences(of: "file://", with: "")
        return filePath
    }

    static private func cacheDir() -> URL {
        let paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
        let cacheDir = URL(fileURLWithPath: paths.isEmpty ? "" : paths[0])
        return cacheDir
    }
}
