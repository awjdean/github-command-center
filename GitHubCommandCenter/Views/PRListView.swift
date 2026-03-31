import SwiftUI

enum PanelMode {
    case pullRequests
    case settings

    static let width: CGFloat = 480

    var headerTitle: String {
        switch self {
        case .pullRequests: "GitHub Command Center"
        case .settings: "Settings"
        }
    }

    var showsBackButton: Bool {
        self == .settings
    }

    var showsRefreshRow: Bool {
        self == .pullRequests
    }

    var showsInlineAppControls: Bool {
        self == .settings
    }
}

struct PRListView: View {
    @Environment(AppState.self) private var appState
    @State private var panelMode: PanelMode

    init(initialPanelMode: PanelMode = .pullRequests) {
        _panelMode = State(initialValue: initialPanelMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            bannerSection
            contentView
            footerView
        }
        .frame(width: PanelMode.width)
        .background(Theme.Colors.panelBackground)
        .animation(.easeInOut(duration: 0.2), value: panelMode)
        .onAppear {
            appState.startPollingIfNeeded()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            if panelMode.showsBackButton {
                Button {
                    panelMode = .pullRequests
                } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Back")
            }

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(panelMode.headerTitle)
                    .font(.panelTitle)
                    .foregroundColor(Theme.Colors.textPrimary)
                panelSubtitleView
            }
            Spacer()

            if panelMode == .pullRequests {
                Button {
                    panelMode = .settings
                } label: {
                    Image(systemName: "gear")
                        .imageScale(.medium)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var panelSubtitle: String {
        switch panelMode {
        case .pullRequests:
            appState.panelSubtitleText
        case .settings:
            ""
        }
    }

    @ViewBuilder
    private var panelSubtitleView: some View {
        let actionCount = appState.menuBarBadgeCount
        if panelMode == .pullRequests && actionCount > 0 {
            (Text(panelSubtitle)
                .foregroundColor(Theme.Colors.textTertiary)
                + Text("  ·  ")
                .foregroundColor(Theme.Colors.textMuted)
                + Text("\(actionCount) need attention")
                .foregroundColor(Theme.Colors.statusYellow))
                .font(.panelSubtitle)
        } else if !panelSubtitle.isEmpty {
            Text(panelSubtitle)
                .font(.panelSubtitle)
                .foregroundColor(Theme.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private var bannerSection: some View {
        if panelMode == .pullRequests {
            if appState.isRateLimited {
                warningBar(
                    text: "Rate limited"
                        + (appState.rateLimitResetDate.map {
                            " — resets \(Self.relativeDateFormatter.localizedString(for: $0, relativeTo: Date()))"
                        } ?? ""),
                    color: Theme.Colors.statusRed
                )
            } else if appState.isStale {
                warningBar(
                    text: "Data may be outdated — last update \(formattedLastUpdated)",
                    color: Theme.Colors.statusYellow
                )
            }

            if case .failed = appState.authenticationStatus {
                authErrorBanner
            } else if case .noToken = appState.authenticationStatus {
                noTokenBanner
            }
        }
    }

    private var contentView: some View {
        ScrollView {
            if panelMode == .pullRequests {
                LazyVStack(spacing: 0) {
                    switch appState.panelContentState {
                    case .loading:
                        skeletonView
                    case .setupRequired:
                        setupStateView
                    case .authError:
                        authFailedStateView
                    case .loadError:
                        loadErrorStateView
                    case .empty:
                        emptyStateView
                    case .prList:
                        prSections
                    }

                    if appState.showsRecentlyClosedSection {
                        sectionHeader("RECENTLY CLOSED")
                        ForEach(appState.recentlyClosedPRs) { pr in
                            PRRowView(pr: pr).opacity(0.5)
                            themedDivider()
                        }
                    }
                }
            } else {
                SettingsContentView(showsAppControls: panelMode.showsInlineAppControls)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: panelMode == .settings ? 700 : 600)
    }

    // MARK: - PR sections

    @ViewBuilder
    private var prSections: some View {
        let needsAction = appState.needsActionPRs
        let waiting = appState.waitingOnOthersPRs
        let drafts = appState.yourDraftPRs

        if !needsAction.isEmpty {
            sectionHeader("NEEDS YOUR ACTION")
            ForEach(needsAction) { pr in
                PRRowView(pr: pr)
                themedDivider()
            }
        }

        if !waiting.isEmpty {
            sectionHeader("WAITING ON OTHERS")
            ForEach(waiting) { pr in
                PRRowView(pr: pr).opacity(0.55)
                themedDivider()
            }
        }

        if !drafts.isEmpty {
            sectionHeader("YOUR DRAFT PRs")
            ForEach(drafts) { pr in
                PRRowView(pr: pr).opacity(0.5)
                themedDivider()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .tracking(1)
            .foregroundColor(Theme.Colors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxs)
    }

    // MARK: - Loading skeleton

    private var skeletonView: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRowView()
                themedDivider()
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(Theme.Colors.statusGreen)
            Text("No tracked pull requests right now.")
                .font(.prTitle)
                .foregroundColor(Theme.Colors.textSecondary)
            if let emptyStateMessage = appState.emptyStateMessage {
                Text(emptyStateMessage)
                    .font(.footerText)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxxl)
    }

    private var setupStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundColor(Theme.Colors.statusYellow)
            Text("Add a GitHub token in Settings to start tracking pull requests.")
                .font(.prTitle)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxxl)
    }

    private var authFailedStateView: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundColor(Theme.Colors.statusRed)
            Text("Update your GitHub token in Settings to resume tracking pull requests.")
                .font(.prTitle)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxxl)
    }

    private var loadErrorStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(Theme.Colors.statusRed)
            Text(appState.error?.errorDescription ?? "Unable to load pull requests right now.")
                .font(.prTitle)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                appState.forceRefresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.xxxl)
    }

    // MARK: - Error banners

    private var authErrorBanner: some View {
        actionBanner(
            icon: "exclamationmark.circle.fill",
            text: "Authentication failed",
            buttonLabel: "Fix",
            color: Theme.Colors.statusRed
        )
    }

    private var noTokenBanner: some View {
        actionBanner(
            icon: "key.fill",
            text: "Add a GitHub token to get started",
            buttonLabel: "Add token",
            color: Theme.Colors.statusYellow
        )
    }

    private func actionBanner(icon: String, text: String, buttonLabel: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.footerText)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Button {
                panelMode = .settings
            } label: {
                Text(buttonLabel)
                    .font(.footerText)
                    .foregroundColor(Theme.Colors.linkBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
        .background(color.opacity(0.15))
    }

    private func warningBar(text: String, color: Color) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(.footerText)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.12))
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerView: some View {
        if panelMode.showsRefreshRow {
            VStack(spacing: 0) {
                themedDivider()

                HStack {
                    if appState.lastUpdated != nil {
                        Text("Updated \(formattedLastUpdated)")
                            .font(.footerText)
                            .foregroundColor(Theme.Colors.textMuted)
                    } else {
                        Text(appState.isLoading ? "Loading…" : "Never updated")
                            .font(.footerText)
                            .foregroundColor(Theme.Colors.textMuted)
                    }

                    Spacer()

                    Button {
                        appState.forceRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.small)
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh (⌘R)")
                    .keyboardShortcut("r", modifiers: .command)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - Helpers

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func themedDivider() -> some View {
        Divider().background(Theme.Colors.textMuted.opacity(0.2))
    }

    private var formattedLastUpdated: String {
        guard let date = appState.lastUpdated else { return "—" }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("PR Panel") {
    PRListView()
        .environment(previewAppState(with: previewPRs))
}

#Preview("Settings Panel") {
    PRListView(initialPanelMode: .settings)
        .environment(previewAppState())
}

@MainActor
private func previewAppState(with prs: [PRState] = []) -> AppState {
    let appState = AppState(
        makePollingEngine: { _ in NoOpPollingController() },
        requestNotificationPermission: {}
    )
    appState.isLoading = false
    appState.prs = prs
    appState.authenticationStatus = .noToken
    return appState
}

private let previewPRs = [
    PRState(
        number: 12,
        title: "Refine menu bar panel layout",
        repoFullName: "awjdean/github-command-center",
        url: previewURL("https://github.com/awjdean/github-command-center/pull/12"),
        headSHA: "abc123",
        draftStatus: .ready,
        ciStatus: .failing(checks: [.init(name: "unit-tests", conclusion: "failure", url: nil)], totalChecks: 3),
        reviewStatus: .changesRequested(by: ["octocat"]),
        mergeStatus: .conflicts,
        assignment: .init(createdByMe: true, reviewRequestedFromMe: false, assignedToMe: false),
        updatedAt: .now
    ),
    PRState(
        number: 34,
        title: "Add inline settings screen",
        repoFullName: "awjdean/github-command-center",
        url: previewURL("https://github.com/awjdean/github-command-center/pull/34"),
        headSHA: "def456",
        draftStatus: .ready,
        ciStatus: .passing,
        reviewStatus: .requested(by: ["teammate"]),
        mergeStatus: .ready,
        assignment: .init(createdByMe: true, reviewRequestedFromMe: false, assignedToMe: false),
        updatedAt: .now.addingTimeInterval(-3_600)
    ),
    PRState(
        number: 56,
        title: "WIP: Extract polling into background actor",
        repoFullName: "awjdean/github-command-center",
        url: previewURL("https://github.com/awjdean/github-command-center/pull/56"),
        headSHA: "ghi789",
        draftStatus: .draft,
        ciStatus: .pending,
        reviewStatus: .none,
        mergeStatus: .pending,
        assignment: .init(createdByMe: true, reviewRequestedFromMe: false, assignedToMe: false),
        updatedAt: .now.addingTimeInterval(-7_200)
    ),
]

private func previewURL(_ string: String) -> URL {
    guard let url = URL(string: string) else {
        preconditionFailure("Invalid preview URL: \(string)")
    }

    return url
}

// MARK: - Skeleton row

private struct SkeletonRowView: View {
    @State private var shimmerOffset: CGFloat = -200
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        skeletonContent
            .overlay(alignment: .leading) {
                shimmerSweep
                    .mask(skeletonContent)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 200
                }
            }
            .onDisappear {
                shimmerOffset = -200
            }
    }

    private var skeletonContent: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: 3).fill(shimmerColor).frame(width: 60, height: 10)
                RoundedRectangle(cornerRadius: 3).fill(shimmerColor).frame(
                    maxWidth: .infinity,
                    minHeight: 10,
                    maxHeight: 10
                )
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
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.sm)
    }

    private var shimmerColor: Color {
        Theme.Colors.panelSurface.opacity(0.8)
    }

    private var shimmerSweep: some View {
        LinearGradient(
            colors: [
                shimmerColor.opacity(0),
                shimmerColor.opacity(0.9),
                shimmerColor.opacity(0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 120)
        .offset(x: shimmerOffset)
    }
}
