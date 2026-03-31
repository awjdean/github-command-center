import Foundation
import Observation

@MainActor
protocol PollingControlling: AnyObject {
    func start()
    func stop()
    func reset()
    func forceRefresh()
}

@MainActor
final class NoOpPollingController: PollingControlling {
    func start() {}
    func stop() {}
    func reset() {}
    func forceRefresh() {}
}

@MainActor
@Observable
final class AppState {
    enum AuthStatus: Equatable, Sendable {
        case unknown
        case authenticated(username: String)
        case failed
        case noToken
    }

    enum HealthStatus: Equatable, Sendable {
        case green
        case yellow
        case red
    }

    enum PanelContentState: Equatable, Sendable {
        case loading
        case setupRequired
        case authError
        case loadError
        case empty
        case prList
    }

    struct TriageSnapshot: Equatable, Sendable {
        var prs: [PRState]
        var needsActionPRs: [PRState]
        var waitingOnOthersPRs: [PRState]
        var yourDraftPRs: [PRState]
        var menuBarBadgeCount: Int
        var healthStatus: HealthStatus

        static let empty = build(from: [])

        static func build(from prs: [PRState]) -> TriageSnapshot {
            let needsActionPRs =
                prs
                .filter { $0.triageCategory == .needsYourAction }
                .sorted(using: PRState.needsActionComparator)
            let waitingOnOthersPRs =
                prs
                .filter { $0.triageCategory == .waitingOnOthers }
                .sorted { $0.updatedAt > $1.updatedAt }
            let yourDraftPRs =
                prs
                .filter { $0.triageCategory == .yourDraft }
                .sorted { $0.updatedAt > $1.updatedAt }
            let menuBarBadgeCount = needsActionPRs.count
            let healthStatus: HealthStatus

            if prs.isEmpty || needsActionPRs.isEmpty {
                healthStatus = .green
            } else {
                healthStatus = needsActionPRs.contains { $0.urgencyScore >= 3 } ? .red : .yellow
            }

            return TriageSnapshot(
                prs: prs,
                needsActionPRs: needsActionPRs,
                waitingOnOthersPRs: waitingOnOthersPRs,
                yourDraftPRs: yourDraftPRs,
                menuBarBadgeCount: menuBarBadgeCount,
                healthStatus: healthStatus
            )
        }
    }

    struct PanelState: Equatable, Sendable {
        var triageSnapshot: TriageSnapshot = .empty
        var recentlyClosedPRs: [PRState] = []
        var lastUpdated: Date?
        var isLoading = true
        var error: AppError?
        var isStale = false
    }

    struct AuthState: Equatable, Sendable {
        var authenticationStatus: AuthStatus = .unknown
        var tokenValidationWarningMessage: String?
    }

    struct PollSnapshot: Equatable, Sendable {
        var panel: PanelState
        var auth: AuthState
    }

    struct PollContext: Equatable, Sendable {
        var panel: PanelState
        var auth: AuthState
    }

    var panel = PanelState()
    var auth = AuthState()

    @ObservationIgnored private var pollingEngine: (any PollingControlling)?
    @ObservationIgnored private let makePollingEngine: (AppState) -> any PollingControlling
    @ObservationIgnored private let requestNotificationPermission: () async -> Void
    @ObservationIgnored private let preloadTokenIfNeeded: () -> Void

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

    var prs: [PRState] {
        get { panel.triageSnapshot.prs }
        set { panel.triageSnapshot = TriageSnapshot.build(from: newValue) }
    }

    var recentlyClosedPRs: [PRState] {
        get { panel.recentlyClosedPRs }
        set { panel.recentlyClosedPRs = newValue }
    }

    var lastUpdated: Date? {
        get { panel.lastUpdated }
        set { panel.lastUpdated = newValue }
    }

    var isLoading: Bool {
        get { panel.isLoading }
        set { panel.isLoading = newValue }
    }

    var error: AppError? {
        get { panel.error }
        set { panel.error = newValue }
    }

    var isStale: Bool {
        get { panel.isStale }
        set { panel.isStale = newValue }
    }

    var authenticationStatus: AuthStatus {
        get { auth.authenticationStatus }
        set { auth.authenticationStatus = newValue }
    }

    var tokenValidationWarningMessage: String? {
        get { auth.tokenValidationWarningMessage }
        set { auth.tokenValidationWarningMessage = newValue }
    }

