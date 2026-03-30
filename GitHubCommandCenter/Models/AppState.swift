import Foundation
import SwiftUI

@MainActor
protocol PollingControlling: AnyObject {
    func start()
    func stop()
    func reset()
    func forceRefresh()
}

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
        case loadError
        case empty
        case prList
    }

    // MARK: - Triage-sorted PR lists

    var needsActionPRs: [PRState] {
        prs.filter { $0.triageCategory == .needsYourAction }
            .sorted(by: PRState.compareForNeedsAction)
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
            if error != nil {
                return .loadError
            }
            return .empty
        }
    }

    // MARK: - Polling lifecycle (owned by AppState to keep wiring simple)

    private var pollingEngine: (any PollingControlling)?
    private let makePollingEngine: (AppState) -> any PollingControlling
    private let requestNotificationPermission: () async -> Void

    init() {
        self.makePollingEngine = { PollingEngine(appState: $0) }
        self.requestNotificationPermission = { await NotificationService.shared.requestPermission() }
    }

    init(
        makePollingEngine: @escaping (AppState) -> any PollingControlling,
        requestNotificationPermission: @escaping () async -> Void
    ) {
        self.makePollingEngine = makePollingEngine
        self.requestNotificationPermission = requestNotificationPermission
    }

    private func clearPublishedSessionState() {
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

    func startPollingIfNeeded() {
        guard pollingEngine == nil else { return }
        let engine = makePollingEngine(self)
        pollingEngine = engine
        // Intentionally fire-and-forget: notification permission is non-fatal and should not block startup.
        Task { await requestNotificationPermission() }
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
        pollingEngine?.reset()
        clearPublishedSessionState()
    }

    // Called by PollingEngine when token changes in Settings
    func resetPolling() {
        pollingEngine?.reset()
        pollingEngine?.stop()
        clearPublishedSessionState()
        pollingEngine = nil
        startPollingIfNeeded()
    }
}
