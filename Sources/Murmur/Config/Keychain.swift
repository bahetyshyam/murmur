import Foundation
import Security

/// Thin Security.framework wrapper for storing the OpenAI API key.
///
/// Reuses the exact slot the Python prototype wrote to via the `keyring`
/// library so the user's existing key carries over with no re-entry:
///   service = "murmur"
///   account = "openai_api_key"
///   class   = kSecClassGenericPassword
enum Keychain {
    /// Canonical slot for the live API key.
    static let openAIKey = Slot(service: "murmur", account: "openai_api_key")

    struct Slot: Equatable {
        let service: String
        let account: String
    }

    enum KeychainError: Error, CustomStringConvertible {
        case unexpectedStatus(OSStatus)
        case dataEncoding

        var description: String {
            switch self {
            case .unexpectedStatus(let s): return "Keychain OSStatus \(s)"
            case .dataEncoding: return "Keychain value was not valid UTF-8"
            }
        }
    }

    /// Read the secret. Returns nil if absent.
    static func read(_ slot: Slot) throws -> String? {
        var query = baseQuery(slot)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        // Match any sync state — `keyring` may have written with a different
        // sync attribute than we'd use, and we don't want to miss the item.
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data,
                  let text = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataEncoding
            }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Create or overwrite the secret.
    static func write(_ slot: Slot, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataEncoding
        }
        // Try update first; fall back to add. This preserves any existing
        // attributes on the item (e.g., access-control lists) instead of
        // wiping + recreating.
        let update: [String: Any] = [kSecValueData as String: data]
        var query = baseQuery(slot)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break // fall through to add
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var add = baseQuery(slot)
        add[kSecValueData as String] = data
        // Keep on-device. Don't sync via iCloud Keychain — this is a local
        // developer tool, not something the user would expect to appear on
        // another Mac.
        add[kSecAttrSynchronizable as String] = false
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Delete the secret. No-op if it doesn't exist.
    static func delete(_ slot: Slot) throws {
        var query = baseQuery(slot)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(_ slot: Slot) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.service,
            kSecAttrAccount as String: slot.account,
        ]
    }
}
