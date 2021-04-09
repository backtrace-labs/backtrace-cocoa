import Foundation

protocol Config {
    var cacheUrl: URL { get }
    var directoryUrl: URL { get }
    var fileUrl: URL { get }
}

protocol ReportMetadataStorage {
    static func storeToFile(_ dictionary: NSDictionary, config: Config) throws
    static func retrieveFromFile(config: Config) throws -> NSDictionary
    static func removeFile(config: Config) throws
}

extension ReportMetadataStorage {
    static func storeToFile(_ dictionary: NSDictionary, config: Config) throws {
        if !FileManager.default.fileExists(atPath: config.directoryUrl.path) {
            try FileManager.default.createDirectory(atPath: config.directoryUrl.path,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        }
        
        if #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
            try (dictionary).write(to: config.fileUrl)
        } else {
            guard (dictionary).write(to: config.fileUrl, atomically: true) else {
                throw FileError.fileNotWritten
            }
        }
    }
    
    static func retrieveFromFile(config: Config) throws -> NSDictionary {
        guard FileManager.default.fileExists(atPath: config.fileUrl.path) else {
            throw FileError.fileNotExists
        }
        // load file to NSDictionary
        let dictionary: NSDictionary
        if #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
            dictionary = try NSDictionary(contentsOf: config.fileUrl, error: ())
        } else {
            guard let dictionaryFromFile = NSDictionary(contentsOf: config.fileUrl) else {
                throw FileError.invalidPropertyList
            }
            dictionary = dictionaryFromFile
        }
        return dictionary
    }
    
    static func removeFile(config: Config) throws {
        guard FileManager.default.fileExists(atPath: config.fileUrl.path) else {
            throw FileError.fileNotExists
        }
        try FileManager.default.removeItem(at: config.fileUrl)
    }
}
