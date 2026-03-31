import Foundation
import Testing

@testable import GitHubCommandCenter

@MainActor
@Suite(.serialized)
struct PollingEngineTests {
    @MainActor
    private final class Harness {
        let appState = AppState()
        let mockSource = MockGitHubDataSource()
        let engine: PollingEngine

        init(recentlyClosedClearDelay: TimeInterval = 5) {
            engine = PollingEngine(
                appState: appState,
                dataSource: mockSource,
                recentlyClosedClearDelay: recentlyClosedClearDelay
            )
        }
    }

    @Test
    func pollInterval_fewerThan20PRs_is60s() {
        let harness = Harness()
        harness.appState.prs = Array(repeating: .fixture(), count: 5)

        #expect(harness.engine.pollInterval == 60)
    }

    @Test
    func pollInterval_20to39PRs_is120s() {
        let harness = Harness()
        harness.appState.prs = Array(repeating: .fixture(), count: 25)

        #expect(harness.engine.pollInterval == 120)
    }

    @Test
    func pollInterval_40orMorePRs_is300s() {
        let harness = Harness()
        harness.appState.prs = Array(repeating: .fixture(), count: 50)

        #expect(harness.engine.pollInterval == 300)
    }

    @Test
    func pollInterval_exactly20PRs_is120s() {
        let harness = Harness()
        harness.appState.prs = Array(repeating: .fixture(), count: 20)

        #expect(harness.engine.pollInterval == 120)
    }

    @Test
    func pollInterval_exactly40PRs_is300s() {
        let harness = Harness()
        harness.appState.prs = Array(repeating: .fixture(), count: 40)

        #expect(harness.engine.pollInterval == 300)
    }

    @Test
    func poll_updatesAppStatePRs() async {
        let harness = Harness()
        let pr = PRState.fixture(number: 1)
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .success([pr])

        await harness.engine.poll()

        #expect(harness.appState.prs.count == 1)
        #expect(harness.appState.prs.first?.number == 1)
    }

    @Test
    func poll_setsLastUpdated() async {
        let harness = Harness()
        harness.mockSource.fetchResult = .success([.fixture()])

        #expect(harness.appState.lastUpdated == nil)
        await harness.engine.poll()
        #expect(harness.appState.lastUpdated != nil)
    }

    @Test
    func poll_clearsError_onSuccess() async {
        let harness = Harness()
        harness.appState.error = .networkError
        harness.mockSource.fetchResult = .success([])

        await harness.engine.poll()

        #expect(harness.appState.error == nil)
    }

    @Test
    func poll_setsIsLoading_falseAfterSuccess() async {
        let harness = Harness()
        harness.appState.isLoading = true
        harness.mockSource.fetchResult = .success([])

        await harness.engine.poll()

        #expect(harness.appState.isLoading == false)
    }

    @Test
    func poll_firstPoll_doesNotFireNotifications() async {
        let harness = Harness()
        var firedCount = 0
        NotificationService.shared.notificationHandler = { _, _ in firedCount += 1 }
        defer { NotificationService.shared.notificationHandler = nil }

        let pr = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )
        harness.mockSource.fetchResult = .success([pr])

        await harness.engine.poll()

