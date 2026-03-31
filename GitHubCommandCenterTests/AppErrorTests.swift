import Foundation
import Testing

@testable import GitHubCommandCenter

@Suite(.serialized)
struct AppErrorTests {
    @Test(.timeLimit(.minutes(1)))
    func rateLimitContext_nextUpdateDescription_isComputedAtReadTime() async throws {
        let context = AppError.RateLimitContext(resetAt: Date().addingTimeInterval(1))
        let initialDescription = context.nextUpdateDescription

        try await Task.sleep(nanoseconds: 1_200_000_000)

        let refreshedDescription = context.nextUpdateDescription

        #expect(refreshedDescription == context.resetAt.formatted(.relative(presentation: .named, unitsStyle: .wide)))
        #expect(refreshedDescription != initialDescription)
    }
}
