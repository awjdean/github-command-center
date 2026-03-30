import Foundation

@MainActor
final class PollingEngine: PollingControlling {
    enum PollOutcome: Equatable {
        case useRegularInterval
        case continueImmediately
        case stopLoop
    }

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
        pollingLoop: while !Task.isCancelled {
            let outcome = await poll()
            guard !Task.isCancelled else { break }

            switch outcome {
            case .useRegularInterval:
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            case .continueImmediately:
                continue pollingLoop
            case .stopLoop:
                break pollingLoop
            }
        }
    }

    // Internal so tests can assert the dynamic interval value
    var pollInterval: TimeInterval {
        // Dynamic interval based on PR count to stay within rate limits
        switch appState.prs.count {
        case 0..<20: return 60
        case 20..<40: return 120
        default: return 300
        }
    }

    // MARK: - Poll

    // Internal so tests can call a single poll cycle directly
    @discardableResult
    func poll() async -> PollOutcome {
        appState.recomputeStaleness()
        defer { appState.recomputeStaleness() }

        if client == nil {
            let token: String?
            do {
                token = try KeychainService.shared.loadToken()
            } catch {
                handleAuthFailure(status: .failed, error: .authError)
                return .stopLoop
            }

            guard let token, !token.isEmpty else {
                handleAuthFailure(status: .noToken, error: .noToken)
                return .stopLoop
            }
            client = GitHubRESTClient(token: token)
        }
        guard let client else { return .stopLoop }

        appState.isLoading = appState.prs.isEmpty

        do {
            let username: String
            if case .authenticated(let authenticatedUsername) = appState.authenticationStatus {
                username = authenticatedUsername
            } else {
                username = try await client.validateToken()
                appState.authenticationStatus = .authenticated(username: username)
            }

            let newPRs = try await client.fetchAllPRStates(username: username)

            let disappeared = previousPRs.filter { prev in
                !newPRs.contains { $0.id == prev.id }
            }
            let recentlyClosed = await client.resolveDisappearedPRs(disappeared)

            if !previousPRs.isEmpty {
                NotificationService.shared.checkTransitions(
                    from: previousPRs,
                    to: newPRs,
                    disappeared: recentlyClosed
                )
            }

            appState.recentlyClosedPRs = recentlyClosed
            if !recentlyClosed.isEmpty {
                clearRecentlyClosedTask?.cancel()
                clearRecentlyClosedTask = Task { @MainActor [weak self] in
                    let delay = UInt64((self?.recentlyClosedClearDelay ?? 0) * 1_000_000_000)
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

            previousPRs = newPRs
            consecutiveFailures = 0
            return .useRegularInterval

        } catch AppError.authError {
            handleAuthFailure(status: .failed, error: .authError)
            return .stopLoop

        } catch AppError.noToken {
            handleAuthFailure(status: .noToken, error: .noToken)
            return .stopLoop

        } catch AppError.rateLimitExceeded(let resetAt) {
            appState.error = .rateLimitExceeded(resetAt: resetAt)
            appState.isLoading = false

            let delay = max(resetAt.timeIntervalSinceNow + 5, 60)
            stop()
            pollingTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                appState.error = nil
                await runLoop()
            }
            return .stopLoop

        } catch AppError.incompleteSearchResults {
            appState.error = .incompleteSearchResults
            appState.isLoading = false
            return .useRegularInterval

        } catch {
            consecutiveFailures += 1
            appState.error = .networkError
            appState.isLoading = false
            let backoff = min(Double(2 << min(consecutiveFailures, 5)), 60.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            return .continueImmediately
        }
    }

    private func handleAuthFailure(status: AppState.AuthStatus, error: AppError) {
        appState.authenticationStatus = status
        appState.error = error
        appState.isLoading = false
        stop()
    }

}
