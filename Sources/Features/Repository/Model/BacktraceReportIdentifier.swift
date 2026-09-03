import CryptoKit
import Foundation

#if BACKTRACE_UNITY_PREFIXED_PLCRASHREPORTER
import BTUnityCrashReporter
#else
import CrashReporter
#endif

enum BacktraceReportIdentifier {
    /// Produces a stable UUID for a pending PLCrashReporter payload.
    ///
    /// The report bytes are immutable once PLCrashReporter exposes them as pending.
    /// A stable identifier makes ingestion idempotent when persistence succeeds but purging the PLCrashReporter source does not.
    static func pendingReportIdentifier(for reportData: Data) -> UUID {
        return pendingReportIdentifier(embeddedIdentifier: embeddedIdentifier(for: reportData),
                                       reportData: reportData)
    }

    /// Prefers PLCrashReporter's client-generated identifier and falls back to the immutable payload digest.
    static func pendingReportIdentifier(embeddedIdentifier: UUID?, reportData: Data) -> UUID {
        return embeddedIdentifier ?? digestIdentifier(for: reportData)
    }

    static func embeddedIdentifier(for reportData: Data) -> UUID? {
        guard let crashReport = try? PLCrashReport(data: reportData),
              let uuidRef = crashReport.uuidRef else {
            return nil
        }

        let bytes = CFUUIDGetUUIDBytes(uuidRef)
        return UUID(uuid: uuid_t(bytes.byte0, bytes.byte1, bytes.byte2, bytes.byte3,
                                 bytes.byte4, bytes.byte5, bytes.byte6, bytes.byte7,
                                 bytes.byte8, bytes.byte9, bytes.byte10, bytes.byte11,
                                 bytes.byte12, bytes.byte13, bytes.byte14, bytes.byte15))
    }

    static func digestIdentifier(for reportData: Data) -> UUID {
        var bytes = Array(SHA256.hash(data: reportData).prefix(16))

        // RFC 4122 variant plus a name-based version bit pattern. The payload hash remains the source of all identifier entropy;
        // these bits simply make the resulting value a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        return UUID(uuid: uuid_t(bytes[0], bytes[1], bytes[2], bytes[3],
                                 bytes[4], bytes[5], bytes[6], bytes[7],
                                 bytes[8], bytes[9], bytes[10], bytes[11],
                                 bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
