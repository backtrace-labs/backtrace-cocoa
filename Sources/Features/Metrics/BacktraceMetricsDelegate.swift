import Foundation

/// Events produced by `BacktraceMetrics` class.
@objc public protocol BacktraceMetricsDelegate: class {
    /// Event executed before HTTP request to Backtrace services is made.
    /// Allows the delegate object to modify request right before sending.
    ///
    /// - Parameter request: HTTP request to send.
    /// - Returns: Modified HTTP request.
    @objc optional func willSendRequest(_ request: URLRequest) -> URLRequest

    /// Event executed after receiving HTTP response from Backtrace services.
    /// Allows the delegate object to react after receiving a response.
    ///
    /// - Parameter result: Backtrace metrics result.
    @objc optional func serverDidRespond(_ result: BacktraceMetricsResult)

    /// Event executed when connection to Backtrace services failed.
    /// Allows the delegate object to react when connection fails.
    ///
    /// - Parameter error: Error containing information about the failure cause.
    @objc optional func connectionDidFail(_ error: Error)
}
