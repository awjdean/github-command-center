import Foundation

@testable import GitHubCommandCenter

final class MockGitHubDataSource: GitHubDataSource, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "MockGitHubDataSource.state")

    private var storedValidateTokenResult: Result<String, Error> = .success("testuser")
    private var storedFetchResult: Result<PRFetchResult, Error> = .success(.init(prs: []))
    private var storedValidateTokenCallCount = 0
    private var storedFetchCallCount = 0
    private var storedResolvedDisappearedPRs: [PRState] = []
    private var storedLastResolvedDisappearedInput: [PRState] = []

    var validateTokenResult: Result<String, Error> {
        get { stateQueue.sync { storedValidateTokenResult } }
        set { stateQueue.sync { storedValidateTokenResult = newValue } }
    }

    var fetchResult: Result<PRFetchResult, Error> {
        get { stateQueue.sync { storedFetchResult } }
        set { stateQueue.sync { storedFetchResult = newValue } }
    }

    var resolvedDisappearedPRs: [PRState] {
        get { stateQueue.sync { storedResolvedDisappearedPRs } }
        set { stateQueue.sync { storedResolvedDisappearedPRs = newValue } }
    }

    var lastResolvedDisappearedInput: [PRState] {
        get { stateQueue.sync { storedLastResolvedDisappearedInput } }
        set { stateQueue.sync { storedLastResolvedDisappearedInput = newValue } }
    }

    var validateTokenCallCount: Int {
        stateQueue.sync { storedValidateTokenCallCount }
    }

    var fetchCallCount: Int {
        stateQueue.sync { storedFetchCallCount }
    }

    func validateToken() async throws -> String {
        let result = stateQueue.sync {
            storedValidateTokenCallCount += 1
            return storedValidateTokenResult
        }

        switch result {
        case .success(let username): return username
        case .failure(let error): throw error
        }
    }

    func fetchAllPRStates(username: String) async throws -> PRFetchResult {
        let fetchResult = stateQueue.sync {
            storedFetchCallCount += 1
            return storedFetchResult
        }

        switch fetchResult {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    func resolveDisappearedPRs(_ prs: [PRState]) async -> [PRState] {
        stateQueue.sync {
            storedLastResolvedDisappearedInput = prs
            return storedResolvedDisappearedPRs
        }
    }
}
