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
    @EnvironmentObject var appState: AppState
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
        .background(Color.panelBackground)
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
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Back")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(panelMode.headerTitle)
                    .font(.panelTitle)
                    .foregroundColor(.textPrimary)
                panelSubtitleView
            }
            Spacer()

            if panelMode == .pullRequests {
                Button {
                    panelMode = .settings
                } label: {
                    Image(systemName: "gear")
                        .imageScale(.medium)
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                .foregroundColor(.textTertiary)
                + Text("  ·  ")
                .foregroundColor(.textMuted)
                + Text("\(actionCount) need attention")
                .foregroundColor(.statusYellow))
                .font(.panelSubtitle)
        } else if !panelSubtitle.isEmpty {
            Text(panelSubtitle)
                .font(.panelSubtitle)
                .foregroundColor(.textTertiary)
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
                    color: .statusRed
                )
            } else if appState.isStale {
                warningBar(
                    text: "Data may be outdated — last update \(formattedLastUpdated)",
                    color: .statusYellow
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

                    if !appState.recentlyClosedPRs.isEmpty {
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
                themedDivider()
            }
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundColor(.statusGreen)
            Text("No tracked pull requests right now.")
                .font(.prTitle)
                .foregroundColor(.textSecondary)
            if let emptyStateMessage = appState.emptyStateMessage {
                Text(emptyStateMessage)
                    .font(.footerText)
                    .foregroundColor(.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
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

    private var loadErrorStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(.statusRed)
            Text(appState.error?.errorDescription ?? "Unable to load pull requests right now.")
                .font(.prTitle)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                appState.forceRefresh()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    // MARK: - Error banners

    private var authErrorBanner: some View {
        actionBanner(
            icon: "exclamationmark.circle.fill",
            text: "Authentication failed",
            buttonLabel: "Fix",
            color: .statusRed
        )
    }

    private var noTokenBanner: some View {
        actionBanner(
            icon: "key.fill",
            text: "Add a GitHub token to get started",
            buttonLabel: "Add token",
            color: .statusYellow
        )
    }

    private func actionBanner(icon: String, text: String, buttonLabel: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.footerText)
                .foregroundColor(.textSecondary)
            Spacer()
            Button {
                panelMode = .settings
            } label: {
                Text(buttonLabel)
                    .font(.footerText)
                    .foregroundColor(.linkBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.15))
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

    @ViewBuilder
    private var footerView: some View {
        if panelMode.showsRefreshRow {
            VStack(spacing: 0) {
                themedDivider()

                HStack {
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
        Divider().background(Color.textMuted.opacity(0.2))
    }

    private var formattedLastUpdated: String {
        guard let date = appState.lastUpdated else { return "—" }
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("PR Panel") {
    PRListView()
        .environmentObject(previewAppState(with: previewPRs))
}

#Preview("Settings Panel") {
    PRListView(initialPanelMode: .settings)
        .environmentObject(previewAppState())
}

@MainActor
private func previewAppState(with prs: [PRState] = []) -> AppState {
    let appState = AppState(
        makePollingEngine: { _ in PreviewPollingController() },
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

@MainActor
private final class PreviewPollingController: PollingControlling {
    func start() {}
    func stop() {}
    func reset() {}
    func forceRefresh() {}
}

// MARK: - Skeleton row

private struct SkeletonRowView: View {
    @State private var shimmerOffset: CGFloat = -200
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
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
