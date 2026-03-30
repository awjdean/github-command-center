import SwiftUI
import Testing

@Suite
struct SettingsOpeningTests {
    @MainActor
    @Test
    func settingsLinkSupportsCustomLabels() {
        let gearLink = SettingsLink {
            Image(systemName: "gear")
        }
        let textLink = SettingsLink {
            Text("Open Settings")
        }

        _ = gearLink
        _ = textLink
    }
}
