import Foundation

struct TokenAccessDetails: Equatable, Sendable {
    let username: String
    let oauthScopes: [String]
    let accessibleRepositories: [AccessibleRepository]

    struct AccessibleRepository: Identifiable, Equatable, Sendable {
        let id: Int
        let fullName: String
        let accessLevel: AccessLevel

        enum AccessLevel: String, Equatable, Sendable {
            case admin
            case write
            case read
        }
    }
}
