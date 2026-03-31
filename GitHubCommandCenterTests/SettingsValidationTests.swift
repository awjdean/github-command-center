import Security
import Testing

@testable import GitHubCommandCenter

@Suite
struct SettingsValidationTests {
    @Test
    func tokenSaveFailure_authError_marksTokenInvalid() {
        let outcome = SettingsContentView.tokenSaveFailureOutcome(for: AppError.authError)

        #expect(outcome.tokenState == SettingsContentView.TokenState.invalid)
        #expect(outcome.message == nil)
    }

    @Test
    func tokenSaveFailure_retryableAppError_keepsTokenUnvalidated() {
        let outcome = SettingsContentView.tokenSaveFailureOutcome(for: AppError.networkError)

        #expect(outcome.tokenState == SettingsContentView.TokenState.unvalidated)
        #expect(outcome.message == AppError.networkError.errorDescription)
    }

    @Test
    func tokenSaveFailure_keychainError_keepsTokenUnvalidated() {
        let outcome = SettingsContentView.tokenSaveFailureOutcome(
            for: KeychainService.KeychainError.saveFailed(status: errSecInteractionNotAllowed)
        )

        #expect(outcome.tokenState == SettingsContentView.TokenState.unvalidated)
        #expect(outcome.message == "Failed to save token (OSStatus -25308)")
    }
}