        #expect(firedCount == 0)
    }

    @Test
    func poll_PRDisappears_addedToRecentlyClosed() async {
        let harness = Harness()
        let pr = PRState.fixture(number: 99)
        harness.mockSource.resolvedDisappearedPRs = [pr]
        harness.mockSource.fetchResult = .success([pr])
        await harness.engine.poll()

        harness.mockSource.fetchResult = .success([])
        await harness.engine.poll()

        #expect(harness.appState.recentlyClosedPRs.count == 1)
        #expect(harness.appState.recentlyClosedPRs.first?.number == 99)
    }

    @Test
    func poll_PRDisappears_withoutConfirmedClosure_notMarkedRecentlyClosed() async {
        let harness = Harness()
        let pr = PRState.fixture(number: 99)
        harness.mockSource.fetchResult = .success([pr])
        await harness.engine.poll()

        harness.mockSource.resolvedDisappearedPRs = []
        harness.mockSource.fetchResult = .success([])
        await harness.engine.poll()

        #expect(harness.appState.recentlyClosedPRs.isEmpty)
    }

    @Test
    func poll_consecutiveSuccesses_resetsFailureCount() async {
        let harness = Harness()
        harness.mockSource.fetchResult = .failure(AppError.networkError)
        await harness.engine.poll()

        harness.mockSource.fetchResult = .success([])
        await harness.engine.poll()

        #expect(harness.appState.error == nil)
    }

    @Test
    func poll_authError_stopsPollingAndSetsStatus() async {
        let harness = Harness()
        harness.mockSource.validateTokenResult = .failure(AppError.authError)

        await harness.engine.poll()

        if case .failed = harness.appState.authenticationStatus {
        } else {
            Issue.record("Expected .failed, got \(harness.appState.authenticationStatus)")
        }
        #expect(harness.appState.error == .authError)
    }

    @Test
    func poll_networkError_setsNetworkError() async {
        let harness = Harness()
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .failure(AppError.networkError)

        await harness.engine.poll()

        #expect(harness.appState.error == .networkError)
    }

    @Test
    func poll_networkError_requestsImmediateRetryAfterBackoff() async {
        let harness = Harness()
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .failure(AppError.networkError)

        let outcome = await harness.engine.poll()

        #expect(outcome == .continueImmediately)
    }

    @Test
    func poll_rateLimitExceeded_setsRateLimitState() async {
        let harness = Harness()
        let resetAt = Date().addingTimeInterval(3600)
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .failure(AppError.rateLimitExceeded(resetAt: resetAt))

        await harness.engine.poll()

        #expect(harness.appState.isRateLimited)
        if case .rateLimitExceeded = harness.appState.error {
        } else {
            Issue.record("Expected rateLimitExceeded error")
        }
    }

    @Test
    func poll_setsAuthenticatedStatus_onFirstSuccess() async {
        let harness = Harness()
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .success([])

        await harness.engine.poll()

        if case .authenticated(let username) = harness.appState.authenticationStatus {
            #expect(username == "octocat")
        } else {
            Issue.record("Expected .authenticated, got \(harness.appState.authenticationStatus)")
        }
    }

    @Test
    func poll_reusesUsername_doesNotRevalidateToken() async {
        let harness = Harness()
        harness.appState.authenticationStatus = .authenticated(username: "octocat")
        harness.mockSource.fetchResult = .success([])

        await harness.engine.poll()

        #expect(harness.mockSource.fetchCallCount > 0)
        #expect(harness.mockSource.validateTokenCallCount == 0)
    }

    @Test
    func poll_successWithNoPRs_keepsTokenValidationWarning() async {
        let harness = Harness()
        harness.appState.authenticationStatus = .authenticated(username: "octocat")
        harness.appState.tokenValidationWarningMessage = "Still verifying"
        harness.mockSource.fetchResult = .success([])

        await harness.engine.poll()

        #expect(harness.appState.tokenValidationWarningMessage == "Still verifying")
    }

    @Test
    func poll_successWithPRs_clearsTokenValidationWarning() async {
        let harness = Harness()
        harness.appState.authenticationStatus = .authenticated(username: "octocat")
        harness.appState.tokenValidationWarningMessage = "Still verifying"
        harness.mockSource.fetchResult = .success([.fixture(number: 7)])

        await harness.engine.poll()

        #expect(harness.appState.tokenValidationWarningMessage == nil)
    }

    @Test
    func reset_clearsPreviousPRsBeforeNextPoll() async {
        let harness = Harness()
        let pr = PRState.fixture(number: 99)
        harness.mockSource.fetchResult = .success([pr])
        await harness.engine.poll()

        harness.engine.reset()
        harness.mockSource.resolvedDisappearedPRs = [pr]
        harness.mockSource.fetchResult = .success([])
        await harness.engine.poll()

        #expect(harness.mockSource.lastResolvedDisappearedInput.isEmpty)
    }

    @Test
    func reset_cancelsRecentlyClosedClearTask() async {
        let harness = Harness(recentlyClosedClearDelay: 0.05)
        let pr = PRState.fixture(number: 99)
        harness.mockSource.fetchResult = .success([pr])
        await harness.engine.poll()

        harness.mockSource.resolvedDisappearedPRs = [pr]
        harness.mockSource.fetchResult = .success([])
        await harness.engine.poll()
        #expect(harness.appState.recentlyClosedPRs.map(\.number) == [99])

        harness.engine.reset()
        harness.appState.recentlyClosedPRs = [.fixture(number: 100)]
        var recentlyClosedWasCleared = false

        await confirmation("recently closed PRs stay visible after reset") { confirmation in
            let deadline = DispatchTime.now().uptimeNanoseconds + 300_000_000
            while DispatchTime.now().uptimeNanoseconds < deadline {
                if harness.appState.recentlyClosedPRs.isEmpty {
                    recentlyClosedWasCleared = true
                    break
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            confirmation()
        }

        #expect(recentlyClosedWasCleared == false)
        #expect(harness.appState.recentlyClosedPRs.map(\.number) == [100])
    }

    @Test
    func clearSessionStateForNewSession_clearsSessionScopedData() {
        let harness = Harness()
        harness.appState.prs = [.fixture(number: 1)]
        harness.appState.recentlyClosedPRs = [.fixture(number: 2)]
        harness.appState.lastUpdated = Date()
        harness.appState.isLoading = false
        harness.appState.error = .rateLimitExceeded(resetAt: Date().addingTimeInterval(60))
        harness.appState.isStale = true
        harness.appState.authenticationStatus = .authenticated(username: "octocat")
        harness.appState.tokenValidationWarningMessage = "Still verifying"

        harness.appState.clearSessionStateForNewSession()

        #expect(harness.appState.prs.isEmpty)
        #expect(harness.appState.recentlyClosedPRs.isEmpty)
        #expect(harness.appState.lastUpdated == nil)
        #expect(harness.appState.error == nil)
        #expect(harness.appState.isRateLimited == false)
        #expect(harness.appState.rateLimitResetDate == nil)
        #expect(harness.appState.isStale == false)
        #expect(harness.appState.isLoading)
        #expect(harness.appState.tokenValidationWarningMessage == nil)

        if case .unknown = harness.appState.authenticationStatus {
        } else {
            Issue.record("Expected authentication status to reset to unknown")
        }
    }

    @Test
    func panelContentState_noTokenWithNoPRs_prefersSetupState() {
        let harness = Harness()
        harness.appState.isLoading = false
        harness.appState.authenticationStatus = .noToken

        #expect(harness.appState.panelContentState == .setupRequired)
    }

    @Test
    func panelContentState_authFailureWithNoPRs_prefersAuthErrorState() {
        let harness = Harness()
        harness.appState.isLoading = false
        harness.appState.authenticationStatus = .failed

        #expect(harness.appState.panelContentState == .authError)
    }

    @Test
    func poll_networkError_withOldLastUpdated_marksStateStale() async {
        let harness = Harness()
        harness.appState.lastUpdated = Date().addingTimeInterval(-301)
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .failure(AppError.networkError)

        await harness.engine.poll()

        #expect(harness.appState.isStale)
    }

    @Test
    func poll_success_clearsExistingStaleState() async {
        let harness = Harness()
        harness.appState.lastUpdated = Date().addingTimeInterval(-301)
        harness.appState.isStale = true
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .success([.fixture()])

        await harness.engine.poll()

        #expect(harness.appState.isStale == false)
    }

    @Test
    func poll_success_populatesObservationSnapshots() async {
        let harness = Harness()
        let pr = PRState.fixture(number: 7, reviewRequestedFromMe: true)
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .success([pr])

        await harness.engine.poll()

        #expect(harness.appState.panel.triageSnapshot.prs.map(\.number) == [7])
        #expect(harness.appState.panel.triageSnapshot.needsActionPRs.map(\.number) == [7])
        #expect(harness.appState.panel.triageSnapshot.menuBarBadgeCount == 1)

        if case .authenticated(let username) = harness.appState.auth.authenticationStatus {
            #expect(username == "octocat")
        } else {
            Issue.record("Expected authenticated auth state after polling")
        }
    }

    @Test
    func poll_samePRs_keepsDerivedSnapshotStable() async {
        let harness = Harness()
        let pr = PRState.fixture(number: 7, reviewRequestedFromMe: true)
        harness.mockSource.validateTokenResult = .success("octocat")
        harness.mockSource.fetchResult = .success([pr])

        await harness.engine.poll()
        let initialSnapshot = harness.appState.panel.triageSnapshot

        await harness.engine.poll()

        #expect(harness.appState.panel.triageSnapshot == initialSnapshot)
    }
}
