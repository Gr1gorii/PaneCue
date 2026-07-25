import Foundation
import PaneCueCore
import Security

enum OpenAIAPIKeyStoreError: LocalizedError {
    case emptyKey
    case unreadableStoredKey
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Nothing was pasted. Copy the full secret key from your password manager and try again."
        case .unreadableStoredKey:
            return "The saved OpenAI API key could not be read."
        case let .keychainFailure(status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return "PaneCue could not access macOS Keychain\(detail.map { ": \($0)" } ?? ".")"
        }
    }
}

@MainActor
final class OpenAIAPIKeyStore {
    private let service = PaneCueIdentity.subsystem("openai")
    private let account = "OPENAI_API_KEY"
    private var cachedKey: String?

    var hasKey: Bool {
        if cachedKey != nil {
            return true
        }

        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip

        var result: CFTypeRef?
        return SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess
    }

    func load() throws -> String? {
        if let cachedKey {
            return cachedKey
        }

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw OpenAIAPIKeyStoreError.keychainFailure(status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else {
            throw OpenAIAPIKeyStoreError.unreadableStoredKey
        }

        cachedKey = key
        return key
    }

    func save(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw OpenAIAPIKeyStoreError.emptyKey
        }

        let data = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            cachedKey = normalized
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw OpenAIAPIKeyStoreError.keychainFailure(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIAPIKeyStoreError.keychainFailure(addStatus)
        }
        cachedKey = normalized
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIAPIKeyStoreError.keychainFailure(status)
        }
        cachedKey = nil
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
