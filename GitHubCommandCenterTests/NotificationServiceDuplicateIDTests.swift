import Testing

@testable import GitHubCommandCenter

@Suite
struct NotificationServiceDuplicateIDTests {
    @Test
    func prsByID_duplicateIDs_keepLastValue() {
        let earlier = PRState.fixture(ciStatus: .passing, createdByMe: true)
        let later = PRState.fixture(
            ciStatus: .failing(checks: [.init(name: "ci", conclusion: "failure", url: nil)], totalChecks: 1),
            createdByMe: true
        )

        let prsByID = NotificationService.prsByID([earlier, later])

        #expect(prsByID.count == 1)
        #expect(prsByID[earlier.id]?.ciStatus == later.ciStatus)
    }
}
