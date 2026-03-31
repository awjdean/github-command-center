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
        case .passing: return .statusGreen
        case .failing: return .statusRed
        case .pending: return .statusYellow
        case .none: return .statusGray
        }
    }

    private var reviewColor: Color {
        switch pr.reviewStatus {
        case .approved: return .statusGreen
        case .changesRequested: return .statusRed
        case .requested: return .statusYellow
        case .none: return .statusGray
        }
    }

    private var mergeColor: Color {
        switch pr.mergeStatus {
        case .ready: return .statusGreen
        case .conflicts: return .statusRed
        case .behind, .blocked: return .statusYellow
        case .pending: return .statusGray
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
                return "Approved by \(by.map { "@\($0)" }.joined(separator: ", "))"
            case .changesRequested(let by):
                return "Changes requested by \(by.map { "@\($0)" }.joined(separator: ", "))"
            case .requested(let from):
                let who = from.prefix(2).map { "@\($0)" }.joined(separator: ", ")
                return "Review requested from \(who)"
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
}

// MARK: - Popover content

private struct CIFailingPopoverView: View {
    let checks: [PRState.FailingCheck]
    let totalChecks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("CI")
                .font(.sectionLabel)
                .tracking(0.5)
                .foregroundColor(.textTertiary)

            Text("\(checks.count) of \(totalChecks) checks failing")
                .font(.footerText)
                .foregroundColor(.textSecondary)

            Divider().background(Color.textMuted.opacity(0.3))

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(checks) { check in
                        failingCheckRow(check)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: 320)
    }

    private func failingCheckRow(_ check: PRState.FailingCheck) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(Color.statusRed)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                if let url = check.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text(check.name)
                            .font(.tooltipDetail)
                            .foregroundColor(.linkBlue)
                            .underline()
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(check.name)
                        .font(.tooltipDetail)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Text(conclusionLabel(check.conclusion))
                    .font(.tooltipLabel)
                    .foregroundColor(.textMuted)
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
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(.sectionLabel)
                .tracking(0.5)
                .foregroundColor(.textTertiary)
            Text(detail)
                .font(.footerText)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .fixedSize()
    }
}
