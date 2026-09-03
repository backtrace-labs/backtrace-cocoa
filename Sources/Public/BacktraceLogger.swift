import Foundation

/// Logging levels.
@objc public enum BacktraceLogLevel: Int {
    /// All logs logged to the destination.
    case debug
    /// Warnings, info and errors logged to the destination.
    case warning
    /// Info and errors logged to the destination.
    case info
    /// Only errors logged to the destination.
    case error
    /// No logs logged to the destination.
    case none

    fileprivate func desc() -> String {
        switch self {
        case .none:
            return ""
        case .debug:
            return "💚"
        case .warning:
            return "💛"
        case .info:
            return "💙"
        case .error:
            return "💔"
        }
    }
}

/// Logs Backtrace events.
@objc public class BacktraceLogger: NSObject {

    private static let destinationsLock = NSLock()
    private static var storedDestinations: Set<BacktraceBaseDestination> = []

    /// Set of logging destinations. Access is synchronized because the Unity bridge can change log level while Cocoa background queues are emitting diagnostics.
    static var destinations: Set<BacktraceBaseDestination> {
        destinationsLock.lock()
        defer { destinationsLock.unlock() }
        return storedDestinations
    }

    /// Replaces the logging destinations.
    ///
    /// - Parameter loggingDestinations: Logging destinations.
    @objc(setDestinations:)
    public class func setDestinations(_ destinations: Set<BacktraceBaseDestination>) {
        destinationsLock.lock()
        storedDestinations = destinations
        destinationsLock.unlock()
    }
    // swiftlint:disable line_length
    class func debug(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, msg: msg(), file: file, function: function, line: line)
    }

    class func warning(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, msg: msg(), file: file, function: function, line: line)
    }

    class func info(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, msg: msg(), file: file, function: function, line: line)
    }

    class func error(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, msg: msg(), file: file, function: function, line: line)
    }

    private class func log(level: BacktraceLogLevel, msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        let message = String(describing: msg())
        let destinationsSnapshot = destinations
        destinationsSnapshot
            .filter { $0.shouldLog(level: level) }
            .forEach { $0.log(level: level, msg: message, file: file, function: function, line: line) }
    }
    // swiftlint:enable line_length
}

/// Abstract class that provides logging functionality.
///
/// A methods `func log(level:msg:file:function:line:)` is abstract and needs to be overridden.
///
@objc open class BacktraceBaseDestination: NSObject {

    private let level: BacktraceLogLevel

    /// Initialize `BacktraceBaseDestination` with given level.
    ///
    /// - Parameters:
    ///   - level: logging level
    @objc public init(level: BacktraceLogLevel) {
        self.level = level
    }

    func shouldLog(level: BacktraceLogLevel) -> Bool {
        return self.level.rawValue <= level.rawValue
    }
    // swiftlint:disable line_length

    /// An abstract method used to log message to provided destination.
    ///
    /// - Parameters:
    ///   - level: logging level
    ///   - msg: message to log
    ///   - file: the name of the file in which it appears
    ///   - function: the name of the declaration in which it appears
    ///   - line: the line number on which it appears
    @objc public func log(level: BacktraceLogLevel, msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        // abstract
    }
    // swiftlint:enable line_length
}

/// Provides logging functionality to IDE console.
@objc final public class BacktraceFancyConsoleDestination: BacktraceBaseDestination {

    /// Used date formatter for logging.
    @objc public static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ssSSS"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }

    // swiftlint:disable line_length
    /// Logs the event to console destination. Formats log in more verbose way.
    ///
    /// - Parameters:
    ///   - level: logging level
    ///   - msg: message to log
    ///   - file: the name of the file in which it appears
    ///   - function: the name of the declaration in which it appears
    ///   - line: the line number on which it appears
    override public func log(level: BacktraceLogLevel, msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        print("\(BacktraceFancyConsoleDestination.dateFormatter.string(from: Date())) [\(level.desc()) Backtrace] [\(URL(fileURLWithPath: file).lastPathComponent)]:\(line) \(function) -> \(msg)")
    }
    // swiftlint:enable line_length
}

/// Provides logging functionality to IDE console.
@objc final public class BacktraceConsoleDestination: BacktraceBaseDestination {

    // swiftlint:disable line_length
    /// Logs the event to console destination.
    ///
    /// - Parameters:
    ///   - level: logging level
    ///   - msg: message to log
    ///   - file: the name of the file in which it appears
    ///   - function: the name of the declaration in which it appears
    ///   - line: the line number on which it appears
    override public func log(level: BacktraceLogLevel, msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        print("\(Date()) [Backtrace]: \(msg)")
    }
    // swiftlint:enable line_length
}
