import Testing

@testable import GitHubCommandCenter

extension GitHubRESTClientTests {
    @Test
    func validateTokenForAppAccess_success_returnsUsernameWhenSearchEmpty() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        let expectedMessage =
            "Token saved, but full PR status access could not be verified yet. "
            + "The warning will clear after a successful poll loads PR status data."

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
        let result = try await client.validateTokenForAppAccess()

        #expect(result == .warning(username: "octocat", message: expectedMessage))
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
        defer { harness.teardown() }
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
    func validateTokenForAppAccess_incompleteSearchResults_returnsWarning() async {
        let harness = Harness()
        defer { harness.teardown() }
        let expectedMessage =
            "GitHub search results are temporarily incomplete. "
            + "The token was saved, but full PR status access could not be verified yet."

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
            let result = try await client.validateTokenForAppAccess()
            #expect(result == .warning(username: "octocat", message: expectedMessage))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func validateTokenForAppAccess_nonEmptySearch_commitStatus403_throwsAuthError() async {
        let harness = Harness()
        defer { harness.teardown() }
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        stubFullPRFlow(checkRunsStatusCode: 403, statusCodeForCommitStatuses: 403)

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
    func validateTokenForAppAccess_nonEmptySearch_checkRuns403_stillVerifiesWhenCommitStatusesReadable() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        MockURLProtocol.stub(urlContains: "/user", json: ["login": "octocat"])
        stubFullPRFlow(
            checkRunsStatusCode: 403,
            statusState: "success",
            commitStatuses: [["context": "legacy-ci", "state": "success"]]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let result = try await client.validateTokenForAppAccess()

        #expect(result == .verified(username: "octocat"))
    }
}
