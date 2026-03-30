import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()

    // Injected in tests to capture fired notifications without UNUserNotificationCenter.
    var notificationHandler: ((String, String) -> Void)?  // (title, body)

    init() {}

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // Detects state transitions between two poll cycles and fires notifications.
    func checkTransitions(from oldPRs: [PRState], to newPRs: [PRState], disappeared: [PRState]) {
        let oldByID = Dictionary(uniqueKeysWithValues: oldPRs.map { ($0.id, $0) })

        for new in newPRs {
            guard let old = oldByID[new.id] else { continue }

            // CI: passing/none → failing (only on your PRs)
            if new.assignment.createdByMe {
                let wasPassingOrNone: Bool
                switch old.ciStatus {
                case .passing, .none: wasPassingOrNone = true
                default: wasPassingOrNone = false
                }
                if wasPassingOrNone, case .failing(let names, _) = new.ciStatus {
                    let check = names.first ?? "a check"
                    fire(title: "CI Failing — #\(new.number)",
                         body: "\(check) failed on \"\(new.title)\"")
                }

                // Changes requested (on your PRs)
                if case .changesRequested(let reviewers) = new.reviewStatus {
                    if case .changesRequested = old.reviewStatus {} else {
                        let who = reviewers.first.map { "@\($0)" } ?? "A reviewer"
                        fire(title: "Changes Requested — #\(new.number)",
                             body: "\(who) requested changes on \"\(new.title)\"")
                    }
                }

                // Approved (on your PRs)
                if case .approved(let reviewers) = new.reviewStatus {
                    if case .approved = old.reviewStatus {} else {
                        let who = reviewers.first.map { "@\($0)" } ?? "A reviewer"
                        fire(title: "PR Approved — #\(new.number)",
                             body: "\(who) approved \"\(new.title)\"")
                    }
                }

                // Merge conflicts detected (on your PRs)
                if new.mergeStatus == .conflicts && old.mergeStatus != .conflicts {
                    fire(title: "Merge Conflict — #\(new.number)",
                         body: "Conflicts detected in \"\(new.title)\"")
                }
            }

            // Review requested from you (any PR)
            if new.assignment.reviewRequestedFromMe && !old.assignment.reviewRequestedFromMe {
                fire(title: "Review Requested — #\(new.number)",
                     body: "You've been asked to review \"\(new.title)\"")
            }
        }

        // PR merged or closed
        for pr in disappeared {
            fire(title: "PR Closed — #\(pr.number)",
                 body: "\"\(pr.title)\" was merged or closed")
        }
    }

    func fire(title: String, body: String) {
        if let handler = notificationHandler {
            handler(title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
