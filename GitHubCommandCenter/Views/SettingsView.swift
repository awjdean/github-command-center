import OSLog
import ServiceManagement
import SwiftUI

enum SettingsLinks {
    static let personalAccessTokens = URL(string: "https://github.com/settings/personal-access-tokens")
    static let projectRepository = URL(string: "https://github.com/awjdean/github-command-center")
}

struct TokenSaveFailureOutcome: Equatable {
    let tokenState: SettingsContentView.TokenState
    let message: String?
}

struct TokenSaveSuccessOutcome: Equatable {
    let tokenState: SettingsContentView.TokenState
    let warningMessage: String?
}

struct SettingsContentView: View {
    private static let logger = Logger(subsystem: Log.subsystem, category: "SettingsView")

    @Environment(AppState.self) private var appState
    @State private var tokenInput = ""
    @State private var tokenState: TokenState = .empty
    @State private var tokenSaveErrorMessage: String?
    @State private var tokenAccessDetails: TokenAccessDetails?
    @State private var tokenAccessErrorMessage: String?
    @State private var tokenSaveTask: Task<Void, Never>?
    @State private var tokenSaveTaskID: UUID?
    @State private var tokenAccessTask: Task<Void, Never>?
    @State private var tokenAccessTaskID: UUID?
    @State private var isValidating = false
    @State private var isLoadingTokenAccess = false
    @State private var isReposExpanded = false
    @State private var launchAtLogin = false
    let showsAppControls: Bool

    init(showsAppControls: Bool = true) {
        self.showsAppControls = showsAppControls
    }

