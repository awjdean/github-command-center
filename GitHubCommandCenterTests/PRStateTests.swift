import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite
struct PRStateTests {
    @Test
    func id_sameNumberDifferentRepos_areDistinct() {
        let first = PRState.fixture(number: 42, repoFullName: "org/one")
        let second = PRState.fixture(number: 42, repoFullName: "org/two")

        #expect(first.id != second.id)
    }

    @Test
    func triageCategory_reviewRequestedFromMe_needsAction() {
        let pr = PRState.fixture(reviewRequestedFromMe: true)
        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_assignedToMe_needsAction() {
        let pr = PRState.fixture(assignedToMe: true)
        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_createdByMe_ciFailing_needsAction() {
        let pr = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "unit-tests", conclusion: "failure", url: nil)], totalChecks: 3),
            createdByMe: true
        )

        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_createdByMe_changesRequested_needsAction() {
        let pr = PRState.fixture(
            reviewStatus: .changesRequested(by: ["reviewer"]),
            createdByMe: true
        )

        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_createdByMe_mergeConflicts_needsAction() {
        let pr = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)
        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_createdByMe_branchBehind_needsAction() {
        let pr = PRState.fixture(mergeStatus: .behind, createdByMe: true)
        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_createdByMe_approvedAndClean_needsAction() {
        let pr = PRState.fixture(
            reviewStatus: .approved(by: ["reviewer"]),
            mergeStatus: .ready,
            createdByMe: true
        )

        #expect(pr.triageCategory == .needsYourAction)
    }

    @Test
    func triageCategory_createdByMe_allGreenWaitingReview_waitingOnOthers() {
        let pr = PRState.fixture(
            ciStatus: .passing,
            reviewStatus: .none,
            mergeStatus: .ready,
            createdByMe: true
        )

        #expect(pr.triageCategory == .waitingOnOthers)
    }

    @Test
    func triageCategory_createdByMe_reviewRequested_waitingOnOthers() {
        let pr = PRState.fixture(
            reviewStatus: .requested(by: ["reviewer"]),
            createdByMe: true
        )

        #expect(pr.triageCategory == .waitingOnOthers)
    }

    @Test
    func triageCategory_draft_reviewRequestedOnly_waitingOnOthers() {
        let pr = PRState.fixture(draftStatus: .draft, reviewRequestedFromMe: true)
        #expect(pr.triageCategory == .waitingOnOthers)
    }

    @Test
    func triageCategory_draft_createdByMe_yourDraft() {
        let pr = PRState.fixture(draftStatus: .draft, createdByMe: true)
        #expect(pr.triageCategory == .yourDraft)
    }

    @Test
    func triageCategory_draft_assignedToMe_yourDraft() {
        let pr = PRState.fixture(draftStatus: .draft, assignedToMe: true)
        #expect(pr.triageCategory == .yourDraft)
    }

    @Test
    func triageCategory_draft_createdByMeAndReviewRequested_yourDraft() {
        let pr = PRState.fixture(draftStatus: .draft, createdByMe: true, reviewRequestedFromMe: true)
        #expect(pr.triageCategory == .yourDraft)
    }

    @Test
    func triageCategory_draft_notMine_waitingOnOthers() {
        let pr = PRState.fixture(draftStatus: .draft)
        #expect(pr.triageCategory == .waitingOnOthers)
    }

    @Test
    func triageCategory_noFlags_waitingOnOthers() {
        let pr = PRState.fixture()
        #expect(pr.triageCategory == .waitingOnOthers)
    }

    @Test
    func urgencyScore_ciFailing_yourPR_adds3() {
        let pr = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )

        #expect(pr.urgencyScore >= 3)
    }

    @Test
    func urgencyScore_ciFailing_notYourPR_doesNotAdd() {
        let pr = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: false
        )

        #expect(pr.urgencyScore < 3)
    }

    @Test
    func urgencyScore_changesRequested_yourPR_adds3() {
        let pr = PRState.fixture(
            reviewStatus: .changesRequested(by: ["reviewer"]),
            createdByMe: true
        )

        #expect(pr.urgencyScore >= 3)
    }

    @Test
    func urgencyScore_changesRequested_notYourPR_doesNotAdd3() {
        let pr = PRState.fixture(
            reviewStatus: .changesRequested(by: ["reviewer"]),
            createdByMe: false
        )

        #expect(pr.urgencyScore == 0)
    }

    @Test
    func urgencyScore_mergeConflicts_adds2() {
        let pr = PRState.fixture(mergeStatus: .conflicts)
        #expect(pr.urgencyScore >= 2)
    }

    @Test
    func urgencyScore_branchBehind_adds2() {
        let pr = PRState.fixture(mergeStatus: .behind)
        #expect(pr.urgencyScore >= 2)
    }

    @Test
    func urgencyScore_reviewRequestedFromMe_adds2() {
        let pr = PRState.fixture(reviewRequestedFromMe: true)
        #expect(pr.urgencyScore >= 2)
    }

    @Test
    func urgencyScore_assignedToMe_notAuthor_adds1() {
        let pr = PRState.fixture(createdByMe: false, assignedToMe: true)
        #expect(pr.urgencyScore >= 1)
    }

    @Test
    func urgencyScore_approvedAndReadyToMerge_yourPR_adds1() {
        let pr = PRState.fixture(
            reviewStatus: .approved(by: ["reviewer"]),
            mergeStatus: .ready,
            createdByMe: true
        )

        #expect(pr.urgencyScore >= 1)
    }

    @Test
    func urgencyScore_draft_alwaysZero() {
        let pr = PRState.fixture(
            draftStatus: .draft,
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["reviewer"]),
            mergeStatus: .conflicts,
            createdByMe: true,
            reviewRequestedFromMe: true,
            assignedToMe: true
        )

        #expect(pr.urgencyScore == 0)
    }

    @Test
    func urgencyScore_multipleFlags_addsUp() {
        let pr = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["reviewer"]),
            mergeStatus: .conflicts,
            createdByMe: true
        )

        #expect(pr.urgencyScore >= 8)
    }

    @Test
    func urgencyScore_noFlags_isZero() {
        let pr = PRState.fixture()
        #expect(pr.urgencyScore == 0)
    }

    @Test
    func needsActionSortOrder_higherUrgencyFirst() {
        let low = PRState.fixture(number: 1, assignedToMe: true)
        let high = PRState.fixture(number: 2, reviewRequestedFromMe: true)
        let prs = [low, high].sorted(by: PRState.compareForNeedsAction)

        #expect(prs.first?.number == 2)
    }

    @Test
    func needsActionSortOrder_tiebreaker_moreRecentFirst() {
        let older = PRState.fixture(
            number: 1,
            reviewRequestedFromMe: true,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = PRState.fixture(
            number: 2,
            reviewRequestedFromMe: true,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let prs = [older, newer].sorted(by: PRState.compareForNeedsAction)

        #expect(prs.first?.number == 2)
    }

    @Test
    func displayRole_reviewRequestedFromMe_highestPrecedence() {
        let pr = PRState.fixture(createdByMe: true, reviewRequestedFromMe: true, assignedToMe: true)
        #expect(pr.displayRole == "Review requested")
    }

    @Test
    func displayRole_assignedButNotReviewRequested() {
        let pr = PRState.fixture(createdByMe: true, assignedToMe: true)
        #expect(pr.displayRole == "Assigned")
    }

    @Test
    func displayRole_onlyAuthor() {
        let pr = PRState.fixture(createdByMe: true)
        #expect(pr.displayRole == "Your PR")
    }

    @Test
    func displayRole_noFlags_empty() {
        let pr = PRState.fixture()
        #expect(pr.displayRole.isEmpty)
    }

    @Test
    func mergeStatus_blocked_isDistinctFromConflicts() {
        let blocked = PRState.fixture(mergeStatus: .blocked)
        let conflicts = PRState.fixture(mergeStatus: .conflicts)

        #expect(blocked.mergeStatus != conflicts.mergeStatus)
    }

    @Test
    func mergeStatus_pending_isNotReady() {
        let pr = PRState.fixture(mergeStatus: .pending)
        #expect(pr.mergeStatus != .ready)
    }
}
