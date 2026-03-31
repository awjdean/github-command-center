import Testing

@testable import GitHubCommandCenter

extension GitHubRESTClientTests {
    @Test
    func fetchTokenAccessDetails_classicTokenParsesReportedScopes() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        MockURLProtocol.stub(
            urlContains: "/user",
            headers: ["X-OAuth-Scopes": "repo, workflow"],
            json: ["login": "octocat"]
        )
        MockURLProtocol.stub(
            urlContains: "/user/repos?affiliation=owner,collaborator,organization_member&per_page=100&page=1",
            json: []
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let details = try await client.fetchTokenAccessDetails()

        #expect(details.username == "octocat")
        #expect(details.oauthScopes == ["repo", "workflow"])
    }

    @Test
    func fetchTokenAccessDetails_withoutReportedScopesReturnsEmptyScopeList() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        MockURLProtocol.stub(
            urlContains: "/user",
            json: ["login": "octocat"]
        )
        MockURLProtocol.stub(
            urlContains: "/user/repos?affiliation=owner,collaborator,organization_member&per_page=100&page=1",
            json: []
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let details = try await client.fetchTokenAccessDetails()

        #expect(details.oauthScopes.isEmpty)
    }

    @Test
    func fetchTokenAccessDetails_accessibleRepositoriesPaginatesAndMapsAccessLevels() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        MockURLProtocol.stub(
            urlContains: "/user",
            json: ["login": "octocat"]
        )

        let firstPage: [[String: Any]] = (1...100).map { number in
            [
                "id": number,
                "full_name": "org/repo-\(number)",
                "permissions": [
                    "admin": false,
                    "push": false,
                    "pull": true,
                ],
            ]
        }

        MockURLProtocol.stub(
            urlContains: "/user/repos?affiliation=owner,collaborator,organization_member&per_page=100&page=1",
            json: firstPage
        )
        MockURLProtocol.stub(
            urlContains: "/user/repos?affiliation=owner,collaborator,organization_member&per_page=100&page=2",
            json: [
                [
                    "id": 101,
                    "full_name": "org/admin-repo",
                    "permissions": [
                        "admin": true,
                        "push": true,
                        "pull": true,
                    ],
                ],
                [
                    "id": 102,
                    "full_name": "org/write-repo",
                    "permissions": [
                        "admin": false,
                        "push": true,
                        "pull": true,
                    ],
                ],
            ]
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let details = try await client.fetchTokenAccessDetails()

        #expect(details.accessibleRepositories.count == 102)
        #expect(details.accessibleRepositories.first?.fullName == "org/repo-1")
        #expect(details.accessibleRepositories.first?.accessLevel == .read)
        #expect(details.accessibleRepositories[99].fullName == "org/repo-100")
        #expect(details.accessibleRepositories[100].fullName == "org/admin-repo")
        #expect(details.accessibleRepositories[100].accessLevel == .admin)
        #expect(details.accessibleRepositories[101].fullName == "org/write-repo")
        #expect(details.accessibleRepositories[101].accessLevel == .write)
    }

    @Test
    func fetchTokenAccessDetails_accessibleRepositoriesStopsAtConfiguredLimit() async throws {
        let harness = Harness()
        defer { harness.teardown() }
        MockURLProtocol.stub(
            urlContains: "/user",
            json: ["login": "octocat"]
        )

        for page in 1...10 {
            let repositories: [[String: Any]] = (1...100).map { offset in
                let id = ((page - 1) * 100) + offset
                return [
                    "id": id,
                    "full_name": "org/repo-\(id)",
                    "permissions": [
                        "admin": false,
                        "push": false,
                        "pull": true,
                    ],
                ]
            }
            MockURLProtocol.stub(
                urlContains: "/user/repos?affiliation=owner,collaborator,organization_member&per_page=100&page=\(page)",
                json: repositories
            )
        }
        MockURLProtocol.stub(
            urlContains: "/user/repos?affiliation=owner,collaborator,organization_member&per_page=100&page=11",
            json: []
        )

        let client = GitHubRESTClient(token: "test-token", session: harness.session)
        let details = try await client.fetchTokenAccessDetails()

        #expect(details.accessibleRepositories.count == 1000)
        #expect(details.accessibleRepositories.last?.fullName == "org/repo-1000")
        #expect(
            MockURLProtocol.capturedRequests.contains {
                $0.url?.absoluteString.contains("page=11") == true
            } == false
        )
    }
}