    var needsActionPRs: [PRState] {
        panel.triageSnapshot.needsActionPRs
    }

    var waitingOnOthersPRs: [PRState] {
        panel.triageSnapshot.waitingOnOthersPRs
    }

    var yourDraftPRs: [PRState] {
        panel.triageSnapshot.yourDraftPRs
    }

    var menuBarBadgeCount: Int {
        panel.triageSnapshot.menuBarBadgeCount
    }

    var healthStatus: HealthStatus {
        if case .failed = auth.authenticationStatus {
            return .red
        }

        if let error = panel.error {
            switch error {
            case .rateLimitExceeded, .networkError, .serverError, .paginationLimitExceeded:
                return .red
            case .incompleteSearchResults:
                return .yellow
            case .authError, .noToken:
                break
            }
        }

        if case .noToken = auth.authenticationStatus {
            return .yellow
        }

        if panel.isStale {
            return .yellow
        }

        return panel.triageSnapshot.healthStatus
    }

    var isRateLimited: Bool {
        if case .rateLimitExceeded = panel.error {
            return true
        }

        return false
    }

    var rateLimitResetDate: Date? {
        if case .rateLimitExceeded(let context) = panel.error {
            return context.resetAt
        }

        return nil
    }

    var panelSubtitleText: String {
        let prCount = panel.triageSnapshot.prs.count

        switch auth.authenticationStatus {
        case .authenticated:
            return "\(prCount) tracked PR\(prCount == 1 ? "" : "s")"
        default:
            return "\(prCount) open PR\(prCount == 1 ? "" : "s")"
        }
    }

    var emptyStateMessage: String? {
        guard !panel.isLoading, panel.triageSnapshot.prs.isEmpty else { return nil }
        guard case .authenticated(let username) = auth.authenticationStatus else { return nil }

        return
            "This app tracks pull requests involving @\(username). "
            + "If you expected results here, make sure your GitHub token can access those repositories."
    }

    var panelContentState: PanelContentState {
        if panel.isLoading {
            return .loading
        }

        guard panel.triageSnapshot.prs.isEmpty else {
            return .prList
        }

        switch auth.authenticationStatus {
        case .noToken:
            return .setupRequired
        case .failed:
            return .authError
        default:
            if panel.error != nil {
                return .loadError
            }

            return .empty
        }
    }

    var showsRecentlyClosedSection: Bool {
        guard !panel.recentlyClosedPRs.isEmpty else { return false }

        switch panelContentState {
        case .empty, .prList:
            return true
        case .loading, .setupRequired, .authError, .loadError:
            return false
        }
    }

    func startPollingIfNeeded() {
        guard pollingEngine == nil else { return }
        preloadTokenIfNeeded()
        let engine = makePollingEngine(self)
        pollingEngine = engine
        Task { await requestNotificationPermission() }
        engine.start()
    }

    func forceRefresh() {
        pollingEngine?.forceRefresh()
    }

    func currentPollContext() -> PollContext {
        PollContext(panel: panel, auth: auth)
    }

    func applyPollSnapshot(_ snapshot: PollSnapshot) {
        panel = snapshot.panel
        auth = snapshot.auth
    }

    func clearRecentlyClosedPRs() {
        panel.recentlyClosedPRs = []
    }

    func recomputeStaleness(now: Date = Date()) {
        panel.isStale = Self.staleStatus(lastUpdated: panel.lastUpdated, now: now)
    }

    nonisolated static func staleStatus(lastUpdated: Date?, now: Date = Date()) -> Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > 300
    }

    func clearSessionStateForNewSession() {
        pollingEngine?.reset()
        clearObservedSessionState()
    }

    func stopPollingForMissingToken() {
        pollingEngine?.reset()
        pollingEngine?.stop()
        pollingEngine = nil
        clearObservedSessionState()
        panel.isLoading = false
        auth.authenticationStatus = .noToken
    }

    func resetPolling() {
        pollingEngine?.reset()
        pollingEngine?.stop()
        clearObservedSessionState(preserveTokenValidationWarning: true)
        pollingEngine = nil
        startPollingIfNeeded()
    }

    private func clearObservedSessionState(preserveTokenValidationWarning: Bool = false) {
        let warningMessage = preserveTokenValidationWarning ? auth.tokenValidationWarningMessage : nil
        panel = PanelState()
        auth = AuthState(authenticationStatus: .unknown, tokenValidationWarningMessage: warningMessage)
    }
}
