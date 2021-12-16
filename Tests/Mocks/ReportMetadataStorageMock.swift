import Foundation
import XCTest
@testable import Backtrace

struct ReportMetadataStorageMock: ReportMetadataStorage {
    static var fileSystemMock = [String: [String: Any]]()

    static func storeToFile(_ dictionary: [String: Any], config: Config) throws {
        fileSystemMock[config.fileUrl.path] = dictionary
    }

    static func retrieveFromFile(config: Config) throws -> [String: Any] {
        return fileSystemMock[config.fileUrl.path]!
    }

    static func removeFile(config: Config) throws {
        fileSystemMock.removeValue(forKey: config.fileUrl.path)
    }
}
