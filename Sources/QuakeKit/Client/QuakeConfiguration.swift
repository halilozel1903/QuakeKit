import Foundation

/// Settings of a ``QuakeClient``.
public struct QuakeConfiguration: Sendable {
    /// `https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary`.
    public static let defaultFeedBaseURL = URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary")!
    /// `https://earthquake.usgs.gov/fdsnws/event/1`.
    public static let defaultEventServiceURL = URL(string: "https://earthquake.usgs.gov/fdsnws/event/1")!

    /// Where the summary feeds are.
    public var feedBaseURL: URL
    /// The FDSN event web service; `query` and `count` are below it.
    public var eventServiceURL: URL
    /// The session that performs requests. Give it a `URLProtocol` subclass to stub responses.
    public var session: URLSession
    /// Sent as `User-Agent`. The USGS needs no key; naming your app helps them reach you.
    public var userAgent: String
    /// How many times a request is retried after HTTP 429, 500, 502, 503 or 504, a timeout or a
    /// lost connection (default 2).
    public var maxRetries: Int
    /// The request timeout in seconds.
    public var timeout: TimeInterval

    public init(
        feedBaseURL: URL = QuakeConfiguration.defaultFeedBaseURL,
        eventServiceURL: URL = QuakeConfiguration.defaultEventServiceURL,
        session: URLSession = .shared,
        userAgent: String = "QuakeKit/1.0 (+https://github.com/halilozel1903/QuakeKit)",
        maxRetries: Int = 2,
        timeout: TimeInterval = 30
    ) {
        self.feedBaseURL = feedBaseURL
        self.eventServiceURL = eventServiceURL
        self.session = session
        self.userAgent = userAgent
        self.maxRetries = max(0, maxRetries)
        self.timeout = timeout
    }
}
