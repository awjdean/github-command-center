import Foundation

protocol GitHubDataSource {
    /// Validates the token and returns the authenticated username.
    func validateToken() async throws -> String

    /// Fetches all open PRs involving the given username across all accessible repos.
    func fetchAllPRStates(username: String) async throws -> [PRState]

    /// Confirms which PRs that disappeared from the open/involved search are actually closed.
    func resolveDisappearedPRs(_ prs: [PRState]) async -> [PRState]
}
