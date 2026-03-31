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
    @Published var prs: [PRState] = [] {
        didSet {
            recomputePRCaches()
        }
    }
    @Published var recentlyClosedPRs: [PRState] = []  // Shown for one poll cycle
    @Published var lastUpdated: Date?
    @Published var isLoading = true
    @Published var error: AppError?
    @Published var isStale = false
    @Published var authenticationStatus: AuthStatus = .unknown

    var isRateLimited: Bool {
        if case .rateLimitExceeded = error { return true } else { return false }
    }

    var rateLimitResetDate: Date? {
        if case .rateLimitExceeded(let date) = error { return date } else { return nil }
    }

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
        cachedNeedsActionPRs
    }

    var waitingOnOthersPRs: [PRState] {
        cachedWaitingOnOthersPRs
    }

    var healthStatus: HealthStatus {
        guard !prs.isEmpty else { return .green }
        let needsAction = needsActionPRs
        guard !needsAction.isEmpty else { return .green }
        return needsAction.contains { $0.urgencyScore >= 3 } ? .red : .yellow
    }

    var panelSubtitleText: String {
        switch authenticationStatus {
        case .authenticated:
            return "\(prs.count) tracked PR\(prs.count == 1 ? "" : "s")"
        default:
            return "\(prs.count) open PR\(prs.count == 1 ? "" : "s")"
        }
    }

    var emptyStateMessage: String? {
        guard !isLoading, prs.isEmpty else { return nil }
        guard case .authenticated(let username) = authenticationStatus else { return nil }

        return
            "This app tracks pull requests involving @\(username). "
            + "If you expected results here, make sure your GitHub token can access those repositories."
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
    private let preloadTokenIfNeeded: () -> Void
    private var cachedNeedsActionPRs: [PRState] = []
    private var cachedWaitingOnOthersPRs: [PRState] = []

    init() {
        self.makePollingEngine = { PollingEngine(appState: $0) }
        self.requestNotificationPermission = { await NotificationService.shared.requestPermission() }
        self.preloadTokenIfNeeded = {
            _ = EnvironmentTokenBootstrapper().preloadIfNeeded()
        }
    }

    init(
        makePollingEngine: @escaping (AppState) -> any PollingControlling,
        requestNotificationPermission: @escaping () async -> Void,
        preloadTokenIfNeeded: @escaping () -> Void = {}
    ) {
        self.makePollingEngine = makePollingEngine
        self.requestNotificationPermission = requestNotificationPermission
        self.preloadTokenIfNeeded = preloadTokenIfNeeded
    }

    private func clearPublishedSessionState() {
        prs = []
        recentlyClosedPRs = []
        lastUpdated = nil
        isLoading = true
        error = nil
        isStale = false
        authenticationStatus = .unknown
    }

    private func recomputePRCaches() {
        cachedNeedsActionPRs =
            prs
            .filter { $0.triageCategory == .needsYourAction }
            .sorted(by: PRState.compareForNeedsAction)
        cachedWaitingOnOthersPRs =
            prs
            .filter { $0.triageCategory == .waitingOnOthers }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func startPollingIfNeeded() {
        guard pollingEngine == nil else { return }
        preloadTokenIfNeeded()
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

    func stopPollingForMissingToken() {
        pollingEngine?.reset()
        pollingEngine?.stop()
        pollingEngine = nil
        clearPublishedSessionState()
        isLoading = false
        authenticationStatus = .noToken
    }

    func resetPolling() {
        pollingEngine?.reset()
        pollingEngine?.stop()
        clearPublishedSessionState()
        pollingEngine = nil
        startPollingIfNeeded()
    }
}
