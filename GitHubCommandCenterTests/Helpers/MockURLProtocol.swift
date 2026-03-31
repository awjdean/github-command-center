import Foundation
import XCTest

/// Pattern-matched URLProtocol for unit testing URLSession-based code.
/// Register stubs before each test; call `reset()` in tearDown.
final class MockURLProtocol: URLProtocol {
    enum MockError: Error {
        case missingURL
        case invalidResponse(url: URL)
    }

    private struct Handler {
        let urlContains: String
        let response: MockResponse
        let persistent: Bool
    }

    struct MockResponse {
        let data: Data
        let statusCode: Int
        let headers: [String: String]
    }

    private static let stateQueue = DispatchQueue(label: "MockURLProtocol.state")
    private static var handlers: [Handler] = []
    private static var storedCapturedRequests: [URLRequest] = []

    static var capturedRequests: [URLRequest] {
        stateQueue.sync { storedCapturedRequests }
    }

    static func reset() {
        stateQueue.sync {
            handlers = []
            storedCapturedRequests = []
        }
    }

    /// Register a JSON response for any URL that contains `pattern`.
    static func stub(
        urlContains pattern: String,
        persistent: Bool = false,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        json: Any
    ) {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: json)
        } catch {
            XCTFail("Failed to serialize JSON stub for pattern \(pattern): \(error)")
            return
        }
        let handler = Handler(
            urlContains: pattern,
            response: MockResponse(data: data, statusCode: statusCode, headers: headers),
            persistent: persistent
        )
        stateQueue.sync {
            handlers.append(handler)
        }
    }

    /// Register an empty response (for 304, 401, etc.).
    static func stub(
        urlContains pattern: String,
        persistent: Bool = false,
        statusCode: Int,
        headers: [String: String] = [:]
    ) {
        let handler = Handler(
            urlContains: pattern,
            response: MockResponse(data: Data(), statusCode: statusCode, headers: headers),
            persistent: persistent
        )
        stateQueue.sync {
            handlers.append(handler)
        }
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
        let mock = Self.stateQueue.sync { () -> MockResponse? in
            Self.storedCapturedRequests.append(request)

            guard let matchIndex = Self.handlers.firstIndex(where: { urlStr.contains($0.urlContains) }) else {
                return nil
            }

            let handler = Self.handlers[matchIndex]
            if !handler.persistent {
                Self.handlers.remove(at: matchIndex)
            }

            return handler.response
        }

        guard let mock else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        var headerFields = mock.headers
        if headerFields["Content-Type"] == nil, !mock.data.isEmpty {
            headerFields["Content-Type"] = "application/json"
        }

        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: mock.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headerFields
            )
        else {
            client?.urlProtocol(self, didFailWithError: MockError.invalidResponse(url: url))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mock.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
