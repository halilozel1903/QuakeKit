import Foundation
import Testing
@testable import QuakeKit

@Suite("QuakeClient requests")
struct ClientTests {
    @Test func summaryFeedURL() async throws {
        let stub = StubbedClient { _ in try .json("feed-4.5-week") }
        let feed = try await stub.client.feed(.m4_5, .week)

        #expect(feed.earthquakes.count == 6)
        let request = try #require(stub.lastRequest)
        #expect(request.url?.path == "/earthquakes/feed/v1.0/summary/4.5_week.geojson")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "QuakeKitTests/1.0")
    }

    @Test func everyFeedPath() async throws {
        let stub = StubbedClient { _ in try .json("query-empty") }
        for feed in SummaryFeed.all {
            _ = try await stub.client.feed(feed)
            #expect(stub.lastRequest?.url?.lastPathComponent == feed.fileName)
        }
        #expect(stub.requests.count == 20)
        #expect(SummaryFeed(.significant, .month).fileName == "significant_month.geojson")
        #expect(SummaryFeed(.m1_0, .hour).fileName == "1.0_hour.geojson")
        #expect(SummaryFeed(.all, .day).url().absoluteString == "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson")
    }

    @Test func fdsnQueryParameters() async throws {
        let stub = StubbedClient { _ in try .json("query-near-tokyo") }
        var query = EventQuery(
            start: fixtureTime.addingTimeInterval(-90 * 86_400),
            end: fixtureTime,
            minMagnitude: 4.5,
            area: .circle(center: GeoCoordinate(latitude: 35.68, longitude: 139.77), radiusKilometers: 600),
            limit: 3,
            orderBy: .magnitude
        )
        query.maxDepth = 300
        let feed = try await stub.client.events(query)

        #expect(feed.earthquakes.count == 3)
        let request = try #require(stub.lastRequest)
        #expect(request.url?.path == "/fdsnws/event/1/query")
        #expect(request.queryValue("format") == "geojson")
        #expect(request.queryValue("starttime") == "2026-06-23T14:13:20")
        #expect(request.queryValue("endtime") == "2026-09-21T14:13:20")
        #expect(request.queryValue("minmagnitude") == "4.5")
        #expect(request.queryValue("maxdepth") == "300")
        #expect(request.queryValue("latitude") == "35.68")
        #expect(request.queryValue("longitude") == "139.77")
        #expect(request.queryValue("maxradiuskm") == "600")
        #expect(request.queryValue("limit") == "3")
        #expect(request.queryValue("orderby") == "magnitude")
        #expect(request.queryValue("maxmagnitude") == nil)
    }

    @Test func rectangleAndFilters() async throws {
        let stub = StubbedClient { _ in try .json("query-empty") }
        var query = EventQuery(area: .rectangle(minLatitude: 32, maxLatitude: 42, minLongitude: -125, maxLongitude: -114))
        query.alertLevel = .orange
        query.minFelt = 10
        query.eventType = "earthquake"
        query.productType = "shakemap"
        query.offset = 21
        _ = try await stub.client.events(query)

        #expect(stub.lastQueryValue("minlatitude") == "32")
        #expect(stub.lastQueryValue("maxlongitude") == "-114")
        #expect(stub.lastQueryValue("alertlevel") == "orange")
        #expect(stub.lastQueryValue("minfelt") == "10")
        #expect(stub.lastQueryValue("eventtype") == "earthquake")
        #expect(stub.lastQueryValue("producttype") == "shakemap")
        #expect(stub.lastQueryValue("offset") == "21")
    }

    @Test func countLeavesOutPaging() async throws {
        let stub = StubbedClient { _ in try .json("count") }
        let count = try await stub.client.count(EventQuery(start: fixtureTime, minMagnitude: 6, limit: 10, orderBy: .time))

        #expect(count.count == 1432)
        let request = try #require(stub.lastRequest)
        #expect(request.url?.path == "/fdsnws/event/1/count")
        #expect(request.queryValue("format") == "geojson")
        #expect(request.queryValue("minmagnitude") == "6")
        #expect(!request.queryNames.contains("limit"))
        #expect(!request.queryNames.contains("orderby"))
    }

    @Test func countAsPlainText() async throws {
        let stub = StubbedClient { _ in .raw("57 ", headers: ["Content-Type": "text/plain"]) }
        let count = try await stub.client.count(EventQuery())
        #expect(count.count == 57)
        #expect(count.maxAllowed == nil)
    }

    @Test func noContentIsAnEmptyResult() async throws {
        let stub = StubbedClient { _ in .status(204) }
        let feed = try await stub.client.events(EventQuery(minMagnitude: 9.5))
        #expect(feed.earthquakes.isEmpty)
        let count = try await stub.client.count(EventQuery(minMagnitude: 9.5))
        #expect(count.count == 0)
    }

