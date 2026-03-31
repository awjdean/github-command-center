import Foundation
import OSLog

// swiftlint:disable file_length type_body_length

actor GitHubRESTClient: GitHubDataSource {
    private static let searchResultCap = 1_000
    private static let searchResultsMaxPageLimit = 100
    private static let reviewMaxPageLimit = 10
    private static let checkRunsMaxPageLimit = 10
    private static let logger = Logger(subsystem: Log.subsystem, category: "GitHubRESTClient")
    private static let searchCapWarningMessage =
        "Showing the first 1,000 matching pull requests due to GitHub search limits."
    private static let incompleteSearchWarningMessage =
        "GitHub search results are temporarily incomplete. "
        + "The token was saved, but full PR status access could not be verified yet."
    private static let deferredValidationWarningMessage =
        "Token saved, but full PR status access could not be verified yet. "
        + "The warning will clear after a successful poll loads PR status data."

    enum TokenValidationResult: Equatable, Sendable {
        case verified(username: String)
        case warning(username: String, message: String)
    }

    private enum RequestError: Error {
        case app(AppError)
        case statusCode(Int)
    }

    private struct CachedResponseEntry {
        let data: Data
        let etag: String
    }

    private struct SearchItemsResult {
        let items: [SearchItem]
        let warningMessage: String?
    }

    private struct LRUCache<Key: Hashable, Value> {
        private final class Node {
            let key: Key
            weak var previous: Node?
            var next: Node?

            init(key: Key) {
                self.key = key
            }
        }

        private var values: [Key: Value] = [:]
        private var nodes: [Key: Node] = [:]
        private var head: Node?
        private var tail: Node?

        var count: Int {
            values.count
        }

        subscript(key: Key) -> Value? {
            mutating get {
                guard let value = values[key] else { return nil }
                touch(key)
                return value
            }
            set {
                switch newValue {
                case .some(let value):
                    values[key] = value
                    touch(key)
                case .none:
                    _ = removeValue(forKey: key)
                }
            }
        }

        @discardableResult
        mutating func removeValue(forKey key: Key) -> Value? {
            guard let value = values.removeValue(forKey: key) else { return nil }
            if let node = nodes.removeValue(forKey: key) {
                remove(node)
            }
            return value
        }

        mutating func trim(to maxEntries: Int) {
            guard maxEntries >= 0 else { return }
            while values.count > maxEntries, let oldestKey = head?.key {
                _ = removeValue(forKey: oldestKey)
            }
        }

        private mutating func touch(_ key: Key) {
            if let node = nodes[key] {
                moveToTail(node)
                return
            }

            let node = Node(key: key)
            nodes[key] = node
            append(node)
        }

        private mutating func append(_ node: Node) {
            node.previous = tail
            node.next = nil

            if let tail {
                tail.next = node
            } else {
                head = node
            }

            tail = node
        }

        private mutating func moveToTail(_ node: Node) {
            guard tail !== node else { return }
            remove(node)
            append(node)
        }

        private mutating func remove(_ node: Node) {
            let previous = node.previous
            let next = node.next

            previous?.next = next
            next?.previous = previous

            if head === node {
                head = next
            }

            if tail === node {
                tail = previous
            }

            node.previous = nil
            node.next = nil
        }
    }

    private let token: String
    private let session: URLSession
    private let mergeabilityRetryDelayNanoseconds: UInt64
    private let maxCacheEntries: Int
    private var responseCache = LRUCache<URL, CachedResponseEntry>()

    init(
        token: String,
        session: URLSession = .shared,
        mergeabilityRetryDelayNanoseconds: UInt64 = 2_500_000_000,
        maxCacheEntries: Int = 500
    ) {
        self.token = token
        self.session = session
        self.mergeabilityRetryDelayNanoseconds = mergeabilityRetryDelayNanoseconds
        self.maxCacheEntries = maxCacheEntries
    }

    // MARK: - GitHubDataSource

    func validateToken() async throws -> String {
        let data = try await get("/user")
        let user = try decode(GitHubUser.self, from: data)
        return user.login
    }

    func validateTokenForAppAccess() async throws -> TokenValidationResult {
        let username = try await validateToken()
        let response = try await searchOpenPRsPage(
            username: username,
            perPage: 1,
            page: 1,
            treatIncompleteResultsAsError: false
        )

        if response.incompleteResults {
            return .warning(
                username: username,
                message: Self.incompleteSearchWarningMessage
            )
        }

        guard let firstPR = response.items.first else {
            return .warning(
                username: username,
                message: Self.deferredValidationWarningMessage
            )
        }

        try await probePRStatusAccess(using: firstPR)
        return .verified(username: username)
    }

    func fetchTokenAccessDetails() async throws -> TokenAccessDetails {
        let userResponse = try await getResponse("/user")
        let user = try decode(GitHubUser.self, from: userResponse.data)

        return TokenAccessDetails(
            username: user.login,
            oauthScopes: parseOAuthScopes(from: userResponse.response),
            accessibleRepositories: try await fetchAccessibleRepositories()
        )
    }

    func fetchAllPRStates(username: String) async throws -> PRFetchResult {
        let searchResult = try await searchOpenPRs(username: username)
        let searchItems = searchResult.items
        let maxConcurrency = 8
        let prs = try await withThrowingTaskGroup(of: PRState?.self) { group in
            var results: [PRState] = []
            var index = 0

            func addNextTask() {
                guard index < searchItems.count else { return }
                let item = searchItems[index]
                index += 1
                group.addTask { [self] in
                    try await buildPRState(from: item, username: username)
                }
            }

            for _ in 0..<min(maxConcurrency, searchItems.count) {
                addNextTask()
            }

            for try await state in group {
                if let state { results.append(state) }
                addNextTask()
            }

            return results
        }

        return PRFetchResult(prs: prs, warningMessage: searchResult.warningMessage)
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

    private func searchOpenPRsPage(
        username: String,
        perPage: Int,
        page: Int,
        treatIncompleteResultsAsError: Bool = true
    ) async throws -> SearchResponse {
        let query = "is:pr is:open involves:\(username)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw AppError.networkError
        }
        let path = "/search/issues?q=\(encoded)&per_page=\(perPage)&page=\(page)&sort=updated&order=desc"
        let data = try await get(path)
        let response = try decode(SearchResponse.self, from: data)
        if treatIncompleteResultsAsError, response.incompleteResults {
            throw AppError.incompleteSearchResults
        }
        return response
    }

    private func searchOpenPRs(username: String, perPage: Int = 100) async throws -> SearchItemsResult {
        var allItems: [SearchItem] = []
        var page = 1
        var warningMessage: String?

        while true {
            guard page <= Self.searchResultsMaxPageLimit else {
                throw AppError.paginationLimitExceeded
            }
            let response = try await searchOpenPRsPage(username: username, perPage: perPage, page: page)
            if response.totalCount > Self.searchResultCap {
                warningMessage = Self.searchCapWarningMessage
            }

            let remainingCapacity = Self.searchResultCap - allItems.count
            guard remainingCapacity > 0 else { break }

            allItems.append(contentsOf: response.items.prefix(remainingCapacity))
            if allItems.count >= min(response.totalCount, Self.searchResultCap) || response.items.count < perPage {
                break
            }
            page += 1
        }

        return SearchItemsResult(items: allItems, warningMessage: warningMessage)
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

    private func probePRStatusAccess(using item: SearchItem) async throws {
        guard let repoFullName = extractRepoName(from: item.repositoryUrl),
            let (owner, repo) = splitRepoFullName(repoFullName)
        else {
            return
        }

        let detail = try await fetchPRDetail(owner: owner, repo: repo, number: item.number)
        _ = try await fetchCommitStatuses(owner: owner, repo: repo, sha: detail.head.sha)
    }

    private func fetchPRDetail(
        owner: String,
        repo: String,
        number: Int,
        retryForMergeability: Bool = true
    ) async throws -> PRDetail {
        let data = try await get("/repos/\(owner)/\(repo)/pulls/\(number)")
        var detail = try decode(PRDetail.self, from: data)

        // GitHub's mergeable field may be null or "unknown" while being computed — retry once after a delay
        if retryForMergeability && (detail.mergeableState == nil || detail.mergeableState == "unknown") {
            try await Task.sleep(nanoseconds: mergeabilityRetryDelayNanoseconds)
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
            // Cap pagination for long-lived PRs so review fetching stays bounded.
            guard page <= Self.reviewMaxPageLimit else {
                return reviews
            }
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
        let perPage = 100
        var page = 1
        var allCheckRuns: [CheckRun] = []

        while page <= Self.checkRunsMaxPageLimit {
            let data: Data
            do {
                data = try await requestData(
                    "/repos/\(owner)/\(repo)/commits/\(sha)/check-runs?per_page=\(perPage)&page=\(page)"
                )
            } catch RequestError.statusCode(let statusCode)
                where statusCode == 401 || statusCode == 403 || statusCode == 404
            {
                let repository = "\(owner)/\(repo)"
                Self.logger.info(
                    """
                    fetchCheckRuns falling back after check-runs request returned \
                    \(statusCode, privacy: .public) for \(repository, privacy: .public) \
                    @\(sha, privacy: .public)
                    """
                )
                return allCheckRuns
            } catch {
                throw mapRequestError(error)
            }

            let response = try decode(CheckRunsResponse.self, from: data)
            allCheckRuns.append(contentsOf: response.checkRuns)

            if allCheckRuns.count >= response.totalCount || response.checkRuns.count < perPage {
                return allCheckRuns
            }

            page += 1
        }

        return allCheckRuns
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

    private func fetchAccessibleRepositories() async throws -> [TokenAccessDetails.AccessibleRepository] {
        let perPage = 100
        let maxRepositories = 1_000
        let maxPages = maxRepositories / perPage
        var page = 1
        var repositories: [TokenAccessDetails.AccessibleRepository] = []

        while page <= maxPages {
            let path =
                "/user/repos?affiliation=owner,collaborator,organization_member&per_page=\(perPage)&page=\(page)"
            let data = try await get(path)
            let pageRepositories = try decode([AccessibleRepositoryResponse].self, from: data)
            repositories.append(contentsOf: pageRepositories.map(\.tokenAccessRepository))

            if repositories.count >= maxRepositories {
                return Array(repositories.prefix(maxRepositories))
            }

            if pageRepositories.count < perPage {
                return repositories
            }

            page += 1
        }

        return repositories
    }

    // MARK: - State builders

    private func buildCIStatus(
        from checkRuns: [CheckRun],
        commitStatuses: [CommitStatus],
        combinedStatusState: String
    ) -> PRState.CIStatus {
        let uniqueChecks = aggregatedCIChecks(from: checkRuns, commitStatuses: commitStatuses)
        guard !uniqueChecks.isEmpty else { return .none }

        let failingChecks = uniqueChecks.compactMap(\.failingCheck)
        if !failingChecks.isEmpty {
            return .failing(checks: failingChecks, totalChecks: uniqueChecks.count)
        }

        if uniqueChecks.contains(where: \.isPending) || combinedStatusState == "pending" {
            return .pending
        }

        return .passing
    }

    private func aggregatedCIChecks(
        from checkRuns: [CheckRun],
        commitStatuses: [CommitStatus]
    ) -> [AggregatedCICheck] {
        let latestStatuses = deduplicatedCommitStatuses(commitStatuses)
        var orderedChecks: [AggregatedCICheck] = []
        var indexByIdentifier: [String: Int] = [:]

        func merge(_ check: AggregatedCICheck) {
            if let index = indexByIdentifier[check.identifier] {
                orderedChecks[index] = orderedChecks[index].merged(with: check)
            } else {
                indexByIdentifier[check.identifier] = orderedChecks.count
                orderedChecks.append(check)
            }
        }

        for run in checkRuns {
            merge(
                AggregatedCICheck(
                    identifier: ciCheckIdentifier(name: run.name, urlString: run.htmlUrl),
                    failingCheck: failingCheck(for: run),
                    isPending: run.status != "completed"
                )
            )
        }

        for status in latestStatuses {
            merge(
                AggregatedCICheck(
                    identifier: ciCheckIdentifier(name: status.context, urlString: status.targetUrl),
                    failingCheck: failingCheck(for: status),
                    isPending: status.state == "pending"
                )
            )
        }

        return orderedChecks
    }

    private func buildReviewStatus(reviews: [Review], requestedReviewers: [GitHubUser]) -> PRState.ReviewStatus {
        // Latest review per reviewer. Keep DISMISSED so it clears older approvals/changes requests.
        var latestByReviewer: [String: Review] = [:]
        for review in reviews where review.state != "COMMENTED" {
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
        case "behind": return .behind
        case "has_hooks": return .blocked
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

    private func failingCheck(for run: CheckRun) -> PRState.FailingCheck? {
        guard run.status == "completed",
            run.conclusion != "success",
            run.conclusion != "skipped",
            run.conclusion != "neutral"
        else {
            return nil
        }

        return PRState.FailingCheck(
            name: run.name,
            conclusion: run.conclusion ?? "failure",
            url: run.htmlUrl.flatMap(URL.init(string:))
        )
    }

    private func failingCheck(for status: CommitStatus) -> PRState.FailingCheck? {
        guard ["error", "failure"].contains(status.state) else {
            return nil
        }

        return PRState.FailingCheck(
            name: status.context,
            conclusion: status.state,
            url: status.targetUrl.flatMap(URL.init(string:))
        )
    }

    private func ciCheckIdentifier(name: String, urlString: String?) -> String {
        if let urlString,
            let url = URL(string: urlString)?.absoluteString.lowercased(),
            !url.isEmpty
        {
            return "url:\(url)"
        }

        return "name:\(normalizedCheckName(name))"
    }

    private func normalizedCheckName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - HTTP

    private func get(
        _ path: String,
        allowRetryWithoutETag: Bool = true
    ) async throws -> Data {
        do {
            return try await requestData(path, allowRetryWithoutETag: allowRetryWithoutETag)
        } catch {
            throw mapRequestError(error)
        }
    }

    private func getResponse(_ path: String) async throws -> HTTPDataResponse {
        do {
            return try await requestResponse(path)
        } catch {
            throw mapRequestError(error)
        }
    }

    // MARK: - Request infrastructure

    private func buildRequest(_ path: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw RequestError.app(.networkError)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RequestError.app(.networkError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RequestError.app(.networkError)
        }
        return (data, http)
    }

    private func checkForErrors(data: Data, response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299, 304:
            return
        case 401:
            throw RequestError.statusCode(401)
        case 403:
            if isRateLimitedResponse(data, response) {
                throw RequestError.app(.rateLimitExceeded(.init(resetAt: rateLimitResetDate(from: response))))
            }
            throw RequestError.statusCode(403)
        case 404:
            throw RequestError.statusCode(404)
        case 429:
            throw RequestError.app(.rateLimitExceeded(.init(resetAt: rateLimitResetDate(from: response))))
        case 500...599:
            throw RequestError.app(.serverError(statusCode: response.statusCode))
        default:
            throw RequestError.app(.networkError)
        }
    }

    private func requestData(
        _ path: String,
        allowRetryWithoutETag: Bool = true
    ) async throws -> Data {
        var request = try buildRequest(path)
        guard let url = request.url else { throw RequestError.app(.networkError) }

        if let cachedEntry = responseCache[url] {
            request.setValue(cachedEntry.etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, http) = try await performRequest(request)
        try checkForErrors(data: data, response: http)

        switch http.statusCode {
        case 304:
            if let cachedEntry = responseCache[url] { return cachedEntry.data }
            guard allowRetryWithoutETag else { throw RequestError.app(.networkError) }

            let previousEntry = responseCache.removeValue(forKey: url)
            do {
                return try await requestData(path, allowRetryWithoutETag: false)
            } catch {
                if let previousEntry, responseCache[url] == nil {
                    responseCache[url] = previousEntry
                }
                throw error
            }
        default:
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                responseCache[url] = CachedResponseEntry(data: data, etag: etag)
                evictCacheIfNeeded()
            }
            return data
        }
    }

    private func evictCacheIfNeeded() {
        guard responseCache.count > maxCacheEntries else { return }
        responseCache.trim(to: maxCacheEntries)
    }

    private func requestResponse(_ path: String) async throws -> HTTPDataResponse {
        let request = try buildRequest(path)
        let (data, http) = try await performRequest(request)
        try checkForErrors(data: data, response: http)
        return HTTPDataResponse(data: data, response: http)
    }

    private func mapRequestError(_ error: Error) -> Error {
        switch error {
        case let requestError as RequestError:
            switch requestError {
            case .app(let appError):
                return appError
            case .statusCode(401), .statusCode(403):
                return AppError.authError
            case .statusCode:
                return AppError.networkError
            }
        default:
            return error
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

        return apiError.message.range(
            of: "rate limit",
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ) != nil
    }

    private func parseOAuthScopes(from response: HTTPURLResponse) -> [String] {
        response.value(forHTTPHeaderField: "X-OAuth-Scopes")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func extractRepoName(from repositoryURL: String) -> String? {
        guard let url = URL(string: repositoryURL) else { return nil }
        let components = url.pathComponents
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
}
// swiftlint:enable file_length type_body_length
