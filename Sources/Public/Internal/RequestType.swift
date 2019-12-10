import Foundation

protocol RequestType {
    func urlRequest() throws -> URLRequest
}
