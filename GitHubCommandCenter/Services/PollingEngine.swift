import Foundation

@MainActor
final class PollingEngine {
    private let appState: AppState
    private let recentlyClosedClearDelay: TimeInterval
    // Typed as the protocol so tests can inject a mock without touching Keychain
    var client: (any GitHubDataSource)?
    private var pollingTask: Task<Void, Never>?
    private var clearRecentlyClosedTask: Task<Void, Never>?
    private var previousPRs: [PRState] = []
    private var consecutiveFailures = 0

    init(
        appState: AppState,
        dataSource: (any GitHubDataSource)? = nil,
        recentlyClosedClearDelay: TimeInterval = 5
    ) {
        self.appState = appState
        self.client = dataSource
        self.recentlyClosedClearDelay = recentlyClosedClearDelay
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { await runLoop() }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func reset() {
        clearRecentlyClosedTask?.cancel()
        clearRecentlyClosedTask = nil
        previousPRs = []
        consecutiveFailures = 0
    }

    func forceRefresh() {
        pollingTask?.cancel()
        pollingTask = Task {
            await poll()
            await runLoop()
        }
    }

    // MARK: - Loop

    private func runLoop() async {
        while !Task.isCancelled {
            await poll()
            guard !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    // Internal so tests can assert the dynamic interval value
    var pollInterval: TimeInterval {
        // Dynamic interval based on PR count to stay within rate limits
        switch appState.prs.count {
        case 0..<20: return 60
        case 20..<40: return 120
        default:     return 300
        }
    }

    // MARK: - Poll

    // Internal so tests can call a single poll cycle directly
    func poll() async {
        appState.recomputeStaleness()

        // Create REST client from Keychain token if none was injected
        if client == nil {
            let token: String?
            do {
                token = try KeychainService.shared.loadToken()
            } catch {
                appState.authenticationStatus = .failed
                appState.error = .authError
                appState.isLoading = false
                appState.recomputeStaleness()
                stop()
                return
            }

            guard let token, !token.isEmpty else {
                appState.authenticationStatus = .noToken
                appState.error = .noToken
                appState.isLoading = false
                appState.recomputeStaleness()
                stop()
                return
            }
            client = GitHubRESTClient(token: token)
        }
        guard let client else { return }

        appState.isLoading = appState.prs.isEmpty

        do {
            // Get username — validate once, then reuse
            let username: String
            if case .authenticated(let u) = appState.authenticationStatus {
                username = u
            } else {
                username = try await client.validateToken()
                appState.authenticationStatus = .authenticated(username: username)
            }

            let newPRs = try await client.fetchAllPRStates(username: username)

            // Detect PRs that disappeared from the open/involved search, then confirm closure.
            let disappeared = previousPRs.filter { prev in
                !newPRs.contains { $0.id == prev.id }
            }
            let recentlyClosed = await client.resolveDisappearedPRs(disappeared)

            // Fire transition notifications (skip on very first poll — no baseline yet)
            if !previousPRs.isEmpty {
                NotificationService.shared.checkTransitions(
                    from: previousPRs,
                    to: newPRs,
                    disappeared: recentlyClosed
                )
            }

            // Show recently closed for one poll cycle then clear
            appState.recentlyClosedPRs = recentlyClosed
            if !recentlyClosed.isEmpty {
                clearRecentlyClosedTask?.cancel()
                clearRecentlyClosedTask = Task { @MainActor [weak self] in
                    let delay = UInt64(recentlyClosedClearDelay * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled else { return }
                    self?.appState.recentlyClosedPRs = []
                    self?.clearRecentlyClosedTask = nil
                }
            }

            if newPRs != previousPRs {
                appState.prs = newPRs
            }
            appState.lastUpdated = Date()
            if appState.isLoading { appState.isLoading = false }
            if appState.error != nil { appState.error = nil }
            if appState.isRateLimited { appState.isRateLimited = false }
            appState.recomputeStaleness()

            previousPRs = newPRs
            consecutiveFailures = 0

        } catch AppError.authError {
            appState.authenticationStatus = .failed
            appState.error = .authError
            appState.isLoading = false
            appState.recomputeStaleness()
            stop()

        } catch AppError.noToken {
            appState.authenticationStatus = .noToken
            appState.error = .noToken
            appState.isLoading = false
            appState.recomputeStaleness()
            stop()

        } catch AppError.rateLimitExceeded(let resetAt) {
            appState.isRateLimited = true
            appState.rateLimitResetDate = resetAt
            appState.error = .rateLimitExceeded(resetAt: resetAt)
            appState.isLoading = false
            appState.recomputeStaleness()

            // Back off until rate limit resets
            let delay = max(resetAt.timeIntervalSinceNow + 5, 60)
            stop()
            pollingTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                appState.isRateLimited = false
                await runLoop()
            }

        } catch AppError.incompleteSearchResults {
            appState.error = .incompleteSearchResults
            appState.isLoading = false
            appState.recomputeStaleness()

        } catch {
            consecutiveFailures += 1
            appState.error = .networkError
            appState.isLoading = false
            appState.recomputeStaleness()
            // Exponential backoff capped at 60s
            let backoff = min(Double(2 << min(consecutiveFailures, 5)), 60.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
    }

}
