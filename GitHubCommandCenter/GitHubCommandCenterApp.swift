import SwiftUI

@main
struct GitHubCommandCenterApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PRListView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView(healthStatus: appState.healthStatus, prCount: appState.prs.count)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
