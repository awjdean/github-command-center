import Foundation

struct PRState: Identifiable, Equatable, Sendable {
    let number: Int
    let title: String
    let repoFullName: String  // "owner/repo"
    let url: URL
    let headSHA: String
    let draftStatus: DraftStatus
    let ciStatus: CIStatus
    let reviewStatus: ReviewStatus
    let mergeStatus: MergeStatus
    let assignment: Assignment
    let updatedAt: Date

    enum DraftStatus: Equatable, Sendable {
        case draft
        case ready
    }

    struct FailingCheck: Identifiable, Equatable, Sendable {
        let name: String
        let conclusion: String  // "failure", "timed_out", "cancelled", "action_required", "error"
        let url: URL?

        var id: String {
            if let url {
                return url.absoluteString
            }

            return "\(name)|\(conclusion)"
        }
    }

    enum CIStatus: Equatable, Sendable {
        case passing
        case failing(checks: [FailingCheck], totalChecks: Int)
        case pending
        case none  // no CI configured
    }

    enum ReviewStatus: Equatable, Sendable {
        case none
        case requested(by: [String])
        case changesRequested(by: [String])
        case approved(by: [String])
    }

    // Mapped from GitHub's undocumented mergeable_state field
    enum MergeStatus: Equatable, Sendable {
        case ready  // "clean"
        case conflicts  // "dirty"
        case behind  // branch needs updating before merge
        case blocked  // "blocked" — branch protection not satisfied
        case pending  // "unknown" or null — not yet computed
    }

    struct Assignment: Equatable, Sendable {
        let createdByMe: Bool
        let reviewRequestedFromMe: Bool
        let assignedToMe: Bool
    }

    enum TriageCategory: Sendable {
        case needsYourAction
        case waitingOnOthers
        case yourDraft
    }

    // MARK: - Computed

    var id: String {
        "\(repoFullName)#\(number)"
    }

    var triageCategory: TriageCategory {
        guard draftStatus == .ready else {
            if assignment.createdByMe || assignment.assignedToMe {
                return .yourDraft
            }
            return .waitingOnOthers
        }

        if assignment.reviewRequestedFromMe || assignment.assignedToMe {
            return .needsYourAction
        }

        if assignment.createdByMe {
            let ciNeedsAction: Bool
            if case .failing = ciStatus { ciNeedsAction = true } else { ciNeedsAction = false }

            let mergeNeedsAction = mergeStatus == .conflicts || mergeStatus == .behind

            let reviewNeedsAction: Bool
            switch reviewStatus {
            case .changesRequested: reviewNeedsAction = true
            case .approved where mergeStatus == .ready: reviewNeedsAction = true  // ready to merge
            default: reviewNeedsAction = false
            }

            if ciNeedsAction || mergeNeedsAction || reviewNeedsAction {
                return .needsYourAction
            }
        }

        return .waitingOnOthers
    }

    var urgencyScore: Int {
        guard draftStatus == .ready else { return 0 }
        var score = 0
        if case .failing = ciStatus, assignment.createdByMe { score += 3 }
        if case .changesRequested = reviewStatus, assignment.createdByMe { score += 3 }
        if mergeStatus == .conflicts || mergeStatus == .behind { score += 2 }
        if assignment.reviewRequestedFromMe { score += 2 }
        if assignment.assignedToMe && !assignment.createdByMe { score += 1 }
        if case .approved = reviewStatus, mergeStatus == .ready, assignment.createdByMe { score += 1 }
        return score
    }

    /// higher urgency first, then more recent first
    struct NeedsActionComparator: SortComparator {
        var order: SortOrder = .forward

        func compare(_ lhs: PRState, _ rhs: PRState) -> ComparisonResult {
            let result: ComparisonResult

            if lhs.urgencyScore != rhs.urgencyScore {
                result = lhs.urgencyScore > rhs.urgencyScore ? .orderedAscending : .orderedDescending
            } else if lhs.updatedAt != rhs.updatedAt {
                result = lhs.updatedAt > rhs.updatedAt ? .orderedAscending : .orderedDescending
            } else {
                result = .orderedSame
            }

            switch order {
            case .forward:
                return result
            case .reverse:
                switch result {
                case .orderedAscending: return .orderedDescending
                case .orderedDescending: return .orderedAscending
                case .orderedSame: return .orderedSame
                }
            }
        }
    }
    static let needsActionComparator = NeedsActionComparator()

    // Highest-precedence role label for display in the PR row
    var displayRole: String {
        if assignment.reviewRequestedFromMe { return "Review requested" }
        if assignment.assignedToMe { return "Assigned" }
        if assignment.createdByMe { return "Your PR" }
        return ""
    }
}
