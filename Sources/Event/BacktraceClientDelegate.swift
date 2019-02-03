import Foundation

/// Events produced by BacktraceClient class.
@objc public protocol BacktraceClientDelegate: class {
    
    /// Event execute before sending report data to Backtrace services.
    ///
    /// - Parameter report: Backtrace report to send
    /// - Returns: Modified Backtrace report.
    @objc optional func willSend(_ report: BacktraceCrashReport) -> BacktraceCrashReport
    
    /// Event executed before HTTP request to Backtrace services.
    ///
    /// - Parameter request: HTTP request to send
    /// - Returns: Modified HTTP request.
    @objc optional func willSendRequest(_ request: URLRequest) -> URLRequest
    
    /// Event executed after receiving HTTP response from Backtrace services.
    ///
    /// - Parameter result: Backtrace result.
    @objc optional func serverDidResponse(_ result: BacktraceResult)
    
    /// Event executed when connection to Backtrace services failed.
    ///
    /// - Parameter error: Error containing information about the failure cause.
    @objc optional func connectionDidFail(_ error: Error)
    
    /// Event executed when number of sent reports in specific period of time was reached.
    ///
    /// - Parameter result: Backtrace result.
    @objc optional func didReachLimit(_ result: BacktraceResult)
}