    @Test func detailFromTheDetailURL() async throws {
        let stub = StubbedClient(extraHosts: ["earthquake.usgs.gov"]) { request in
            if request.url?.path.hasSuffix(".geojson") == true, request.url?.path.contains("/detail/") == true {
                return try .json("detail-us6000qa01")
            }
            return try .json("feed-4.5-week")
        }
        let feed = try await stub.client.feed(.m4_5, .week)
        let quake = try #require(feed.earthquakes.first)
        let detail = try await stub.client.detail(for: quake)

        #expect(detail.id == quake.id)
        #expect(detail.feltReports == 240)
        let sent = StubRegistry.shared.requests(for: "earthquake.usgs.gov")
        #expect(sent.last?.url?.absoluteString == "https://earthquake.usgs.gov/earthquakes/feed/v1.0/detail/us6000qa01.geojson")
    }

    @Test func detailByID() async throws {
        let stub = StubbedClient { _ in try .json("detail-us6000qa01") }
        let detail = try await stub.client.detail(id: "us6000qa01")

        #expect(detail.alertLevel == .yellow)
        #expect(stub.lastRequest?.url?.path == "/fdsnws/event/1/query")
        #expect(stub.lastQueryValue("eventid") == "us6000qa01")
        #expect(stub.lastQueryValue("format") == "geojson")
    }

    @Test func detailWithoutADetailURLAsksByID() async throws {
        let stub = StubbedClient { _ in try .json("detail-us6000qa01") }
        let quake = Earthquake(
            id: "us6000qa01",
            properties: EarthquakeProperties(magnitude: 6.4, time: fixtureTime),
            location: Hypocenter(coordinate: GeoCoordinate(latitude: 40.55, longitude: 142.85), depthKilometers: 35.2)
        )
        _ = try await stub.client.detail(for: quake)
        #expect(stub.lastQueryValue("eventid") == "us6000qa01")
    }

    @Test func unknownEventIsNotFound() async throws {
        let stub = StubbedClient { _ in .raw("Error 404: Not Found", status: 404, headers: ["Content-Type": "text/plain"]) }
        do {
            _ = try await stub.client.detail(id: "us0000none")
            Issue.record("Expected a not found error")
        } catch let error as QuakeError {
            #expect(error.statusCode == 404)
        }
    }

    @Test func invalidEventIDIsRefusedBeforeSending() async throws {
        let stub = StubbedClient { _ in try .json("detail-us6000qa01") }
        await #expect(throws: QuakeError.self) {
            _ = try await stub.client.detail(id: "us 1&x=2")
        }
        await #expect(throws: QuakeError.self) {
            _ = try await stub.client.detail(id: "  ")
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func badRequestCarriesTheServiceMessage() async throws {
        let stub = StubbedClient { _ in try .text("error-400", status: 400) }
        do {
            _ = try await stub.client.events(EventQuery(minMagnitude: 2))
            Issue.record("Expected a bad request error")
        } catch let error as QuakeError {
            let url = try #require(stub.lastRequest?.url)
            #expect(error == .badRequest(message: #"Bad minmagnitude value "big"."#, url: url))
            #expect(error.errorDescription == #"Bad minmagnitude value "big"."#)
        }
    }

    @Test func invalidQueryIsRefusedBeforeSending() async throws {
        let stub = StubbedClient { _ in try .json("query-empty") }
        let backwards = EventQuery(start: fixtureTime, end: fixtureTime.addingTimeInterval(-60))
        await #expect(throws: QuakeError.invalidQuery("The start time is after the end time.")) {
            _ = try await stub.client.events(backwards)
        }
        await #expect(throws: QuakeError.self) {
            _ = try await stub.client.count(EventQuery(limit: 0))
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func retriesBusyResponses() async throws {
        let counter = Counter()
        let stub = StubbedClient { _ in
            if counter.next() < 3 {
                return .status(503, headers: ["Retry-After": "0"])
            }
            return try .json("feed-4.5-week")
        }
        let feed = try await stub.client.feed(.m4_5, .week)
        #expect(feed.earthquakes.count == 6)
        #expect(counter.count == 3)
    }

    @Test func givesUpAfterMaxRetries() async throws {
        let counter = Counter()
        let stub = StubbedClient(maxRetries: 1) { _ in
            _ = counter.next()
            return .status(503, headers: ["Retry-After": "0"])
        }
        await #expect(throws: QuakeError.http(statusCode: 503, message: nil, url: SummaryFeed(.all, .hour).url(base: stub.client.configuration.feedBaseURL))) {
            _ = try await stub.client.feed(.all, .hour)
        }
        #expect(counter.count == 2)
    }

    @Test func malformedBodyIsADecodingError() async throws {
        let stub = StubbedClient { _ in .raw(#"{"type":"FeatureCollection"}"#) }
        do {
            _ = try await stub.client.feed(.m2_5, .day)
            Issue.record("Expected a decoding error")
        } catch let error as QuakeError {
            guard case let .decoding(type, _) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(type == "QuakeFeed")
        }
    }
}
