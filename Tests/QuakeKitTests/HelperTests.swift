import Foundation
import Testing
@testable import QuakeKit

@Suite("Magnitude scale")
struct MagnitudeScaleTests {
    @Test func stopsAreExact() {
        #expect(MagnitudeScale.color(for: 4).hexString == "#F6A13A")
        #expect(MagnitudeScale.color(for: 6).hexString == "#D7263D")
        #expect(MagnitudeScale.color(for: 1).hexString == "#5FB8A8")
    }

    @Test func clampsAtTheEnds() {
        #expect(MagnitudeScale.color(for: -1.5) == MagnitudeScale.color(for: 1))
        #expect(MagnitudeScale.color(for: 9.1) == MagnitudeScale.color(for: 8))
        #expect(MagnitudeScale.color(for: .nan) == MagnitudeScale.color(for: 1))
    }

    @Test func blendsBetweenStops() {
        let mid = MagnitudeScale.color(for: 4.5)
        let lower = MagnitudeScale.color(for: 4), upper = MagnitudeScale.color(for: 5)
        #expect(mid == lower.mix(with: upper, fraction: 0.5))
        #expect(mid != lower)
        #expect(mid != upper)
    }

    @Test func classes() {
        #expect(MagnitudeClass(magnitude: 2.9) == .micro)
        #expect(MagnitudeClass(magnitude: 3.0) == .minor)
        #expect(MagnitudeClass(magnitude: 4.99) == .light)
        #expect(MagnitudeClass(magnitude: 6.4) == .strong)
        #expect(MagnitudeClass(magnitude: 7.8) == .major)
        #expect(MagnitudeClass(magnitude: 9.1) == .great)
        #expect(MagnitudeClass.light.rangeLabel == "4.0–4.9")
        #expect(MagnitudeClass.great.rangeLabel == "8.0+")
        #expect(MagnitudeClass.micro.lowerBound == nil)
        #expect(MagnitudeClass.moderate.lowerBound == 5)
        #expect(MagnitudeClass.minor < MagnitudeClass.major)
    }

    @Test func markerSizesGrowAndClamp() {
        let small = MagnitudeScale.markerDiameter(for: 2.5)
        let large = MagnitudeScale.markerDiameter(for: 6.5)
        #expect(MagnitudeScale.markerDiameter(for: 0.5) == 8)
        #expect(small > 8)
        #expect(large > small)
        #expect(MagnitudeScale.markerDiameter(for: 12) == 64)
    }

    @Test func radiusAndEnergy() {
        #expect(abs(MagnitudeScale.radiusMeters(for: 4) - 20_000) < 0.001)
        #expect(abs(MagnitudeScale.radiusMeters(for: 6) - 200_000) < 0.01)
        let ratio = MagnitudeScale.energyRatio(7, to: 6)
        #expect(abs(ratio - 31.6227766) < 0.0001)
        #expect(MagnitudeScale.energyJoules(for: 6) > MagnitudeScale.energyJoules(for: 5))
    }

    @Test func colorHelpers() {
        let color = QuakeColor(hex: 0xF6A13A)
        #expect(color.hexString == "#F6A13A")
        #expect(QuakeColor(red: 2, green: -1, blue: 0.5).hexString == "#FF0080")
        #expect(QuakeColor(hex: 0xFFFFFF).prefersDarkText)
        #expect(!QuakeColor(hex: 0x5E2A84).prefersDarkText)
    }

    @Test func alertLevels() {
        #expect(AlertLevel(text: " Orange ") == .orange)
        #expect(AlertLevel(text: "pink") == nil)
        #expect(AlertLevel.green < AlertLevel.red)
        #expect(AlertLevel.allCases.max() == .red)
        #expect(AlertLevel.yellow.response == "Local or regional response")
        #expect(AlertLevel.red.color.hexString == "#D0202E")
    }
}

@Suite("Distances")
struct DistanceTests {
    let tokyo = GeoCoordinate(latitude: 35.6812, longitude: 139.7671)
    let osaka = GeoCoordinate(latitude: 34.7025, longitude: 135.4959)
    let sanFrancisco = GeoCoordinate(latitude: 37.7749, longitude: -122.4194)

