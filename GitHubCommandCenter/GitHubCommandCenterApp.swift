import SwiftUI

@main
@MainActor
struct GitHubCommandCenterApp: App {
    @StateObject private var appState: AppState

    init() {
        self.init(appState: AppState())
    }

    init(appState: AppState) {
        _appState = StateObject(wrappedValue: appState)
        appState.startPollingIfNeeded()
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
