import Foundation
@testable import GitHubCommandCenter

extension PRState {
    static func fixture(
        number: Int = 1,
        title: String = "Test PR",
        repoFullName: String = "owner/repo",
        draftStatus: DraftStatus = .ready,
        ciStatus: CIStatus = .passing,
        reviewStatus: ReviewStatus = .none,
        mergeStatus: MergeStatus = .ready,
        createdByMe: Bool = false,
        reviewRequestedFromMe: Bool = false,
        assignedToMe: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_743_321_600)
    ) -> PRState {
        PRState(
            number: number,
            title: title,
            repoFullName: repoFullName,
            url: URL(string: "https://github.com/\(repoFullName)/pull/\(number)")!,
            headSHA: "abc123def456",
            draftStatus: draftStatus,
            ciStatus: ciStatus,
            reviewStatus: reviewStatus,
            mergeStatus: mergeStatus,
            assignment: Assignment(
                createdByMe: createdByMe,
                reviewRequestedFromMe: reviewRequestedFromMe,
                assignedToMe: assignedToMe
            ),
            updatedAt: updatedAt
        )
    }
}
