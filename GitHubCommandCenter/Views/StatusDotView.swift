import OSLog
import SwiftUI

enum StatusDimension {
    case ci, review, merge
}

struct StatusDotView: View {
    let dimension: StatusDimension
    let pr: PRState

    @State private var showingPopover = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)

                // Accessibility: show letter inside dot when "Differentiate without color" is on
                if differentiateWithoutColor {
                    Text(accessibilityLetter)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(accessibilityForegroundColor)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            if let failing = tooltip.failingCIChecks {
                CIFailingPopoverView(
                    checks: failing.checks,
                    totalChecks: failing.totalChecks
                )
            } else {
                StatusPopoverView(
                    label: tooltip.label,
                    detail: tooltip.detail
                )
            }
        }
    }

    private var tooltip: StatusDotTooltip {
        StatusDotTooltip(dimension: dimension, pr: pr)
    }

    // MARK: - Color

    private var dotColor: Color {
        switch dimension {
        case .ci: return ciColor
        case .review: return reviewColor
        case .merge: return mergeColor
        }
    }

    private var ciColor: Color {
        switch pr.ciStatus {
        case .passing: return Theme.Colors.statusGreen
        case .failing: return Theme.Colors.statusRed
        case .pending: return Theme.Colors.statusYellow
        case .none: return Theme.Colors.statusGray
        }
    }

    private var reviewColor: Color {
        switch pr.reviewStatus {
        case .approved: return Theme.Colors.statusGreen
        case .changesRequested: return Theme.Colors.statusRed
        case .requested: return Theme.Colors.statusYellow
        case .none: return Theme.Colors.statusGray
        }
    }

    private var mergeColor: Color {
        switch pr.mergeStatus {
        case .ready: return Theme.Colors.statusGreen
        case .conflicts: return Theme.Colors.statusRed
        case .behind, .blocked: return Theme.Colors.statusYellow
        case .pending: return Theme.Colors.statusGray
        }
    }

    // MARK: - Accessibility letter

    private var accessibilityLetter: String {
        switch dimension {
        case .ci:
            switch pr.ciStatus {
            case .passing: return "P"
            case .failing: return "X"
            case .pending: return "~"
            case .none: return "-"
            }
        case .review:
            switch pr.reviewStatus {
            case .approved: return "A"
            case .changesRequested: return "X"
            case .requested: return "~"
            case .none: return "-"
            }
        case .merge:
            switch pr.mergeStatus {
            case .ready: return "M"
            case .conflicts: return "C"
            case .behind: return "U"
            case .blocked: return "B"
            case .pending: return "~"
            }
        }
    }

    private var accessibilityForegroundColor: Color {
        switch dimension {
        case .ci:
            switch pr.ciStatus {
            case .pending:
                return .black
            case .passing, .failing, .none:
                return .white
            }
        case .review:
            switch pr.reviewStatus {
            case .requested:
                return .black
            case .approved, .changesRequested, .none:
                return .white
            }
        case .merge:
            switch pr.mergeStatus {
            case .behind, .blocked:
                return .black
            case .ready, .conflicts, .pending:
                return .white
            }
        }
    }

}

// MARK: - Tooltip data (extracted for testability)

struct StatusDotTooltip {
    private static let reviewerDisplayLimit = 2

    let dimension: StatusDimension
    let pr: PRState

    var label: String {
        switch dimension {
        case .ci: return "CI"
        case .review: return "REVIEW"
        case .merge: return "MERGE"
        }
    }

    var failingCIChecks: (checks: [PRState.FailingCheck], totalChecks: Int)? {
        guard dimension == .ci, case .failing(let checks, let total) = pr.ciStatus else {
            return nil
        }
        return (checks, total)
    }

    var detail: String {
        switch dimension {
        case .ci:
            switch pr.ciStatus {
            case .passing:
                return "All checks passing"
            case .failing(let checks, let total):
                let names = checks.map(\.name)
                guard !names.isEmpty else {
                    return "Failing (\(total) total)"
                }
                let display = names.prefix(2).joined(separator: ", ")
                let more = names.count > 2 ? " (+\(names.count - 2) more)" : ""
                return "\(display)\(more) failing (\(total) total)"
            case .pending:
                return "Checks in progress"
            case .none:
                return "No CI configured"
            }
        case .review:
            switch pr.reviewStatus {
            case .approved(let by):
                return "Approved by \(formattedReviewers(by, maxCount: Self.reviewerDisplayLimit))"
            case .changesRequested(let by):
                return "Changes requested by \(formattedReviewers(by, maxCount: Self.reviewerDisplayLimit))"
            case .requested(let from):
                return "Review requested from \(formattedReviewers(from, maxCount: Self.reviewerDisplayLimit))"
            case .none:
                return "No reviews"
            }
        case .merge:
            switch pr.mergeStatus {
            case .ready:
                return "Ready to merge"
            case .conflicts:
                return "Has merge conflicts"
            case .behind:
                return "Branch is behind base and needs updating"
            case .blocked:
                return "Merge blocked by branch protection"
            case .pending:
                return "Checking mergeability…"
            }
        }
    }

