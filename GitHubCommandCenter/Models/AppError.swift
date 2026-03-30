import Foundation

enum AppError: LocalizedError, Sendable, Equatable {
    case authError
    case noToken
    case rateLimitExceeded(resetAt: Date)
    case networkError
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .authError:
            return "Authentication failed. Check your GitHub token."
        case .noToken:
            return "No GitHub token configured."
        case .rateLimitExceeded(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return "Rate limited — next update \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .networkError:
            return "Network connection failed."
        case .serverError(let code):
            return "GitHub API error (\(code))."
        }
    }
}
