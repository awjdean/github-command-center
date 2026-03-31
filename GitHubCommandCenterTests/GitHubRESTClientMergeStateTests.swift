import Foundation
import Testing

@testable import GitHubCommandCenter

extension GitHubRESTClientTests {
    @Test
    func fetchAllPRStates_behindMergeableState_mapsToBehind() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, mergeableState: "behind")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .behind)
    }

    @Test
    func fetchAllPRStates_hasHooksMergeableState_mapsToBlocked() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, mergeableState: "has_hooks")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .blocked)
    }

    @Test
    func fetchAllPRStates_nilMergeableState_retriesUsingInjectedDelay() async throws {
        let harness = Harness()
        MockURLProtocol.stub(
            urlContains: "/search/issues",
            json: [
                "total_count": 1,
                "incomplete_results": false,
                "items": [
                    [
                        "number": 1,
                        "title": "Test PR",
                        "html_url": "https://github.com/org/repo/pull/1",
                        "draft": false,
                        "updated_at": "2026-03-30T10:00:00Z",
                        "repository_url": "https://api.github.com/repos/org/repo",
                    ]
                ],
            ]
        )
        MockURLProtocol.stub(urlContains: "/pulls/1/reviews?per_page=100&page=1", json: [])
        MockURLProtocol.stub(urlContains: "/pulls/1/reviews?per_page=100&page=2", json: [])
        MockURLProtocol.stub(urlContains: "/commits/abc123def456/check-runs", json: ["check_runs": []])
        MockURLProtocol.stub(
            urlContains: "/commits/abc123def456/status",
            json: [
                "state": "success",
                "statuses": [],
            ]
        )
        MockURLProtocol.stub(
            urlContains: "/pulls/1",
            json: [
                "head": ["sha": "abc123def456"],
                "state": "open",
                "user": ["login": "octocat"],
                "assignees": [],
                "requested_reviewers": [],
                "mergeable_state": NSNull(),
            ]
        )
        MockURLProtocol.stub(
            urlContains: "/pulls/1",
            json: [
                "head": ["sha": "abc123def456"],
                "state": "open",
                "user": ["login": "octocat"],
                "assignees": [],
                "requested_reviewers": [],
                "mergeable_state": "behind",
            ]
        )

        let client = GitHubRESTClient(
            token: "test-token",
            session: harness.session,
            mergeabilityRetryDelayNanoseconds: 0
        )
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .behind)
        let detailRequests = MockURLProtocol.capturedRequests.filter {
            ($0.url?.absoluteString.contains("/pulls/1") ?? false)
                && ($0.url?.absoluteString.contains("/reviews") ?? false) == false
        }
        #expect(detailRequests.count == 2)
    }
}
