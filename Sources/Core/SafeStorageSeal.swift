import CommonCrypto
import Foundation

/// Electron safeStorage 在 macOS 上的封包。口令来自钥匙串，算法沿用 Chromium OSCrypt。
enum SafeStorageSeal {
    static let envelopePrefix = "cursor-safe-storage:v1:"

    private static let versionPrefix = Data("v10".utf8)
    private static let salt = Array("saltysalt".utf8)
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16
    private static let iv = [UInt8](repeating: 0x20, count: 16)

    static func isSealed(_ value: String) -> Bool {
        value.hasPrefix(envelopePrefix)
    }

    static func open(_ stored: String, password: Data) throws -> String {
        guard isSealed(stored) else { throw QuotaError.loginUnreadable }
        let encoded = String(stored.dropFirst(envelopePrefix.count))
        guard let blob = Data(base64Encoded: encoded) else { throw QuotaError.loginUnreadable }
        guard blob.starts(with: versionPrefix) else { throw QuotaError.loginUnreadable }
        let ciphertext = [UInt8](blob.dropFirst(versionPrefix.count))
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: iv.count) else {
            throw QuotaError.loginUnreadable
        }
        let key = try derivedKey(password: password)
        let plain = try decrypt(ciphertext, key: key)
        guard let text = String(data: plain, encoding: .utf8), !text.isEmpty else {
            throw QuotaError.loginUnreadable
        }
        return text
    }

    private static func derivedKey(password: Data) throws -> [UInt8] {
        guard !password.isEmpty else { throw QuotaError.loginUnreadable }
        let passwordBytes = [UInt8](password)
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = key.withUnsafeMutableBytes { keyBytes in
            passwordBytes.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: CChar.self).baseAddress,
                        passwordBytes.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        iterations,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw QuotaError.loginUnreadable }
        return key
    }

    private static func decrypt(_ ciphertext: [UInt8], key: [UInt8]) throws -> Data {
        let outputCount = ciphertext.count
        var output = [UInt8](repeating: 0, count: outputCount)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCount,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, moved > 0 else { throw QuotaError.loginUnreadable }
        return Data(output.prefix(moved))
    }
}
