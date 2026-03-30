import SwiftUI

enum StatusDimension {
    case ci, review, merge
}

struct StatusDotView: View {
    let dimension: StatusDimension
    let pr: PRState

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            // Accessibility: show letter inside dot when "Differentiate without color" is on
            if differentiateWithoutColor {
                Text(accessibilityLetter)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .help("\(tooltipLabel): \(tooltipDetail)")
    }

    // MARK: - Color

    private var dotColor: Color {
        switch dimension {
        case .ci:     return ciColor
        case .review: return reviewColor
        case .merge:  return mergeColor
        }
    }

    private var ciColor: Color {
        switch pr.ciStatus {
        case .passing:  return .statusGreen
        case .failing:  return .statusRed
        case .pending:  return .statusYellow
        case .none:     return .statusGray
        }
    }

    private var reviewColor: Color {
        switch pr.reviewStatus {
        case .approved:          return .statusGreen
        case .changesRequested:  return .statusRed
        case .requested:         return .statusYellow
        case .none:              return .statusGray
        }
    }

    private var mergeColor: Color {
        switch pr.mergeStatus {
        case .ready:     return .statusGreen
        case .conflicts: return .statusRed
        case .blocked:   return .statusYellow
        case .pending:   return .statusGray
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
            case .none:    return "-"
            }
        case .review:
            switch pr.reviewStatus {
            case .approved:         return "A"
            case .changesRequested: return "X"
            case .requested:        return "~"
            case .none:             return "-"
            }
        case .merge:
            switch pr.mergeStatus {
            case .ready:     return "M"
            case .conflicts: return "C"
            case .blocked:   return "B"
            case .pending:   return "~"
            }
        }
    }

    // MARK: - Tooltip

    private var tooltipLabel: String {
        switch dimension {
        case .ci:     return "CI"
        case .review: return "REVIEW"
        case .merge:  return "MERGE"
        }
    }

    private var tooltipDetail: String {
        switch dimension {
        case .ci:
            switch pr.ciStatus {
            case .passing:
                return "All checks passing"
            case .failing(let names, let total):
                let failing = names.prefix(2).joined(separator: ", ")
                let more = names.count > 2 ? " (+\(names.count - 2) more)" : ""
                return "\(failing)\(more) failing (\(total) total)"
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
            case .blocked:
                return "Merge blocked by branch protection"
            case .pending:
                return "Checking mergeability…"
            }
        }
    }
}
