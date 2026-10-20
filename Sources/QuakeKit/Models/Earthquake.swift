import Foundation

/// One event of a USGS GeoJSON feed or FDSN query: a GeoJSON `Feature` with a `Point` geometry.
public struct Earthquake: Identifiable, Hashable, Sendable, Decodable {
    /// The preferred event id, such as `us7000n7n8`.
    public var id: String
    public var properties: EarthquakeProperties
    /// The epicenter and the depth of the hypocenter.
    public var location: Hypocenter

    public init(id: String, properties: EarthquakeProperties, location: Hypocenter) {
        self.id = id
        self.properties = properties
        self.location = location
    }

    private enum CodingKeys: String, CodingKey {
        case id, properties, geometry
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        properties = try container.decode(EarthquakeProperties.self, forKey: .properties)
        location = try container.decode(Hypocenter.self, forKey: .geometry)
        if let id = container.lenient(String.self, forKey: .id), !id.isEmpty {
            self.id = id
        } else if let net = properties.network, let code = properties.code {
            self.id = net + code
        } else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: decoder.codingPath, debugDescription: "A feature without an id"))
        }
    }

    // MARK: - Shortcuts

    /// The magnitude, or nil when the event has none yet.
    public var magnitude: Double? { properties.magnitude }
    /// Where it happened, such as `"10 km SSW of Hualien City, Taiwan"`.
    public var place: String { properties.place ?? properties.title ?? id }
    /// The origin time.
    public var time: Date { properties.time }
    public var coordinate: GeoCoordinate { location.coordinate }
    public var depthKilometers: Double { location.depthKilometers }
    /// The PAGER alert level, when PAGER has assessed the event.
    public var alertLevel: AlertLevel? { properties.alert }
    /// Whether the event is in an oceanic region large enough that the USGS links to NOAA's
    /// tsunami warning centers. It does not mean a tsunami exists.
    public var hasTsunamiFlag: Bool { properties.tsunami }
    /// The number of "Did You Feel It?" reports.
    public var feltReports: Int? { properties.felt }
    /// The magnitude class.
    public var magnitudeClass: MagnitudeClass { MagnitudeClass(magnitude: magnitude ?? 0) }
    /// The scale's color for the magnitude.
    public var color: QuakeColor { MagnitudeScale.color(for: magnitude ?? 0) }

    /// `"M 4.6"`, or `"M ?"` without a magnitude.
    public var magnitudeLabel: String {
        guard let magnitude else { return "M ?" }
        return String(format: "M %.1f", magnitude)
    }

    /// The distance from the epicenter to `point`.
    public func distance(from point: GeoCoordinate) -> QuakeDistance {
        QuakeDistance(kilometers: coordinate.distance(to: point))
    }

    /// The distance between two epicenters.
    public func distance(to other: Earthquake) -> QuakeDistance {
        distance(from: other.coordinate)
    }
}

/// The epicenter and depth from a GeoJSON `Point` of `[longitude, latitude, depth]`.
public struct Hypocenter: Hashable, Sendable, Decodable {
    public var coordinate: GeoCoordinate
    /// Depth below the surface in kilometers. Negative values (above sea level) occur for events
    /// in mountains.
    public var depthKilometers: Double

    public init(coordinate: GeoCoordinate, depthKilometers: Double) {
        self.coordinate = coordinate
        self.depthKilometers = depthKilometers
    }

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let values = try container.decode([Double?].self, forKey: .coordinates)
        guard values.count >= 2, let longitude = values[0], let latitude = values[1] else {
            throw DecodingError.dataCorruptedError(forKey: .coordinates, in: container, debugDescription: "A point needs a longitude and a latitude")
        }
        coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        depthKilometers = (values.count > 2 ? values[2] : nil) ?? 0
    }

    /// `"10.0 km deep"`.
    public var depthLabel: String {
        String(format: "%.1f km deep", depthKilometers)
    }

    /// Shallow (0–70 km), intermediate (70–300 km) or deep (300 km and more).
    public var depthClass: DepthClass {
        DepthClass(kilometers: depthKilometers)
    }
}

/// The usual depth ranges of earthquakes.
public enum DepthClass: String, Sendable, CaseIterable {
    case shallow
    case intermediate
    case deep

    public init(kilometers: Double) {
        switch kilometers {
        case ..<70: self = .shallow
        case ..<300: self = .intermediate
        default: self = .deep
        }
    }
}

