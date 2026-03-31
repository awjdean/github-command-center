import OSLog
import SwiftUI

struct PRRowView: View {
    private static let logger = Logger(subsystem: Log.subsystem, category: "PRRowView")

    let pr: PRState
    @State private var isHovered = false
    @State private var isShowingOpenError = false
    @State private var openErrorMessage = ""

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                HStack(spacing: Theme.Spacing.xs) {
                    Button {
                        openPullRequest()
                    } label: {
                        Text("#\(pr.number)")
                            .font(Theme.Fonts.prNumber)
                            .foregroundColor(Theme.Colors.linkBlue)
                            .underline()
                    }
                    .buttonStyle(.plain)

                    if !pr.displayRole.isEmpty {
                        Text(pr.displayRole)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Theme.Colors.textMuted)
                            .padding(.horizontal, Theme.Spacing.xxs)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.panelSurface)
                            .cornerRadius(Theme.Spacing.xxxs)
                    }

                    Spacer()

                    if pr.draftStatus == .draft {
                        Text("DRAFT")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Theme.Colors.textMuted)
                            .padding(.horizontal, Theme.Spacing.xxxs)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Spacing.xxxs)
                                    .stroke(Theme.Colors.textMuted.opacity(0.5), lineWidth: 0.5)
                            )
                    }
                }

                Text(pr.title)
                    .font(Theme.Fonts.prTitle)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: Theme.Spacing.xs) {
                    Text(pr.repoFullName)
                        .font(Theme.Fonts.prRepo)
                        .foregroundColor(Theme.Colors.textMuted)

                    Spacer()

                    HStack(spacing: 5) {
                        StatusDotView(dimension: .ci, pr: pr)
                        StatusDotView(dimension: .review, pr: pr)
                        StatusDotView(dimension: .merge, pr: pr)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(isHovered ? Theme.Colors.panelSurface : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .accessibilityLabel(PRRowPresentation.accessibilityLabel(for: pr))
        .alert("Unable to Open Pull Request", isPresented: $isShowingOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openErrorMessage)
        }
    }

    private func openPullRequest() {
        if let failureMessage = ExternalURLPresentation.open(
            pr.url,
            logger: Self.logger,
            failureMessage: PRRowPresentation.openFailureMessage(for: pr)
        ) {
            openErrorMessage = failureMessage
            isShowingOpenError = true
        }
    }
}

enum PRRowPresentation {
    static func accessibilityLabel(for pr: PRState) -> String {
        "PR \(pr.number), \(pr.title), \(pr.repoFullName), \(statusSummary(for: pr))"
    }

    static func openFailureMessage(for pr: PRState) -> String {
        "GitHub Command Center couldn't open pull request #\(pr.number). URL: \(pr.url.absoluteString)"
    }

    private static func statusSummary(for pr: PRState) -> String {
        let ciSummary = ciStatusText(for: pr.ciStatus)
        let reviewSummary = reviewStatusText(for: pr.reviewStatus)
        let mergeSummary = mergeStatusText(for: pr.mergeStatus)
        return "CI \(ciSummary), review \(reviewSummary), merge \(mergeSummary)"
    }

    private static func ciStatusText(for status: PRState.CIStatus) -> String {
        switch status {
        case .passing:
            return "passing"
        case .failing:
            return "failing"
        case .pending:
            return "pending"
        case .none:
            return "not configured"
        }
    }

    private static func reviewStatusText(for status: PRState.ReviewStatus) -> String {
        switch status {
        case .approved:
            return "approved"
        case .changesRequested:
            return "changes requested"
        case .requested:
            return "requested"
        case .none:
            return "not started"
        }
    }

    private static func mergeStatusText(for status: PRState.MergeStatus) -> String {
        switch status {
        case .ready:
            return "ready"
        case .conflicts:
            return "conflicts"
        case .behind:
            return "branch behind"
        case .blocked:
            return "blocked"
        case .pending:
            return "pending"
        }
    }
}

enum ExternalURLPresentation {
    static func open(
        _ url: URL,
        logger: Logger,
        failureMessage: @autoclosure () -> String
    ) -> String? {
        guard NSWorkspace.shared.open(url) else {
            logger.error("Failed to open external URL: \(url.absoluteString, privacy: .public)")
            return failureMessage()
        }

        return nil
    }
}

#Preview("PR Row - Needs Action") {
    PRRowView(
        pr: prRowPreviewPR(
            number: 42,
            title: "Stabilize review queue ordering",
            repoFullName: "openai/github-command-center",
            ciStatus: .failing(
                checks: [.init(name: "Unit Tests", conclusion: "failure", url: URL(string: "https://github.com"))],
                totalChecks: 6
            ),
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )
    )
    .padding()
    .background(Theme.Colors.panelBackground)
}

private func prRowPreviewPR(
    number: Int,
    title: String,
    repoFullName: String,
    draftStatus: PRState.DraftStatus = .ready,
    ciStatus: PRState.CIStatus = .passing,
    reviewStatus: PRState.ReviewStatus = .none,
    mergeStatus: PRState.MergeStatus = .ready,
    createdByMe: Bool = false,
    reviewRequestedFromMe: Bool = false,
    assignedToMe: Bool = false,
    updatedAt: Date = Date()
) -> PRState {
    guard let pullRequestURL = URL(string: "https://github.com/\(repoFullName)/pull/\(number)") else {
        preconditionFailure("Invalid PR row preview URL for \(repoFullName)#\(number)")
    }

    return PRState(
        number: number,
        title: title,
        repoFullName: repoFullName,
        url: pullRequestURL,
        headSHA: "abc123def456",
        draftStatus: draftStatus,
        ciStatus: ciStatus,
        reviewStatus: reviewStatus,
        mergeStatus: mergeStatus,
        assignment: .init(
            createdByMe: createdByMe,
            reviewRequestedFromMe: reviewRequestedFromMe,
            assignedToMe: assignedToMe
        ),
        updatedAt: updatedAt
    )
}