    private func formattedReviewers(_ reviewers: [String], maxCount: Int) -> String {
        let displayedReviewers = reviewers.prefix(maxCount).map { "@\($0)" }
        guard reviewers.count > maxCount else {
            return displayedReviewers.joined(separator: ", ")
        }

        return "\(displayedReviewers.joined(separator: ", ")) and \(reviewers.count - maxCount) more"
    }
}

// MARK: - Popover content

private struct CIFailingPopoverView: View {
    private static let logger = Logger(subsystem: Log.subsystem, category: "StatusDotView")

    let checks: [PRState.FailingCheck]
    let totalChecks: Int
    @State private var isShowingOpenError = false
    @State private var openErrorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("CI")
                .font(Theme.Fonts.sectionLabel)
                .tracking(0.5)
                .foregroundColor(Theme.Colors.textTertiary)

            Text("\(checks.count) of \(totalChecks) checks failing")
                .font(Theme.Fonts.footerText)
                .foregroundColor(Theme.Colors.textSecondary)

            Divider().background(Theme.Colors.textMuted.opacity(0.3))

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(checks) { check in
                        failingCheckRow(check)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: 320)
        .alert("Unable to Open Pull Request", isPresented: $isShowingOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(openErrorMessage)
        }
    }

    private func failingCheckRow(_ check: PRState.FailingCheck) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Colors.statusRed)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                if let url = check.url {
                    Button {
                        let failureMessage =
                            "GitHub Command Center couldn't open CI link \"\(check.name)\". "
                            + "URL: \(url.absoluteString)"
                        if let failureMessage = ExternalURLPresentation.open(
                            url,
                            logger: Self.logger,
                            failureMessage: failureMessage
                        ) {
                            openErrorMessage = failureMessage
                            isShowingOpenError = true
                        }
                    } label: {
                        Text(check.name)
                            .font(Theme.Fonts.tooltipDetail)
                            .foregroundColor(Theme.Colors.linkBlue)
                            .underline()
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(check.name)
                        .font(Theme.Fonts.tooltipDetail)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Text(conclusionLabel(check.conclusion))
                    .font(Theme.Fonts.tooltipLabel)
                    .foregroundColor(Theme.Colors.textMuted)
            }

            Spacer()
        }
    }

    private func conclusionLabel(_ conclusion: String) -> String {
        switch conclusion {
        case "failure": return "Failed"
        case "timed_out": return "Timed out"
        case "cancelled": return "Cancelled"
        case "action_required": return "Action required"
        case "error": return "Error"
        case "startup_failure": return "Startup failure"
        default: return conclusion.capitalized
        }
    }
}

private struct StatusPopoverView: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(Theme.Fonts.sectionLabel)
                .tracking(0.5)
                .foregroundColor(Theme.Colors.textTertiary)
            Text(detail)
                .font(Theme.Fonts.footerText)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .fixedSize()
    }
}

#Preview("CI Passing") {
    StatusDotView(dimension: .ci, pr: statusDotPreviewPR(ciStatus: .passing))
        .padding()
        .background(Theme.Colors.panelBackground)
}

#Preview("CI Failing") {
    StatusDotView(
        dimension: .ci,
        pr: statusDotPreviewPR(
            ciStatus: .failing(
                checks: [
                    .init(name: "lint", conclusion: "failure", url: nil),
                    .init(
                        name: "unit-tests",
                        conclusion: "failure",
                        url: statusDotPreviewURL(
                            "https://github.com/awjdean/github-command-center/actions/runs/1"
                        ),
                    ),
                ],
                totalChecks: 4
            )
        )
    )
    .padding()
    .background(Theme.Colors.panelBackground)
}

#Preview("Review Requested") {
    StatusDotView(
        dimension: .review,
        pr: statusDotPreviewPR(reviewStatus: .requested(by: ["octocat"]))
    )
    .padding()
    .background(Theme.Colors.panelBackground)
}

#Preview("Merge Conflicts") {
    StatusDotView(dimension: .merge, pr: statusDotPreviewPR(mergeStatus: .conflicts))
        .padding()
        .background(Theme.Colors.panelBackground)
}

private func statusDotPreviewPR(
    ciStatus: PRState.CIStatus = .passing,
    reviewStatus: PRState.ReviewStatus = .none,
    mergeStatus: PRState.MergeStatus = .ready
) -> PRState {
    PRState(
        number: 42,
        title: "Refine PR status previews",
        repoFullName: "awjdean/github-command-center",
        url: statusDotPreviewURL("https://github.com/awjdean/github-command-center/pull/42"),
        headSHA: "abc123def456",
        draftStatus: .ready,
        ciStatus: ciStatus,
        reviewStatus: reviewStatus,
        mergeStatus: mergeStatus,
        assignment: .init(createdByMe: true, reviewRequestedFromMe: false, assignedToMe: false),
        updatedAt: .now
    )
}

private func statusDotPreviewURL(_ string: String) -> URL {
    guard let url = URL(string: string) else {
        preconditionFailure("Invalid StatusDotView preview URL: \(string)")
    }
    return url
}
