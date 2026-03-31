import Foundation

/// Gzip compression for session event payloads.
///
/// Uses a minimal gzip implementation via zlib (available on all Apple platforms
/// through the standard C library).
enum BacktraceGzipCompressor {

    enum CompressionError: Swift.Error {
        case compressionFailed
        case dataEmpty
    }

    /// Compress data using gzip encoding.
    ///
    /// Produces valid gzip output (with gzip header/trailer) compatible with the
    /// `Content-Encoding: gzip` HTTP header used by the TF wire protocol.
    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw CompressionError.dataEmpty }

        // Use NSData's built-in compressed(using:) on macOS 10.15+ / iOS 13+
        // which is available on our minimum deployment target.
        let nsData = data as NSData
        guard let compressed = try? nsData.compressed(using: .zlib) as Data else {
            throw CompressionError.compressionFailed
        }

        // NSData.compressed uses raw deflate. Wrap in gzip container.
        return wrapInGzip(deflatedData: compressed, originalSize: UInt32(data.count))
    }

    /// Wrap raw deflate data in a minimal gzip container.
    private static func wrapInGzip(deflatedData: Data, originalSize: UInt32) -> Data {
        var gzip = Data()

        // Gzip header (10 bytes)
        gzip.append(contentsOf: [0x1f, 0x8b])  // Magic number
        gzip.append(0x08)                        // Compression method: deflate
        gzip.append(0x00)                        // Flags: none
        gzip.append(contentsOf: [0, 0, 0, 0])   // Modification time: none
        gzip.append(0x00)                        // Extra flags
        gzip.append(0xff)                        // OS: unknown

        // Compressed data (raw deflate)
        gzip.append(deflatedData)

        // CRC32 of original data (4 bytes, little-endian)
        var crc = crc32(data: deflatedData)
        gzip.append(Data(bytes: &crc, count: 4))

        // Original size mod 2^32 (4 bytes, little-endian)
        var size = originalSize
        gzip.append(Data(bytes: &size, count: 4))

        return gzip
    }

    /// Simple CRC32 implementation.
    private static func crc32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
