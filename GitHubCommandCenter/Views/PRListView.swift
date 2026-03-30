import SwiftUI
import ServiceManagement

struct PRListView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(spacing: 0) {
            headerView

            // Stale / rate-limit warning bar
            if appState.isRateLimited {
                warningBar(
                    text: "Rate limited" + (appState.rateLimitResetDate.map {
                        " — resets \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()))"
                    } ?? ""),
                    color: .statusRed
                )
            } else if appState.isStale {
                warningBar(
                    text: "Data may be outdated — last update \(formattedLastUpdated)",
                    color: .statusYellow
                )
            }

            // Auth error banner
            if case .failed = appState.authenticationStatus {
                authErrorBanner
            } else if case .noToken = appState.authenticationStatus {
                noTokenBanner
            }

            // Main content
            ScrollView {
                LazyVStack(spacing: 0) {
                    switch appState.panelContentState {
                    case .loading:
                        skeletonView
                    case .setupRequired:
                        setupStateView
                    case .authError:
                        authFailedStateView
                    case .empty:
                        emptyStateView
                    case .prList:
                        prSections
                    }

                    // Recently closed (transient)
                    if !appState.recentlyClosedPRs.isEmpty {
                        sectionHeader("RECENTLY CLOSED")
                        ForEach(appState.recentlyClosedPRs) { pr in
                            PRRowView(pr: pr).opacity(0.5)
                            Divider().background(Color.textMuted.opacity(0.2))
                        }
                    }
                }
            }
            .frame(maxHeight: 400)

            footerView
        }
        .frame(width: 360)
        .background(Color.panelBackground)
        .onAppear { appState.startPollingIfNeeded() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("GitHub Command Center")
                    .font(.panelTitle)
                    .foregroundColor(.textPrimary)
                Text("\(appState.prs.count) open PR\(appState.prs.count == 1 ? "" : "s")")
                    .font(.panelSubtitle)
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear")
                    .imageScale(.medium)
                    .foregroundColor(.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - PR sections

    @ViewBuilder
    private var prSections: some View {
        let needsAction = appState.needsActionPRs
        let waiting = appState.waitingOnOthersPRs

        if !needsAction.isEmpty {
            sectionHeader("NEEDS YOUR ACTION")
            ForEach(needsAction) { pr in
                PRRowView(pr: pr)
                Divider().background(Color.textMuted.opacity(0.2))
            }
        }

        if !waiting.isEmpty {
            sectionHeader("WAITING ON OTHERS")
            ForEach(waiting) { pr in
                PRRowView(pr: pr).opacity(0.55)
                Divider().background(Color.textMuted.opacity(0.2))
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .tracking(1)
            .foregroundColor(.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - Loading skeleton

    private var skeletonView: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRowView()
                Divider().background(Color.textMuted.opacity(0.2))
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.statusGreen)
            Text("All clear. No open pull requests.")
                .font(.prTitle)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var setupStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundColor(.statusYellow)
            Text("Add a GitHub token in Settings to start tracking pull requests.")
                .font(.prTitle)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    private var authFailedStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.statusRed)
            Text("Update your GitHub token in Settings to resume tracking pull requests.")
                .font(.prTitle)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    // MARK: - Error banners

    private var authErrorBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.statusRed)
            Text("Authentication failed")
                .font(.footerText)
                .foregroundColor(.textSecondary)
            Spacer()
            Button("Fix") { openSettings() }
                .font(.footerText)
                .foregroundColor(.linkBlue)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.statusRed.opacity(0.15))
    }

    private var noTokenBanner: some View {
        HStack {
            Image(systemName: "key.fill")
                .foregroundColor(.statusYellow)
            Text("Add a GitHub token to get started")
                .font(.footerText)
                .foregroundColor(.textSecondary)
            Spacer()
            Button("Add token") { openSettings() }
                .font(.footerText)
                .foregroundColor(.linkBlue)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.statusYellow.opacity(0.15))
    }

    private func warningBar(text: String, color: Color) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(.footerText)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
    }

    // MARK: - Footer

    private var footerView: some View {
        VStack(spacing: 0) {
            Divider().background(Color.textMuted.opacity(0.2))
            HStack {
                // Last updated + refresh
                if appState.lastUpdated != nil {
                    Text("Updated \(formattedLastUpdated)")
                        .font(.footerText)
                        .foregroundColor(.textMuted)
                } else {
                    Text(appState.isLoading ? "Loading…" : "Never updated")
                        .font(.footerText)
                        .foregroundColor(.textMuted)
                }

                Spacer()

                Button {
                    appState.forceRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Refresh (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            HStack {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .font(.footerText)
                    .foregroundColor(.textMuted)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Silently revert if registration fails
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.footerText)
                .foregroundColor(.textMuted)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Helpers

    private var formattedLastUpdated: String {
        guard let date = appState.lastUpdated else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Skeleton row

private struct SkeletonRowView: View {
    @State private var shimmerOffset: CGFloat = -200
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(shimmerColor).frame(width: 60, height: 10)
                RoundedRectangle(cornerRadius: 3).fill(shimmerColor).frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(shimmerColor).frame(width: 80, height: 8)
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(shimmerColor).frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }

    private var shimmerColor: Color {
        Color.panelSurface.opacity(0.8)
    }
}
