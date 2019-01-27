import Foundation

final class BacktraceFileManager {
    static let fileManger = FileManager.default
    
    /// Returns size of file in bytes.
    static func sizeOfFile(at url: URL) throws -> Int {
        guard url.isFileURL else {
            throw FileError.unsupportedScheme
        }
        //TODO: Check if file exists
        let resourceKeys = Set([URLResourceKey.fileSizeKey])
        let values = try url.resourceValues(forKeys: resourceKeys)
        guard let fileSize = values.fileSize else { throw FileError.resourceValueUnavailable }
        return fileSize
    }
}
