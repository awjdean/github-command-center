import XCTest
@testable import GitHubCommandCenter

final class PRStateTests: XCTestCase {

    func testID_sameNumberDifferentRepos_areDistinct() {
        let first = PRState.fixture(number: 42, repoFullName: "org/one")
        let second = PRState.fixture(number: 42, repoFullName: "org/two")

        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - triageCategory

    func testTriageCategory_reviewRequestedFromMe_needsAction() {
        let pr = PRState.fixture(reviewRequestedFromMe: true)
        XCTAssertEqual(pr.triageCategory, .needsYourAction)
    }

    func testTriageCategory_assignedToMe_needsAction() {
        let pr = PRState.fixture(assignedToMe: true)
        XCTAssertEqual(pr.triageCategory, .needsYourAction)
    }

    func testTriageCategory_createdByMe_ciFailing_needsAction() {
        let pr = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["unit-tests"], totalChecks: 3),
            createdByMe: true
        )
        XCTAssertEqual(pr.triageCategory, .needsYourAction)
    }

    func testTriageCategory_createdByMe_changesRequested_needsAction() {
        let pr = PRState.fixture(reviewStatus: .changesRequested(by: ["reviewer"]), createdByMe: true)
        XCTAssertEqual(pr.triageCategory, .needsYourAction)
    }

    func testTriageCategory_createdByMe_mergeConflicts_needsAction() {
        let pr = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)
        XCTAssertEqual(pr.triageCategory, .needsYourAction)
    }

    func testTriageCategory_createdByMe_approvedAndClean_needsAction() {
        // Approved + ready to merge = action required (merge it)
        let pr = PRState.fixture(
            reviewStatus: .approved(by: ["reviewer"]),
            mergeStatus: .ready,
            createdByMe: true
        )
        XCTAssertEqual(pr.triageCategory, .needsYourAction)
    }

    func testTriageCategory_createdByMe_allGreenWaitingReview_waitingOnOthers() {
        // CI passing, no reviews yet, ready to merge — still waiting on reviewers
        let pr = PRState.fixture(
            ciStatus: .passing,
            reviewStatus: .none,
            mergeStatus: .ready,
            createdByMe: true
        )
        XCTAssertEqual(pr.triageCategory, .waitingOnOthers)
    }

    func testTriageCategory_createdByMe_reviewRequested_waitingOnOthers() {
        let pr = PRState.fixture(
            reviewStatus: .requested(by: ["reviewer"]),
            createdByMe: true
        )
        XCTAssertEqual(pr.triageCategory, .waitingOnOthers)
    }

    func testTriageCategory_draft_alwaysWaiting() {
        // Draft suppresses even if reviewRequestedFromMe is set
        let pr = PRState.fixture(draftStatus: .draft, reviewRequestedFromMe: true)
        XCTAssertEqual(pr.triageCategory, .waitingOnOthers)
    }

    func testTriageCategory_noFlags_waitingOnOthers() {
        let pr = PRState.fixture()
        XCTAssertEqual(pr.triageCategory, .waitingOnOthers)
    }

    // MARK: - urgencyScore

    func testUrgencyScore_ciFailing_yourPR_adds3() {
        let pr = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            createdByMe: true
        )
        XCTAssertGreaterThanOrEqual(pr.urgencyScore, 3)
    }

    func testUrgencyScore_ciFailing_notYourPR_doesNotAdd() {
        // CI failing but not your PR — no +3 for CI
        let pr = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            createdByMe: false
        )
        XCTAssertLessThan(pr.urgencyScore, 3)
    }

    func testUrgencyScore_changesRequested_adds3() {
        let pr = PRState.fixture(reviewStatus: .changesRequested(by: ["reviewer"]))
        XCTAssertGreaterThanOrEqual(pr.urgencyScore, 3)
    }

    func testUrgencyScore_mergeConflicts_adds2() {
        let pr = PRState.fixture(mergeStatus: .conflicts)
        XCTAssertGreaterThanOrEqual(pr.urgencyScore, 2)
    }

    func testUrgencyScore_reviewRequestedFromMe_adds2() {
        let pr = PRState.fixture(reviewRequestedFromMe: true)
        XCTAssertGreaterThanOrEqual(pr.urgencyScore, 2)
    }

    func testUrgencyScore_assignedToMe_notAuthor_adds1() {
        let pr = PRState.fixture(createdByMe: false, assignedToMe: true)
        XCTAssertGreaterThanOrEqual(pr.urgencyScore, 1)
    }

    func testUrgencyScore_approvedAndReadyToMerge_yourPR_adds1() {
        let pr = PRState.fixture(
            reviewStatus: .approved(by: ["reviewer"]),
            mergeStatus: .ready,
            createdByMe: true
        )
        XCTAssertGreaterThanOrEqual(pr.urgencyScore, 1)
    }

    func testUrgencyScore_draft_alwaysZero() {
        let pr = PRState.fixture(
            draftStatus: .draft,
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["reviewer"]),
            mergeStatus: .conflicts,
            createdByMe: true,
            reviewRequestedFromMe: true,
            assignedToMe: true
        )
        XCTAssertEqual(pr.urgencyScore, 0)
    }

    func testUrgencyScore_multipleFlags_addsUp() {
        // CI failing (your PR: +3) + changes requested (+3) + conflicts (+2) = 8 minimum
        let pr = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["reviewer"]),
            mergeStatus: .conflicts,
            createdByMe: true
        )
        XCTAssertEqual(pr.urgencyScore, 8)
    }

    func testUrgencyScore_noFlags_isZero() {
        let pr = PRState.fixture()
        XCTAssertEqual(pr.urgencyScore, 0)
    }

    func testNeedsActionSortOrder_higherUrgencyFirst() {
        let low  = PRState.fixture(number: 1, assignedToMe: true)           // +1
        let high = PRState.fixture(number: 2, reviewRequestedFromMe: true)  // +2
        let prs = [low, high].sorted { lhs, rhs in
            lhs.urgencyScore != rhs.urgencyScore
                ? lhs.urgencyScore > rhs.urgencyScore
                : lhs.updatedAt > rhs.updatedAt
        }
        XCTAssertEqual(prs.first?.number, 2)
    }

    func testNeedsActionSortOrder_tiebreaker_moreRecentFirst() {
        let older  = PRState.fixture(number: 1, reviewRequestedFromMe: true,
                                     updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer  = PRState.fixture(number: 2, reviewRequestedFromMe: true,
                                     updatedAt: Date(timeIntervalSince1970: 2_000))
        let prs = [older, newer].sorted { lhs, rhs in
            lhs.urgencyScore != rhs.urgencyScore
                ? lhs.urgencyScore > rhs.urgencyScore
                : lhs.updatedAt > rhs.updatedAt
        }
        XCTAssertEqual(prs.first?.number, 2)
    }

    // MARK: - displayRole

    func testDisplayRole_reviewRequestedFromMe_highestPrecedence() {
        let pr = PRState.fixture(createdByMe: true, reviewRequestedFromMe: true, assignedToMe: true)
        XCTAssertEqual(pr.displayRole, "Review requested")
    }

    func testDisplayRole_assignedButNotReviewRequested() {
        let pr = PRState.fixture(createdByMe: true, assignedToMe: true)
        XCTAssertEqual(pr.displayRole, "Assigned")
    }

    func testDisplayRole_onlyAuthor() {
        let pr = PRState.fixture(createdByMe: true)
        XCTAssertEqual(pr.displayRole, "Your PR")
    }

    func testDisplayRole_noFlags_empty() {
        let pr = PRState.fixture()
        XCTAssertEqual(pr.displayRole, "")
    }

    // MARK: - MergeStatus mapping edge cases

    func testMergeStatus_blocked_isDistinctFromConflicts() {
        let blocked   = PRState.fixture(mergeStatus: .blocked)
        let conflicts = PRState.fixture(mergeStatus: .conflicts)
        XCTAssertNotEqual(blocked.mergeStatus, conflicts.mergeStatus)
    }

    func testMergeStatus_pending_isNotReady() {
        let pr = PRState.fixture(mergeStatus: .pending)
        XCTAssertNotEqual(pr.mergeStatus, .ready)
    }
}
