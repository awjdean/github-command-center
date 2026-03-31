import Security
import Testing

@testable import GitHubCommandCenter

@Suite
struct SettingsValidationTests {
    @Test
    func tokenSaveSuccess_verifiedResult_setsValidStateWithoutWarning() {
        let outcome = SettingsContentView.tokenSaveSuccessOutcome(
            for: .verified(username: "octocat")
        )

        #expect(outcome.tokenState == SettingsContentView.TokenState.valid(username: "octocat"))
        #expect(outcome.warningMessage == nil)
    }

    @Test
    func tokenSaveSuccess_warningResult_setsValidStateAndWarning() {
        let outcome = SettingsContentView.tokenSaveSuccessOutcome(
            for: .warning(
                username: "octocat",
                message: "Status access could not be fully verified."
            )
        )

        #expect(outcome.tokenState == SettingsContentView.TokenState.valid(username: "octocat"))
        #expect(outcome.warningMessage == "Status access could not be fully verified.")
    }

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
        #expect(outcome.message?.contains("-25308") == true)
    }
}
