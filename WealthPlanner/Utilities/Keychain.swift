import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case duplicateEntry
    case unknown(OSStatus)
    case notFound
    case unexpectedData
    case encodingError

    var errorDescription: String? {
        switch self {
        case .duplicateEntry:
            return "An item with this key already exists"
        case .unknown(let status):
            return "Keychain error: \(status)"
        case .notFound:
            return "Item not found in keychain"
        case .unexpectedData:
            return "Unexpected data format in keychain"
        case .encodingError:
            return "Failed to encode data"
        }
    }
}

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.wealthplanner.app"

    private init() {}

    func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            try update(data, forKey: key)
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    func save(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        try save(data, forKey: key)
    }

    func save<T: Encodable>(_ object: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(object)
        try save(data, forKey: key)
    }

    private func update(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    func read(forKey key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.unknown(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }

    func readString(forKey key: String) throws -> String {
        let data = try read(forKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }

    func read<T: Decodable>(forKey key: String, as type: T.Type) throws -> T {
        let data = try read(forKey: key)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unknown(status)
        }
    }

    func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unknown(status)
        }
    }
}

// MARK: - Plaid Token Storage

extension KeychainManager {
    private static let plaidAccessTokenPrefix = "plaid_access_token_"
    private static let plaidItemIdKey = "plaid_item_ids"

    func savePlaidAccessToken(_ token: String, forItemId itemId: String) throws {
        try save(token, forKey: Self.plaidAccessTokenPrefix + itemId)

        var itemIds = (try? read(forKey: Self.plaidItemIdKey, as: [String].self)) ?? []
        if !itemIds.contains(itemId) {
            itemIds.append(itemId)
            try save(itemIds, forKey: Self.plaidItemIdKey)
        }
    }

    func getPlaidAccessToken(forItemId itemId: String) throws -> String {
        try readString(forKey: Self.plaidAccessTokenPrefix + itemId)
    }

    func deletePlaidAccessToken(forItemId itemId: String) throws {
        try delete(forKey: Self.plaidAccessTokenPrefix + itemId)

        var itemIds = (try? read(forKey: Self.plaidItemIdKey, as: [String].self)) ?? []
        itemIds.removeAll { $0 == itemId }
        try save(itemIds, forKey: Self.plaidItemIdKey)
    }

    func getAllPlaidItemIds() -> [String] {
        (try? read(forKey: Self.plaidItemIdKey, as: [String].self)) ?? []
    }
}
