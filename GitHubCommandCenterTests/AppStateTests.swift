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

        if case .noToken = appState.authenticationStatus {
        } else {
            Issue.record("Expected authentication status to be noToken")
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
    func panelSubtitle_authenticatedEmptyStateUsesTrackedLanguage() {
        let appState = AppState(
            makePollingEngine: { _ in StubPollingEngine() },
            requestNotificationPermission: {}
        )
        appState.authenticationStatus = .authenticated(username: "octocat")

        #expect(appState.panelSubtitleText == "0 tracked PRs")
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
}
