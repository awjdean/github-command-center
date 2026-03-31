import Foundation

struct PRFetchResult: Equatable, Sendable, RandomAccessCollection, ExpressibleByArrayLiteral {
    typealias Element = PRState
    typealias Index = Array<PRState>.Index
    typealias ArrayLiteralElement = PRState

    let prs: [PRState]
    let warningMessage: String?

    init(prs: [PRState], warningMessage: String? = nil) {
        self.prs = prs
        self.warningMessage = warningMessage
    }

    init(arrayLiteral elements: PRState...) {
        self.init(prs: elements)
    }

    var startIndex: Index { prs.startIndex }
    var endIndex: Index { prs.endIndex }

    subscript(position: Index) -> PRState {
        prs[position]
    }

    func index(after position: Index) -> Index {
        prs.index(after: position)
    }

    func index(before position: Index) -> Index {
        prs.index(before: position)
    }
}

protocol GitHubDataSource: Sendable {
    /// Validates the token and returns the authenticated username.
    func validateToken() async throws -> String

    /// Fetches all open PRs involving the given username across all accessible repos.
    func fetchAllPRStates(username: String) async throws -> PRFetchResult

    /// Confirms which PRs that disappeared from the open/involved search are actually closed.
    func resolveDisappearedPRs(_ prs: [PRState]) async -> [PRState]
}
