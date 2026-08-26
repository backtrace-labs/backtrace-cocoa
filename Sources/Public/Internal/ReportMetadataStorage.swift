import Foundation

protocol Config {
    var cacheUrl: URL { get }
    var directoryUrl: URL { get }
    var fileUrl: URL { get }
}

protocol ReportMetadataStorage {
    static func storeToFile(_ dictionary: [String: Any], config: Config) throws
    static func retrieveFromFile(config: Config) throws -> [String: Any]
    static func removeFile(config: Config) throws
}

enum ReportMetadataStorageImpl: ReportMetadataStorage {
    static func storeToFile(_ dictionary: [String: Any], config: Config) throws {
        if !FileManager.default.fileExists(atPath: config.directoryUrl.path) {
            try FileManager.default.createDirectory(at: config.directoryUrl,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])
        }

        let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                      format: .binary,
                                                      options: 0)
        try data.write(to: config.fileUrl, options: .atomic)
    }

    static func retrieveFromFile(config: Config) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: config.fileUrl.path) else {
            throw FileError.fileNotExists
        }
        // load file to NSDictionary
        let nsDictionary: NSDictionary
        if #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
            nsDictionary = try NSDictionary(contentsOf: config.fileUrl, error: ())
        } else {
            guard let dictionaryFromFile = NSDictionary(contentsOf: config.fileUrl) else {
                throw FileError.invalidPropertyList
            }
            nsDictionary = dictionaryFromFile
        }
        guard let dictionary = nsDictionary as? [String: Any] else {
            throw FileError.invalidPropertyList
        }
        return dictionary
    }

    static func removeFile(config: Config) throws {
        guard FileManager.default.fileExists(atPath: config.fileUrl.path) else { return }
        try FileManager.default.removeItem(at: config.fileUrl)
    }
}