/// The `properties` of an event in a summary feed or FDSN query response.
public struct EarthquakeProperties: Hashable, Sendable, Decodable {
    /// `mag`.
    public var magnitude: Double?
    /// `magType`, such as `mww`, `mb` or `ml`.
    public var magnitudeType: String?
    public var place: String?
    /// The origin time (`time`, milliseconds since 1970).
    public var time: Date
    /// When the event was last changed (`updated`).
    public var updated: Date?
    /// The event page on earthquake.usgs.gov.
    public var url: URL?
    /// The GeoJSON detail feed of the event, with its products.
    public var detail: URL?
    /// The number of "Did You Feel It?" reports (`felt`).
    public var felt: Int?
    /// The highest reported intensity from "Did You Feel It?" (`cdi`), on the Modified Mercalli scale.
    public var cdi: Double?
    /// The highest intensity estimated by ShakeMap (`mmi`).
    public var mmi: Double?
    /// The PAGER alert level (`alert`).
    public var alert: AlertLevel?
    /// `status`: automatic, reviewed or deleted.
    public var status: ReviewStatus?
    /// The `tsunami` flag: 1 for events in oceanic regions that NOAA's tsunami centers cover.
    public var tsunami: Bool
    /// `sig`, 0 to 1000+: how significant the event is, from magnitude, felt reports and alerts.
    public var significance: Int?
    /// `net`: the network that contributed the preferred solution, such as `us` or `ak`.
    public var network: String?
    /// `code`: the id within that network.
    public var code: String?
    /// `ids`: every event id this event is known by.
    public var ids: [String]
    /// `sources`: the networks that contributed.
    public var sources: [String]
    /// `types`: the products available, such as `origin`, `dyfi`, `losspager` or `shakemap`.
    public var productTypes: [String]
    /// `nst`: stations used to locate the event.
    public var stationCount: Int?
    /// `dmin`: the distance to the nearest station, in degrees.
    public var minimumDistance: Double?
    /// `rms`: the root-mean-square travel time residual, in seconds.
    public var rms: Double?
    /// `gap`: the largest azimuthal gap between stations, in degrees.
    public var gap: Double?
    /// `type`: `earthquake`, `quarry blast`, `explosion`, `ice quake`…
    public var eventType: String?
    /// `title`, such as `"M 6.1 - 10 km SSW of Hualien City, Taiwan"`.
    public var title: String?

    public init(
        magnitude: Double? = nil,
        magnitudeType: String? = nil,
        place: String? = nil,
        time: Date,
        updated: Date? = nil,
        url: URL? = nil,
        detail: URL? = nil,
        felt: Int? = nil,
        cdi: Double? = nil,
        mmi: Double? = nil,
        alert: AlertLevel? = nil,
        status: ReviewStatus? = nil,
        tsunami: Bool = false,
        significance: Int? = nil,
        network: String? = nil,
        code: String? = nil,
        ids: [String] = [],
        sources: [String] = [],
        productTypes: [String] = [],
        stationCount: Int? = nil,
        minimumDistance: Double? = nil,
        rms: Double? = nil,
        gap: Double? = nil,
        eventType: String? = "earthquake",
        title: String? = nil
    ) {
        self.magnitude = magnitude
        self.magnitudeType = magnitudeType
        self.place = place
        self.time = time
        self.updated = updated
        self.url = url
        self.detail = detail
        self.felt = felt
        self.cdi = cdi
        self.mmi = mmi
        self.alert = alert
        self.status = status
        self.tsunami = tsunami
        self.significance = significance
        self.network = network
        self.code = code
        self.ids = ids
        self.sources = sources
        self.productTypes = productTypes
        self.stationCount = stationCount
        self.minimumDistance = minimumDistance
        self.rms = rms
        self.gap = gap
        self.eventType = eventType
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case mag, magType, place, time, updated, url, detail, felt, cdi, mmi, alert, status, tsunami, sig
        case net, code, ids, sources, types, nst, dmin, rms, gap, type, title
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let time = c.lenientMilliseconds(forKey: .time) else {
            throw DecodingError.keyNotFound(CodingKeys.time, .init(codingPath: decoder.codingPath, debugDescription: "An event without a time"))
        }
        self.time = time
        magnitude = c.lenientDouble(forKey: .mag)
        magnitudeType = c.lenient(String.self, forKey: .magType)
        place = c.lenient(String.self, forKey: .place).flatMap { $0.isEmpty ? nil : $0 }
        updated = c.lenientMilliseconds(forKey: .updated)
        url = c.lenientURL(forKey: .url)
        detail = c.lenientURL(forKey: .detail)
        felt = c.lenientInt(forKey: .felt)
        cdi = c.lenientDouble(forKey: .cdi)
        mmi = c.lenientDouble(forKey: .mmi)
        alert = c.lenient(String.self, forKey: .alert).flatMap(AlertLevel.init(text:))
        status = c.lenient(String.self, forKey: .status).flatMap { ReviewStatus(rawValue: $0.lowercased()) }
        tsunami = (c.lenientInt(forKey: .tsunami) ?? 0) != 0
        significance = c.lenientInt(forKey: .sig)
        network = c.lenient(String.self, forKey: .net)
        code = c.lenient(String.self, forKey: .code)
        ids = c.lenient(String.self, forKey: .ids)?.commaList ?? []
        sources = c.lenient(String.self, forKey: .sources)?.commaList ?? []
        productTypes = c.lenient(String.self, forKey: .types)?.commaList ?? []
        stationCount = c.lenientInt(forKey: .nst)
        minimumDistance = c.lenientDouble(forKey: .dmin)
        rms = c.lenientDouble(forKey: .rms)
        gap = c.lenientDouble(forKey: .gap)
        eventType = c.lenient(String.self, forKey: .type)
        title = c.lenient(String.self, forKey: .title)
    }
}
