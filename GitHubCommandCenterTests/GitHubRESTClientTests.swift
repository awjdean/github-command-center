import XCTest
@testable import GitHubCommandCenter

final class GitHubRESTClientTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    override func tearDown() {
        MockURLProtocol.reset()
    }

    // MARK: - validateToken

    func testValidateToken_success_returnsUsername() async throws {
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        let client = GitHubRESTClient(token: "test-token", session: session)
        let username = try await client.validateToken()
        XCTAssertEqual(username, "octocat")
    }

    func testValidateToken_401_throwsAuthError() async {
        MockURLProtocol.stub(urlContains: "/user", statusCode: 401)
        let client = GitHubRESTClient(token: "bad-token", session: session)
        do {
            _ = try await client.validateToken()
            XCTFail("Expected authError")
        } catch AppError.authError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateToken_403_throwsAuthError() async {
        MockURLProtocol.stub(urlContains: "/user", statusCode: 403)
        let client = GitHubRESTClient(token: "forbidden-token", session: session)
        do {
            _ = try await client.validateToken()
            XCTFail("Expected authError")
        } catch AppError.authError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateToken_403RateLimit_throwsRateLimitExceeded() async {
        let resetTS = Int(Date().timeIntervalSince1970) + 120
        MockURLProtocol.stub(
            urlContains: "/user",
            statusCode: 403,
            headers: [
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": "\(resetTS)"
            ],
            json: ["message": "API rate limit exceeded"]
        )

        let client = GitHubRESTClient(token: "throttled-token", session: session)

        do {
            _ = try await client.validateToken()
            XCTFail("Expected rateLimitExceeded")
        } catch AppError.rateLimitExceeded(let resetAt) {
            XCTAssertGreaterThan(resetAt, Date())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateToken_429_throwsRateLimitExceeded() async {
        let resetTS = Int(Date().timeIntervalSince1970) + 3600
        MockURLProtocol.stub(urlContains: "/user", statusCode: 429,
                              headers: ["X-RateLimit-Reset": "\(resetTS)"])
        let client = GitHubRESTClient(token: "test-token", session: session)
        do {
            _ = try await client.validateToken()
            XCTFail("Expected rateLimitExceeded")
        } catch AppError.rateLimitExceeded(let resetAt) {
            XCTAssertGreaterThan(resetAt, Date())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateToken_500_throwsServerError() async {
        MockURLProtocol.stub(urlContains: "/user", statusCode: 500)
        let client = GitHubRESTClient(token: "test-token", session: session)
        do {
            _ = try await client.validateToken()
            XCTFail("Expected serverError")
        } catch AppError.serverError(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testValidateTokenForAppAccess_success_returnsUsernameWhenSearchEmpty() async throws {
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        MockURLProtocol.stub(urlContains: "/search/issues", json: [
            "total_count": 0,
            "items": []
        ])

        let client = GitHubRESTClient(token: "test-token", session: session)
        let username = try await client.validateTokenForAppAccess()

        XCTAssertEqual(username, "octocat")
        XCTAssertTrue(
            MockURLProtocol.capturedRequests.contains {
                ($0.url?.absoluteString.contains("/search/issues") ?? false) &&
                ($0.url?.absoluteString.contains("per_page=1") ?? false)
            }
        )
    }

    func testValidateTokenForAppAccess_search403_throwsAuthError() async {
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        MockURLProtocol.stub(urlContains: "/search/issues", statusCode: 403)

        let client = GitHubRESTClient(token: "test-token", session: session)

        do {
            _ = try await client.validateTokenForAppAccess()
            XCTFail("Expected authError")
        } catch AppError.authError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - fetchAllPRStates — happy path

    func testFetchAllPRStates_emptySearch_returnsEmptyArray() async throws {
        MockURLProtocol.stub(urlContains: "/search/issues", json: [
            "total_count": 0,
            "items": []
        ])
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertTrue(prs.isEmpty)
    }

    func testFetchAllPRStates_singlePR_buildsCorrectState() async throws {
        stubFullPRFlow(
            number: 42,
            title: "Fix the bug",
            owner: "org",
            repo: "app",
            authorLogin: "octocat",
            requestedReviewers: [],
            assignees: [],
            mergeableState: "clean",
            reviews: [],
            checkRuns: [["name": "CI", "status": "completed", "conclusion": "success"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        XCTAssertEqual(prs.count, 1)
        guard let pr = prs.first else { return XCTFail() }
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Fix the bug")
        XCTAssertEqual(pr.repoFullName, "org/app")
        XCTAssertEqual(pr.assignment.createdByMe, true)
        XCTAssertEqual(pr.ciStatus, .passing)
        XCTAssertEqual(pr.mergeStatus, .ready)
    }

    func testFetchAllPRStates_sameNumberDifferentRepos_haveDistinctIDs() async throws {
        MockURLProtocol.stub(urlContains: "/search/issues", json: [
            "total_count": 2,
            "items": [
                [
                    "number": 42,
                    "title": "Repo one",
                    "html_url": "https://github.com/org/one/pull/42",
                    "draft": false,
                    "updated_at": "2026-03-30T10:00:00Z",
                    "repository_url": "https://api.github.com/repos/org/one"
                ],
                [
                    "number": 42,
                    "title": "Repo two",
                    "html_url": "https://github.com/org/two/pull/42",
                    "draft": false,
                    "updated_at": "2026-03-30T11:00:00Z",
                    "repository_url": "https://api.github.com/repos/org/two"
                ]
            ]
        ])

        for repo in ["one", "two"] {
            MockURLProtocol.stub(urlContains: "/repos/org/\(repo)/pulls/42/reviews", json: [])
            MockURLProtocol.stub(urlContains: "/repos/org/\(repo)/commits/abc123def456/check-runs", json: ["check_runs": []])
            MockURLProtocol.stub(urlContains: "/repos/org/\(repo)/commits/abc123def456/status", json: [
                "state": "success",
                "statuses": []
            ])
            MockURLProtocol.stub(urlContains: "/repos/org/\(repo)/pulls/42", json: [
                "head": ["sha": "abc123def456"],
                "state": "open",
                "user": ["login": "octocat"],
                "assignees": [],
                "requested_reviewers": [],
                "mergeable_state": "clean"
            ])
        }

        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        XCTAssertEqual(prs.count, 2)
        XCTAssertEqual(Set(prs.map(\.id)).count, 2)
    }

    func testFetchAllPRStates_unknownMergeableState_mapsToPending() async throws {
        stubFullPRFlow(
            number: 1,
            mergeableState: "future_unknown_value"
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertEqual(prs.first?.mergeStatus, .pending)
    }

    func testFetchAllPRStates_dirtyMergeableState_mapsToConflicts() async throws {
        stubFullPRFlow(number: 1, mergeableState: "dirty")
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertEqual(prs.first?.mergeStatus, .conflicts)
    }

    func testFetchAllPRStates_blockedMergeableState_mapsToBlocked() async throws {
        stubFullPRFlow(number: 1, mergeableState: "blocked")
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertEqual(prs.first?.mergeStatus, .blocked)
    }

    func testFetchAllPRStates_unstableMergeableState_mapsToReady() async throws {
        // "unstable" = mergeable despite failing optional checks; CI tracked via check-runs
        stubFullPRFlow(number: 1, mergeableState: "unstable")
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertEqual(prs.first?.mergeStatus, .ready)
    }

    func testFetchAllPRStates_failingCheckRuns_mapsToCIFailing() async throws {
        stubFullPRFlow(
            number: 1,
            mergeableState: "clean",
            checkRuns: [
                ["name": "unit-tests", "status": "completed", "conclusion": "failure"],
                ["name": "lint",       "status": "completed", "conclusion": "success"]
            ]
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        guard let pr = prs.first else { return XCTFail() }
        if case .failing(let names, let total) = pr.ciStatus {
            XCTAssertEqual(names, ["unit-tests"])
            XCTAssertEqual(total, 2)
        } else {
            XCTFail("Expected .failing, got \(pr.ciStatus)")
        }
    }

    func testFetchAllPRStates_pendingCheckRuns_mapsToCIPending() async throws {
        stubFullPRFlow(
            number: 1,
            checkRuns: [["name": "build", "status": "in_progress"]]
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertEqual(prs.first?.ciStatus, .pending)
    }

    func testFetchAllPRStates_noCheckRuns_mapsToCINone() async throws {
        stubFullPRFlow(number: 1, checkRuns: [])
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        XCTAssertEqual(prs.first?.ciStatus, PRState.CIStatus.none)
    }

    func testFetchAllPRStates_commitStatusFailureWithoutCheckRuns_mapsToCIFailing() async throws {
        stubFullPRFlow(
            number: 1,
            checkRuns: [],
            statusState: "failure",
            commitStatuses: [[
                "context": "legacy-ci",
                "state": "failure"
            ]]
        )

        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        guard let pr = prs.first else { return XCTFail() }
        if case .failing(let names, _) = pr.ciStatus {
            XCTAssertEqual(names, ["legacy-ci"])
        } else {
            XCTFail("Expected .failing, got \(pr.ciStatus)")
        }
    }

    func testFetchAllPRStates_reviewsApproved_mapsToApproved() async throws {
        stubFullPRFlow(
            number: 1,
            reviews: [["user": ["login": "alice"], "state": "APPROVED"]]
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        if case .approved(let by) = prs.first?.reviewStatus {
            XCTAssertEqual(by, ["alice"])
        } else {
            XCTFail("Expected .approved, got \(String(describing: prs.first?.reviewStatus))")
        }
    }

    func testFetchAllPRStates_reviewChangesRequested_mapsToChangesRequested() async throws {
        stubFullPRFlow(
            number: 1,
            reviews: [["user": ["login": "bob"], "state": "CHANGES_REQUESTED"]]
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        if case .changesRequested(let by) = prs.first?.reviewStatus {
            XCTAssertEqual(by, ["bob"])
        } else {
            XCTFail("Expected .changesRequested")
        }
    }

    func testFetchAllPRStates_requestedReviewers_mapsToRequested() async throws {
        stubFullPRFlow(
            number: 1,
            requestedReviewers: [["login": "carol"]],
            reviews: []
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")
        if case .requested(let by) = prs.first?.reviewStatus {
            XCTAssertEqual(by, ["carol"])
        } else {
            XCTFail("Expected .requested, got \(String(describing: prs.first?.reviewStatus))")
        }
    }

    func testFetchAllPRStates_requestedReviewers_overridePriorApproval() async throws {
        stubFullPRFlow(
            number: 1,
            requestedReviewers: [["login": "carol"]],
            reviews: [["user": ["login": "alice"], "state": "APPROVED"]]
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .requested(let by) = prs.first?.reviewStatus {
            XCTAssertEqual(by, ["carol"])
        } else {
            XCTFail("Expected .requested when new reviewers are still outstanding")
        }
    }

    func testFetchAllPRStates_changesRequested_overrideRequestedReviewers() async throws {
        stubFullPRFlow(
            number: 1,
            requestedReviewers: [["login": "carol"]],
            reviews: [["user": ["login": "alice"], "state": "CHANGES_REQUESTED"]]
        )
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .changesRequested(let by) = prs.first?.reviewStatus {
            XCTAssertEqual(by, ["alice"])
        } else {
            XCTFail("Expected .changesRequested to keep highest precedence")
        }
    }

    func testFetchAllPRStates_paginatedReviews_useLatestPage() async throws {
        MockURLProtocol.stub(urlContains: "/search/issues", json: [
            "total_count": 1,
            "items": [[
                "number": 1,
                "title": "Test PR",
                "html_url": "https://github.com/owner/repo/pull/1",
                "draft": false,
                "updated_at": "2026-03-30T10:00:00Z",
                "repository_url": "https://api.github.com/repos/owner/repo"
            ]]
        ])
        MockURLProtocol.stub(urlContains: "/pulls/1/reviews?per_page=100&page=1", json: Array(repeating: [
            "user": ["login": "alice"],
            "state": "APPROVED"
        ], count: 100))
        MockURLProtocol.stub(urlContains: "/pulls/1/reviews?per_page=100&page=2", json: [[
            "user": ["login": "alice"],
            "state": "CHANGES_REQUESTED"
        ]])
        MockURLProtocol.stub(urlContains: "/pulls/1/reviews", json: Array(repeating: [
            "user": ["login": "alice"],
            "state": "APPROVED"
        ], count: 30))
        MockURLProtocol.stub(urlContains: "/commits/abc123def456/check-runs", json: ["check_runs": []])
        MockURLProtocol.stub(urlContains: "/commits/abc123def456/status", json: [
            "state": "success",
            "statuses": []
        ])
        MockURLProtocol.stub(urlContains: "/pulls/1", json: [
            "head": ["sha": "abc123def456"],
            "state": "open",
            "user": ["login": "octocat"],
            "assignees": [],
            "requested_reviewers": [],
            "mergeable_state": "clean"
        ])

        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        if case .changesRequested(let by) = prs.first?.reviewStatus {
            XCTAssertEqual(by, ["alice"])
        } else {
            XCTFail("Expected .changesRequested from later review page")
        }
    }

    func testFetchAllPRStates_parsesUpdatedAtWithoutFractionalSeconds() async throws {
        stubFullPRFlow(number: 1, updatedAt: "2026-03-30T10:00:00Z")
        let client = GitHubRESTClient(token: "test-token", session: session)
        let prs = try await client.fetchAllPRStates(username: "octocat")

        XCTAssertEqual(
            prs.first?.updatedAt,
            ISO8601DateFormatter().date(from: "2026-03-30T10:00:00Z")
        )
    }

    func testFetchAllPRStates_etag304_returnsCachedData() async throws {
        // First request — prime the cache
        MockURLProtocol.stub(urlContains: "/user",
                              headers: ["ETag": "\"abc\""],
                              json: ["login": "octocat"])
        let client = GitHubRESTClient(token: "test-token", session: session)
        _ = try await client.validateToken()

        // Second request — server returns 304
        MockURLProtocol.reset()
        MockURLProtocol.stub(urlContains: "/user", statusCode: 304)
        session = MockURLProtocol.makeSession()
        // Re-use same client instance (holds ETag cache)
        let username = try await client.validateToken()
        XCTAssertEqual(username, "octocat")
    }

    // MARK: - Helpers

    private func stubFullPRFlow(
        number: Int = 1,
        title: String = "Test PR",
        owner: String = "owner",
        repo: String = "repo",
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
        // Register more-specific patterns first so they win over prefix matches.
        // Search
        MockURLProtocol.stub(urlContains: "/search/issues", json: [
            "total_count": 1,
            "items": [[
                "number": number,
                "title": title,
                "html_url": "https://github.com/\(owner)/\(repo)/pull/\(number)",
                "draft": false,
                "updated_at": updatedAt,
                "repository_url": "https://api.github.com/repos/\(owner)/\(repo)"
            ]]
        ])
        // Reviews — register paginated URLs before the generic pattern so test stubs match real requests.
        MockURLProtocol.stub(urlContains: "/pulls/\(number)/reviews?per_page=100&page=1", json: reviews)
        MockURLProtocol.stub(urlContains: "/pulls/\(number)/reviews?per_page=100&page=2", json: [])
        MockURLProtocol.stub(urlContains: "/pulls/\(number)/reviews", json: reviews)
        // Check runs
        MockURLProtocol.stub(urlContains: "/check-runs", json: ["check_runs": checkRuns])
        MockURLProtocol.stub(urlContains: "/status", json: [
            "state": statusState,
            "statuses": commitStatuses
        ])
        // PR detail (least specific, registered last)
        MockURLProtocol.stub(urlContains: "/pulls/\(number)", json: [
            "head": ["sha": "abc123def456"],
            "state": "open",
            "user": ["login": authorLogin],
            "assignees": assignees,
            "requested_reviewers": requestedReviewers,
            "mergeable_state": mergeableState
        ])
    }
}
