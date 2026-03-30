import Foundation

actor GitHubRESTClient: GitHubDataSource {
    private let token: String
    private let session: URLSession
    private var etags: [URL: String] = [:]
    private var cachedResponses: [URL: Data] = [:]

    // Track both rate limit buckets independently
    private var coreRateLimitRemaining = 5000
    private var searchRateLimitRemaining = 30
    private var coreRateLimitResetDate = Date()
    private var searchRateLimitResetDate = Date()

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - GitHubDataSource

    func validateToken() async throws -> String {
        let data = try await get("/user")
        let user = try decode(GitHubUser.self, from: data)
        return user.login
    }

    func validateTokenForAppAccess() async throws -> String {
        let username = try await validateToken()
        _ = try await searchOpenPRs(username: username, perPage: 1)
        return username
    }

    func fetchAllPRStates(username: String) async throws -> [PRState] {
        let searchItems = try await searchOpenPRs(username: username)
        return try await withThrowingTaskGroup(of: PRState?.self) { group in
            for item in searchItems {
                group.addTask { [self] in
                    try await buildPRState(from: item, username: username)
                }
            }
            var results: [PRState] = []
            for try await state in group {
                if let state { results.append(state) }
            }
            return results
        }
    }

    func resolveDisappearedPRs(_ prs: [PRState]) async -> [PRState] {
        guard !prs.isEmpty else { return [] }

        return await withTaskGroup(of: PRState?.self) { group in
            for pr in prs {
                group.addTask { [self] in
                    await confirmedClosedPR(pr)
                }
            }

            var confirmedClosed: [PRState] = []
            for await pr in group {
                if let pr {
                    confirmedClosed.append(pr)
                }
            }
            return confirmedClosed
        }
    }

    // MARK: - Search

    private func searchOpenPRs(username: String, perPage: Int = 100) async throws -> [SearchItem] {
        var allItems: [SearchItem] = []
        var page = 1

        while true {
            let query = "is:pr is:open involves:\(username)"
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw AppError.networkError
            }
            let path = "/search/issues?q=\(encoded)&per_page=\(perPage)&page=\(page)&sort=updated&order=desc"
            let data = try await get(path, rateLimit: .search)
            let response = try decode(SearchResponse.self, from: data)
            if response.incompleteResults {
                throw AppError.incompleteSearchResults
            }

            allItems.append(contentsOf: response.items)
            if allItems.count >= response.totalCount || response.items.count < perPage { break }
            page += 1
        }

        return allItems
    }

    // MARK: - PR state building

    private func buildPRState(from item: SearchItem, username: String) async throws -> PRState? {
        guard let repoFullName = extractRepoName(from: item.repositoryUrl),
            let (owner, repo) = splitRepoFullName(repoFullName)
        else { return nil }
        let number = item.number

        // Fetch PR detail, reviews, and check runs concurrently
        async let detailTask = fetchPRDetail(owner: owner, repo: repo, number: number)
        async let reviewsTask = fetchReviews(owner: owner, repo: repo, number: number)
        let (detail, reviews) = try await (detailTask, reviewsTask)

        async let checkRunsTask = fetchCheckRuns(owner: owner, repo: repo, sha: detail.head.sha)
        async let commitStatusesTask = fetchCommitStatuses(owner: owner, repo: repo, sha: detail.head.sha)
        let (checkRuns, commitStatuses) = try await (checkRunsTask, commitStatusesTask)

        let assignment = PRState.Assignment(
            createdByMe: detail.user.login == username,
            reviewRequestedFromMe: detail.requestedReviewers.contains { $0.login == username },
            assignedToMe: detail.assignees.contains { $0.login == username }
        )

        let updatedAt = Self.parseGitHubDate(item.updatedAt) ?? Date()

        guard let prURL = URL(string: item.htmlUrl) else { return nil }

        return PRState(
            number: number,
            title: item.title,
            repoFullName: repoFullName,
            url: prURL,
            headSHA: detail.head.sha,
            draftStatus: item.draft == true ? .draft : .ready,
            ciStatus: buildCIStatus(
                from: checkRuns,
                commitStatuses: commitStatuses.statuses,
                combinedStatusState: commitStatuses.state
            ),
            reviewStatus: buildReviewStatus(reviews: reviews, requestedReviewers: detail.requestedReviewers),
            mergeStatus: buildMergeStatus(from: detail.mergeableState),
            assignment: assignment,
            updatedAt: updatedAt
        )
    }

    private func fetchPRDetail(
        owner: String,
        repo: String,
        number: Int,
        retryForMergeability: Bool = true
    ) async throws -> PRDetail {
        let data = try await get("/repos/\(owner)/\(repo)/pulls/\(number)")
        var detail = try decode(PRDetail.self, from: data)

        // GitHub's mergeable field may be null while being computed — retry once after a delay
        if retryForMergeability, detail.mergeableState == nil {
            try await Task.sleep(nanoseconds: 2_500_000_000)
            let retryData = try await get("/repos/\(owner)/\(repo)/pulls/\(number)")
            detail = try decode(PRDetail.self, from: retryData)
        }
        return detail
    }

    private func fetchReviews(owner: String, repo: String, number: Int) async throws -> [Review] {
        let perPage = 100
        var page = 1
        var reviews: [Review] = []

        while true {
            let data = try await get("/repos/\(owner)/\(repo)/pulls/\(number)/reviews?per_page=\(perPage)&page=\(page)")
            let pageReviews = try decode([Review].self, from: data)
            reviews.append(contentsOf: pageReviews)

            if pageReviews.count < perPage {
                return reviews
            }

            page += 1
        }
    }

    private func fetchCheckRuns(owner: String, repo: String, sha: String) async throws -> [CheckRun] {
        let data = try await get("/repos/\(owner)/\(repo)/commits/\(sha)/check-runs?per_page=100")
        let response = try decode(CheckRunsResponse.self, from: data)
        return response.checkRuns
    }

    private func fetchCommitStatuses(owner: String, repo: String, sha: String) async throws -> CombinedStatusResponse {
        let data = try await get("/repos/\(owner)/\(repo)/commits/\(sha)/status")
        return try decode(CombinedStatusResponse.self, from: data)
    }

    private func confirmedClosedPR(_ pr: PRState) async -> PRState? {
        guard let (owner, repo) = splitRepoFullName(pr.repoFullName) else {
            return nil
        }

        do {
            let detail = try await fetchPRDetail(
                owner: owner,
                repo: repo,
                number: pr.number,
                retryForMergeability: false
            )
            return detail.state == "closed" ? pr : nil
        } catch {
            return nil
        }
    }

    // MARK: - State builders

    private func buildCIStatus(
        from checkRuns: [CheckRun],
        commitStatuses: [CommitStatus],
        combinedStatusState: String
    ) -> PRState.CIStatus {
        let latestStatuses = deduplicatedCommitStatuses(commitStatuses)
        let totalChecks = checkRuns.count + latestStatuses.count
        guard totalChecks > 0 else { return .none }

        let hasPending = checkRuns.contains { $0.status != "completed" }
        let hasPendingCommitStatus =
            combinedStatusState == "pending" || latestStatuses.contains { $0.state == "pending" }
        if hasPending || hasPendingCommitStatus { return .pending }

        let failingCheckRuns = checkRuns.filter { run in
            run.status == "completed" && run.conclusion != "success" && run.conclusion != "skipped"
                && run.conclusion != "neutral"
        }
        let failingCommitStatuses = latestStatuses.filter { ["error", "failure"].contains($0.state) }

        let failingNames = failingCheckRuns.map(\.name) + failingCommitStatuses.map(\.context)
        if failingNames.isEmpty { return .passing }
        return .failing(failingCheckNames: failingNames, totalChecks: totalChecks)
    }

    private func buildReviewStatus(reviews: [Review], requestedReviewers: [GitHubUser]) -> PRState.ReviewStatus {
        // Latest review per reviewer (ignoring comment-only reviews)
        var latestByReviewer: [String: Review] = [:]
        for review in reviews where review.state != "COMMENTED" && review.state != "DISMISSED" {
            latestByReviewer[review.user.login] = review
        }

        let states = latestByReviewer.values.map(\.state)

        if states.contains("CHANGES_REQUESTED") {
            let who = latestByReviewer.values
                .filter { $0.state == "CHANGES_REQUESTED" }
                .map(\.user.login)
            return .changesRequested(by: who)
        }

        if !requestedReviewers.isEmpty {
            // Outstanding review requests should keep the PR in a "waiting for review"
            // state even if it already has older approvals.
            return .requested(by: requestedReviewers.map(\.login))
        }

        if states.contains("APPROVED") {
            let who = latestByReviewer.values
                .filter { $0.state == "APPROVED" }
                .map(\.user.login)
            return .approved(by: who)
        }

        return .none
    }

    private func buildMergeStatus(from mergeableState: String?) -> PRState.MergeStatus {
        switch mergeableState {
        case "clean": return .ready
        case "dirty": return .conflicts
        case "blocked": return .blocked
        case "unstable": return .ready  // mergeable despite failing checks; CI tracked separately
        default: return .pending  // "unknown", nil, or any future undocumented value
        }
    }

    private func deduplicatedCommitStatuses(_ statuses: [CommitStatus]) -> [CommitStatus] {
        var seenContexts = Set<String>()
        var latestStatuses: [CommitStatus] = []

        for status in statuses {
            guard seenContexts.insert(status.context).inserted else { continue }
            latestStatuses.append(status)
        }

        return latestStatuses
    }

    // MARK: - HTTP

    private enum RateLimitBucket { case core, search }

    private func get(
        _ path: String,
        rateLimit: RateLimitBucket = .core,
        allowRetryWithoutETag: Bool = true
    ) async throws -> Data {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw AppError.networkError
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        if let etag = etags[url] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw AppError.networkError }

        updateRateLimits(from: http, bucket: rateLimit)

        switch http.statusCode {
        case 200:
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                etags[url] = etag
                cachedResponses[url] = data
            }
            return data
        case 304:
            if let cached = cachedResponses[url] { return cached }
            guard allowRetryWithoutETag else { throw AppError.networkError }

            let previousETag = etags.removeValue(forKey: url)
            do {
                return try await get(path, rateLimit: rateLimit, allowRetryWithoutETag: false)
            } catch {
                if let previousETag, etags[url] == nil {
                    etags[url] = previousETag
                }
                throw error
            }
        case 401:
            throw AppError.authError
        case 403:
            if isRateLimitedResponse(data, http) {
                throw AppError.rateLimitExceeded(resetAt: rateLimitResetDate(from: http))
            }
            throw AppError.authError
        case 429:
            let resetAt = rateLimitResetDate(from: http)
            throw AppError.rateLimitExceeded(resetAt: resetAt)
        case 500...599:
            throw AppError.serverError(statusCode: http.statusCode)
        default:
            throw AppError.networkError
        }
    }

    private func updateRateLimits(from response: HTTPURLResponse, bucket: RateLimitBucket) {
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
            switch bucket {
            case .core: coreRateLimitRemaining = remaining
            case .search: searchRateLimitRemaining = remaining
            }
        }
        if let resetTS = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
            let resetDate = Date(timeIntervalSince1970: resetTS)
            switch bucket {
            case .core: coreRateLimitResetDate = resetDate
            case .search: searchRateLimitResetDate = resetDate
            }
        }
    }

    private func rateLimitResetDate(from response: HTTPURLResponse) -> Date {
        if let ts = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: ts)
        }
        return Date().addingTimeInterval(60)
    }

    private func isRateLimitedResponse(_ data: Data, _ response: HTTPURLResponse) -> Bool {
        if response.value(forHTTPHeaderField: "Retry-After") != nil {
            return true
        }

        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            return true
        }

        guard let apiError = try? decode(APIErrorResponse.self, from: data) else {
            return false
        }

        return apiError.message.localizedCaseInsensitiveContains("rate limit")
    }

    private func extractRepoName(from repositoryURL: String) -> String? {
        guard let url = URL(string: repositoryURL) else { return nil }
        let components = url.pathComponents
        // pathComponents: ["/", "repos", "owner", "repo"]
        guard let reposIdx = components.firstIndex(of: "repos"),
            reposIdx + 2 < components.count
        else { return nil }
        return "\(components[reposIdx + 1])/\(components[reposIdx + 2])"
    }

    private func splitRepoFullName(_ repoFullName: String) -> (String, String)? {
        let parts = repoFullName.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseGitHubDate(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? internetDateFormatter.date(from: value)
    }

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try Self.jsonDecoder.decode(type, from: data)
    }

    // MARK: - API response models

    private struct APIErrorResponse: Codable, Sendable {
        let message: String
    }

    private struct GitHubUser: Codable, Sendable {
        let login: String
    }

    private struct SearchResponse: Codable, Sendable {
        let totalCount: Int
        let incompleteResults: Bool
        let items: [SearchItem]
    }

    private struct SearchItem: Codable, Sendable {
        let number: Int
        let title: String
        let htmlUrl: String
        let draft: Bool?
        let updatedAt: String
        let repositoryUrl: String
    }

    private struct PRDetail: Codable, Sendable {
        let head: Head
        let state: String
        let user: GitHubUser
        let assignees: [GitHubUser]
        let requestedReviewers: [GitHubUser]
        let mergeableState: String?

        struct Head: Codable, Sendable {
            let sha: String
        }
    }

    private struct Review: Codable, Sendable {
        let user: GitHubUser
        let state: String
    }

    private struct CheckRunsResponse: Codable, Sendable {
        let checkRuns: [CheckRun]
    }

    private struct CheckRun: Codable, Sendable {
        let name: String
        let status: String
        let conclusion: String?
    }

    private struct CombinedStatusResponse: Codable, Sendable {
        let state: String
        let statuses: [CommitStatus]
    }

    private struct CommitStatus: Codable, Sendable {
        let context: String
        let state: String
    }
}
