import Foundation
import Security
import Testing
@testable import GitHubCommandCenter

@Suite
struct KeychainServiceTests {
    @Test
    func saveAndLoad_returnsStoredToken() throws {
        let service = makeService()
        try service.saveToken("ghp_test_token_123")

        let loaded = try service.loadToken()

        #expect(loaded == "ghp_test_token_123")
        try? service.deleteToken()
    }

    @Test
    func load_whenNoTokenStored_returnsNil() throws {
        let service = makeService()

        let loaded = try service.loadToken()

        #expect(loaded == nil)
    }

    @Test
    func save_overwritesPreviousToken() throws {
        let service = makeService()
        try service.saveToken("old_token")
        try service.saveToken("new_token")

        let loaded = try service.loadToken()

        #expect(loaded == "new_token")
        try? service.deleteToken()
    }

    @Test
    func delete_removesToken() throws {
        let service = makeService()
        try service.saveToken("to_be_deleted")
        try service.deleteToken()

        let loaded = try service.loadToken()

        #expect(loaded == nil)
    }

    @Test
    func delete_whenNoToken_doesNotThrow() throws {
        let service = makeService()
        try service.deleteToken()
    }

    @Test
    func save_emptyString_canBeLoadedBack() throws {
        let service = makeService()
        try service.saveToken("")

        let loaded = try service.loadToken()

        #expect(loaded == "")
        try? service.deleteToken()
    }

    @Test
    func save_unicodeToken_roundtrips() throws {
        let service = makeService()
        let token = "ghp_🔑_test_token"
        try service.saveToken(token)

        let loaded = try service.loadToken()

        #expect(loaded == token)
        try? service.deleteToken()
    }

    @Test
    func load_whenStoredDataIsInvalidUTF8_throwsDecodingFailed() throws {
        let serviceName = uniqueServiceName()
        let service = KeychainService(serviceName: serviceName)
        try storeRawTokenData(Data([0xFF, 0xFE, 0xFD]), serviceName: serviceName)

        do {
            _ = try service.loadToken()
            Issue.record("Expected a decodingFailed error")
        } catch let error as KeychainService.KeychainError {
            #expect(error == .decodingFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        try? service.deleteToken()
    }

    private func makeService() -> KeychainService {
        KeychainService(serviceName: uniqueServiceName())
    }

    private func uniqueServiceName() -> String {
        "com.githubcommandcenter.tests.\(UUID().uuidString)"
    }

    private func storeRawTokenData(_ data: Data, serviceName: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: "github-pat"
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)
        #expect(deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound)

        let addQuery = query.merging([kSecValueData: data] as [CFString: Any]) { _, new in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        #expect(status == errSecSuccess)
    }
}
