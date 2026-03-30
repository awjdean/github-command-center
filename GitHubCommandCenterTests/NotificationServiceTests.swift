import XCTest
@testable import GitHubCommandCenter

final class NotificationServiceTests: XCTestCase {
    var service: NotificationService!
    var fired: [(String, String)] = []  // (title, body)

    override func setUp() {
        service = NotificationService()
        fired = []
        service.notificationHandler = { [weak self] title, body in
            self?.fired.append((title, body))
        }
    }

    // MARK: - CI transitions

    func testNotification_ciPassingToFailing_yourPR_fires() {
        let old = PRState.fixture(ciStatus: .passing, createdByMe: true)
        let new = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["unit-tests"], totalChecks: 3),
            createdByMe: true
        )
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(fired[0].1.contains("unit-tests"))
    }

    func testNotification_ciPassingToFailing_notYourPR_silent() {
        let old = PRState.fixture(ciStatus: .passing, createdByMe: false)
        let new = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            createdByMe: false
        )
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    func testNotification_ciNoneToFailing_yourPR_fires() {
        let old = PRState.fixture(ciStatus: .none, createdByMe: true)
        let new = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["lint"], totalChecks: 1),
            createdByMe: true
        )
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 1)
    }

    func testNotification_ciFailingToFailing_noRepeat() {
        // Already failing — no new notification
        let old = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            createdByMe: true
        )
        let new = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            createdByMe: true
        )
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    // MARK: - Review transitions

    func testNotification_changesRequested_yourPR_fires() {
        let old = PRState.fixture(reviewStatus: .none, createdByMe: true)
        let new = PRState.fixture(
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(fired[0].1.contains("@alice"))
    }

    func testNotification_changesRequested_alreadySet_noRepeat() {
        let old = PRState.fixture(reviewStatus: .changesRequested(by: ["alice"]), createdByMe: true)
        let new = PRState.fixture(reviewStatus: .changesRequested(by: ["alice"]), createdByMe: true)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    func testNotification_approved_yourPR_fires() {
        let old = PRState.fixture(reviewStatus: .requested(by: ["alice"]), createdByMe: true)
        let new = PRState.fixture(reviewStatus: .approved(by: ["alice"]), createdByMe: true)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(fired[0].1.contains("@alice"))
    }

    func testNotification_approved_notYourPR_silent() {
        let old = PRState.fixture(reviewStatus: .requested(by: ["alice"]), createdByMe: false)
        let new = PRState.fixture(reviewStatus: .approved(by: ["alice"]), createdByMe: false)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    // MARK: - Review requested from you

    func testNotification_reviewRequestedFromMe_newRequest_fires() {
        let old = PRState.fixture(reviewRequestedFromMe: false)
        let new = PRState.fixture(reviewRequestedFromMe: true)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 1)
    }

    func testNotification_reviewRequestedFromMe_alreadyRequested_noRepeat() {
        let old = PRState.fixture(reviewRequestedFromMe: true)
        let new = PRState.fixture(reviewRequestedFromMe: true)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    // MARK: - Merge conflicts

    func testNotification_mergeConflictsAppear_yourPR_fires() {
        let old = PRState.fixture(mergeStatus: .ready, createdByMe: true)
        let new = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 1)
    }

    func testNotification_mergeConflictsAlreadyPresent_noRepeat() {
        let old = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)
        let new = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    // MARK: - Disappeared PRs

    func testNotification_disappearedPR_fires() {
        let disappeared = PRState.fixture(number: 99, title: "Old PR")
        service.checkTransitions(from: [disappeared], to: [], disappeared: [disappeared])
        XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(fired[0].0.contains("99"))
    }

    func testNotification_disappearedMultiplePRs_firesForEach() {
        let prs = [PRState.fixture(number: 1), PRState.fixture(number: 2)]
        service.checkTransitions(from: prs, to: [], disappeared: prs)
        XCTAssertEqual(fired.count, 2)
    }

    // MARK: - New PR in current poll (no old state)

    func testNotification_newPR_noOldEntry_silent() {
        // No prior state → no baseline → no notifications
        let new = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["test"], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )
        service.checkTransitions(from: [], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }

    // MARK: - Silent transitions

    func testNotification_ciPendingToFailing_notYourPR_silent() {
        let old = PRState.fixture(ciStatus: .pending, createdByMe: false)
        let new = PRState.fixture(
            ciStatus: .failing(failingCheckNames: ["build"], totalChecks: 1),
            createdByMe: false
        )
        service.checkTransitions(from: [old], to: [new], disappeared: [])
        XCTAssertEqual(fired.count, 0)
    }
}
