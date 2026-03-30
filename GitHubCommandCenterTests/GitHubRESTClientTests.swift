import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite(.serialized)
struct GitHubRESTClientTests {
    private final class Harness {
        let session: URLSession

        init() {
            MockURLProtocol.reset()
            session = MockURLProtocol.makeSession()
        }

        deinit {
            MockURLProtocol.reset()
        }
    }

    @Test
    func validateToken_success_returnsUsername() async throws {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let username = try await client.validateToken()

        #expect(username == "octocat")
    }

    @Test
    func validateToken_401_throwsAuthError() async {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", statusCode: 401)
        let client = GitHubRESTClient(token: "bad-token", session: harness.session)

        do {
            _ = try await client.validateToken()
            Issue.record("Expected authError")
        } catch let error as AppError {
            #expect(error == .authError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateToken_403_throwsAuthError() async {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", statusCode: 403)
        let client = GitHubRESTClient(token: "forbidden-token", session: harness.session)

        do {
            _ = try await client.validateToken()
            Issue.record("Expected authError")
        } catch let error as AppError {
            #expect(error == .authError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateToken_403RateLimit_throwsRateLimitExceeded() async {
        let harness = Harness()
        let resetTS = Int(Date().timeIntervalSince1970) + 120
        MockURLProtocol.stub(
            urlContains: "/user",
            statusCode: 403,
            headers: [
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": "\(resetTS)",
            ],
            json: ["message": "API rate limit exceeded"]
        )

        let client = GitHubRESTClient(token: "throttled-token", session: harness.session)

        do {
            _ = try await client.validateToken()
            Issue.record("Expected rateLimitExceeded")
        } catch AppError.rateLimitExceeded(let resetAt) {
            #expect(resetAt > Date())
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateToken_429_throwsRateLimitExceeded() async {
        let harness = Harness()
        let resetTS = Int(Date().timeIntervalSince1970) + 3600
        MockURLProtocol.stub(
            urlContains: "/user",
            statusCode: 429,
            headers: ["X-RateLimit-Reset": "\(resetTS)"]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)

        do {
            _ = try await client.validateToken()
            Issue.record("Expected rateLimitExceeded")
        } catch AppError.rateLimitExceeded(let resetAt) {
            #expect(resetAt > Date())
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateToken_500_throwsServerError() async {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", statusCode: 500)
        let client = GitHubRESTClient(token: "test-token", session: harness.session)

        do {
            _ = try await client.validateToken()
            Issue.record("Expected serverError")
        } catch AppError.serverError(let code) {
            #expect(code == 500)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateToken_304WithoutCachedResponse_retriesWithoutETag() async throws {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", statusCode: 304)
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let username = try await client.validateToken()

        #expect(username == "octocat")
        #expect(MockURLProtocol.capturedRequests.count == 2)
    }

    @Test
    func validateTokenForAppAccess_success_returnsUsernameWhenSearchEmpty() async throws {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        MockURLProtocol.stub(
            urlContains: "/search/issues",
            json: [
                "total_count": 0,
                "incomplete_results": false,
                "items": [],
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let username = try await client.validateTokenForAppAccess()

        #expect(username == "octocat")
        #expect(
            MockURLProtocol.capturedRequests.contains {
                ($0.url?.absoluteString.contains("/search/issues") ?? false)
                    && ($0.url?.absoluteString.contains("per_page=1") ?? false)
            }
        )
    }

    @Test
    func validateTokenForAppAccess_search403_throwsAuthError() async {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        MockURLProtocol.stub(urlContains: "/search/issues", statusCode: 403)

        let client = GitHubRESTClient(token: "test-token", session: harness.session)

        do {
            _ = try await client.validateTokenForAppAccess()
            Issue.record("Expected authError")
        } catch let error as AppError {
            #expect(error == .authError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateTokenForAppAccess_incompleteSearchResults_throwsIncompleteSearchResults() async {
        let harness = Harness()
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        MockURLProtocol.stub(
            urlContains: "/search/issues",
            json: [
                "total_count": 1,
                "incomplete_results": true,
                "items": [],
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)

        do {
            _ = try await client.validateTokenForAppAccess()
            Issue.record("Expected incompleteSearchResults")
        } catch let error as AppError {
            #expect(error == .incompleteSearchResults)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func fetchAllPRStates_emptySearch_returnsEmptyArray() async throws {
        let harness = Harness()
        MockURLProtocol.stub(
            urlContains: "/search/issues",
            json: [
                "total_count": 0,
                "incomplete_results": false,
                "items": [],
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.isEmpty)
    }

    @Test
    func fetchAllPRStates_singlePR_buildsCorrectState() async throws {
        let harness = Harness()
        stubFullPRFlow()

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        let pr = try #require(prs.first)

        #expect(prs.count == 1)
        #expect(pr.number == 42)
        #expect(pr.title == "Fix the bug")
        #expect(pr.repoFullName == "org/app")
        #expect(pr.assignment.createdByMe)
        #expect(pr.ciStatus == .passing)
        #expect(pr.mergeStatus == .ready)
    }

    @Test
    func fetchAllPRStates_sameNumberDifferentRepos_haveDistinctIDs() async throws {
        let harness = Harness()
        MockURLProtocol.stub(
            urlContains: "/search/issues",
            json: [
                "total_count": 2,
                "incomplete_results": false,
                "items": [
                    [
                        "number": 42,
                        "title": "Repo one",
                        "html_url": "https://github.com/org/one/pull/42",
                        "draft": false,
                        "updated_at": "2026-03-30T10:00:00Z",
                        "repository_url": "https://api.github.com/repos/org/one",
                    ],
                    [
                        "number": 42,
                        "title": "Repo two",
                        "html_url": "https://github.com/org/two/pull/42",
                        "draft": false,
                        "updated_at": "2026-03-30T11:00:00Z",
                        "repository_url": "https://api.github.com/repos/org/two",
                    ],
                ],
            ]
        )

        for repo in ["one", "two"] {
            MockURLProtocol.stub(urlContains: "/repos/org/\(repo)/pulls/42/reviews", json: [])
            MockURLProtocol.stub(
                urlContains: "/repos/org/\(repo)/commits/abc123def456/check-runs",
                json: ["check_runs": []]
            )
            MockURLProtocol.stub(
                urlContains: "/repos/org/\(repo)/commits/abc123def456/status",
                json: [
                    "state": "success",
                    "statuses": [],
                ]
            )
            MockURLProtocol.stub(
                urlContains: "/repos/org/\(repo)/pulls/42",
                json: [
                    "head": ["sha": "abc123def456"],
                    "state": "open",
                    "user": ["login": "octocat"],
                    "assignees": [],
                    "requested_reviewers": [],
                    "mergeable_state": "clean",
                ]
            )
        }

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.count == 2)
        #expect(Set(prs.map(\.id)).count == 2)
    }

    @Test
    func fetchAllPRStates_unknownMergeableState_mapsToPending() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, mergeableState: "future_unknown_value")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .pending)
    }

    @Test
    func fetchAllPRStates_dirtyMergeableState_mapsToConflicts() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, mergeableState: "dirty")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .conflicts)
    }

    @Test
    func fetchAllPRStates_blockedMergeableState_mapsToBlocked() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, mergeableState: "blocked")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .blocked)
    }

    @Test
    func fetchAllPRStates_unstableMergeableState_mapsToReady() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, mergeableState: "unstable")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.mergeStatus == .ready)
    }

    @Test
    func fetchAllPRStates_failingCheckRuns_mapsToCIFailing() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            mergeableState: "clean",
            checkRuns: [
                ["name": "unit-tests", "status": "completed", "conclusion": "failure"],
                ["name": "lint", "status": "completed", "conclusion": "success"],
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        let pr = try #require(prs.first)

        if case .failing(let names, let total) = pr.ciStatus {
            #expect(names == ["unit-tests"])
            #expect(total == 2)
        } else {
            Issue.record("Expected .failing, got \(pr.ciStatus)")
        }
    }

    @Test
    func fetchAllPRStates_pendingCheckRuns_mapsToCIPending() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            checkRuns: [["name": "build", "status": "in_progress"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.ciStatus == .pending)
    }

    @Test
    func fetchAllPRStates_noCheckRuns_mapsToCINone() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, checkRuns: [])

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(prs.first?.ciStatus == PRState.CIStatus.none)
    }

    @Test
    func fetchAllPRStates_commitStatusFailureWithoutCheckRuns_mapsToCIFailing() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            checkRuns: [],
            statusState: "failure",
            commitStatuses: [
                [
                    "context": "legacy-ci",
                    "state": "failure",
                ]
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        let pr = try #require(prs.first)

        if case .failing(let names, _) = pr.ciStatus {
            #expect(names == ["legacy-ci"])
        } else {
            Issue.record("Expected .failing, got \(pr.ciStatus)")
        }
    }

    @Test
    func fetchAllPRStates_reviewsApproved_mapsToApproved() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            reviews: [["user": ["login": "alice"], "state": "APPROVED"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .approved(let by) = prs.first?.reviewStatus {
            #expect(by == ["alice"])
        } else {
            Issue.record("Expected .approved, got \(String(describing: prs.first?.reviewStatus))")
        }
    }

    @Test
    func fetchAllPRStates_reviewChangesRequested_mapsToChangesRequested() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            reviews: [["user": ["login": "bob"], "state": "CHANGES_REQUESTED"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .changesRequested(let by) = prs.first?.reviewStatus {
            #expect(by == ["bob"])
        } else {
            Issue.record("Expected .changesRequested")
        }
    }

    @Test
    func fetchAllPRStates_requestedReviewers_mapsToRequested() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            requestedReviewers: [["login": "carol"]],
            reviews: []
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .requested(let by) = prs.first?.reviewStatus {
            #expect(by == ["carol"])
        } else {
            Issue.record("Expected .requested, got \(String(describing: prs.first?.reviewStatus))")
        }
    }

    @Test
    func fetchAllPRStates_requestedReviewers_overridePriorApproval() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            requestedReviewers: [["login": "carol"]],
            reviews: [["user": ["login": "alice"], "state": "APPROVED"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .requested(let by) = prs.first?.reviewStatus {
            #expect(by == ["carol"])
        } else {
            Issue.record("Expected .requested when new reviewers are still outstanding")
        }
    }

    @Test
    func fetchAllPRStates_changesRequested_overrideRequestedReviewers() async throws {
        let harness = Harness()
        stubFullPRFlow(
            number: 1,
            requestedReviewers: [["login": "carol"]],
            reviews: [["user": ["login": "alice"], "state": "CHANGES_REQUESTED"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .changesRequested(let by) = prs.first?.reviewStatus {
            #expect(by == ["alice"])
        } else {
            Issue.record("Expected .changesRequested to keep highest precedence")
        }
    }

    @Test
    func fetchAllPRStates_paginatedReviews_useLatestPage() async throws {
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
        MockURLProtocol.stub(
            urlContains: "/pulls/1/reviews?per_page=100&page=1",
            json: Array(
                repeating: [
                    "user": ["login": "alice"],
                    "state": "APPROVED",
                ],
                count: 100
            )
        )
        MockURLProtocol.stub(
            urlContains: "/pulls/1/reviews?per_page=100&page=2",
            json: [
                [
                    "user": ["login": "alice"],
                    "state": "CHANGES_REQUESTED",
                ]
            ]
        )
        MockURLProtocol.stub(
            urlContains: "/pulls/1/reviews",
            json: Array(
                repeating: [
                    "user": ["login": "alice"],
                    "state": "APPROVED",
                ],
                count: 30
            )
        )
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

        if case .changesRequested(let by) = prs.first?.reviewStatus {
            #expect(by == ["alice"])
        } else {
            Issue.record("Expected .changesRequested from later review page")
        }
    }

    @Test
    func fetchAllPRStates_parsesUpdatedAtWithoutFractionalSeconds() async throws {
        let harness = Harness()
        stubFullPRFlow(number: 1, updatedAt: "2026-03-30T10:00:00Z")

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        #expect(
            prs.first?.updatedAt == ISO8601DateFormatter().date(from: "2026-03-30T10:00:00Z")
        )
    }

    @Test
    func fetchAllPRStates_etag304_returnsCachedData() async throws {
        let harness = Harness()
        MockURLProtocol.stub(
            urlContains: "/user",
            headers: ["ETag": "\"abc\""],
            json: ["login": "octocat"]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        _ = try await client.validateToken()

        MockURLProtocol.reset()
        MockURLProtocol.stub(urlContains: "/user", statusCode: 304)

        let username = try await client.validateToken()
        #expect(username == "octocat")
    }

    private func stubFullPRFlow(
        number: Int = 42,
        title: String = "Fix the bug",
        owner: String = "org",
        repo: String = "app",
        authorLogin: String = "octocat",
        requestedReviewers: [[String: Any]] = [],
        assignees: [[String: Any]] = [],
        mergeableState: String = "clean",
        reviews: [[String: Any]] = [],
        checkRuns: [[String: Any]] = [["name": "CI", "status": "completed", "conclusion": "success"]],
        updatedAt: String = "2026-03-30T10:00:00.000Z",
        statusState: String = "success",
        commitStatuses: [[String: Any]] = []
    ) {
        MockURLProtocol.stub(
            urlContains: "/search/issues",
            json: [
                "total_count": 1,
                "incomplete_results": false,
                "items": [
                    [
                        "number": number,
                        "title": title,
                        "html_url": "https://github.com/\(owner)/\(repo)/pull/\(number)",
                        "draft": false,
                        "updated_at": updatedAt,
                        "repository_url": "https://api.github.com/repos/\(owner)/\(repo)",
                    ]
                ],
            ]
        )
        MockURLProtocol.stub(urlContains: "/pulls/\(number)/reviews?per_page=100&page=1", json: reviews)
        MockURLProtocol.stub(urlContains: "/pulls/\(number)/reviews?per_page=100&page=2", json: [])
        MockURLProtocol.stub(urlContains: "/pulls/\(number)/reviews", json: reviews)
        MockURLProtocol.stub(urlContains: "/check-runs", json: ["check_runs": checkRuns])
        MockURLProtocol.stub(
            urlContains: "/status",
            json: [
                "state": statusState,
                "statuses": commitStatuses,
            ]
        )
        MockURLProtocol.stub(
            urlContains: "/pulls/\(number)",
            json: [
                "head": ["sha": "abc123def456"],
                "state": "open",
                "user": ["login": authorLogin],
                "assignees": assignees,
                "requested_reviewers": requestedReviewers,
                "mergeable_state": mergeableState,
            ]
        )
    }
}
