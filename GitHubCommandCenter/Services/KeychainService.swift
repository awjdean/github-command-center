import Foundation
import Security

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let serviceName: String
    private let accountName: String

    init(serviceName: String = "com.githubcommandcenter", accountName: String = "github-pat") {
        self.serviceName = serviceName
        self.accountName = accountName
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountName,
        ]

        let addQuery = query.merging([kSecValueData: data] as [CFString: Any]) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateAttributes: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.saveFailed(status: updateStatus)
            }
            return
        }

        guard addStatus == errSecSuccess else {
            throw KeychainError.saveFailed(status: addStatus)
        }
    }

    func loadToken() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountName,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.loadFailed(status: errSecInternalError)
            }
            guard let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status: status)
        }
    }

    func deleteToken() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: accountName,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    enum KeychainError: LocalizedError, Equatable {
        case decodingFailed
        case saveFailed(status: OSStatus)
        case loadFailed(status: OSStatus)
        case deleteFailed(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .decodingFailed:
                return "Stored token data could not be decoded as UTF-8."
            case .saveFailed(let status): return "Failed to save token (OSStatus \(status))"
            case .loadFailed(let status): return "Failed to load token (OSStatus \(status))"
            case .deleteFailed(let status): return "Failed to delete token (OSStatus \(status))"
            }
        }
    }
}
