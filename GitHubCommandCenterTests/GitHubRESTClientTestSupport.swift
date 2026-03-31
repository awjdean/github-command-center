import Foundation

@testable import GitHubCommandCenter

final class Harness {
    let session: URLSession

    init() {
        MockURLProtocol.reset()
        session = MockURLProtocol.makeSession()
    }

    func teardown() {
        MockURLProtocol.reset()
    }
}

extension GitHubRESTClientTests {
    func stubFullPRFlow(
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
        checkRunsStatusCode: Int = 200,
        updatedAt: String = "2026-03-30T10:00:00.000Z",
        statusState: String = "success",
        statusCodeForCommitStatuses: Int = 200,
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
        if checkRunsStatusCode == 200 {
            MockURLProtocol.stub(
                urlContains: "/check-runs",
                json: ["total_count": checkRuns.count, "check_runs": checkRuns]
            )
        } else {
            MockURLProtocol.stub(urlContains: "/check-runs", statusCode: checkRunsStatusCode)
        }
        if statusCodeForCommitStatuses == 200 {
            MockURLProtocol.stub(
                urlContains: "/status",
                json: [
                    "state": statusState,
                    "statuses": commitStatuses,
                ]
            )
        } else {
            MockURLProtocol.stub(urlContains: "/status", statusCode: statusCodeForCommitStatuses)
        }
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
