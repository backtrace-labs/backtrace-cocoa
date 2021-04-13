import Foundation
import XCTest
@testable import Backtrace

struct ReportMetadataStorageMock: ReportMetadataStorage {
    static var fileSystemMock = [String: NSDictionary]()
    
    static func storeToFile(_ dictionary: NSDictionary, config: Config) throws {
        fileSystemMock[config.fileUrl.path] = dictionary
    }
    
    static func retrieveFromFile(config: Config) throws -> NSDictionary {
        return fileSystemMock[config.fileUrl.path]!
    }
    
    static func removeFile(config: Config) throws {
        fileSystemMock.removeValue(forKey: config.fileUrl.path)
    }
}
