import ServiceManagement
import SwiftUI

enum SettingsLinks {
    static let personalAccessTokens = URL(string: "https://github.com/settings/personal-access-tokens")
    static let projectRepository = URL(string: "https://github.com/awjdean/github-command-center")
}

struct SettingsContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenInput = ""
    @State private var tokenState: TokenState = .empty
    @State private var isValidating = false
    @State private var launchAtLogin = false
    let showsAppControls: Bool

    init(showsAppControls: Bool = true) {
        self.showsAppControls = showsAppControls
    }

    enum TokenState {
        case empty
        case unvalidated
        case valid(username: String)
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tokenSection
            if showsAppControls {
                appControlsSection
            }
            aboutSection
        }
        .padding(24)
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            loadSavedToken()
        }
    }

    // MARK: - Token Section

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Authentication")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            } icon: {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.linkBlue)
            }

            if case .valid(let username) = tokenState {
                connectedView(username: username)
            } else {
                tokenInputView
            }
        }
        .settingsCard()
    }

    private func connectedView(username: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.statusGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(username)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Token stored in Keychain")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.statusGreen.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.statusGreen.opacity(0.2), lineWidth: 1)
            )

            Button(role: .destructive) {
                clearToken()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Remove Token")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var tokenInputView: some View {
        VStack(alignment: .leading, spacing: 14) {
            SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $tokenInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.textPrimary)
                .padding(10)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tokenBorderColor, lineWidth: 1)
                )
                .onChange(of: tokenInput) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tokenState = tokenInput.isEmpty ? .empty : .unvalidated
                    }
                }

            if case .invalid = tokenState {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.statusRed)
                    Text("Invalid token \u{2014} check scopes and try again")
                        .font(.system(size: 11))
                        .foregroundColor(.statusRed)
                }
                .transition(.opacity)
            }

            scopeInfo

            if let url = SettingsLinks.personalAccessTokens {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Manage personal access tokens")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.linkBlue)
                }
            }

            HStack(spacing: 8) {
                Button {
                    saveToken()
                } label: {
                    HStack(spacing: 4) {
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isValidating ? "Validating…" : "Save Token")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(minWidth: 100)
                }
                .disabled(tokenInput.isEmpty || isValidating)
                .buttonStyle(.borderedProminent)
                .tint(.linkBlue)

                if !tokenInput.isEmpty && !isValidating {
                    Button("Clear") {
                        tokenInput = ""
                        tokenState = .empty
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Scope Info

    private var scopeInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FINE-GRAINED PAT SCOPES")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.textMuted)

            scopeRow(
                scopes: [
                    .init(name: "Pull requests: Read"),
                    .init(name: "Commit statuses: Read"),
                    .init(name: "Actions: Read", isOptional: true),
                ]
            )
        }
    }

    private func scopeRow(scopes: [ScopeItem]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(scopes) { scope in
                scopeBadge(scope.name, optional: scope.isOptional)
            }
        }
    }

    private func scopeBadge(_ text: String, optional: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            if optional {
                Text("optional")
                    .font(.system(size: 8))
                    .foregroundColor(.textMuted)
            }
        }
        .foregroundColor(optional ? .textTertiary : .textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.panelBackground.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.textMuted.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - App Controls

    private var appControlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Application")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            } icon: {
                Image(systemName: "switch.2")
                    .font(.system(size: 11))
                    .foregroundColor(.linkBlue)
            }

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.textSecondary)
            .buttonStyle(.bordered)
        }
        .settingsCard()
    }

    private var aboutSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("GitHub Command Center")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 8) {
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.panelBackground.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("MIT License")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
            }
            Spacer()
            if let url = SettingsLinks.projectRepository {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("View on GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.linkBlue)
                }
            }
        }
        .settingsCard()
    }

    private var tokenBorderColor: Color {
        switch tokenState {
        case .empty, .unvalidated: Color.textMuted.opacity(0.25)
        case .valid: .statusGreen.opacity(0.6)
        case .invalid: .statusRed.opacity(0.6)
        }
    }

    private func loadSavedToken() {
        do {
            if let saved = try KeychainService.shared.loadToken(), !saved.isEmpty {
                tokenInput = saved
                if case .authenticated(let username) = appState.authenticationStatus {
                    tokenState = .valid(username: username)
                } else {
                    tokenState = .unvalidated
                }
            }
        } catch {
            tokenInput = ""
            tokenState = .invalid
        }
    }

    private func saveToken() {
        guard !tokenInput.isEmpty else { return }
        isValidating = true

        Task { @MainActor in
            do {
                let client = GitHubRESTClient(token: tokenInput)
                let username = try await client.validateTokenForAppAccess()
                try KeychainService.shared.saveToken(tokenInput)
                withAnimation(.easeInOut(duration: 0.2)) {
                    tokenState = .valid(username: username)
                }
                appState.resetPolling()
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tokenState = .invalid
                }
            }
            isValidating = false
        }
    }

    private func clearToken() {
        do {
            try KeychainService.shared.deleteToken()
        } catch {
            print("Failed to delete token from keychain in clearToken: \(error.localizedDescription)")
        }
        tokenInput = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            tokenState = .empty
        }
        appState.resetPolling()
    }
}

#Preview("Settings Content") {
    SettingsContentView()
        .environmentObject(settingsPreviewAppState())
        .frame(width: 360)
        .background(Color.panelBackground)
}

@MainActor
private func settingsPreviewAppState() -> AppState {
    let appState = AppState(
        makePollingEngine: { _ in SettingsPreviewPollingController() },
        requestNotificationPermission: {}
    )
    appState.isLoading = false
    appState.authenticationStatus = .noToken
    return appState
}

@MainActor
private final class SettingsPreviewPollingController: PollingControlling {
    func start() {}
    func stop() {}
    func reset() {}
    func forceRefresh() {}
}

// MARK: - Supporting Types

private struct ScopeItem: Identifiable {
    var id: String { name }
    let name: String
    var isOptional: Bool = false
}

// MARK: - Settings Card

private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    fileprivate func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    struct Cache {
        var size: CGSize
        var positions: [CGPoint]
    }

    func makeCache(subviews: Subviews) -> Cache {
        arrange(in: .infinity, subviews: subviews)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = arrange(in: .infinity, subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        cache = arrange(in: proposal.width ?? .infinity, subviews: subviews)
        return cache.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        for (index, position) in cache.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> Cache {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return Cache(size: CGSize(width: totalWidth, height: currentY + rowHeight), positions: positions)
    }
}