    enum TokenState: Equatable {
        case empty
        case unvalidated
        case valid(username: String)
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            tokenSection
            aboutSection
            if showsAppControls {
                appControlsSection
            }
        }
        .padding(Theme.Spacing.xxl)
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
                    .foregroundColor(Theme.Colors.textPrimary)
            } icon: {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.linkBlue)
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
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.statusGreen)
                VStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                    Text("@\(username)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Colors.textPrimary)
                    Text("Token stored in Keychain")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.statusGreen.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.Colors.statusGreen.opacity(0.2), lineWidth: 1)
            )

            if let tokenValidationWarningMessage = appState.tokenValidationWarningMessage {
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.statusYellow)
                    Text(tokenValidationWarningMessage)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.statusYellow)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.statusYellow.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.Colors.statusYellow.opacity(0.2), lineWidth: 1)
                )
            }

            tokenAccessSection

            Button(role: .destructive) {
                clearToken()
            } label: {
                HStack(spacing: Theme.Spacing.xxs) {
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
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.md)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(tokenBorderColor, lineWidth: 1)
                )
                .onChange(of: tokenInput) {
                    clearTokenAccessState()
                    clearTokenSaveValidationState()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tokenState = tokenInput.isEmpty ? .empty : .unvalidated
                    }
                }

            if case .invalid = tokenState {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.statusRed)
                    Text("Invalid token \u{2014} check scopes and try again")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.statusRed)
                }
                .transition(.opacity)
            }

            if let tokenSaveErrorMessage {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.statusRed)
                    Text(tokenSaveErrorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.statusRed)
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }

            scopeInfo

            if let url = SettingsLinks.personalAccessTokens {
                Link(destination: url) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Manage personal access tokens")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.Colors.linkBlue)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    saveToken()
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
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
                .tint(Theme.Colors.linkBlue)

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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("APP REQUIREMENTS")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Theme.Colors.textMuted)

            scopeRow(
                scopes: [
                    .init(name: "Pull requests: Read"),
                    .init(name: "Commit statuses: Read"),
                    .init(name: "Checks: Read", isOptional: true),
                ]
            )

            Text(
                "Grant repository access to every repo you want tracked. "
                    + "Commit statuses are required for full verification. "
                    + "Checks access is recommended for richer CI detail. "
                    + "This app shows pull requests involving the authenticated account."
            )
            .font(.system(size: 10))
            .foregroundColor(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scopeRow(scopes: [ScopeItem]) -> some View {
        FlowLayout(spacing: Theme.Spacing.xxs) {
            ForEach(scopes) { scope in
                scopeBadge(scope.name, optional: scope.isOptional)
            }
        }
    }

    @ViewBuilder
    private var tokenAccessSection: some View {
        if isLoadingTokenAccess {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading token access…")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        } else if let tokenAccessDetails {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                tokenPermissionsSection(details: tokenAccessDetails)
                accessibleRepositoriesSection(details: tokenAccessDetails)
            }
        } else if let tokenAccessErrorMessage {
            Text(tokenAccessErrorMessage)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.statusRed)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tokenPermissionsSection(details: TokenAccessDetails) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("REPORTED PERMISSIONS")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Theme.Colors.textMuted)

            if details.oauthScopes.isEmpty {
                Text(
                    "GitHub did not report OAuth scopes for this token. "
                        + "Fine-grained personal access token permissions are not "
                        + "fully introspectable via the REST API."
                )
                .font(.system(size: 10))
                .foregroundColor(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                scopeRow(scopes: details.oauthScopes.map { ScopeItem(name: $0) })
            }
        }
    }

    private func accessibleRepositoriesSection(details: TokenAccessDetails) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isReposExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.Colors.textMuted)
                        .rotationEffect(.degrees(isReposExpanded ? 90 : 0))
                    Text("ACCESSIBLE REPOSITORIES")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Theme.Colors.textMuted)
                    Spacer()
                    Text("\(details.accessibleRepositories.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isReposExpanded {
                if details.accessibleRepositories.isEmpty {
                    Text("No accessible repositories were returned for this token.")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Colors.textTertiary)
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(details.accessibleRepositories) { repository in
                            accessibleRepositoryRow(repository)
                        }
                    }
                }
            }
        }
    }

    private func accessibleRepositoryRow(_ repository: TokenAccessDetails.AccessibleRepository) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(repository.fullName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)

            Spacer(minLength: Theme.Spacing.sm)

            Text(repository.accessLevel.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(accessLevelColor(repository.accessLevel))
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, Theme.Spacing.micro)
                .background(accessLevelColor(repository.accessLevel).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.xxs))
        }
    }

    private func accessLevelColor(_ accessLevel: TokenAccessDetails.AccessibleRepository.AccessLevel) -> Color {
        switch accessLevel {
        case .admin:
            Theme.Colors.statusRed
        case .write:
            Theme.Colors.statusYellow
        case .read:
            Theme.Colors.statusGreen
        }
    }

    private func scopeBadge(_ text: String, optional: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.xxxs) {
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            if optional {
                Text("optional")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.Colors.textMuted)
            }
        }
        .foregroundColor(optional ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, Theme.Spacing.xxxs)
        .background(Theme.Colors.panelBackground.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.xxs))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Spacing.xxs)
                .stroke(Theme.Colors.textMuted.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - App Controls

    private var appControlsSection: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textSecondary)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        let action = enabled ? "register" : "unregister"
                        let errorDescription = error.localizedDescription
                        Self.logger.error(
                            "\(action, privacy: .public) launch at login failed: \(errorDescription, privacy: .public)"
                        )
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.Colors.textSecondary)
            .buttonStyle(.bordered)
        }
        .settingsCard()
    }

    private var aboutSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("GitHub Command Center")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                HStack(spacing: Theme.Spacing.sm) {
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, Theme.Spacing.micro)
                        .background(Theme.Colors.panelBackground.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.xxs))
                    Text("MIT License")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
            Spacer()
            if let url = SettingsLinks.projectRepository {
                Link(destination: url) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("View on GitHub")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.Colors.linkBlue)
                }
            }
        }
        .settingsCard()
    }

    private var tokenBorderColor: Color {
        switch tokenState {
        case .empty, .unvalidated: Theme.Colors.textMuted.opacity(0.25)
        case .valid: Theme.Colors.statusGreen.opacity(0.6)
        case .invalid: Theme.Colors.statusRed.opacity(0.6)
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
                refreshTokenAccessDetails(using: saved)
            }
        } catch {
            tokenInput = ""
            tokenState = .empty
            let errorDescription = error.localizedDescription
            Self.logger.error(
                "loadSavedToken Keychain read failed: \(errorDescription, privacy: .public)"
            )
        }
    }

    private func saveToken() {
        guard !tokenInput.isEmpty else { return }
        let tokenToSave = tokenInput
        tokenSaveTask?.cancel()
        let taskID = UUID()
        tokenSaveTaskID = taskID
        isValidating = true

        tokenSaveTask = Task { @MainActor in
            defer {
                if tokenSaveTaskID == taskID {
                    isValidating = false
                    tokenSaveTask = nil
                    tokenSaveTaskID = nil
                }
            }

            do {
                clearTokenSaveValidationState()
                let client = GitHubRESTClient(token: tokenToSave)
                let validationResult = try await client.validateTokenForAppAccess()
                guard !Task.isCancelled, tokenInput == tokenToSave else { return }
                try KeychainService.shared.saveToken(tokenToSave)
                guard !Task.isCancelled, tokenInput == tokenToSave else { return }
                let successOutcome = Self.tokenSaveSuccessOutcome(for: validationResult)
                withAnimation(.easeInOut(duration: 0.2)) {
                    tokenState = successOutcome.tokenState
                }
                appState.tokenValidationWarningMessage = successOutcome.warningMessage
                refreshTokenAccessDetails(using: tokenToSave)
                appState.resetPolling()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let outcome = Self.tokenSaveFailureOutcome(for: error)
                withAnimation(.easeInOut(duration: 0.2)) {
                    tokenState = outcome.tokenState
                }
                tokenSaveErrorMessage = outcome.message
            }
        }
    }

    private func clearToken() {
        tokenSaveTask?.cancel()
        tokenSaveTask = nil
        tokenSaveTaskID = nil
        isValidating = false
        clearTokenAccessState()
        do {
            try KeychainService.shared.deleteToken()
        } catch {
            let errorDescription = error.localizedDescription
            Self.logger.error(
                "clearToken Keychain deletion failed: \(errorDescription, privacy: .public)"
            )
            // Token may still exist in Keychain — don't clear UI state
            tokenSaveErrorMessage = "Could not remove token: \(errorDescription)"
            return
        }
        tokenInput = ""
        clearTokenSaveValidationState()
        withAnimation(.easeInOut(duration: 0.2)) {
            tokenState = .empty
        }
        appState.stopPollingForMissingToken()
    }

    private func clearTokenSaveValidationState() {
        tokenSaveErrorMessage = nil
    }

    private func clearTokenAccessState() {
        tokenAccessTask?.cancel()
        tokenAccessTask = nil
        tokenAccessTaskID = nil
        tokenAccessDetails = nil
        tokenAccessErrorMessage = nil
        isLoadingTokenAccess = false
    }

    private func refreshTokenAccessDetails(using token: String) {
        clearTokenAccessState()
        isLoadingTokenAccess = true
        let taskID = UUID()
        tokenAccessTaskID = taskID

        tokenAccessTask = Task { @MainActor in
            defer {
                if tokenAccessTaskID == taskID {
                    isLoadingTokenAccess = false
                    tokenAccessTask = nil
                    tokenAccessTaskID = nil
                }
            }

            do {
                let details = try await GitHubRESTClient(token: token).fetchTokenAccessDetails()
                guard !Task.isCancelled, tokenInput == token else { return }

                tokenAccessDetails = details
                tokenAccessErrorMessage = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    tokenState = .valid(username: details.username)
                }
            } catch let error as AppError {
                guard !Task.isCancelled, tokenInput == token else { return }

                if error == .authError {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tokenState = .invalid
                    }
                }

                tokenAccessErrorMessage =
                    error.errorDescription ?? "Unable to load token access details right now."
            } catch {
                guard !Task.isCancelled, tokenInput == token else { return }
                tokenAccessErrorMessage = "Unable to load token access details right now."
            }
        }
    }

    static func tokenSaveSuccessOutcome(
        for result: GitHubRESTClient.TokenValidationResult
    ) -> TokenSaveSuccessOutcome {
        switch result {
        case .verified(let username):
            return TokenSaveSuccessOutcome(
                tokenState: .valid(username: username),
                warningMessage: nil
            )
        case .warning(let username, let message):
            return TokenSaveSuccessOutcome(
                tokenState: .valid(username: username),
                warningMessage: message
            )
        }
    }

    static func tokenSaveFailureOutcome(for error: Error) -> TokenSaveFailureOutcome {
        if let appError = error as? AppError {
            switch appError {
            case .authError:
                return TokenSaveFailureOutcome(tokenState: .invalid, message: nil)
            default:
                return TokenSaveFailureOutcome(
                    tokenState: .unvalidated,
                    message: appError.errorDescription ?? "Unable to save token right now."
                )
            }
        }

        return TokenSaveFailureOutcome(
            tokenState: .unvalidated,
            message: (error as NSError).localizedDescription
        )
    }
}

#Preview("Settings Content") {
    SettingsContentView()
        .environment(settingsPreviewAppState())
        .frame(width: 360)
        .background(Theme.Colors.panelBackground)
}

@MainActor
private func settingsPreviewAppState() -> AppState {
    let appState = AppState(
        makePollingEngine: { _ in NoOpPollingController() },
        requestNotificationPermission: {}
    )
    appState.isLoading = false
    appState.authenticationStatus = .noToken
    return appState
}
