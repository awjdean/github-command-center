import Foundation
import Testing

@testable import GitHubCommandCenter

@MainActor
@Suite
struct AppStateTests {
    private final class StubPollingEngine: PollingControlling {
        var onStart: (() -> Void)?
        var startCallCount = 0
        var stopCallCount = 0
        var resetCallCount = 0
        var forceRefreshCallCount = 0

        func start() {
            startCallCount += 1
            onStart?()
        }

        func stop() {
            stopCallCount += 1
        }

        func reset() {
            resetCallCount += 1
        }

        func forceRefresh() {
            forceRefreshCallCount += 1
        }
    }

    @Test
    func appInit_startsPollingBeforeMenuAppears() {
        let engine = StubPollingEngine()
        let appState = AppState(
            makePollingEngine: { _ in engine },
            requestNotificationPermission: {}
        )

        _ = GitHubCommandCenterApp(appState: appState)

        #expect(engine.startCallCount == 1)
    }

    @Test
    func appInit_preloadsTokenBeforePollingStarts() {
        let engine = StubPollingEngine()
        var preloadCallCount = 0
        engine.onStart = {
            #expect(preloadCallCount == 1)
        }

        let appState = AppState(
            makePollingEngine: { _ in engine },
            requestNotificationPermission: {},
            preloadTokenIfNeeded: { preloadCallCount += 1 }
        )

        _ = GitHubCommandCenterApp(appState: appState)

        #expect(preloadCallCount == 1)
        #expect(engine.startCallCount == 1)
    }

    @Test
    func stopPollingForMissingToken_stopsWithoutRestartingOrPreloading() {
        let engine = StubPollingEngine()
        var preloadCallCount = 0
        let appState = AppState(
            makePollingEngine: { _ in engine },
            requestNotificationPermission: {},
            preloadTokenIfNeeded: { preloadCallCount += 1 }
        )

        appState.startPollingIfNeeded()
        appState.prs = [.fixture(number: 1)]
        appState.recentlyClosedPRs = [.fixture(number: 2)]
        appState.lastUpdated = Date()
        appState.isLoading = false
        appState.error = .networkError
        appState.authenticationStatus = .authenticated(username: "octocat")

        appState.stopPollingForMissingToken()

        #expect(preloadCallCount == 1)
        #expect(engine.startCallCount == 1)
        #expect(engine.resetCallCount == 1)
        #expect(engine.stopCallCount == 1)
        #expect(appState.prs.isEmpty)
        #expect(appState.recentlyClosedPRs.isEmpty)
        #expect(appState.lastUpdated == nil)
        #expect(appState.error == nil)
        #expect(!appState.isLoading)
        #expect(appState.panelContentState == .setupRequired)

        guard case .noToken = appState.authenticationStatus else {
            Issue.record("Expected authentication status to be noToken")
            return
        }
    }

    @Test
    func panelContentState_networkErrorWithNoPRs_prefersLoadError() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.error = .networkError

