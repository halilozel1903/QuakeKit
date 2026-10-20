import Foundation

/// A GeoJSON `FeatureCollection` of events: a summary feed or the answer to an FDSN query.
public struct QuakeFeed: Hashable, Sendable, Decodable {
    public var metadata: FeedMetadata
    /// The events, newest first in summary feeds and in the order asked for in queries.
    public var earthquakes: [Earthquake]
    /// `[minLongitude, minLatitude, minDepth, maxLongitude, maxLatitude, maxDepth]`, when sent.
    public var boundingBox: BoundingBox?

    public init(metadata: FeedMetadata, earthquakes: [Earthquake], boundingBox: BoundingBox? = nil) {
        self.metadata = metadata
        self.earthquakes = earthquakes
        self.boundingBox = boundingBox
    }

    /// An empty result, as FDSN's "204 No Content" means.
    public static func empty(title: String = "No events", url: URL? = nil) -> QuakeFeed {
        QuakeFeed(metadata: FeedMetadata(generated: Date(), url: url, title: title, status: 204, api: nil, count: 0), earthquakes: [])
    }

    private enum CodingKeys: String, CodingKey {
        case type, metadata, features, bbox
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = container.lenient(String.self, forKey: .type)
        guard type == nil || type == "FeatureCollection" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected a FeatureCollection, got \(type ?? "")")
        }
        earthquakes = try container.decode(LossyArray<Earthquake>.self, forKey: .features).elements
        metadata = container.lenient(FeedMetadata.self, forKey: .metadata)
            ?? FeedMetadata(generated: nil, url: nil, title: nil, status: nil, api: nil, count: earthquakes.count)
        boundingBox = container.lenient([Double].self, forKey: .bbox).flatMap(BoundingBox.init(values:))
    }

    // MARK: - Helpers

    /// The event with the largest magnitude.
    public var strongest: Earthquake? {
        earthquakes.max { ($0.magnitude ?? -10) < ($1.magnitude ?? -10) }
    }

    /// The most recent event.
    public var latest: Earthquake? {
        earthquakes.max { $0.time < $1.time }
    }

    /// The events sorted as asked.
    public func sorted(by order: EarthquakeOrder) -> [Earthquake] {
        earthquakes.sorted(by: order)
    }

    /// Events of at least `magnitude`.
    public func filtered(minimumMagnitude magnitude: Double) -> [Earthquake] {
        earthquakes.filter { ($0.magnitude ?? -10) >= magnitude }
    }

    /// How many events fall in each magnitude class.
    public var countsByClass: [MagnitudeClass: Int] {
        Dictionary(grouping: earthquakes, by: \.magnitudeClass).mapValues(\.count)
    }
}

/// The `metadata` of a feed.
public struct FeedMetadata: Hashable, Sendable, Decodable {
    /// When the feed was generated.
    public var generated: Date?
    public var url: URL?
    /// Such as `"USGS Magnitude 4.5+ Earthquakes, Past Week"`.
    public var title: String?
    public var status: Int?
    /// The API version, such as `1.10.3`.
    public var api: String?
    /// The number of events in the feed.
    public var count: Int?

    public init(generated: Date?, url: URL?, title: String?, status: Int?, api: String?, count: Int?) {
        self.generated = generated
        self.url = url
        self.title = title
        self.status = status
        self.api = api
        self.count = count
    }

    private enum CodingKeys: String, CodingKey {
        case generated, url, title, status, api, count
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generated = c.lenientMilliseconds(forKey: .generated)
        url = c.lenientURL(forKey: .url)
        title = c.lenient(String.self, forKey: .title)
        status = c.lenientInt(forKey: .status)
        api = c.lenient(String.self, forKey: .api)
        count = c.lenientInt(forKey: .count)
    }
}

/// The extent of a feed's events.
public struct BoundingBox: Hashable, Sendable {
    public var southWest: GeoCoordinate
    public var northEast: GeoCoordinate
    public var minDepth: Double
    public var maxDepth: Double

    public init(southWest: GeoCoordinate, northEast: GeoCoordinate, minDepth: Double, maxDepth: Double) {
        self.southWest = southWest
        self.northEast = northEast
        self.minDepth = minDepth
        self.maxDepth = maxDepth
    }

    /// From GeoJSON's six numbers, or four without depths.
    public init?(values: [Double]) {
        switch values.count {
        case 6:
            self.init(
                southWest: GeoCoordinate(latitude: values[1], longitude: values[0]),
                northEast: GeoCoordinate(latitude: values[4], longitude: values[3]),
                minDepth: values[2], maxDepth: values[5]
            )
        case 4:
            self.init(
                southWest: GeoCoordinate(latitude: values[1], longitude: values[0]),
                northEast: GeoCoordinate(latitude: values[3], longitude: values[2]),
                minDepth: 0, maxDepth: 0
            )
        default:
            return nil
        }
    }

    public var center: GeoCoordinate {
        GeoCoordinate(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }
}

/// Orders for a list of events.
public enum EarthquakeOrder: String, CaseIterable, Sendable, Identifiable {
    /// Newest first.
    case newest
    /// Oldest first.
    case oldest
    /// Largest magnitude first.
    case largest
    /// Smallest magnitude first.
    case smallest
    /// Shallowest first.
    case shallowest
    /// Deepest first.
    case deepest

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .largest: "Largest"
        case .smallest: "Smallest"
        case .shallowest: "Shallowest"
        case .deepest: "Deepest"
        }
    }
}

extension Sequence where Element == Earthquake {
    /// The events sorted by `order`; ties keep the newest first.
    public func sorted(by order: EarthquakeOrder) -> [Earthquake] {
        sorted { a, b in
            let magA = a.magnitude ?? -10, magB = b.magnitude ?? -10
            switch order {
            case .newest: return a.time > b.time
            case .oldest: return a.time < b.time
            case .largest: return magA != magB ? magA > magB : a.time > b.time
            case .smallest: return magA != magB ? magA < magB : a.time > b.time
            case .shallowest: return a.depthKilometers != b.depthKilometers ? a.depthKilometers < b.depthKilometers : a.time > b.time
            case .deepest: return a.depthKilometers != b.depthKilometers ? a.depthKilometers > b.depthKilometers : a.time > b.time
            }
        }
    }

    /// The events sorted by the distance of their epicenters from `point`, nearest first.
    public func sorted(byDistanceFrom point: GeoCoordinate) -> [Earthquake] {
        map { ($0, $0.coordinate.distance(to: point)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The events with an epicenter within `radiusKilometers` of `point`.
    public func within(_ radiusKilometers: Double, of point: GeoCoordinate) -> [Earthquake] {
        filter { $0.coordinate.distance(to: point) <= radiusKilometers }
    }

    /// Other events within `radiusKilometers` of `event`'s epicenter, nearest first, with their
    /// distance and the compass direction from `event`.
    public func neighbors(of event: Earthquake, within radiusKilometers: Double) -> [(earthquake: Earthquake, distance: QuakeDistance, direction: CompassPoint)] {
        compactMap { other -> (earthquake: Earthquake, distance: QuakeDistance, direction: CompassPoint)? in
            guard other.id != event.id else { return nil }
            let kilometers = event.coordinate.distance(to: other.coordinate)
            guard kilometers <= radiusKilometers else { return nil }
            return (other, QuakeDistance(kilometers: kilometers), CompassPoint(bearing: event.coordinate.bearing(to: other.coordinate)))
        }
        .sorted { $0.distance < $1.distance }
    }
}
