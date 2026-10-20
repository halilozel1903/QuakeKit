import Foundation

/// A client for the USGS earthquake
/// [GeoJSON summary feeds](https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php) and
/// the [FDSN event web service](https://earthquake.usgs.gov/fdsnws/event/1/).
///
/// ```swift
/// let usgs = QuakeClient()
///
/// let week = try await usgs.feed(.m4_5, .week)
/// week.strongest?.magnitudeLabel                  // "M 6.4"
///
/// let nearTokyo = try await usgs.events(.around(
///     GeoCoordinate(latitude: 35.68, longitude: 139.77), radiusKilometers: 300, days: 90
/// ))
/// let total = try await usgs.count(EventQuery.recent(days: 365, minMagnitude: 6))
///
/// let detail = try await usgs.detail(for: week.earthquakes[0])
/// detail.feltReports
/// detail.alertLevel                               // .green … .red
/// ```
///
/// The client is `Sendable`; share one across your app. No API key is needed.
public final class QuakeClient: Sendable {
    public let configuration: QuakeConfiguration

    public init(configuration: QuakeConfiguration = QuakeConfiguration()) {
        self.configuration = configuration
    }

    public convenience init(session: URLSession) {
        self.init(configuration: QuakeConfiguration(session: session))
    }

    // MARK: - Summary feeds

    /// A real-time summary feed, such as `4.5_week.geojson`.
    public func feed(_ feed: SummaryFeed) async throws -> QuakeFeed {
        let body = try await data(for: makeRequest(url: feed.url(base: configuration.feedBaseURL)))
        return try decode(QuakeFeed.self, from: body)
    }

    /// A real-time summary feed by magnitude and period: `feed(.m2_5, .day)`.
    public func feed(_ magnitude: FeedMagnitude, _ period: FeedPeriod) async throws -> QuakeFeed {
        try await feed(SummaryFeed(magnitude, period))
    }

    // MARK: - FDSN event service

    /// Events matching `query` from the whole catalog (`/query?format=geojson&…`). A query
    /// with no matches gives an empty feed.
    public func events(_ query: EventQuery) async throws -> QuakeFeed {
        let request = try queryRequest(method: "query", items: checked(query).queryItems())
        guard let body = try await data(for: request, allowNoContent: true) else {
            return .empty(url: request.url)
        }
        return try decode(QuakeFeed.self, from: body)
    }

    /// How many events match `query` (`/count?format=geojson&…`), without downloading them.
    /// `limit`, `offset` and `orderBy` are ignored.
    public func count(_ query: EventQuery) async throws -> EventCount {
        let request = try queryRequest(method: "count", items: checked(query).queryItems(includePaging: false))
        guard let body = try await data(for: request, allowNoContent: true) else {
            return EventCount(count: 0)
        }
        if let count = try? JSONDecoder().decode(EventCount.self, from: body) {
            return count
        }
        // Without format=geojson the service answers with a bare number.
        if let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), let value = Int(text) {
            return EventCount(count: value)
        }
        return try decode(EventCount.self, from: body)
    }

    // MARK: - Event detail

    /// The detail of an event from its `detail` URL, or by its id when it has none.
    public func detail(for earthquake: Earthquake) async throws -> EventDetail {
        if let url = earthquake.properties.detail {
            let body = try await data(for: makeRequest(url: url))
            return try decode(EventDetail.self, from: body)
        }
        return try await detail(id: earthquake.id)
    }

    /// The detail of an event by id (`/query?eventid={id}&format=geojson`). Any of the event's
    /// ids works. Throws ``QuakeError/notFound(url:)`` for an unknown id.
    public func detail(id: String) async throws -> EventDetail {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            throw QuakeError.invalidQuery("\"\(id)\" is not an event id.")
        }
        let request = try queryRequest(method: "query", items: [URLQueryItem(name: "eventid", value: id)])
        guard let body = try await data(for: request, allowNoContent: true) else {
            throw QuakeError.notFound(url: request.url ?? configuration.eventServiceURL)
        }
        return try decode(EventDetail.self, from: body)
    }

    /// The bytes of a product file, such as a ShakeMap image, retried like API requests.
    public func contentData(from url: URL) async throws -> Data {
        try await data(for: makeRequest(url: url, accept: "*/*"))
    }

    // MARK: - Requests

    /// The URL of an FDSN request, such as `query` with the given items plus `format=geojson`.
    /// Exposed for tests and debugging.
    public func eventServiceURL(method: String, items: [URLQueryItem]) throws -> URL {
        let base = configuration.eventServiceURL.appendingPathComponent(method)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw QuakeError.invalidQuery("Could not build the URL for \(method).")
        }
        components.queryItems = [URLQueryItem(name: "format", value: "geojson")] + items
        // URLComponents leaves "+" as is; servers read it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            throw QuakeError.invalidQuery("Could not build the URL for \(method).")
        }
        return url
    }

    func checked(_ query: EventQuery) throws -> EventQuery {
        if let problem = query.problem {
            throw QuakeError.invalidQuery(problem)
        }
        return query
    }

    func queryRequest(method: String, items: [URLQueryItem]) throws -> URLRequest {
        makeRequest(url: try eventServiceURL(method: method, items: items))
    }

    func makeRequest(url: URL, accept: String = "application/geo+json, application/json") -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw QuakeError.decoding(type: String(describing: Value.self), description: String(describing: error))
        }
    }

    func data(for request: URLRequest) async throws -> Data {
        guard let body = try await data(for: request, allowNoContent: false) else {
            throw QuakeError.invalidResponse
        }
        return body
    }

    /// Performs a request, retrying busy and failed attempts. Returns the body of a successful
    /// response, or nil for "204 No Content" when `allowNoContent` is set.
    func data(for request: URLRequest, allowNoContent: Bool) async throws -> Data? {
        let url = request.url ?? configuration.eventServiceURL
        var attempt = 0
        while true {
            let response: (Data, HTTPURLResponse)
            do {
                response = try await send(request)
            } catch QuakeError.transport(let error) where Self.isRetryable(error) && attempt < configuration.maxRetries {
                attempt += 1
                try await Self.pause(Self.backoff(attempt: attempt))
                continue
            }
            let (data, http) = response
            switch http.statusCode {
            case 204:
                if allowNoContent { return nil }
                throw QuakeError.invalidResponse
            case 200..<300:
                return data
            case 400:
                throw QuakeError.badRequest(message: QuakeError.message(in: data) ?? "", url: url)
            case 404:
                throw QuakeError.notFound(url: url)
            case 429, 500, 502, 503, 504:
                guard attempt < configuration.maxRetries else {
                    throw QuakeError.http(statusCode: http.statusCode, message: QuakeError.message(in: data), url: url)
                }
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                try await Self.pause(min(retryAfter ?? Self.backoff(attempt: attempt), 30))
            default:
                throw QuakeError.http(statusCode: http.statusCode, message: QuakeError.message(in: data), url: url)
            }
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result: (Data, URLResponse)
        do {
            result = try await configuration.session.data(for: request)
        } catch let error as URLError {
            throw QuakeError.transport(error)
        } catch is CancellationError {
            throw QuakeError.transport(URLError(.cancelled))
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw QuakeError.invalidResponse
        }
        return (result.0, http)
    }

    static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// 0.5 s, 1 s, 2 s… for the first, second, third retry.
    static func backoff(attempt: Int) -> TimeInterval {
        0.5 * pow(2, Double(max(0, attempt - 1)))
    }

    static func pause(_ seconds: TimeInterval) async throws {
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            throw QuakeError.transport(URLError(.cancelled))
        }
    }
}
