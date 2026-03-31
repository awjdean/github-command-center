import SwiftUI

@main
@MainActor
struct GitHubCommandCenterApp: App {
    @StateObject private var appState: AppState

    init() {
        self.init(
            appState: AppState(),
            shouldStartPolling: !RuntimeEnvironment.isRunningTests
        )
    }

    init(appState: AppState, shouldStartPolling: Bool = true) {
        _appState = StateObject(wrappedValue: appState)
        if shouldStartPolling {
            appState.startPollingIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PRListView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView(healthStatus: appState.healthStatus, prCount: appState.prs.count)
        }
        .menuBarExtraStyle(.window)
    }
}

private enum RuntimeEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
