import Foundation

/// Events produced by `BacktraceClient` class.
@objc public protocol BacktraceClientDelegate: class {

    /// Event executed before sending report data to Backtrace services.
    /// Allows the delegate object to modify report right before sending.
    ///
    /// - Parameter report: Backtrace report to send.
    /// - Returns: Modified Backtrace report.
    @objc optional func willSend(_ report: BacktraceReport) -> BacktraceReport

    /// Event executed before HTTP request to Backtrace services is made.
    /// Allows the delegate object to modify request right before sending.
    ///
    /// - Parameter request: HTTP request to send.
    /// - Returns: Modified HTTP request.
    @objc optional func willSendRequest(_ request: URLRequest) -> URLRequest

    /// Event executed after receiving HTTP response from Backtrace services.
    /// Allows the delegate object to react after receiving a response.
    ///
    /// - Parameter result: Backtrace result.
    @available(*, renamed: "serverDidResponse")
    @objc optional func serverDidRespond(_ result: BacktraceResult)

    /// Event executed when connection to Backtrace services failed.
    /// Allows the delegate object to react when connection fails.
    ///
    /// - Parameter error: Error containing information about the failure cause.
    @objc optional func connectionDidFail(_ error: Error)

    /// Event executed when number of sent reports in specific period of time was reached.
    ///
    /// - Parameter result: Backtrace result.
    @objc optional func didReachLimit(_ result: BacktraceResult)
}
