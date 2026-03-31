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
    private(set) var client: (any GitHubDataSource)?
    private var pollingTask: Task<Void, Never>?
    private var clearRecentlyClosedTask: Task<Void, Never>?
    private var clearRecentlyClosedTaskID: UUID?
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
        clearRecentlyClosedTaskID = nil
        previousPRs = []
        consecutiveFailures = 0
    }

    func forceRefresh() {
        pollingTask?.cancel()
        pollingTask = Task {
            let outcome = await poll()
            guard outcome != .stopLoop else { return }
            await runLoop()
        }
    }

    var pollInterval: TimeInterval {
        switch appState.prs.count {
        case 0..<20:
            return 60
        case 20..<40:
            return 120
        default:
            return 300
        }
    }

    private func runLoop() async {
        pollingLoop: while !Task.isCancelled {
            let outcome = await poll()
            guard !Task.isCancelled else { break }

            switch outcome {
            case .useRegularInterval:
                let interval = pollInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            case .continueImmediately:
                continue pollingLoop
            case .stopLoop:
                break pollingLoop
            }
        }
    }

    @discardableResult
    func poll() async -> PollOutcome {
        var context = await appState.currentPollContext()
        context.panel.isStale = AppState.staleStatus(lastUpdated: context.panel.lastUpdated)

        if client == nil {
            do {
                let token = try KeychainService.shared.loadToken()
                guard let token, !token.isEmpty else {
                    await handleAuthFailure(status: .noToken, error: .noToken, context: &context)
                    return .stopLoop
                }
                client = GitHubRESTClient(token: token)
            } catch {
                await handleAuthFailure(status: .failed, error: .authError, context: &context)
                return .stopLoop
            }
        }

        guard let client else { return .stopLoop }

        do {
            let username: String
            if case .authenticated(let authenticatedUsername) = context.auth.authenticationStatus {
                username = authenticatedUsername
            } else {
                username = try await client.validateToken()
                context.auth.authenticationStatus = .authenticated(username: username)
            }

            let newPRs = try await client.fetchAllPRStates(username: username)
            let newIDs = Set(newPRs.map(\.id))
            let disappeared = previousPRs.filter { !newIDs.contains($0.id) }
            let recentlyClosed = await client.resolveDisappearedPRs(disappeared)

            if !previousPRs.isEmpty {
                NotificationService.shared.checkTransitions(
                    from: previousPRs,
                    to: newPRs,
                    disappeared: recentlyClosed
                )
            }

            context.panel.triageSnapshot = .build(from: newPRs)
            context.panel.recentlyClosedPRs = recentlyClosed
            context.panel.lastUpdated = Date()
            context.panel.isLoading = false
            context.panel.error = nil
            context.panel.isStale = false

            if !newPRs.isEmpty {
                context.auth.tokenValidationWarningMessage = nil
            }

            if !recentlyClosed.isEmpty {
                scheduleRecentlyClosedClearTask()
            }

            previousPRs = newPRs
            consecutiveFailures = 0
            await appState.applyPollSnapshot(.init(panel: context.panel, auth: context.auth))
            return .useRegularInterval

        } catch AppError.authError {
            await handleAuthFailure(status: .failed, error: .authError, context: &context)
            return .stopLoop

        } catch AppError.noToken {
            await handleAuthFailure(status: .noToken, error: .noToken, context: &context)
            return .stopLoop

        } catch AppError.rateLimitExceeded(let resetAt) {
            context.panel.error = .rateLimitExceeded(resetAt: resetAt)
            context.panel.isLoading = false
            context.panel.isStale = AppState.staleStatus(lastUpdated: context.panel.lastUpdated)
            await appState.applyPollSnapshot(.init(panel: context.panel, auth: context.auth))

            let delay = min(max(resetAt.timeIntervalSinceNow + 5, 60), 3600)
            stop()
            pollingTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }

                var recoveryContext = await self.appState.currentPollContext()
                recoveryContext.panel.error = nil
                recoveryContext.panel.isStale = AppState.staleStatus(lastUpdated: recoveryContext.panel.lastUpdated)
                await self.appState.applyPollSnapshot(.init(panel: recoveryContext.panel, auth: recoveryContext.auth))
                await self.runLoop()
            }
            return .stopLoop

        } catch AppError.incompleteSearchResults {
            context.panel.error = .incompleteSearchResults
            context.panel.isLoading = false
            context.panel.isStale = AppState.staleStatus(lastUpdated: context.panel.lastUpdated)
            await appState.applyPollSnapshot(.init(panel: context.panel, auth: context.auth))
            return .useRegularInterval

        } catch {
            consecutiveFailures += 1
            context.panel.error = .networkError
            context.panel.isLoading = false
            context.panel.isStale = AppState.staleStatus(lastUpdated: context.panel.lastUpdated)
            await appState.applyPollSnapshot(.init(panel: context.panel, auth: context.auth))

            let backoff = min(Double(2 << min(consecutiveFailures, 5)), 60.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            return .continueImmediately
        }
    }

    private func handleAuthFailure(
        status: AppState.AuthStatus,
        error: AppError,
        context: inout AppState.PollContext
    ) async {
        context.auth.authenticationStatus = status
        context.panel.error = error
        context.panel.isLoading = false
        context.panel.isStale = AppState.staleStatus(lastUpdated: context.panel.lastUpdated)
        await appState.applyPollSnapshot(.init(panel: context.panel, auth: context.auth))
        stop()
    }

    private func scheduleRecentlyClosedClearTask() {
        clearRecentlyClosedTask?.cancel()
        let taskID = UUID()
        clearRecentlyClosedTask = Task { [weak self] in
            guard let self else { return }

            let delay = UInt64(self.recentlyClosedClearDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            await self.appState.clearRecentlyClosedPRs()
            if self.clearRecentlyClosedTaskID == taskID {
                self.clearRecentlyClosedTask = nil
                self.clearRecentlyClosedTaskID = nil
            }
        }
        clearRecentlyClosedTaskID = taskID
    }
}