    @Test func haversine() {
        // Tokyo to Osaka is about 400 km in a straight line.
        let km = tokyo.distance(to: osaka)
        #expect(km > 395 && km < 405)
        // Tokyo to San Francisco, across the antimeridian, about 8,270 km.
        let pacific = tokyo.distance(to: sanFrancisco)
        #expect(pacific > 8_200 && pacific < 8_330)
        #expect(tokyo.distance(to: tokyo) == 0)
        #expect(abs(tokyo.distance(to: osaka) - osaka.distance(to: tokyo)) < 1e-9)
    }

    @Test func bearingAndCompass() {
        let north = GeoCoordinate(latitude: 0, longitude: 0).bearing(to: GeoCoordinate(latitude: 10, longitude: 0))
        let east = GeoCoordinate(latitude: 0, longitude: 0).bearing(to: GeoCoordinate(latitude: 0, longitude: 10))
        let west = GeoCoordinate(latitude: 0, longitude: 0).bearing(to: GeoCoordinate(latitude: 0, longitude: -10))
        #expect(abs(north) < 1e-9)
        #expect(abs(east - 90) < 1e-9)
        #expect(abs(west - 270) < 1e-9)
        #expect(CompassPoint(bearing: tokyo.bearing(to: osaka)) == .wsw)
        #expect(CompassPoint(bearing: 359) == .n)
        #expect(CompassPoint(bearing: -45) == .nw)
        #expect(CompassPoint(bearing: 202.5) == .ssw)
    }

    @Test func destinationRoundTrip() {
        let point = tokyo.destination(kilometers: 250, bearing: 45)
        #expect(abs(tokyo.distance(to: point) - 250) < 0.01)
        #expect(abs(tokyo.bearing(to: point) - 45) < 0.5)
        let wrapped = GeoCoordinate(latitude: 0, longitude: 179.5).destination(kilometers: 111.2, bearing: 90)
        #expect(wrapped.longitude < -179)
    }

    @Test func distanceLabels() {
        #expect(QuakeDistance(kilometers: 0.85).formatted() == "850 m")
        #expect(QuakeDistance(kilometers: 12.44).formatted() == "12.4 km")
        #expect(QuakeDistance(kilometers: 1240.4).formatted() == "1,240 km")
        #expect(QuakeDistance(kilometers: 321.8688).formatted(miles: true) == "200 mi")
        #expect(abs(QuakeDistance(miles: 1).kilometers - 1.609344) < 1e-9)
        #expect(QuakeDistance(kilometers: 1) < QuakeDistance(kilometers: 2))
    }

    @Test func coordinateValidity() {
        #expect(tokyo.isValid)
        #expect(!GeoCoordinate(latitude: 91, longitude: 0).isValid)
        #expect(!GeoCoordinate(latitude: 0, longitude: .nan).isValid)
        #expect(GeoCoordinate(latitude: -33.5, longitude: -70.25).description == "33.5000° S, 70.2500° W")
    }

    @Test func sortingAndNeighbors() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "feed-4.5-week")
        let main = try #require(feed.earthquakes.first { $0.id == "us6000qa01" })

        let nearest = feed.earthquakes.sorted(byDistanceFrom: GeoCoordinate(latitude: 40.5, longitude: 141.5))
        #expect(nearest.first?.id == "us6000qa03")

        let neighbors = feed.earthquakes.neighbors(of: main, within: 500)
        #expect(neighbors.map({ $0.earthquake.id }) == ["us6000qa03"])
        let first = try #require(neighbors.first)
        #expect(first.distance.kilometers > 100 && first.distance.kilometers < 160)
        #expect(first.direction == .w || first.direction == .wsw)

        #expect(feed.earthquakes.within(500, of: main.coordinate).count == 2)
        #expect(main.distance(to: first.earthquake) == first.distance)
    }
}

@Suite("Feeds, queries and ordering")
struct QueryTests {
    @Test func feedNames() {
        #expect(FeedMagnitude.allCases.map(\.rawValue) == ["all", "significant", "4.5", "2.5", "1.0"])
        #expect(FeedPeriod.allCases.map(\.rawValue) == ["hour", "day", "week", "month"])
        #expect(SummaryFeed.all.count == 20)
        #expect(SummaryFeed.m45Week.title == "M4.5+ · Past 7 Days")
        #expect(FeedMagnitude.m2_5.minimumMagnitude == 2.5)
        #expect(FeedMagnitude.significant.minimumMagnitude == nil)
    }

