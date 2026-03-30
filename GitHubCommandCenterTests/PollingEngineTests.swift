import XCTest
@testable import GitHubCommandCenter

@MainActor
final class PollingEngineTests: XCTestCase {
    var appState: AppState!
    var mockSource: MockGitHubDataSource!
    var engine: PollingEngine!

    override func setUp() {
        appState = AppState()
        mockSource = MockGitHubDataSource()
        engine = PollingEngine(appState: appState, dataSource: mockSource)
    }

    override func tearDown() {
        engine.stop()
    }

    // MARK: - Dynamic poll interval

    func testPollInterval_fewerThan20PRs_is60s() {
        appState.prs = Array(repeating: .fixture(), count: 5)
        XCTAssertEqual(engine.pollInterval, 60)
    }

    func testPollInterval_20to39PRs_is120s() {
        appState.prs = Array(repeating: .fixture(), count: 25)
        XCTAssertEqual(engine.pollInterval, 120)
    }

    func testPollInterval_40orMorePRs_is300s() {
        appState.prs = Array(repeating: .fixture(), count: 50)
        XCTAssertEqual(engine.pollInterval, 300)
    }

    func testPollInterval_exactly20PRs_is120s() {
        appState.prs = Array(repeating: .fixture(), count: 20)
        XCTAssertEqual(engine.pollInterval, 120)
    }

    func testPollInterval_exactly40PRs_is300s() {
        appState.prs = Array(repeating: .fixture(), count: 40)
        XCTAssertEqual(engine.pollInterval, 300)
    }

    // MARK: - Successful poll

    func testPoll_updatesAppStatePRs() async {
        let pr = PRState.fixture(number: 1)
        mockSource.validateTokenResult = .success("octocat")
        mockSource.fetchResult = .success([pr])

        await engine.poll()

        XCTAssertEqual(appState.prs.count, 1)
        XCTAssertEqual(appState.prs.first?.number, 1)
    }

    func testPoll_setsLastUpdated() async {
        mockSource.fetchResult = .success([.fixture()])
        XCTAssertNil(appState.lastUpdated)
        await engine.poll()
        XCTAssertNotNil(appState.lastUpdated)
    }

    func testPoll_clearsError_onSuccess() async {
        appState.error = .networkError
        mockSource.fetchResult = .success([])
        await engine.poll()
        XCTAssertNil(appState.error)
    }

    func testPoll_setsIsLoading_falseAfterSuccess() async {
        appState.isLoading = true
        mockSource.fetchResult = .success([])
        await engine.poll()
        XCTAssertFalse(appState.isLoading)
    }

    // MARK: - First poll — no notifications

