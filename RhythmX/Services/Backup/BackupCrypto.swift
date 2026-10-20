//
//  BackupCrypto.swift
//
//  Passphrase encryption for backup files.
//  Key: PBKDF2-HMAC-SHA256 (CommonCrypto). Cipher: AES-256-GCM (CryptoKit).
//  Blob layout: 16-byte salt | 4-byte big-endian iteration count | AES.GCM combined box (nonce | ciphertext | tag).
//

import CommonCrypto
import CryptoKit
import Foundation
import Security

enum BackupCrypto {
    static let defaultIterations = 600_000
    /// Upper bound on the iteration count accepted from a file, so a hostile file cannot hang the app.
    static let maxIterations = 2_000_000

    static let saltLength = 16
    private static let iterationFieldLength = 4
    private static let headerLength = saltLength + iterationFieldLength
    /// 12-byte nonce + 16-byte tag: the smallest possible combined box.
    private static let minimumBoxLength = 12 + 16

    static func seal(_ data: Data, passphrase: String, iterations: Int = defaultIterations) throws -> Data {
        precondition(iterations > 0 && iterations <= maxIterations, "iteration count out of range")

        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw BackupFileError.corrupted }

        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        guard let box = try AES.GCM.seal(data, using: key).combined else { throw BackupFileError.corrupted }

        let count = UInt32(iterations)
        var blob = salt
        blob.append(contentsOf: [
            UInt8(truncatingIfNeeded: count >> 24),
            UInt8(truncatingIfNeeded: count >> 16),
            UInt8(truncatingIfNeeded: count >> 8),
            UInt8(truncatingIfNeeded: count)
        ])
        blob.append(box)
        return blob
    }

    static func open(_ blob: Data, passphrase: String) throws -> Data {
        let bytes = [UInt8](blob)
        guard bytes.count >= headerLength + minimumBoxLength else { throw BackupFileError.corrupted }

        let salt = Data(bytes[0..<saltLength])
        let iterations = bytes[saltLength..<headerLength].reduce(0) { ($0 << 8) | Int($1) }
        guard iterations > 0, iterations <= maxIterations else { throw BackupFileError.corrupted }

        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
        } catch {
            throw BackupFileError.corrupted
        }

        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        do {
            return try AES.GCM.open(box, using: key)
        } catch {
            // GCM cannot tell a wrong key from tampered ciphertext; a wrong passphrase is by far the likely cause.
            throw BackupFileError.wrongPassphrase
        }
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordLength = passphrase.utf8.count
        let saltBytes = [UInt8](salt)
        var derived = [UInt8](repeating: 0, count: 32)
        // Zeroed on every exit, including a failed derivation.
        defer { derived.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        let status = passphrase.withCString { passwordPointer in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordPointer, passwordLength,
                saltBytes, saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw BackupFileError.corrupted }
        return SymmetricKey(data: derived)
    }
}
