import Foundation
import Testing
@testable import QuakeKit

@Suite("GeoJSON decoding")
struct DecodingTests {
    @Test func summaryFeed() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "feed-4.5-week")

        #expect(feed.metadata.title == "USGS Magnitude 4.5+ Earthquakes, Past Week")
        #expect(feed.metadata.status == 200)
        #expect(feed.metadata.api == "1.14.1")
        #expect(feed.metadata.generated == Date(timeIntervalSince1970: 1_790_000_060))
        // The feature without a geometry is skipped; the other six are kept.
        #expect(feed.earthquakes.count == 6)
        #expect(!feed.earthquakes.contains { $0.id == "us6000bad1" })

        let box = try #require(feed.boundingBox)
        #expect(box.southWest == GeoCoordinate(latitude: -58.12, longitude: -178.4))
        #expect(box.northEast == GeoCoordinate(latitude: 40.55, longitude: 142.85))
        #expect(box.maxDepth == 560.3)
    }

    @Test func earthquakeProperties() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "feed-4.5-week")
        let quake = try #require(feed.earthquakes.first)

        #expect(quake.id == "us6000qa01")
        #expect(quake.magnitude == 6.4)
        #expect(quake.magnitudeLabel == "M 6.4")
        #expect(quake.place == "112 km E of Hachinohe, Japan")
        #expect(quake.time == fixtureTime)
        #expect(quake.properties.updated == fixtureTime.addingTimeInterval(600))
        #expect(quake.coordinate == GeoCoordinate(latitude: 40.55, longitude: 142.85))
        #expect(quake.depthKilometers == 35.2)
        #expect(quake.location.depthClass == .shallow)
        #expect(quake.alertLevel == .yellow)
        #expect(quake.hasTsunamiFlag)
        #expect(quake.feltReports == 212)
        #expect(quake.properties.cdi == 5.1)
        #expect(quake.properties.mmi == 5.6)
        #expect(quake.properties.significance == 829)
        #expect(quake.properties.status == .reviewed)
        #expect(quake.properties.magnitudeType == "mww")
        #expect(quake.properties.network == "us")
        #expect(quake.properties.code == "6000qa01")
        #expect(quake.properties.ids == ["us6000qa01"])
        #expect(quake.properties.sources == ["us"])
        #expect(quake.properties.productTypes.contains("shakemap"))
        #expect(quake.properties.url?.absoluteString == "https://earthquake.usgs.gov/earthquakes/eventpage/us6000qa01")
        #expect(quake.properties.detail?.lastPathComponent == "us6000qa01.geojson")
        #expect(quake.magnitudeClass == .strong)
    }

    @Test func nullsAndMissingValues() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "feed-4.5-week")
        let quake = try #require(feed.earthquakes.first { $0.id == "us6000qa06" })

        #expect(quake.magnitude == nil)
        #expect(quake.magnitudeLabel == "M ?")
        #expect(quake.alertLevel == nil)
        #expect(quake.feltReports == nil)
        #expect(!quake.hasTsunamiFlag)
        #expect(quake.properties.status == .automatic)
        #expect(quake.properties.stationCount == nil)
    }

    @Test func deepEvent() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "feed-4.5-week")
        let fiji = try #require(feed.earthquakes.first { $0.id == "us6000qa04" })
        #expect(fiji.location.depthClass == .deep)
        #expect(fiji.location.depthLabel == "560.3 km deep")
    }

    @Test func fdsnQueryResult() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "query-near-tokyo")
        #expect(feed.metadata.count == 3)
        #expect(feed.earthquakes.map(\.id) == ["us6000qa03", "us6000qb11", "us6000qb12"])
    }

    @Test func emptyQueryResult() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "query-empty")
        #expect(feed.earthquakes.isEmpty)
        #expect(feed.strongest == nil)
        #expect(feed.boundingBox == nil)
    }

    @Test func rejectsAFeatureWhereACollectionIsExpected() throws {
        #expect(throws: DecodingError.self) {
            _ = try Fixture.decode(QuakeFeed.self, from: "detail-us6000qa01")
        }
    }

    @Test func eventDetailProducts() throws {
        let detail = try Fixture.decode(EventDetail.self, from: "detail-us6000qa01")

        #expect(detail.id == "us6000qa01")
        #expect(detail.earthquake.magnitude == 6.4)
        #expect(detail.productTypes == ["dyfi", "losspager", "moment-tensor", "origin", "shakemap"])

        // The origin with the higher preferredWeight comes first.
        let origin = try #require(detail.origin)
        #expect(origin.source == "us")
        #expect(origin.preferredWeight == 156)
        #expect(origin.double("depth") == 35.2)
        #expect(origin.int("num-stations-used") == 141)
        #expect(origin.string("review-status") == "reviewed")
        #expect(origin.string("missing") == nil)
        #expect(origin.contents["contents.xml"]?.length == 3020)
        #expect(detail.products["origin"]?.count == 2)

        #expect(detail.magnitudeType == "Mww")
        #expect(detail.stationsUsed == 141)
        #expect(detail.azimuthalGap == 28)
        #expect(detail.horizontalErrorKilometers == 6.2)
        #expect(detail.depthErrorKilometers == 1.8)
    }

    @Test func eventDetailSummaries() throws {
        let detail = try Fixture.decode(EventDetail.self, from: "detail-us6000qa01")

        // `felt`, `mmi` and `alert` are null in this detail; the products fill them in.
        #expect(detail.properties.felt == nil)
        #expect(detail.feltReports == 240)
        #expect(detail.alertLevel == .yellow)
        #expect(detail.maxReportedIntensity == 5.1)
        #expect(detail.maxEstimatedIntensity == 5.6)
        #expect(detail.hasTsunamiFlag)
        #expect(detail.shakemapIntensityImageURL?.lastPathComponent == "intensity.jpg")
        // A deleted product and a malformed one are not preferred.
        #expect(detail.momentTensor == nil)
        #expect(detail.products["moment-tensor"]?.count == 1)
        // Numbers inside product properties are read as text.
        #expect(detail.dyfi?.string("numResp") == "240")
    }

    @Test func eventCount() throws {
        let count = try Fixture.decode(EventCount.self, from: "count")
        #expect(count.count == 1432)
        #expect(count.maxAllowed == 20000)
        #expect(!count.exceedsLimit)
        #expect(EventCount(count: 25_000, maxAllowed: 20_000).exceedsLimit)
    }

    @Test func lenientNumbers() throws {
        let json = #"""
        {"type":"Feature","id":"ak0001","properties":{"mag":"2.7","time":"1790000000000","felt":3.0,"tsunami":"1","alert":"Orange","status":"REVIEWED","sig":null},
         "geometry":{"type":"Point","coordinates":[-150.1,61.2]}}
        """#
        let quake = try JSONDecoder().decode(Earthquake.self, from: Data(json.utf8))
        #expect(quake.magnitude == 2.7)
        #expect(quake.time == fixtureTime)
        #expect(quake.feltReports == 3)
        #expect(quake.hasTsunamiFlag)
        #expect(quake.alertLevel == .orange)
        #expect(quake.properties.status == .reviewed)
        #expect(quake.properties.significance == nil)
        #expect(quake.depthKilometers == 0)
    }

    @Test func idFromNetworkAndCode() throws {
        let json = #"""
        {"type":"Feature","properties":{"mag":1.2,"time":1790000000000,"net":"nc","code":"75012345"},
         "geometry":{"type":"Point","coordinates":[-122.8,38.8,2.1]}}
        """#
        let quake = try JSONDecoder().decode(Earthquake.self, from: Data(json.utf8))
        #expect(quake.id == "nc75012345")
    }

    @Test func eventWithoutTimeIsRejected() {
        let json = #"{"type":"Feature","id":"x1","properties":{"mag":1.2},"geometry":{"type":"Point","coordinates":[0,0,0]}}"#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Earthquake.self, from: Data(json.utf8))
        }
    }
}
