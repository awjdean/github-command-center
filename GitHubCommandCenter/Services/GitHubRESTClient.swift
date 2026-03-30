import Foundation

final class GitHubRESTClient: GitHubDataSource {
    private let token: String
    private let session: URLSession
    private var etags: [URL: String] = [:]
    private var cachedResponses: [URL: Data] = [:]

    // Track both rate limit buckets independently
    private var coreRateLimitRemaining = 5000
    private var searchRateLimitRemaining = 30
    private var coreRateLimitResetDate = Date()

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

    func fetchAllPRStates(username: String) async throws -> [PRState] {
        let searchItems = try await searchOpenPRs(username: username)
        return try await withThrowingTaskGroup(of: PRState?.self) { group in
            for item in searchItems {
                group.addTask { try await self.buildPRState(from: item, username: username) }
            }
            var results: [PRState] = []
            for try await state in group {
                if let state { results.append(state) }
            }
            return results
        }
    }

    // MARK: - Search

    private func searchOpenPRs(username: String) async throws -> [SearchItem] {
        var allItems: [SearchItem] = []
        var page = 1
        let perPage = 100

        while true {
            let q = "is:pr is:open involves:\(username)"
            guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw AppError.networkError
            }
            let path = "/search/issues?q=\(encoded)&per_page=\(perPage)&page=\(page)&sort=updated&order=desc"
            let data = try await get(path, rateLimit: .search)
            let response = try decode(SearchResponse.self, from: data)

            allItems.append(contentsOf: response.items)
            if allItems.count >= response.totalCount || response.items.count < perPage { break }
            page += 1
        }

        return allItems
    }

    // MARK: - PR state building

    private func buildPRState(from item: SearchItem, username: String) async throws -> PRState? {
        guard let repoFullName = extractRepoName(from: item.repositoryUrl) else { return nil }
        let parts = repoFullName.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let owner = String(parts[0])
        let repo = String(parts[1])
        let number = item.number

        // Fetch PR detail, reviews, and check runs concurrently
        async let detailTask = fetchPRDetail(owner: owner, repo: repo, number: number)
        async let reviewsTask = fetchReviews(owner: owner, repo: repo, number: number)
        let (detail, reviews) = try await (detailTask, reviewsTask)

        let checkRuns = try await fetchCheckRuns(owner: owner, repo: repo, sha: detail.head.sha)

        let assignment = PRState.Assignment(
            createdByMe: detail.user.login == username,
            reviewRequestedFromMe: detail.requestedReviewers.contains { $0.login == username },
            assignedToMe: detail.assignees.contains { $0.login == username }
        )

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAt = iso.date(from: item.updatedAt) ?? Date()

        guard let prURL = URL(string: item.htmlUrl) else { return nil }

        return PRState(
            id: number,
            number: number,
            title: item.title,
            repoFullName: repoFullName,
            url: prURL,
            headSHA: detail.head.sha,
            draftStatus: item.draft == true ? .draft : .ready,
            ciStatus: buildCIStatus(from: checkRuns),
            reviewStatus: buildReviewStatus(reviews: reviews, requestedReviewers: detail.requestedReviewers),
            mergeStatus: buildMergeStatus(from: detail.mergeableState),
            assignment: assignment,
            updatedAt: updatedAt
        )
    }

    private func fetchPRDetail(owner: String, repo: String, number: Int) async throws -> PRDetail {
        let data = try await get("/repos/\(owner)/\(repo)/pulls/\(number)")
        var detail = try decode(PRDetail.self, from: data)

        // GitHub's mergeable field may be null while being computed — retry once after a delay
        if detail.mergeableState == nil {
            try await Task.sleep(nanoseconds: 2_500_000_000)
            let retryData = try await get("/repos/\(owner)/\(repo)/pulls/\(number)")
            detail = try decode(PRDetail.self, from: retryData)
        }
        return detail
    }

    private func fetchReviews(owner: String, repo: String, number: Int) async throws -> [Review] {
        let data = try await get("/repos/\(owner)/\(repo)/pulls/\(number)/reviews")
        return try decode([Review].self, from: data)
    }

    private func fetchCheckRuns(owner: String, repo: String, sha: String) async throws -> [CheckRun] {
        let data = try await get("/repos/\(owner)/\(repo)/commits/\(sha)/check-runs?per_page=100")
        let response = try decode(CheckRunsResponse.self, from: data)
        return response.checkRuns
    }

    // MARK: - State builders

    private func buildCIStatus(from checkRuns: [CheckRun]) -> PRState.CIStatus {
        guard !checkRuns.isEmpty else { return .none }

        let hasPending = checkRuns.contains { $0.status != "completed" }
        if hasPending { return .pending }

        let failing = checkRuns.filter { run in
            run.status == "completed" &&
            run.conclusion != "success" &&
            run.conclusion != "skipped" &&
            run.conclusion != "neutral"
        }

        if failing.isEmpty { return .passing }
        return .failing(failingCheckNames: failing.map(\.name), totalChecks: checkRuns.count)
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

        if states.contains("APPROVED") {
            let who = latestByReviewer.values
                .filter { $0.state == "APPROVED" }
                .map(\.user.login)
            return .approved(by: who)
        }

        if !requestedReviewers.isEmpty {
            return .requested(by: requestedReviewers.map(\.login))
        }

        return .none
    }

    private func buildMergeStatus(from mergeableState: String?) -> PRState.MergeStatus {
        switch mergeableState {
        case "clean":    return .ready
        case "dirty":    return .conflicts
        case "blocked":  return .blocked
        case "unstable": return .ready   // mergeable despite failing checks; CI tracked separately
        default:         return .pending // "unknown", nil, or any future undocumented value
        }
    }

    // MARK: - HTTP

    private enum RateLimitBucket { case core, search }

    private func get(_ path: String, rateLimit: RateLimitBucket = .core) async throws -> Data {
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
            throw AppError.networkError
        case 401, 403:
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
            case .core:   coreRateLimitRemaining = remaining
            case .search: searchRateLimitRemaining = remaining
            }
        }
        if let resetTS = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
            coreRateLimitResetDate = Date(timeIntervalSince1970: resetTS)
        }
    }

    private func rateLimitResetDate(from response: HTTPURLResponse) -> Date {
        if let ts = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: ts)
        }
        return Date().addingTimeInterval(60)
    }

    private func extractRepoName(from repositoryURL: String) -> String? {
        guard let url = URL(string: repositoryURL) else { return nil }
        let components = url.pathComponents
        // pathComponents: ["/", "repos", "owner", "repo"]
        guard let reposIdx = components.firstIndex(of: "repos"),
              reposIdx + 2 < components.count else { return nil }
        return "\(components[reposIdx + 1])/\(components[reposIdx + 2])"
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    // MARK: - API response models

    private struct GitHubUser: Codable {
        let login: String
    }

    private struct SearchResponse: Codable {
        let totalCount: Int
        let items: [SearchItem]
    }

    private struct SearchItem: Codable {
        let number: Int
        let title: String
        let htmlUrl: String
        let draft: Bool?
        let updatedAt: String
        let repositoryUrl: String
    }

    private struct PRDetail: Codable {
        let head: Head
        let user: GitHubUser
        let assignees: [GitHubUser]
        let requestedReviewers: [GitHubUser]
        let mergeableState: String?

        struct Head: Codable {
            let sha: String
        }
    }

    private struct Review: Codable {
        let user: GitHubUser
        let state: String
    }

    private struct CheckRunsResponse: Codable {
        let checkRuns: [CheckRun]
    }

    private struct CheckRun: Codable {
        let name: String
        let status: String
        let conclusion: String?
    }
}
