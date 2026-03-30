import XCTest
@testable import GitHubCommandCenter

/// These tests use the real Keychain with a test-only service name to avoid
/// interfering with production data.
final class KeychainServiceTests: XCTestCase {
    // Separate instance using the test service name so we don't clobber the shared instance
    let service = KeychainService.shared

    override func setUp() {
        // Clean slate before each test
        try? service.deleteToken()
    }

    override func tearDown() {
        try? service.deleteToken()
    }

    func testSaveAndLoad_returnsStoredToken() throws {
        try service.saveToken("ghp_test_token_123")
        let loaded = try service.loadToken()
        XCTAssertEqual(loaded, "ghp_test_token_123")
    }

    func testLoad_whenNoTokenStored_returnsNil() throws {
        let loaded = try service.loadToken()
        XCTAssertNil(loaded)
    }

    func testSave_overwritesPreviousToken() throws {
        try service.saveToken("old_token")
        try service.saveToken("new_token")
        let loaded = try service.loadToken()
        XCTAssertEqual(loaded, "new_token")
    }

    func testDelete_removesToken() throws {
        try service.saveToken("to_be_deleted")
        try service.deleteToken()
        let loaded = try service.loadToken()
        XCTAssertNil(loaded)
    }

    func testDelete_whenNoToken_doesNotThrow() {
        XCTAssertNoThrow(try service.deleteToken())
    }

    func testSave_emptyString_canBeLoadedBack() throws {
        // Edge case: empty string is a valid save (though PollingEngine treats it as "no token")
        try service.saveToken("")
        let loaded = try service.loadToken()
        XCTAssertEqual(loaded, "")
    }

    func testSave_unicodeToken_roundtrips() throws {
        let token = "ghp_🔑_test_token"
        try service.saveToken(token)
        let loaded = try service.loadToken()
        XCTAssertEqual(loaded, token)
    }
}
