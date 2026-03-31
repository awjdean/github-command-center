import Testing

@testable import GitHubCommandCenter

@Suite
struct PRRowPresentationTests {
    @Test
    func accessibilityLabel_includesStatusSummary() {
        let pr = PRState.fixture(
            number: 17,
            title: "Improve sync",
            repoFullName: "owner/repo",
            ciStatus: .failing(checks: [.init(name: "test", conclusion: "failure", url: nil)], totalChecks: 3),
            reviewStatus: .changesRequested(by: ["alice"]),
            mergeStatus: .behind
        )

        let label = PRRowPresentation.accessibilityLabel(for: pr)

        #expect(label.contains("PR 17"))
        #expect(label.contains("Improve sync"))
        #expect(label.contains("owner/repo"))
        #expect(label.contains("CI failing"))
        #expect(label.contains("review changes requested"))
        #expect(label.contains("branch behind"))
    }

    @Test
    func openFailureMessage_includesPullRequestContext() {
        let pr = PRState.fixture(number: 42, repoFullName: "owner/repo")

        let message = PRRowPresentation.openFailureMessage(for: pr)

        #expect(message.contains("#42"))
        #expect(message.contains(pr.url.absoluteString))
    }
}
