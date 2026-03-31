import Foundation

enum AppError: LocalizedError, Sendable, Equatable {
    case authError
    case incompleteSearchResults
    case noToken
    case paginationLimitExceeded
    case rateLimitExceeded(resetAt: Date)
    case networkError
    case serverError(statusCode: Int)

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    private static let relativeDateFormatterLock = NSLock()

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
        case .rateLimitExceeded(let date):
            AppError.relativeDateFormatterLock.lock()
            let nextUpdate = AppError.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
            AppError.relativeDateFormatterLock.unlock()
            return
                "Rate limited — next update \(nextUpdate)"
        case .networkError:
            return "Network connection failed."
        case .serverError(let code):
            return "GitHub API error (\(code))."
        }
    }
}
