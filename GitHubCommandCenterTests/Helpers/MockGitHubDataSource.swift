import Foundation

@testable import GitHubCommandCenter

final class MockGitHubDataSource: GitHubDataSource {
    private let stateQueue = DispatchQueue(label: "MockGitHubDataSource.state")

    var validateTokenResult: Result<String, Error> = .success("testuser")
    var fetchResult: Result<[PRState], Error> = .success([])
    private var storedValidateTokenCallCount = 0
    private var storedFetchCallCount = 0
    var resolvedDisappearedPRs: [PRState] = []
    var lastResolvedDisappearedInput: [PRState] = []

    var validateTokenCallCount: Int {
        stateQueue.sync { storedValidateTokenCallCount }
    }

    var fetchCallCount: Int {
        stateQueue.sync { storedFetchCallCount }
    }

    func validateToken() async throws -> String {
        stateQueue.sync { storedValidateTokenCallCount += 1 }
        switch validateTokenResult {
        case .success(let username): return username
        case .failure(let error): throw error
        }
    }

    func fetchAllPRStates(username: String) async throws -> [PRState] {
        stateQueue.sync { storedFetchCallCount += 1 }
        switch fetchResult {
        case .success(let prs): return prs
        case .failure(let error): throw error
        }
    }

    func resolveDisappearedPRs(_ prs: [PRState]) async -> [PRState] {
        stateQueue.sync {
            lastResolvedDisappearedInput = prs
            return resolvedDisappearedPRs
        }
    }
}
