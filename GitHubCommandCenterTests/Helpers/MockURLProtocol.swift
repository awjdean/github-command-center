import Foundation

/// Pattern-matched URLProtocol for unit testing URLSession-based code.
/// Register stubs before each test; call `reset()` in tearDown.
final class MockURLProtocol: URLProtocol {
    enum MockError: Error {
        case missingURL
        case invalidResponse(url: URL)
    }

    struct MockResponse {
        let data: Data
        let statusCode: Int
        let headers: [String: String]
    }

    static var handlers: [(urlContains: String, response: MockResponse)] = []
    static var capturedRequests: [URLRequest] = []

    static func reset() {
        handlers = []
        capturedRequests = []
    }

    /// Register a JSON response for any URL that contains `pattern`.
    static func stub(
        urlContains pattern: String,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        json: Any
    ) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        handlers.append((pattern, MockResponse(data: data, statusCode: statusCode, headers: headers)))
    }

    /// Register an empty response (for 304, 401, etc.).
    static func stub(
        urlContains pattern: String,
        statusCode: Int,
        headers: [String: String] = [:]
    ) {
        handlers.append((pattern, MockResponse(data: Data(), statusCode: statusCode, headers: headers)))
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: MockError.missingURL)
            return
        }

        let urlStr = url.absoluteString
        MockURLProtocol.capturedRequests.append(request)

        guard let matchIndex = MockURLProtocol.handlers.firstIndex(where: { urlStr.contains($0.urlContains) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let mock = MockURLProtocol.handlers.remove(at: matchIndex).response

        var headerFields = mock.headers
        headerFields["Content-Type"] = "application/json"

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: mock.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        ) else {
            client?.urlProtocol(self, didFailWithError: MockError.invalidResponse(url: url))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mock.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
