import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite
struct PRPanelModeTests {
    @Test
    func panelModeHasExpectedWidth() {
        #expect(PanelMode.width == 480)
    }

    @Test
    func pullRequestsModeUsesPRPanelPresentation() {
        #expect(PanelMode.pullRequests.headerTitle == "GitHub Command Center")
        #expect(PanelMode.pullRequests.showsBackButton == false)
        #expect(PanelMode.pullRequests.showsRefreshRow == true)
        #expect(PanelMode.pullRequests.showsInlineAppControls == false)
    }

    @Test
    func settingsModeUsesCompactInlineSettingsPresentation() {
        #expect(PanelMode.settings.headerTitle == "Settings")
        #expect(PanelMode.settings.showsBackButton == true)
        #expect(PanelMode.settings.showsRefreshRow == false)
        #expect(PanelMode.settings.showsInlineAppControls == true)
    }

    @Test
    func settingsUsesPersonalAccessTokensURL() {
        #expect(SettingsLinks.personalAccessTokens == URL(string: "https://github.com/settings/personal-access-tokens"))
    }
}
