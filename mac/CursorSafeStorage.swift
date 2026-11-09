import CommonCrypto
import Foundation

enum CursorSafeStorage {
    static let prefix = "cursor-safe-storage:v1:"

    static func resolveAccessToken(_ stored: String) -> String? {
        guard stored.hasPrefix(prefix) else { return stored }
        let encoded = String(stored.dropFirst(prefix.count))
        guard let ciphertext = Data(base64Encoded: encoded),
              let password = readKeychainPassword()
        else { return nil }
        return decrypt(ciphertext: ciphertext, password: password, iterations: 1003)
    }

    static func decrypt(ciphertext: Data, password: String, iterations: UInt32) -> String? {
        guard ciphertext.count > 3,
              let envelope = String(data: ciphertext.prefix(3), encoding: .utf8),
              envelope == "v10" || envelope == "v11"
        else { return nil }

        let salt = Data("saltysalt".utf8)
        let passwordData = Data(password.utf8)
        let keyLength = kCCKeySizeAES128
        var key = [UInt8](repeating: 0, count: keyLength)
        let deriveStatus = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                key.withUnsafeMutableBytes { keyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
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
        guard deriveStatus == kCCSuccess else { return nil }

        let encrypted = Data(ciphertext.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        let plaintextCapacity = encrypted.count + kCCBlockSizeAES128
        var plaintext = [UInt8](repeating: 0, count: plaintextCapacity)
        var plaintextCount = 0
        let decryptStatus = encrypted.withUnsafeBytes { encryptedBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    plaintext.withUnsafeMutableBytes { plaintextBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            encryptedBytes.baseAddress,
                            encrypted.count,
                            plaintextBytes.baseAddress,
                            plaintextCapacity,
                            &plaintextCount
                        )
                    }
                }
            }
        }
        guard decryptStatus == kCCSuccess else { return nil }
        return String(bytes: plaintext.prefix(plaintextCount), encoding: .utf8)
    }

    private static func readKeychainPassword() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password", "-s", "Cursor Safe Storage",
            "-a", "Cursor Key", "-w",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  var password = String(data: data, encoding: .utf8)
            else { return nil }
            if password.hasSuffix("\r\n") { password.removeLast(2) }
            else if password.hasSuffix("\n") { password.removeLast() }
            return password.isEmpty ? nil : password
        } catch {
            return nil
        }
    }
}
