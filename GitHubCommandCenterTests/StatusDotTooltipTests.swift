import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite
struct StatusDotTooltipTests {

    // MARK: - Labels

    @Test
    func ci_label_isCI() {
        let tooltip = StatusDotTooltip(dimension: .ci, pr: .fixture())
        #expect(tooltip.label == "CI")
    }

    @Test
    func review_label_isReview() {
        let tooltip = StatusDotTooltip(dimension: .review, pr: .fixture())
        #expect(tooltip.label == "REVIEW")
    }

    @Test
    func merge_label_isMerge() {
        let tooltip = StatusDotTooltip(dimension: .merge, pr: .fixture())
        #expect(tooltip.label == "MERGE")
    }

    // MARK: - CI detail

    @Test
    func ci_passing_detail() {
        let tooltip = StatusDotTooltip(dimension: .ci, pr: .fixture(ciStatus: .passing))
        #expect(tooltip.detail == "All checks passing")
    }

    @Test
    func ci_failing_singleCheck_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .ci,
            pr: .fixture(
                ciStatus: .failing(
                    checks: [.init(name: "unit-tests", conclusion: "failure", url: nil)],
                    totalChecks: 3
                )
            )
        )
        #expect(tooltip.detail == "unit-tests failing (3 total)")
    }

    @Test
    func ci_failing_manyChecks_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .ci,
            pr: .fixture(
                ciStatus: .failing(
                    checks: [
                        .init(name: "lint", conclusion: "failure", url: nil),
                        .init(name: "unit", conclusion: "failure", url: nil),
                        .init(name: "integration", conclusion: "failure", url: nil),
                    ],
                    totalChecks: 5
                )
            )
        )
        #expect(tooltip.detail == "lint, unit (+1 more) failing (5 total)")
    }

    @Test
    func ci_failing_noNamedChecks_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .ci,
            pr: .fixture(ciStatus: .failing(checks: [], totalChecks: 4))
        )

        #expect(tooltip.detail == "Failing (4 total)")
    }

    @Test
    func ci_pending_detail() {
        let tooltip = StatusDotTooltip(dimension: .ci, pr: .fixture(ciStatus: .pending))
        #expect(tooltip.detail == "Checks in progress")
    }

    @Test
    func ci_none_detail() {
        let tooltip = StatusDotTooltip(dimension: .ci, pr: .fixture(ciStatus: .none))
        #expect(tooltip.detail == "No CI configured")
    }

    // MARK: - Review detail

    @Test
    func review_approved_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .review,
            pr: .fixture(reviewStatus: .approved(by: ["alice"]))
        )
        #expect(tooltip.detail == "Approved by @alice")
    }

    @Test
    func review_changesRequested_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .review,
            pr: .fixture(reviewStatus: .changesRequested(by: ["bob"]))
        )
        #expect(tooltip.detail == "Changes requested by @bob")
    }

    @Test
    func review_requested_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .review,
            pr: .fixture(reviewStatus: .requested(by: ["carol"]))
        )
        #expect(tooltip.detail == "Review requested from @carol")
    }

    @Test
    func review_none_detail() {
        let tooltip = StatusDotTooltip(
            dimension: .review,
            pr: .fixture(reviewStatus: .none)
        )
        #expect(tooltip.detail == "No reviews")
    }

    // MARK: - Merge detail

    @Test
    func merge_ready_detail() {
        let tooltip = StatusDotTooltip(dimension: .merge, pr: .fixture(mergeStatus: .ready))
        #expect(tooltip.detail == "Ready to merge")
    }

    @Test
    func merge_conflicts_detail() {
        let tooltip = StatusDotTooltip(dimension: .merge, pr: .fixture(mergeStatus: .conflicts))
        #expect(tooltip.detail == "Has merge conflicts")
    }

    @Test
    func merge_blocked_detail() {
        let tooltip = StatusDotTooltip(dimension: .merge, pr: .fixture(mergeStatus: .blocked))
        #expect(tooltip.detail == "Merge blocked by branch protection")
    }

    @Test
    func merge_behind_detail() {
        let tooltip = StatusDotTooltip(dimension: .merge, pr: .fixture(mergeStatus: .behind))
        #expect(tooltip.detail == "Branch is behind base and needs updating")
    }

    @Test
    func merge_pending_detail() {
        let tooltip = StatusDotTooltip(dimension: .merge, pr: .fixture(mergeStatus: .pending))
        #expect(tooltip.detail == "Checking mergeability…")
    }
}
