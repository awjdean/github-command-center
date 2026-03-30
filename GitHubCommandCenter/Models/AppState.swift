import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var prs: [PRState] = []
    @Published var recentlyClosedPRs: [PRState] = []  // Shown for one poll cycle
    @Published var lastUpdated: Date?
    @Published var isLoading = true  // True on first launch before any fetch
    @Published var error: AppError?
    @Published var isRateLimited = false
    @Published var rateLimitResetDate: Date?
    @Published var isStale = false  // True if last update was >5 min ago
    @Published var authenticationStatus: AuthStatus = .unknown

    enum AuthStatus {
        case unknown
        case authenticated(username: String)
        case failed
        case noToken
    }

    enum HealthStatus {
        case green, yellow, red
    }

    // MARK: - Triage-sorted PR lists

    var needsActionPRs: [PRState] {
        prs.filter { $0.triageCategory == .needsYourAction }
            .sorted { lhs, rhs in
                lhs.urgencyScore != rhs.urgencyScore
                    ? lhs.urgencyScore > rhs.urgencyScore
                    : lhs.updatedAt > rhs.updatedAt
            }
    }

    var waitingOnOthersPRs: [PRState] {
        prs.filter { $0.triageCategory == .waitingOnOthers }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var healthStatus: HealthStatus {
        guard !prs.isEmpty else { return .green }
        let needsAction = needsActionPRs
        guard !needsAction.isEmpty else { return .green }
        return needsAction.contains { $0.urgencyScore >= 3 } ? .red : .yellow
    }

    // MARK: - Polling lifecycle (owned by AppState to keep wiring simple)

    private var pollingEngine: PollingEngine?

    func startPollingIfNeeded() {
        guard pollingEngine == nil else { return }
        let engine = PollingEngine(appState: self)
        pollingEngine = engine
        Task { await NotificationService.shared.requestPermission() }
        engine.start()
    }

    func forceRefresh() {
        pollingEngine?.forceRefresh()
    }

    // Called by PollingEngine after each successful fetch
    func markStaleIfNeeded() {
        guard let lastUpdated else { return }
        isStale = Date().timeIntervalSince(lastUpdated) > 300
    }

    // Called by PollingEngine when token changes in Settings
    func resetPolling() {
        pollingEngine?.stop()
        pollingEngine = nil
        authenticationStatus = .unknown
        error = nil
        isRateLimited = false
        isLoading = true
        startPollingIfNeeded()
    }
}
