import XCTest
@testable import Backtrace

struct AttachedDebuggerCheckerMock: DebuggerChecking {
    static func isAttached() -> Bool {
        return true
    }
}

struct DetachedDebuggerCheckerMock: DebuggerChecking {
    static func isAttached() -> Bool {
        return false
    }
}