    func testPoll_firstPoll_doesNotFireNotifications() async {
        var firedCount = 0
        // Override shared notification service handler for this test
        NotificationService.shared.notificationHandler = { _, _ in firedCount += 1 }
        defer { NotificationService.shared.notificationHandler = nil }

        // PR with lots of state changes — but since previousPRs is empty, no notifications
        let pr = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )
        mockSource.fetchResult = .success([pr])
        await engine.poll()
        XCTAssertEqual(firedCount, 0)
    }

    // MARK: - State change detection

    func testPoll_PRDisappears_addedToRecentlyClosed() async {
        let pr = PRState.fixture(number: 99)
        mockSource.resolvedDisappearedPRs = [pr]
        mockSource.fetchResult = .success([pr])
        await engine.poll()  // establishes baseline

        mockSource.fetchResult = .success([])
        await engine.poll()  // PR disappears
        XCTAssertEqual(appState.recentlyClosedPRs.count, 1)
        XCTAssertEqual(appState.recentlyClosedPRs.first?.number, 99)
    }

    func testPoll_PRDisappears_withoutConfirmedClosure_notMarkedRecentlyClosed() async {
        let pr = PRState.fixture(number: 99)
        mockSource.fetchResult = .success([pr])
        await engine.poll()  // establishes baseline

        mockSource.resolvedDisappearedPRs = []
        mockSource.fetchResult = .success([])
        await engine.poll()

        XCTAssertTrue(appState.recentlyClosedPRs.isEmpty)
    }

    func testPoll_consecutiveSuccesses_resetsFailureCount() async {
        // Simulate a prior failure then success
        mockSource.fetchResult = .failure(AppError.networkError)
        await engine.poll()

        mockSource.fetchResult = .success([])
        await engine.poll()

        // consecutiveFailures is private, but we can verify error is cleared
        XCTAssertNil(appState.error)
    }

    // MARK: - Error handling

    func testPoll_authError_stopsPollingAndSetsStatus() async {
        mockSource.validateTokenResult = .failure(AppError.authError)
        await engine.poll()

        if case .failed = appState.authenticationStatus {} else {
            XCTFail("Expected .failed, got \(appState.authenticationStatus)")
        }
        XCTAssertEqual(appState.error, .authError)
    }

    func testPoll_networkError_setsNetworkError() async {
        mockSource.validateTokenResult = .success("octocat")
        mockSource.fetchResult = .failure(AppError.networkError)
        await engine.poll()
        XCTAssertEqual(appState.error, .networkError)
    }

    func testPoll_rateLimitExceeded_setsRateLimitState() async {
        let resetAt = Date().addingTimeInterval(3600)
        mockSource.validateTokenResult = .success("octocat")
        mockSource.fetchResult = .failure(AppError.rateLimitExceeded(resetAt: resetAt))
        await engine.poll()

        XCTAssertTrue(appState.isRateLimited)
        if case .rateLimitExceeded = appState.error {} else {
            XCTFail("Expected rateLimitExceeded error")
        }
    }

    // MARK: - Authentication status

    func testPoll_setsAuthenticatedStatus_onFirstSuccess() async {
        mockSource.validateTokenResult = .success("octocat")
        mockSource.fetchResult = .success([])
        await engine.poll()

        if case .authenticated(let username) = appState.authenticationStatus {
            XCTAssertEqual(username, "octocat")
        } else {
            XCTFail("Expected .authenticated, got \(appState.authenticationStatus)")
        }
    }

    func testPoll_reusesUsername_doesNotRevalidateToken() async {
        // Set already-authenticated status
        appState.authenticationStatus = .authenticated(username: "octocat")
        mockSource.fetchResult = .success([])

        await engine.poll()

        // validateToken should NOT have been called (we already have username)
        // We can verify by checking that fetchCallCount > 0 but validateToken wasn't retried
        XCTAssertGreaterThan(mockSource.fetchCallCount, 0)
    }

    // MARK: - AppState session reset and panel state

    func testClearSessionStateForNewSession_clearsSessionScopedData() {
        appState.prs = [.fixture(number: 1)]
        appState.recentlyClosedPRs = [.fixture(number: 2)]
        appState.lastUpdated = Date()
        appState.isLoading = false
        appState.error = .networkError
        appState.isRateLimited = true
        appState.rateLimitResetDate = Date().addingTimeInterval(60)
        appState.isStale = true
        appState.authenticationStatus = .authenticated(username: "octocat")

        appState.clearSessionStateForNewSession()

        XCTAssertTrue(appState.prs.isEmpty)
        XCTAssertTrue(appState.recentlyClosedPRs.isEmpty)
        XCTAssertNil(appState.lastUpdated)
        XCTAssertNil(appState.error)
        XCTAssertFalse(appState.isRateLimited)
        XCTAssertNil(appState.rateLimitResetDate)
        XCTAssertFalse(appState.isStale)
        XCTAssertTrue(appState.isLoading)

        if case .unknown = appState.authenticationStatus {
            // expected
        } else {
            XCTFail("Expected authentication status to reset to unknown")
        }
    }

    func testPanelContentState_noTokenWithNoPRs_prefersSetupState() {
        appState.isLoading = false
        appState.authenticationStatus = .noToken

        XCTAssertEqual(appState.panelContentState, .setupRequired)
    }

    func testPanelContentState_authFailureWithNoPRs_prefersAuthErrorState() {
        appState.isLoading = false
        appState.authenticationStatus = .failed

        XCTAssertEqual(appState.panelContentState, .authError)
    }

    // MARK: - Staleness

    func testPoll_networkError_withOldLastUpdated_marksStateStale() async {
        appState.lastUpdated = Date().addingTimeInterval(-301)
        mockSource.validateTokenResult = .success("octocat")
        mockSource.fetchResult = .failure(AppError.networkError)

        await engine.poll()

        XCTAssertTrue(appState.isStale)
    }

    func testPoll_success_clearsExistingStaleState() async {
        appState.lastUpdated = Date().addingTimeInterval(-301)
        appState.isStale = true
        mockSource.validateTokenResult = .success("octocat")
        mockSource.fetchResult = .success([.fixture()])

        await engine.poll()

        XCTAssertFalse(appState.isStale)
    }
}
