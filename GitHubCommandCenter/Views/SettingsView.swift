import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var tokenInput = ""
    @State private var tokenState: TokenState = .empty
    @State private var isValidating = false

    enum TokenState {
        case empty
        case valid(username: String)
        case invalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // GitHub Token section
            VStack(alignment: .leading, spacing: 8) {
                Text("GitHub Token")
                    .font(.headline)

                SecureField("Paste your GitHub token here", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderColor, lineWidth: 1.5)
                    )
                    .onChange(of: tokenInput) { _ in
                        tokenState = tokenInput.isEmpty ? .empty : tokenState
                    }

                // Status indicator
                HStack(spacing: 6) {
                    switch tokenState {
                    case .empty:
                        EmptyView()
                    case .valid(let username):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connected as @\(username)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .invalid:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Invalid token. Check scopes.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Needs: **repo** (read) scope")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Create token at github.com/settings/tokens",
                     destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.caption)

                HStack {
                    Button(isValidating ? "Validating…" : "Save Token") {
                        saveToken()
                    }
                    .disabled(tokenInput.isEmpty || isValidating)
                    .buttonStyle(.borderedProminent)

                    if !tokenInput.isEmpty && !isValidating {
                        Button("Clear") {
                            clearToken()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Divider()

            // About section
            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Command Center")
                    .font(.headline)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Open source, MIT License")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link("View on GitHub",
                     destination: URL(string: "https://github.com/awjdean/github-command-center")!)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { loadSavedToken() }
    }

    private var borderColor: Color {
        switch tokenState {
        case .empty:   return .clear
        case .valid:   return .green.opacity(0.7)
        case .invalid: return .red.opacity(0.7)
        }
    }

    private func loadSavedToken() {
        if let saved = try? KeychainService.shared.loadToken(), !saved.isEmpty {
            tokenInput = saved
            if case .authenticated(let username) = appState.authenticationStatus {
                tokenState = .valid(username: username)
            }
        }
    }

    private func saveToken() {
        guard !tokenInput.isEmpty else { return }
        isValidating = true

        Task {
            do {
                let client = GitHubRESTClient(token: tokenInput)
                let username = try await client.validateTokenForAppAccess()
                try KeychainService.shared.saveToken(tokenInput)
                tokenState = .valid(username: username)
                appState.resetPolling()
            } catch {
                tokenState = .invalid
            }
            isValidating = false
        }
    }

    private func clearToken() {
        try? KeychainService.shared.deleteToken()
        tokenInput = ""
        tokenState = .empty
        appState.resetPolling()
    }
}
