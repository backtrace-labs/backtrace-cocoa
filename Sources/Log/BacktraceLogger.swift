import Foundation

/// Logging levels.
@objc public enum BacktraceLogLevel: Int {
    case debug
    case warning
    case info
    case error
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
            return "❤️"
        }
    }
}

/// Logs Backtrace events.
@objc public class BacktraceLogger: NSObject {
    static var destinations: Set<BacktraceBaseDestination> = [BacktraceConsoleDestination(level: .none)]

    /// Replaces the logging destinations
    ///
    /// - Parameter destinations: Logging destinations.
    @objc public class func setDestinations(destinations: Set<BacktraceBaseDestination>) {
        self.destinations = destinations
    }
    //swiftlint:disable line_length
    class func debug(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .debug, msg: msg, file: file, function: function, line: line)
    }

    class func warning(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, msg: msg, file: file, function: function, line: line)
    }

    class func info(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, msg: msg, file: file, function: function, line: line)
    }

    class func error(_ msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .error, msg: msg, file: file, function: function, line: line)
    }

    private class func log(level: BacktraceLogLevel, msg: @autoclosure () -> Any, file: String = #file, function: String = #function, line: Int = #line) {
        let message = String(describing: msg())
        destinations
            .filter { $0.shouldLog(level: level) }
            .forEach { $0.log(level: level, msg: message, file: file, function: function, line: line) }
    }
    //swiftlint:enable line_length
}

/// Generic logging destination.
@objc open class BacktraceBaseDestination: NSObject {

    private let level: BacktraceLogLevel

    @objc public init(level: BacktraceLogLevel) {
        self.level = level
    }

    func shouldLog(level: BacktraceLogLevel) -> Bool {
        return self.level.rawValue <= level.rawValue
    }
    //swiftlint:disable line_length
    
    /// Logs the event to specified destination.
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
    //swiftlint:enable line_length
}

/// Provides the default console destination for logging.
@objc final public class BacktraceFencyConsoleDestination: BacktraceBaseDestination {

    /// Used date formatter for logging.
    @objc public static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd hh:mm:ssSSS"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }

    //swiftlint:disable line_length
    override public func log(level: BacktraceLogLevel, msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        print("\(BacktraceFencyConsoleDestination.dateFormatter.string(from: Date())) [\(level.desc()) Backtrace] [\(URL(fileURLWithPath: file).lastPathComponent)]:\(line) \(function) -> \(msg)")
    }
    //swiftlint:enable line_length
}

/// Provides the default console destination for logging.
@objc final public class BacktraceConsoleDestination: BacktraceBaseDestination {
    
    //swiftlint:disable line_length
    override public func log(level: BacktraceLogLevel, msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        print("\(Date()) [Backtrace]: \(msg)")
    }
    //swiftlint:enable line_length
}
