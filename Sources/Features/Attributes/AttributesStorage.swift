import Foundation

enum AttributesStorage {
    struct AttributesConfig: Config {
        let cacheUrl: URL
        let directoryUrl: URL
        let fileUrl: URL

        init(fileName: String, directoryUrl explicitDirectoryUrl: URL? = nil) throws {
            if let explicitDirectoryUrl = explicitDirectoryUrl {
                self.cacheUrl = explicitDirectoryUrl
                self.directoryUrl = explicitDirectoryUrl
                self.fileUrl = explicitDirectoryUrl.appendingPathComponent("\(fileName).plist")
                return
            }

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

    static func store(_ attributes: Attributes, fileName: String, directoryUrl: URL? = nil) throws {
        try store(attributes,
                  fileName: fileName,
                  directoryUrl: directoryUrl,
                  storage: ReportMetadataStorageImpl.self)
    }

    static func store<T: ReportMetadataStorage>(_ attributes: Attributes, fileName: String, storage: T.Type) throws {
        try store(attributes, fileName: fileName, directoryUrl: nil, storage: storage)
    }

    static func store<T: ReportMetadataStorage>(_ attributes: Attributes,
                                                 fileName: String,
                                                 directoryUrl: URL?,
                                                 storage: T.Type) throws {
        let config = try AttributesConfig(fileName: fileName, directoryUrl: directoryUrl)
        try T.storeToFile(attributes, config: config)
        BacktraceLogger.debug("Stored attributes at path: \(config.fileUrl)")
    }

    static func retrieve(fileName: String, directoryUrl: URL? = nil) throws -> Attributes {
        try retrieve(fileName: fileName,
                     directoryUrl: directoryUrl,
                     storage: ReportMetadataStorageImpl.self)
    }

    static func retrieve<T: ReportMetadataStorage>(fileName: String, storage: T.Type) throws -> Attributes {
        try retrieve(fileName: fileName, directoryUrl: nil, storage: storage)
    }

    static func retrieve<T: ReportMetadataStorage>(fileName: String,
                                                    directoryUrl: URL?,
                                                    storage: T.Type) throws -> Attributes {
        let config = try AttributesConfig(fileName: fileName, directoryUrl: directoryUrl)
        let dictionary = try T.retrieveFromFile(config: config)
        // cast safely to AttributesType
        let attributes: Attributes = dictionary as Attributes
        BacktraceLogger.debug("Retrieved attributes from path: \(config.fileUrl)")
        return attributes
    }

    static func remove(fileName: String, directoryUrl: URL? = nil) throws {
        try remove(fileName: fileName,
                   directoryUrl: directoryUrl,
                   storage: ReportMetadataStorageImpl.self)
    }

    static func remove<T: ReportMetadataStorage>(fileName: String, storage: T.Type) throws {
        try remove(fileName: fileName, directoryUrl: nil, storage: storage)
    }

    static func remove<T: ReportMetadataStorage>(fileName: String,
                                                  directoryUrl: URL?,
                                                  storage: T.Type) throws {
        let config = try AttributesConfig(fileName: fileName, directoryUrl: directoryUrl)
        try T.removeFile(config: config)
        BacktraceLogger.debug("Removed attributes at path: \(config.fileUrl)")
    }
}
