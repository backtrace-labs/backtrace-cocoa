import Foundation
import Security
import CommonCrypto

/// End-to-end encryption for session data using RSA key exchange + AES-256-CBC.
///
/// Uses Apple's built-in Security.framework and CommonCrypto — no external dependencies.
///
/// Wire format: `[encrypted-AES-key-length (4 bytes LE)] [encrypted-AES-key] [IV (16 bytes)] [AES-ciphertext]`
final class BacktraceSessionEncryption {

    private let rsaPublicKey: SecKey

    /// Initialize with an RSA public key in DER (Base64-encoded) format.
    ///
    /// - Parameter publicKeyBase64: Base64-encoded DER representation of the RSA public key.
    /// - Returns: nil if the key cannot be parsed.
    init?(publicKeyBase64: String) {
        guard let keyData = Data(base64Encoded: publicKeyBase64.trimmingPEMHeaders()) else {
            BacktraceLogger.error("BacktraceSessionEncryption: Invalid Base64 key data")
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: keyData.count * 8
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            BacktraceLogger.error("BacktraceSessionEncryption: Failed to create SecKey: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }

        self.rsaPublicKey = key
    }

    /// Encrypt data using AES-256-CBC with a randomly generated key, then encrypt the
    /// AES key with RSA.
    ///
    /// - Parameter data: The plaintext data to encrypt.
    /// - Returns: Encrypted data in the wire format, or nil on failure.
    func encrypt(_ data: Data) -> Data? {
        // Generate random AES-256 key (32 bytes) and IV (16 bytes)
        var aesKey = Data(count: kCCKeySizeAES256)
        var iv = Data(count: kCCBlockSizeAES128)

        let keyResult = aesKey.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, kCCKeySizeAES256, $0.baseAddress!) }
        let ivResult = iv.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128, $0.baseAddress!) }

        guard keyResult == errSecSuccess, ivResult == errSecSuccess else {
            BacktraceLogger.error("BacktraceSessionEncryption: Failed to generate random bytes")
            return nil
        }

        // AES-256-CBC encrypt the data
        guard let ciphertext = aesEncrypt(data: data, key: aesKey, iv: iv) else {
            return nil
        }

        // RSA encrypt the AES key
        guard let encryptedKey = rsaEncrypt(data: aesKey) else {
            return nil
        }

        // Assemble wire format
        var result = Data()
        var keyLength = UInt32(encryptedKey.count).littleEndian
        result.append(Data(bytes: &keyLength, count: 4))
        result.append(encryptedKey)
        result.append(iv)
        result.append(ciphertext)

        return result
    }

    // MARK: - Private: AES

    private func aesEncrypt(data: Data, key: Data, iv: Data) -> Data? {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var bytesEncrypted = 0

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    buffer.withUnsafeMutableBytes { bufferBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES256,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            bufferBytes.baseAddress, bufferSize,
                            &bytesEncrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            BacktraceLogger.error("BacktraceSessionEncryption: AES encryption failed with status \(status)")
            return nil
        }

        return buffer.prefix(bytesEncrypted)
    }

    // MARK: - Private: RSA

    private func rsaEncrypt(data: Data) -> Data? {
        let algorithm = SecKeyAlgorithm.rsaEncryptionOAEPSHA256

        guard SecKeyIsAlgorithmSupported(rsaPublicKey, .encrypt, algorithm) else {
            BacktraceLogger.error("BacktraceSessionEncryption: RSA algorithm not supported")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(rsaPublicKey, algorithm, data as CFData, &error) else {
            BacktraceLogger.error("BacktraceSessionEncryption: RSA encryption failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }

        return encryptedData as Data
    }
}

// MARK: - String PEM Helper

private extension String {
    /// Strip PEM headers/footers and whitespace, returning just the Base64 body.
    func trimmingPEMHeaders() -> String {
        return self
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
