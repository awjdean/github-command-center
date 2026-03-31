import Testing

@testable import GitHubCommandCenter

extension GitHubRESTClientTests {
    @Test
    func validateToken_persistentStub_supportsRepeatedIdenticalRequests() async throws {
        let harness = Harness()
        MockURLProtocol.stub(
            urlContains: "/user",
            persistent: true,
            json: ["login": "octocat"]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let first = try await client.validateToken()
        let second = try await client.validateToken()

        #expect(first == "octocat")
        #expect(second == "octocat")
        #expect(MockURLProtocol.capturedRequests.count == 2)
    }

    @Test
    func validateTokenForAppAccess_largeSearchResultOnlyRequestsFirstPage() async throws {
        let harness = Harness()
        MockURLProtocol.stub(
            urlContains: "/user",
            persistent: true,
            json: ["login": "octocat"]
        )

        MockURLProtocol.stub(
            urlContains: "per_page=1&page=1&sort=updated&order=desc",
            json: [
                "total_count": 101,
                "incomplete_results": false,
                "items": [
                    [
                        "number": 1,
                        "title": "PR 1",
                        "html_url": "https://github.com/org/repo/pull/1",
                        "draft": false,
                        "updated_at": "2026-03-30T10:00:00Z",
                        "repository_url": "https://api.github.com/repos/org/repo",
                    ]
                ],
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let username = try await client.validateTokenForAppAccess()

        #expect(username == "octocat")
        let searchRequests = MockURLProtocol.capturedRequests.filter {
            $0.url?.absoluteString.contains("/search/issues") == true
        }
        #expect(searchRequests.count == 1)
        #expect(searchRequests.first?.url?.absoluteString.contains("per_page=1&page=1") == true)
    }

    @Test
    func fetchAllPRStates_reviewPaginationStopsAtSafeLimit() async throws {
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
                        "html_url": "https://github.com/owner/repo/pull/1",
                        "draft": false,
                        "updated_at": "2026-03-30T10:00:00Z",
                        "repository_url": "https://api.github.com/repos/owner/repo",
                    ]
                ],
            ]
        )
        for page in 1...10 {
            MockURLProtocol.stub(
                urlContains: "/pulls/1/reviews?per_page=100&page=\(page)",
                json: Array(
                    repeating: [
                        "user": ["login": "alice"],
                        "state": "APPROVED",
                    ],
                    count: 100
                )
            )
        }
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
                "mergeable_state": "clean",
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.reviewStatus == .approved(by: ["alice"]))
    }
}
