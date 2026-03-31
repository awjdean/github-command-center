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
}
