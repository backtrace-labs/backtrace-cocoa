import Foundation

@objc open class BacktraceResult: NSObject {

    @objc public let status: BacktraceResultStatus
    @objc public let message: String

    init(_ status: BacktraceResultStatus) {
        self.status = status
        self.message = status.description
    }

    init(status: BacktraceResultStatus, message: String) {
        self.status = status
        self.message = message
    }
}

private extension BacktraceResultStatus {
    var description: String {
        switch self {
        case .serverError:
            return "Unknown server error occurred."
        case .ok:
            return "Ok."
        case .notRegisterd:
            return "Backtrace client is not registered."
        }
    }
}
