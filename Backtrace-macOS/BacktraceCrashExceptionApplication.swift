import Cocoa

/// `NSApplication` subclass to catch additional exceptions on macOS
@objc public class BacktraceCrashExceptionApplication: NSApplication {
    
    /// Catch all exceptions and send them to `Backtrace`
    public override func reportException(_ exception: NSException) {
        super.reportException(exception)
        BacktraceClient.shared?.send(exception: exception, attachmentPaths: [], completion: {_ in })
    }
}