    @Test func queryTimeFormat() {
        #expect(QuakeTime.queryString(fixtureTime) == "2026-09-21T14:13:20")
        #expect(QuakeTime.milliseconds(fixtureTime) == 1_790_000_000_000)
        #expect(QuakeTime.date(milliseconds: 1_790_000_000_000) == fixtureTime)
    }

    @Test func numbersInQueries() {
        #expect(EventQuery.number(4.5) == "4.5")
        #expect(EventQuery.number(500) == "500")
        #expect(EventQuery.number(-122.4194) == "-122.4194")
        #expect(EventQuery.number(0.1234567) == "0.123457")
    }

    @Test func validation() {
        #expect(EventQuery().problem == nil)
        #expect(EventQuery(minMagnitude: 6, maxMagnitude: 5).problem != nil)
        #expect(EventQuery(limit: 20_001).problem != nil)
        #expect(EventQuery(limit: 20_000).problem == nil)
        #expect(EventQuery(area: .circle(center: GeoCoordinate(latitude: 0, longitude: 0), radiusKilometers: 0)).problem != nil)
        #expect(EventQuery(area: .circle(center: GeoCoordinate(latitude: 95, longitude: 0), radiusKilometers: 10)).problem != nil)
        #expect(EventQuery(area: .rectangle(minLatitude: 10, maxLatitude: 0, minLongitude: 0, maxLongitude: 10)).problem != nil)
        #expect(EventQuery(area: .rectangle(minLatitude: 0, maxLatitude: 10, minLongitude: 170, maxLongitude: -170)).problem == nil)
        var deep = EventQuery()
        deep.minDepth = 500
        deep.maxDepth = 100
        #expect(deep.problem != nil)
        var paged = EventQuery()
        paged.offset = 0
        #expect(paged.problem != nil)
    }

    @Test func presets() {
        let recent = EventQuery.recent(days: 7, minMagnitude: 5, limit: 100, now: fixtureTime)
        #expect(recent.startTime == fixtureTime.addingTimeInterval(-7 * 86_400))
        #expect(recent.orderBy == .time)
        let around = EventQuery.around(GeoCoordinate(latitude: 35.68, longitude: 139.77), radiusKilometers: 300, days: 90, now: fixtureTime)
        #expect(around.area == .circle(center: GeoCoordinate(latitude: 35.68, longitude: 139.77), radiusKilometers: 300))
        let names = around.queryItems().map(\.name)
        #expect(names == ["starttime", "latitude", "longitude", "maxradiuskm", "orderby"])
    }

    @Test func ordering() throws {
        let feed = try Fixture.decode(QuakeFeed.self, from: "feed-4.5-week")
        #expect(feed.sorted(by: .largest).first?.id == "us6000qa01")
        // The event without a magnitude sorts last by size.
        #expect(feed.sorted(by: .largest).last?.id == "us6000qa06")
        #expect(feed.sorted(by: .smallest).first?.id == "us6000qa06")
        #expect(feed.sorted(by: .newest).first?.id == "us6000qa01")
        #expect(feed.sorted(by: .oldest).first?.id == "us6000qa06")
        #expect(feed.sorted(by: .deepest).first?.id == "us6000qa04")
        #expect(feed.sorted(by: .shallowest).first?.depthKilometers == 10)
        #expect(feed.strongest?.id == "us6000qa01")
        #expect(feed.latest?.id == "us6000qa01")
        #expect(feed.filtered(minimumMagnitude: 5).map(\.id) == ["us6000qa01", "us6000qa03"])
        #expect(feed.countsByClass[.light] == 3)
        #expect(feed.countsByClass[.strong] == 1)
    }
}

@Suite("Intensity")
struct IntensityTests {
    @Test func romanNumerals() {
        #expect(MercalliIntensity.roman(5.6) == "VI")
        #expect(MercalliIntensity.roman(5.1) == "V")
        #expect(MercalliIntensity.roman(0.2) == "I")
        #expect(MercalliIntensity.roman(10) == "X")
        #expect(MercalliIntensity.roman(11.2) == "X+")
        #expect(MercalliIntensity.shaking(6.2) == "Strong")
        #expect(MercalliIntensity.level(.infinity) == 1)
    }
}
