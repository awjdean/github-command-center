import Foundation
@testable import GitHubCommandCenter

final class MockGitHubDataSource: GitHubDataSource {
    var validateTokenResult: Result<String, Error> = .success("testuser")
    var fetchResult: Result<[PRState], Error> = .success([])
    var validateTokenCallCount = 0
    var fetchCallCount = 0
    var resolvedDisappearedPRs: [PRState] = []
    var lastResolvedDisappearedInput: [PRState] = []

    func validateToken() async throws -> String {
        validateTokenCallCount += 1
        switch validateTokenResult {
        case .success(let username): return username
        case .failure(let error):   throw error
        }
    }

    func fetchAllPRStates(username: String) async throws -> [PRState] {
        fetchCallCount += 1
        switch fetchResult {
        case .success(let prs): return prs
        case .failure(let error): throw error
        }
    }

    func resolveDisappearedPRs(_ prs: [PRState]) async -> [PRState] {
        lastResolvedDisappearedInput = prs
        return resolvedDisappearedPRs
    }
}
