import Testing

@testable import GitHubCommandCenter

@Suite
struct NotificationServiceTests {
    private enum MockDeliveryError: Error, Equatable {
        case failed
    }

    private final class Harness {
        let service = NotificationService()
        var fired: [(String, String)] = []

        init() {
            service.notificationHandler = { [weak self] title, body in
                self?.fired.append((title, body))
            }
        }
    }

    @Test
    func notification_ciPassingToFailing_yourPR_fires() throws {
        let harness = Harness()
        let old = PRState.fixture(ciStatus: .passing, createdByMe: true)
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "unit-tests", conclusion: "failure", url: nil)], totalChecks: 3),
            createdByMe: true
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        try #require(harness.fired.count == 1)
        #expect(harness.fired[0].1.contains("unit-tests"))
    }

    @Test
    func notification_ciPassingToFailing_notYourPR_silent() {
        let harness = Harness()
        let old = PRState.fixture(ciStatus: .passing, createdByMe: false)
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: false
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_ciNoneToFailing_yourPR_fires() {
        let harness = Harness()
        let old = PRState.fixture(ciStatus: .none, createdByMe: true)
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "lint", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.count == 1)
    }

    @Test
    func notification_ciPendingToFailing_yourPR_fires() throws {
        let harness = Harness()
        let old = PRState.fixture(ciStatus: .pending, createdByMe: true)
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "build", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        try #require(harness.fired.count == 1)
        #expect(harness.fired[0].1.contains("build"))
    }

    @Test
    func notification_ciFailingToFailing_noRepeat() {
        let harness = Harness()
        let old = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_changesRequested_yourPR_fires() throws {
        let harness = Harness()
        let old = PRState.fixture(reviewStatus: .none, createdByMe: true)
        let new = PRState.fixture(
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        try #require(harness.fired.count == 1)
        #expect(harness.fired[0].1.contains("@alice"))
    }

    @Test
    func notification_changesRequested_alreadySet_noRepeat() {
        let harness = Harness()
        let old = PRState.fixture(reviewStatus: .changesRequested(by: ["alice"]), createdByMe: true)
        let new = PRState.fixture(reviewStatus: .changesRequested(by: ["alice"]), createdByMe: true)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_approved_yourPR_fires() throws {
        let harness = Harness()
        let old = PRState.fixture(reviewStatus: .requested(by: ["alice"]), createdByMe: true)
        let new = PRState.fixture(reviewStatus: .approved(by: ["alice"]), createdByMe: true)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        try #require(harness.fired.count == 1)
        #expect(harness.fired[0].1.contains("@alice"))
    }

    @Test
    func notification_approved_notYourPR_silent() {
        let harness = Harness()
        let old = PRState.fixture(reviewStatus: .requested(by: ["alice"]), createdByMe: false)
        let new = PRState.fixture(reviewStatus: .approved(by: ["alice"]), createdByMe: false)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_reviewRequestedFromMe_newRequest_fires() {
        let harness = Harness()
        let old = PRState.fixture(reviewRequestedFromMe: false)
        let new = PRState.fixture(reviewRequestedFromMe: true)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.count == 1)
    }

    @Test
    func notification_reviewRequestedFromMe_alreadyRequested_noRepeat() {
        let harness = Harness()
        let old = PRState.fixture(reviewRequestedFromMe: true)
        let new = PRState.fixture(reviewRequestedFromMe: true)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_mergeConflictsAppear_yourPR_fires() {
        let harness = Harness()
        let old = PRState.fixture(mergeStatus: .ready, createdByMe: true)
        let new = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.count == 1)
    }

    @Test
    func notification_mergeConflictsAlreadyPresent_noRepeat() {
        let harness = Harness()
        let old = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)
        let new = PRState.fixture(mergeStatus: .conflicts, createdByMe: true)

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_disappearedPR_createdByMe_fires() throws {
        let harness = Harness()
        let disappeared = PRState.fixture(number: 99, title: "Old PR", createdByMe: true)

        harness.service.checkTransitions(from: [disappeared], to: [], disappeared: [disappeared])

        try #require(harness.fired.count == 1)
        #expect(harness.fired[0].0.contains("99"))
    }

    @Test
    func notification_disappearedPR_notCreatedByMe_isSilent() {
        let harness = Harness()
        let disappeared = PRState.fixture(number: 99, title: "Old PR", createdByMe: false)

        harness.service.checkTransitions(from: [disappeared], to: [], disappeared: [disappeared])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_disappearedMultiplePRs_firesForEachCreatedByMePR() {
        let harness = Harness()
        let prs = [
            PRState.fixture(number: 1, createdByMe: true),
            PRState.fixture(number: 2, createdByMe: false),
            PRState.fixture(number: 3, createdByMe: true),
        ]

        harness.service.checkTransitions(from: prs, to: [], disappeared: prs)

        #expect(harness.fired.count == 2)
    }

    @Test
    func notification_newPRWithoutBaseline_isSilent() {
        let harness = Harness()
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 1),
            reviewStatus: .changesRequested(by: ["alice"]),
            createdByMe: true
        )

        harness.service.checkTransitions(from: [], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_ciPendingToFailing_notYourPR_silent() {
        let harness = Harness()
        let old = PRState.fixture(ciStatus: .pending, createdByMe: false)
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "build", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: false
        )

        harness.service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(harness.fired.isEmpty)
    }

    @Test
    func notification_deliveryFailure_surfacesError() {
        let service = NotificationService()
        var capturedError: MockDeliveryError?
        service.notificationScheduler = { _, completion in
            completion(MockDeliveryError.failed)
        }
        service.notificationDeliveryErrorHandler = { error in
            capturedError = error as? MockDeliveryError
        }

        let old = PRState.fixture(ciStatus: .passing, createdByMe: true)
        let new = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "unit-tests", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )

        service.checkTransitions(from: [old], to: [new], disappeared: [])

        #expect(capturedError == .failed)
    }
}
