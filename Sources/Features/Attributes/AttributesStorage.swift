import Foundation

enum AttributesStorage: ReportMetadataStorage {
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
        let config = try AttributesConfig(fileName: fileName)
        try storeToFile(attributes as NSDictionary, config: config)
        BacktraceLogger.debug("Stored attributes at path: \(config.fileUrl)")
    }
    
    static func retrieve(fileName: String) throws -> Attributes {
        let config = try AttributesConfig(fileName: fileName)
        let dictionary = try retrieveFromFile(config: config)
        // cast safely to AttributesType
        guard let attributes: Attributes = dictionary as? Attributes else {
            throw FileError.invalidPropertyList
        }
        BacktraceLogger.debug("Retrieved attributes from path: \(config.fileUrl)")
        return attributes
    }
        
    static func remove(fileName: String) throws {
        let config = try AttributesConfig(fileName: fileName)
        try removeFile(config: config)
        BacktraceLogger.debug("Removed attributes at path: \(config.fileUrl)")
    }
}
