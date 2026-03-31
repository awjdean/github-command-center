import SwiftUI

@main
@MainActor
struct GitHubCommandCenterApp: App {
    @State private var appState: AppState

    init() {
        self.init(
            appState: AppState(),
            shouldStartPolling: !RuntimeEnvironment.isRunningTests
        )
    }

    init(appState: AppState, shouldStartPolling: Bool = true) {
        _appState = State(initialValue: appState)
        if shouldStartPolling {
            appState.startPollingIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PRListView()
                .environment(appState)
        } label: {
            MenuBarIconView(
                healthStatus: appState.panel.triageSnapshot.healthStatus,
                prCount: appState.panel.triageSnapshot.menuBarBadgeCount,
                isLoading: appState.panel.isLoading
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private enum RuntimeEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
