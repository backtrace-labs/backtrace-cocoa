import Foundation

enum AttributesStorage {
    struct AttributesConfig: Config {
        let cacheUrl: URL
        let directoryUrl: URL
        let fileUrl: URL

        init(fileName: String) throws {
            guard let cacheDirectoryURL =
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    throw FileError.noCacheDirectory
            }
            self.cacheUrl = cacheDirectoryURL
            self.directoryUrl = cacheDirectoryURL.appendingPathComponent(directoryName)
            self.fileUrl = directoryUrl.appendingPathComponent("\(fileName).plist")
        }
    }

    private static let directoryName = Bundle.main.bundleIdentifier ?? "BacktraceCache"

    static func store(_ attributes: Attributes, fileName: String) throws {
        try store(attributes, fileName: fileName, storage: ReportMetadataStorageImpl.self)
    }

    static func store<T: ReportMetadataStorage>(_ attributes: Attributes, fileName: String, storage: T.Type) throws {
        let config = try AttributesConfig(fileName: fileName)
        try T.storeToFile(attributes, config: config)
        BacktraceLogger.debug("Stored attributes at path: \(config.fileUrl)")
    }

    static func retrieve(fileName: String) throws -> Attributes {
        try retrieve(fileName: fileName, storage: ReportMetadataStorageImpl.self)
    }

    static func retrieve<T: ReportMetadataStorage>(fileName: String, storage: T.Type) throws -> Attributes {
        let config = try AttributesConfig(fileName: fileName)
        let dictionary = try T.retrieveFromFile(config: config)
        // cast safely to AttributesType
        let attributes: Attributes = dictionary as Attributes
        BacktraceLogger.debug("Retrieved attributes from path: \(config.fileUrl)")
        return attributes
    }

    static func remove(fileName: String) throws {
        try remove(fileName: fileName, storage: ReportMetadataStorageImpl.self)
    }

    static func remove<T: ReportMetadataStorage>(fileName: String, storage: T.Type) throws {
        let config = try AttributesConfig(fileName: fileName)
        try T.removeFile(config: config)
        BacktraceLogger.debug("Removed attributes at path: \(config.fileUrl)")
    }
}
