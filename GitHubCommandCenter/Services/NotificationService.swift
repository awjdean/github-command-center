import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private static let pullRequestUpdatesThreadIdentifier = "pull_request_updates"
    private let stateQueue = DispatchQueue(label: "NotificationService.state")
    private var storedNotificationHandler: ((String, String) -> Void)?

    // Injected in tests to capture fired notifications without UNUserNotificationCenter.
    var notificationHandler: ((String, String) -> Void)? {  // (title, body)
        get { stateQueue.sync { storedNotificationHandler } }
        set { stateQueue.sync { storedNotificationHandler = newValue } }
    }

    init() {}

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // Detects state transitions between two poll cycles and fires notifications.
    func checkTransitions(from oldPRs: [PRState], to newPRs: [PRState], disappeared: [PRState]) {
        let oldByID = Self.prsByID(oldPRs)

        for new in newPRs {
            guard let old = oldByID[new.id] else { continue }

            // CI: any non-failing state → failing (only on your PRs)
            if new.assignment.createdByMe {
                let wasFailing: Bool
                if case .failing = old.ciStatus {
                    wasFailing = true
                } else {
                    wasFailing = false
                }
                if !wasFailing, case .failing(let checks, _) = new.ciStatus {
                    let check = checks.first?.name ?? "a check"
                    fire(
                        title: "CI Failing — #\(new.number)",
                        body: "\(check) failed on \"\(new.title)\""
                    )
                }

                if case .changesRequested(let reviewers) = new.reviewStatus {
                    notifyChangesRequestedIfNeeded(from: old.reviewStatus, reviewers: reviewers, pr: new)
                }

                if case .approved(let reviewers) = new.reviewStatus {
                    notifyApprovalIfNeeded(from: old.reviewStatus, reviewers: reviewers, pr: new)
                }

                // Merge conflicts detected (on your PRs)
                if new.mergeStatus == .conflicts && old.mergeStatus != .conflicts {
                    fire(
                        title: "Merge Conflict — #\(new.number)",
                        body: "Conflicts detected in \"\(new.title)\""
                    )
                }
            }

            // Review requested from you (any PR)
            if new.assignment.reviewRequestedFromMe && !old.assignment.reviewRequestedFromMe {
                fire(
                    title: "Review Requested — #\(new.number)",
                    body: "You've been asked to review \"\(new.title)\""
                )
            }
        }

        // PR merged or closed
        for pr in disappeared where pr.assignment.createdByMe {
            fire(
                title: "PR Closed — #\(pr.number)",
                body: "\"\(pr.title)\" was merged or closed"
            )
        }
    }

    private func notifyChangesRequestedIfNeeded(
        from oldStatus: PRState.ReviewStatus,
        reviewers: [String],
        pr: PRState
    ) {
        if case .changesRequested = oldStatus { return }

        let who = reviewers.first.map { "@\($0)" } ?? "A reviewer"
        fire(
            title: "Changes Requested — #\(pr.number)",
            body: "\(who) requested changes on \"\(pr.title)\""
        )
    }

    private func notifyApprovalIfNeeded(
        from oldStatus: PRState.ReviewStatus,
        reviewers: [String],
        pr: PRState
    ) {
        if case .approved = oldStatus { return }

        let who = reviewers.first.map { "@\($0)" } ?? "A reviewer"
        fire(
            title: "PR Approved — #\(pr.number)",
            body: "\(who) approved \"\(pr.title)\""
        )
    }

    static func prsByID(_ prs: [PRState]) -> [String: PRState] {
        Dictionary(prs.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    private func fire(title: String, body: String) {
        let handler = stateQueue.sync { storedNotificationHandler }
        if let handler {
            handler(title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = Self.pullRequestUpdatesThreadIdentifier

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
