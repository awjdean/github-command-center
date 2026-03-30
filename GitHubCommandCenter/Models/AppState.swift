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

    enum PanelContentState: Equatable {
        case loading
        case setupRequired
        case authError
        case empty
        case prList
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

    var panelContentState: PanelContentState {
        if isLoading {
            return .loading
        }

        guard prs.isEmpty else {
            return .prList
        }

        switch authenticationStatus {
        case .noToken:
            return .setupRequired
        case .failed:
            return .authError
        default:
            return .empty
        }
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

    func recomputeStaleness(now: Date = Date()) {
        guard let lastUpdated else {
            isStale = false
            return
        }
        isStale = now.timeIntervalSince(lastUpdated) > 300
    }

    func clearSessionStateForNewSession() {
        prs = []
        recentlyClosedPRs = []
        lastUpdated = nil
        isLoading = true
        error = nil
        isRateLimited = false
        rateLimitResetDate = nil
        isStale = false
        authenticationStatus = .unknown
    }

    // Called by PollingEngine when token changes in Settings
    func resetPolling() {
        pollingEngine?.stop()
        pollingEngine = nil
        clearSessionStateForNewSession()
        startPollingIfNeeded()
    }
}
