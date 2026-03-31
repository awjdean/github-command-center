import Foundation

enum AppError: LocalizedError, Sendable, Equatable {
    struct RateLimitContext: Sendable, Equatable {
        let resetAt: Date
        let nextUpdateDescription: String

        init(resetAt: Date) {
            self.resetAt = resetAt
            nextUpdateDescription = resetAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.resetAt == rhs.resetAt
        }
    }

    case authError
    case incompleteSearchResults
    case noToken
    case paginationLimitExceeded
    case rateLimitExceeded(RateLimitContext)
    case networkError
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .authError:
            return "Authentication failed. Check your GitHub token."
        case .incompleteSearchResults:
            return "GitHub search returned incomplete results. Try again later or narrow the search."
        case .noToken:
            return "No GitHub token configured."
        case .paginationLimitExceeded:
            return "GitHub pagination exceeded the safe page limit. Try again later."
        case .rateLimitExceeded(let context):
            return "Rate limited — next update \(context.nextUpdateDescription)"
        case .networkError:
            return "Network connection failed."
        case .serverError(let code):
            return "GitHub API error (\(code))."
        }
    }
}
