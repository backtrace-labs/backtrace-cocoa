import Foundation

final class BacktraceFileManager {
    static let fileManger = FileManager.default

    /// Returns size of file in bytes.
    static func sizeOfFile(at url: URL) throws -> Int {
        guard url.isFileURL else {
            throw FileError.unsupportedScheme
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileError.fileNotExists
        }
        let resourceKeys = Set([URLResourceKey.fileSizeKey])
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard let fileSize = values.fileSize else { throw FileError.resourceValueUnavailable }
        return fileSize
    }

    /// Excluded file from backup to iTunes or iCloud
    ///
    /// - Parameter url: URL to be excluded from backup.
    static func excludeFromBackup(_ url: URL) throws {
        var url = url
        guard url.isFileURL else {
            throw FileError.unsupportedScheme
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileError.fileNotExists
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
    }
}
