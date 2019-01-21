
import Foundation

protocol NetworkClientType {
    @discardableResult
    func send(_ report: Data) throws -> BacktraceResponse
}