        #expect(appState.panelContentState == .loadError)
    }

    @Test
    func panelContentState_incompleteResultsWithNoPRs_prefersLoadError() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.error = .incompleteSearchResults

        #expect(appState.panelContentState == .loadError)
    }

    @Test
    func recentlyClosedSectionVisibility_successfulEmptyState_showsSection() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.authenticationStatus = .authenticated(username: "octocat")
        appState.recentlyClosedPRs = [.fixture(number: 99)]

        #expect(appState.showsRecentlyClosedSection)
    }

    @Test
    func recentlyClosedSectionVisibility_loadError_hidesSection() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.error = .networkError
        appState.recentlyClosedPRs = [.fixture(number: 99)]

        #expect(!appState.showsRecentlyClosedSection)
    }

    @Test
    func panelSubtitle_authenticatedEmptyStateUsesTrackedLanguage() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.authenticationStatus = .authenticated(username: "octocat")

        #expect(appState.panelSubtitleText == "0 tracked PRs")
    }

    @Test
    func healthStatus_noTokenWithNoPRs_isYellow() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.authenticationStatus = .noToken

        #expect(appState.healthStatus == .yellow)
    }

    @Test
    func healthStatus_authFailureWithNoPRs_isRed() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.authenticationStatus = .failed

        #expect(appState.healthStatus == .red)
    }

    @Test
    func healthStatus_rateLimitedWithExistingSnapshot_isRed() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.prs = [.fixture(number: 1)]
        appState.error = .rateLimitExceeded(.init(resetAt: Date().addingTimeInterval(60)))

        #expect(appState.healthStatus == .red)
    }

    @Test
    func healthStatus_staleWithoutHardError_isYellow() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.isStale = true

        #expect(appState.healthStatus == .yellow)
    }

    @Test
    func healthStatus_incompleteSearchResults_isYellow() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.error = .incompleteSearchResults

        #expect(appState.healthStatus == .yellow)
    }

    @Test
    func healthStatus_healthyEmptyState_isGreen() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.authenticationStatus = .authenticated(username: "octocat")

        #expect(appState.healthStatus == .green)
    }

    @Test
    func healthStatus_healthyNeedsActionLowUrgency_usesTriageYellow() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.prs = [.fixture(number: 1, reviewRequestedFromMe: true)]

        #expect(appState.healthStatus == .yellow)
    }

    @Test
    func healthStatus_healthyNeedsActionHighUrgency_usesTriageRed() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.prs = [
            .fixture(
                number: 1,
                reviewStatus: .changesRequested(by: ["alice"]),
                createdByMe: true
            )
        ]

        #expect(appState.healthStatus == .red)
    }

    @Test
    func menuBarBadgeCount_countsOnlyNeedsActionPRs() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.prs = [
            .fixture(number: 1, reviewRequestedFromMe: true),  // needs action
            .fixture(number: 2),  // waiting on others (default: not mine, no review requested)
        ]

        #expect(appState.menuBarBadgeCount == 1)
    }

    @Test
    func menuBarBadgeCount_zeroPRs_returnsZero() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )

        #expect(appState.menuBarBadgeCount == 0)
    }

    @Test
    func menuBarBadgeCount_allNeedAction_returnsTotal() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.prs = [
            .fixture(number: 1, reviewRequestedFromMe: true),
            .fixture(number: 2, reviewRequestedFromMe: true),
            .fixture(number: 3, reviewRequestedFromMe: true),
        ]

        #expect(appState.menuBarBadgeCount == 3)
    }

    @Test
    func triageSnapshot_sortsBackingPRsBeforeDerivingSections() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        let waitingOlder = PRState.fixture(
            number: 1,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let needsActionNewer = PRState.fixture(
            number: 2,
            reviewRequestedFromMe: true,
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )
        let draftNewest = PRState.fixture(
            number: 3,
            draftStatus: .draft,
            createdByMe: true,
            updatedAt: Date(timeIntervalSince1970: 5_000)
        )
        let waitingNewer = PRState.fixture(
            number: 4,
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let needsActionOlder = PRState.fixture(
            number: 5,
            reviewRequestedFromMe: true,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        appState.prs = [waitingOlder, needsActionOlder, draftNewest, waitingNewer, needsActionNewer]

        #expect(appState.prs.map(\.number) == [2, 5, 4, 1, 3])
        #expect(appState.needsActionPRs.map(\.number) == [2, 5])
        #expect(appState.waitingOnOthersPRs.map(\.number) == [4, 1])
        #expect(appState.yourDraftPRs.map(\.number) == [3])
    }

    @Test
    func yourDraftPRs_containsDraftsCreatedByMeOrAssignedToMe() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.prs = [
            .fixture(number: 1, draftStatus: .draft, createdByMe: true),
            .fixture(number: 2, draftStatus: .draft, assignedToMe: true),
            .fixture(number: 3, draftStatus: .draft),  // not mine
            .fixture(number: 4, reviewRequestedFromMe: true),  // needs action (not draft)
        ]

        #expect(appState.yourDraftPRs.count == 2)
        #expect(appState.yourDraftPRs.map(\.number).contains(1))
        #expect(appState.yourDraftPRs.map(\.number).contains(2))
        #expect(appState.waitingOnOthersPRs.count == 1)
        #expect(appState.waitingOnOthersPRs.first?.number == 3)
        #expect(appState.needsActionPRs.count == 1)
        #expect(appState.needsActionPRs.first?.number == 4)
    }

    @Test
    func menuBarBadgeCount_excludesYourDrafts() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.prs = [
            .fixture(number: 1, reviewRequestedFromMe: true),  // needs action
            .fixture(number: 2, draftStatus: .draft, createdByMe: true),  // your draft
        ]

        #expect(appState.menuBarBadgeCount == 1)
    }

    @Test
    func emptyStateMessage_authenticatedExplainsTrackedScopeAndRepoAccess() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.authenticationStatus = .authenticated(username: "octocat")

        #expect(
            appState.emptyStateMessage
                == "This app tracks pull requests involving @octocat. "
                + "If you expected results here, make sure your GitHub token can access those repositories."
        )
    }

    @Test
    func applyPollSnapshot_updatesPanelAndAuthState() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        let primaryPR = PRState.fixture(number: 1, reviewRequestedFromMe: true)
        let closedPR = PRState.fixture(number: 99)
        let timestamp = Date(timeIntervalSince1970: 12_345)
        let snapshot = AppState.PollSnapshot(
            panel: .init(
                triageSnapshot: .build(from: [primaryPR]),
                recentlyClosedPRs: [closedPR],
                lastUpdated: timestamp,
                isLoading: false,
                warningMessage: "Results truncated",
                error: nil,
                isStale: false
            ),
            auth: .init(
                authenticationStatus: .authenticated(username: "octocat"),
                tokenValidationWarningMessage: nil
            )
        )

        appState.applyPollSnapshot(snapshot)

        #expect(appState.panel.triageSnapshot.prs.map(\.number) == [1])
        #expect(appState.panel.recentlyClosedPRs.map(\.number) == [99])
        #expect(appState.panel.lastUpdated == timestamp)
        #expect(appState.panel.isLoading == false)
        #expect(appState.panel.warningMessage == "Results truncated")
        #expect(appState.panel.triageSnapshot.menuBarBadgeCount == 1)

        assertAuthenticated(
            appState: appState,
            expectedUsername: "octocat"
        )
    }

    @Test
    func authStateMutation_preservesExistingPanelSnapshot() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        let existingPRs = [
            PRState.fixture(number: 1, reviewRequestedFromMe: true),
            PRState.fixture(number: 2),
        ]
        appState.applyPollSnapshot(
            .init(
                panel: .init(
                    triageSnapshot: .build(from: existingPRs),
                    recentlyClosedPRs: [],
                    lastUpdated: nil,
                    isLoading: false,
                    warningMessage: nil,
                    error: nil,
                    isStale: false
                ),
                auth: .init(authenticationStatus: .unknown, tokenValidationWarningMessage: nil)
            )
        )
        let originalSnapshot = appState.panel.triageSnapshot

        appState.auth.authenticationStatus = .authenticated(username: "octocat")

        #expect(appState.panel.triageSnapshot == originalSnapshot)
    }

    @Test
    func panelContentState_warningWithExistingPRs_staysPrList() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.applyPollSnapshot(
            .init(
                panel: .init(
                    triageSnapshot: .build(from: [.fixture(number: 1, reviewRequestedFromMe: true)]),
                    recentlyClosedPRs: [],
                    lastUpdated: nil,
                    isLoading: false,
                    warningMessage: "Results truncated",
                    error: nil,
                    isStale: false
                ),
                auth: .init(
                    authenticationStatus: .authenticated(username: "octocat"),
                    tokenValidationWarningMessage: nil
                )
            )
        )

        #expect(appState.panelContentState == .prList)
    }

    @Test
    func healthStatus_warningDoesNotOverrideExistingTriageHealth() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.isLoading = false
        appState.prs = [.fixture(number: 1, reviewRequestedFromMe: true)]
        appState.panel.warningMessage = "Results truncated"

        #expect(appState.healthStatus == .yellow)
    }

    private func assertAuthenticated(
        appState: AppState,
        expectedUsername: String
    ) {
        guard case .authenticated(let username) = appState.auth.authenticationStatus else {
            Issue.record("Expected authenticated auth state")
            return
        }

        #expect(username == expectedUsername)
    }
}
