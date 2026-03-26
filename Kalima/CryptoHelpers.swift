import Foundation
import CryptoKit

/// AES-256-GCM helpers for encrypting API keys before Firestore storage.
///
/// Key derivation: SHA-256(uid + appSalt)
/// This means each user's keys are encrypted with a unique key derived from their
/// Firebase UID. Even a Firestore data leak exposes only ciphertext.
enum CryptoHelpers {

    /// Must match across all app versions — changing this invalidates stored keys.
    private static let appSalt = "kalima-vocab-app-aes-v1"

    // MARK: - Key Derivation

    /// Derives a deterministic AES-256 SymmetricKey from the user's Firebase UID.
    static func symmetricKey(for uid: String) -> SymmetricKey {
        let input = (uid + appSalt).data(using: .utf8)!
        let hash = SHA256.hash(data: input)
        return SymmetricKey(data: hash)
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypts a plaintext string using AES-256-GCM.
    /// Returns a base64-encoded string (nonce + ciphertext + tag, as `combined`).
    /// Returns the original value unchanged if it's empty (no point encrypting empty strings).
    static func encrypt(_ plaintext: String, uid: String) throws -> String {
        guard !plaintext.isEmpty else { return plaintext }
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.encodingFailed
        }
        let key = symmetricKey(for: uid)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined.base64EncodedString()
    }

    /// Decrypts a base64-encoded AES-256-GCM ciphertext string.
    /// Returns the original value unchanged if it's empty.
    static func decrypt(_ ciphertext: String, uid: String) throws -> String {
        guard !ciphertext.isEmpty else { return ciphertext }
        guard let data = Data(base64Encoded: ciphertext) else {
            // Not a valid base64 string — might be a legacy unencrypted value, return as-is
            return ciphertext
        }
        let key = symmetricKey(for: uid)
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)
        return String(data: decrypted, encoding: .utf8) ?? ciphertext
    }

    enum CryptoError: Error {
        case encodingFailed
        case sealFailed
    }
}
