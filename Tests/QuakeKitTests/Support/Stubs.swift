import Foundation
@testable import QuakeKit

/// Responses in `Fixtures/`, hand-written in the shapes of the USGS GeoJSON feeds and the FDSN
/// event service.
enum Fixture {
    struct Missing: Error {
        let name: String
    }

    static func data(_ name: String, extension ext: String = "json") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw Missing(name: name + "." + ext)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

/// A canned HTTP response.
struct StubResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json(_ fixture: String, status: Int = 200) throws -> StubResponse {
        try StubResponse(status: status, headers: ["Content-Type": "application/json"], body: Fixture.data(fixture))
    }

    static func text(_ fixture: String, status: Int) throws -> StubResponse {
        try StubResponse(status: status, headers: ["Content-Type": "text/plain"], body: Fixture.data(fixture, extension: "txt"))
    }

    static func raw(_ text: String, status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"]) -> StubResponse {
        StubResponse(status: status, headers: headers, body: Data(text.utf8))
    }

    static func status(_ status: Int, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, headers: headers, body: Data())
    }
}

typealias StubHandler = @Sendable (URLRequest) throws -> StubResponse

/// Answers requests from a handler registered for the request's host, so every test can run in
/// parallel with a host of its own. Nothing ever reaches the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let handler = StubRegistry.shared.handler(for: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        StubRegistry.shared.record(request, for: host)
        do {
            let stub = try handler(request)
            guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    private let lock = NSLock()
    private var handlers: [String: StubHandler] = [:]
    private var requests: [String: [URLRequest]] = [:]

    func register(_ handler: @escaping StubHandler, for host: String) {
        lock.withLock { handlers[host] = handler }
    }

    func handler(for host: String) -> StubHandler? {
        lock.withLock { handlers[host] }
    }

    func record(_ request: URLRequest, for host: String) {
        lock.withLock { requests[host, default: []].append(request) }
    }

    func requests(for host: String) -> [URLRequest] {
        lock.withLock { requests[host] ?? [] }
    }
}

/// A client wired to the stub, on a host of its own.
struct StubbedClient {
    let host: String
    let client: QuakeClient

    /// `extraHosts` are answered by the same handler, such as `earthquake.usgs.gov` for the
    /// absolute detail URLs in the fixtures.
    init(maxRetries: Int = 2, extraHosts: [String] = [], handler: @escaping StubHandler) {
        host = "stub-" + UUID().uuidString.lowercased() + ".test"
        for name in [host] + extraHosts {
            StubRegistry.shared.register(handler, for: name)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        client = QuakeClient(configuration: QuakeConfiguration(
            feedBaseURL: URL(string: "https://\(host)/earthquakes/feed/v1.0/summary")!,
            eventServiceURL: URL(string: "https://\(host)/fdsnws/event/1")!,
            session: URLSession(configuration: configuration),
            userAgent: "QuakeKitTests/1.0",
            maxRetries: maxRetries
        ))
    }

    /// Every request sent to the stub host, in order.
    var requests: [URLRequest] {
        StubRegistry.shared.requests(for: host)
    }

    var lastRequest: URLRequest? {
        requests.last
    }

    /// The value of a query item of the last request.
    func lastQueryValue(_ name: String) -> String? {
        lastRequest?.queryValue(name)
    }
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }

    var queryNames: [String] {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        return components.queryItems?.map(\.name) ?? []
    }
}

/// Counts calls across a handler's invocations.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    var count: Int {
        lock.withLock { value }
    }
}

/// 2026-09-21T14:13:20Z, the time of the fixtures' main event.
let fixtureTime = Date(timeIntervalSince1970: 1_790_000_000)
