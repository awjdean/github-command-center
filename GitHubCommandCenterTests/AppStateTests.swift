import Testing

@testable import GitHubCommandCenter

@MainActor
@Suite
struct AppStateTests {
    private final class StubPollingEngine: PollingControlling {
        var startCallCount = 0
        var stopCallCount = 0
        var resetCallCount = 0
        var forceRefreshCallCount = 0

        func start() {
            startCallCount += 1
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
}
