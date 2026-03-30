import Foundation

@MainActor
final class PollingEngine {
    private let appState: AppState
    private var client: GitHubRESTClient?
    private var pollingTask: Task<Void, Never>?
    private var previousPRs: [PRState] = []
    private var consecutiveFailures = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { await runLoop() }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
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

    private var pollInterval: TimeInterval {
        // Dynamic interval based on PR count to stay within rate limits
        switch appState.prs.count {
        case 0..<20: return 60
        case 20..<40: return 120
        default:     return 300
        }
    }

    // MARK: - Poll

    private func poll() async {
        // Load token
        guard let token = try? KeychainService.shared.loadToken(), !token.isEmpty else {
            appState.authenticationStatus = .noToken
            appState.error = .noToken
            appState.isLoading = false
            stop()
            return
        }

        // Reuse client across polls to preserve ETags
        if client == nil { client = GitHubRESTClient(token: token) }
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

            // Detect disappeared PRs (merged/closed)
            let disappeared = previousPRs.filter { prev in
                !newPRs.contains { $0.id == prev.id }
            }

            // Fire transition notifications (skip on very first poll — no baseline yet)
            if !previousPRs.isEmpty {
                NotificationService.shared.checkTransitions(
                    from: previousPRs,
                    to: newPRs,
                    disappeared: disappeared
                )
            }

            // Show recently closed for one poll cycle then clear
            appState.recentlyClosedPRs = disappeared
            if !disappeared.isEmpty {
                Task { [weak appState] in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    appState?.recentlyClosedPRs = []
                }
            }

            appState.prs = newPRs
            appState.lastUpdated = Date()
            appState.isLoading = false
            appState.error = nil
            appState.isRateLimited = false
            appState.markStaleIfNeeded()

            previousPRs = newPRs
            consecutiveFailures = 0

        } catch AppError.authError {
            appState.authenticationStatus = .failed
            appState.error = .authError
            appState.isLoading = false
            stop()

        } catch AppError.noToken {
            appState.authenticationStatus = .noToken
            appState.error = .noToken
            appState.isLoading = false
            stop()

        } catch AppError.rateLimitExceeded(let resetAt) {
            appState.isRateLimited = true
            appState.rateLimitResetDate = resetAt
            appState.error = .rateLimitExceeded(resetAt: resetAt)
            appState.isLoading = false

            // Back off until rate limit resets
            let delay = max(resetAt.timeIntervalSinceNow + 5, 60)
            stop()
            pollingTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                appState.isRateLimited = false
                await runLoop()
            }

        } catch {
            consecutiveFailures += 1
            appState.error = .networkError
            appState.isLoading = false
            // Exponential backoff capped at 60s
            let backoff = min(Double(2 << min(consecutiveFailures, 5)), 60.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
    }

    private func sleep(_ interval: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}
