import Foundation

@objc open class BacktraceMetricsResult: NSObject {

    @objc public var statusCode: Int

    init(_ statusCode: Int) {
        self.statusCode = statusCode
    }
}
