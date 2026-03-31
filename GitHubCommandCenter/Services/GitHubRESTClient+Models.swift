import Foundation

extension GitHubRESTClient {
    struct APIErrorResponse: Codable, Sendable {
        let message: String
    }

    struct HTTPDataResponse {
        let data: Data
        let response: HTTPURLResponse
    }

    struct AggregatedCICheck {
        let identifier: String
        let failingCheck: PRState.FailingCheck?
        let isPending: Bool

        func merged(with other: AggregatedCICheck) -> AggregatedCICheck {
            if let failingCheck {
                return .init(identifier: identifier, failingCheck: failingCheck, isPending: false)
            }

            if let otherFailingCheck = other.failingCheck {
                return .init(identifier: identifier, failingCheck: otherFailingCheck, isPending: false)
            }

            return .init(
                identifier: identifier,
                failingCheck: nil,
                isPending: isPending || other.isPending
            )
        }
    }

    struct GitHubUser: Codable, Sendable {
        let login: String
    }

    struct SearchResponse: Codable, Sendable {
        let totalCount: Int
        let incompleteResults: Bool
        let items: [SearchItem]
    }

    struct SearchItem: Codable, Sendable {
        let number: Int
        let title: String
        let htmlUrl: String
        let draft: Bool?
        let updatedAt: String
        let repositoryUrl: String
    }

    struct PRDetail: Codable, Sendable {
        let head: Head
        let state: String
        let user: GitHubUser
        let assignees: [GitHubUser]
        let requestedReviewers: [GitHubUser]
        let mergeableState: String?

        struct Head: Codable, Sendable {
            let sha: String
        }
    }

    struct Review: Codable, Sendable {
        let user: GitHubUser
        let state: String
    }

    struct CheckRunsResponse: Codable, Sendable {
        let checkRuns: [CheckRun]
    }

    struct CheckRun: Codable, Sendable {
        let name: String
        let status: String
        let conclusion: String?
        let htmlUrl: String?
    }

    struct CombinedStatusResponse: Codable, Sendable {
        let state: String
        let statuses: [CommitStatus]
    }

    struct CommitStatus: Codable, Sendable {
        let context: String
        let state: String
        let targetUrl: String?
    }

    struct AccessibleRepositoryResponse: Codable, Sendable {
        let id: Int
        let fullName: String
        let permissions: RepositoryPermissions?

        var tokenAccessRepository: TokenAccessDetails.AccessibleRepository {
            TokenAccessDetails.AccessibleRepository(
                id: id,
                fullName: fullName,
                accessLevel: accessLevel
            )
        }

        private var accessLevel: TokenAccessDetails.AccessibleRepository.AccessLevel {
            guard let permissions else { return .read }
            if permissions.admin { return .admin }
            if permissions.push { return .write }
            return .read
        }
    }

    struct RepositoryPermissions: Codable, Sendable {
        let admin: Bool
        let push: Bool
        let pull: Bool
    }
}
