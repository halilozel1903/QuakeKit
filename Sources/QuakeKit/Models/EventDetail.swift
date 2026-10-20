import Foundation

/// The detail of one event: the GeoJSON `Feature` of its detail feed (the `detail` URL of a
/// summary event, or an FDSN query by `eventid`), with every product contributed to it.
public struct EventDetail: Identifiable, Hashable, Sendable, Decodable {
    public var id: String
    /// The same properties as in a summary feed.
    public var properties: EarthquakeProperties
    public var location: Hypocenter
    /// Products by type, such as `origin`, `dyfi`, `losspager`, `shakemap` or `moment-tensor`.
    /// Each list is ordered by preference, the preferred product first.
    public var products: [String: [EventProduct]]

    public init(id: String, properties: EarthquakeProperties, location: Hypocenter, products: [String: [EventProduct]] = [:]) {
        self.id = id
        self.properties = properties
        self.location = location
        self.products = products
    }

    private enum CodingKeys: String, CodingKey {
        case type, id, properties, geometry
    }

    private enum ProductKeys: String, CodingKey {
        case products
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = container.lenient(String.self, forKey: .type)
        guard type == nil || type == "Feature" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected a Feature, got \(type ?? "")")
        }
        properties = try container.decode(EarthquakeProperties.self, forKey: .properties)
        location = try container.decode(Hypocenter.self, forKey: .geometry)
        id = container.lenient(String.self, forKey: .id) ?? ((properties.network ?? "") + (properties.code ?? ""))
        let nested = try? container.nestedContainer(keyedBy: ProductKeys.self, forKey: .properties)
        let raw = nested?.lenient([String: LossyArray<EventProduct>].self, forKey: .products) ?? [:]
        products = raw.mapValues { list in
            list.elements.sorted { lhs, rhs in
                if lhs.preferredWeight != rhs.preferredWeight {
                    return (lhs.preferredWeight ?? 0) > (rhs.preferredWeight ?? 0)
                }
                return (lhs.updateTime ?? .distantPast) > (rhs.updateTime ?? .distantPast)
            }
        }
    }

    /// The event as it appears in a summary feed.
    public var earthquake: Earthquake {
        Earthquake(id: id, properties: properties, location: location)
    }

    /// The preferred product of a type, such as `preferredProduct("shakemap")`.
    public func preferredProduct(_ type: String) -> EventProduct? {
        products[type]?.first { $0.status?.uppercased() != "DELETE" }
    }

    // MARK: - Summaries

    /// The preferred `origin` product: the location solution with its quality numbers.
    public var origin: EventProduct? { preferredProduct("origin") }
    /// The preferred `dyfi` ("Did You Feel It?") product.
    public var dyfi: EventProduct? { preferredProduct("dyfi") }
    /// The preferred `losspager` (PAGER) product.
    public var pager: EventProduct? { preferredProduct("losspager") }
    /// The preferred `shakemap` product.
    public var shakemap: EventProduct? { preferredProduct("shakemap") }
    /// The preferred `moment-tensor` product.
    public var momentTensor: EventProduct? { preferredProduct("moment-tensor") }

    /// The number of "Did You Feel It?" reports: `felt`, or the DYFI product's `num-responses`.
    public var feltReports: Int? {
        properties.felt ?? dyfi?.int("num-responses") ?? dyfi?.int("numResp")
    }

    /// The highest intensity people reported (Community Decimal Intensity).
    public var maxReportedIntensity: Double? {
        properties.cdi ?? dyfi?.double("maxmmi")
    }

    /// The highest intensity ShakeMap estimated.
    public var maxEstimatedIntensity: Double? {
        properties.mmi ?? shakemap?.double("maxmmi")
    }

    /// Whether the USGS set the tsunami flag for the event.
    public var hasTsunamiFlag: Bool { properties.tsunami }

    /// The PAGER alert level: `alert`, or the PAGER product's `alertlevel`.
    public var alertLevel: AlertLevel? {
        properties.alert ?? pager?.string("alertlevel").flatMap(AlertLevel.init(text:))
    }

    /// The ShakeMap intensity map image, when there is one.
    public var shakemapIntensityImageURL: URL? {
        shakemap?.contents["download/intensity.jpg"]?.url
    }

    /// The magnitude type of the preferred origin, or of the event.
    public var magnitudeType: String? {
        origin?.string("magnitude-type") ?? properties.magnitudeType
    }

    /// Stations used by the preferred origin.
    public var stationsUsed: Int? {
        origin?.int("num-stations-used") ?? properties.stationCount
    }

    /// The azimuthal gap of the preferred origin, in degrees.
    public var azimuthalGap: Double? {
        origin?.double("azimuthal-gap") ?? properties.gap
    }

    /// The horizontal location uncertainty of the preferred origin, in kilometers.
    public var horizontalErrorKilometers: Double? {
        origin?.double("horizontal-error")
    }

    /// The depth uncertainty of the preferred origin, in kilometers.
    public var depthErrorKilometers: Double? {
        origin?.double("vertical-error")
    }

    /// Every product type the event has, sorted.
    public var productTypes: [String] {
        products.keys.sorted()
    }
}

/// A product contributed to an event by a network: an origin, a ShakeMap, a PAGER estimate…
/// All of its `properties` are text in the feed; read them with ``string(_:)``,
/// ``double(_:)`` and ``int(_:)``.
public struct EventProduct: Hashable, Sendable, Decodable, Identifiable {
    /// Such as `urn:usgs-product:us:origin:us7000n7n8:1712108215040`.
    public var id: String
    public var type: String
    public var code: String?
    /// The network that sent it.
    public var source: String?
    /// `UPDATE` or `DELETE`.
    public var status: String?
    public var updateTime: Date?
    /// How strongly the product is preferred; the highest wins.
    public var preferredWeight: Int?
    public var properties: [String: String]
    /// Files of the product, by path, such as `download/intensity.jpg`.
    public var contents: [String: ProductContent]

    public init(
        id: String,
        type: String,
        code: String? = nil,
        source: String? = nil,
        status: String? = "UPDATE",
        updateTime: Date? = nil,
        preferredWeight: Int? = nil,
        properties: [String: String] = [:],
        contents: [String: ProductContent] = [:]
    ) {
        self.id = id
        self.type = type
        self.code = code
        self.source = source
        self.status = status
        self.updateTime = updateTime
        self.preferredWeight = preferredWeight
        self.properties = properties
        self.contents = contents
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, code, source, status, updateTime, preferredWeight, properties, contents
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        code = c.lenient(String.self, forKey: .code)
        source = c.lenient(String.self, forKey: .source)
        id = c.lenient(String.self, forKey: .id) ?? [source ?? "", type, code ?? ""].joined(separator: ":")
        status = c.lenient(String.self, forKey: .status)
        updateTime = c.lenientMilliseconds(forKey: .updateTime)
        preferredWeight = c.lenientInt(forKey: .preferredWeight)
        let raw = c.lenient([String: ScalarText].self, forKey: .properties) ?? [:]
        properties = raw.compactMapValues(\.value)
        contents = c.lenient([String: ProductContent].self, forKey: .contents) ?? [:]
    }

    public func string(_ key: String) -> String? {
        guard let value = properties[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    public func double(_ key: String) -> Double? {
        string(key).flatMap(Double.init)
    }

    public func int(_ key: String) -> Int? {
        guard let text = string(key) else { return nil }
        if let value = Int(text) { return value }
        if let value = Double(text), value.rounded() == value, abs(value) < 1e15 { return Int(value) }
        return nil
    }
}

/// A file of a product.
public struct ProductContent: Hashable, Sendable, Decodable {
    public var contentType: String?
    public var length: Int?
    public var lastModified: Date?
    public var url: URL?

    public init(contentType: String? = nil, length: Int? = nil, lastModified: Date? = nil, url: URL? = nil) {
        self.contentType = contentType
        self.length = length
        self.lastModified = lastModified
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case contentType, length, lastModified, url
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contentType = c.lenient(String.self, forKey: .contentType)
        length = c.lenientInt(forKey: .length)
        lastModified = c.lenientMilliseconds(forKey: .lastModified)
        url = c.lenientURL(forKey: .url)
    }
}

/// The answer of the FDSN `count` method: how many events match a query.
public struct EventCount: Hashable, Sendable, Decodable {
    public var count: Int
    /// The most events one query may return (20,000).
    public var maxAllowed: Int?

    public init(count: Int, maxAllowed: Int? = nil) {
        self.count = count
        self.maxAllowed = maxAllowed
    }

    /// Whether a query for every match would exceed ``maxAllowed``.
    public var exceedsLimit: Bool {
        guard let maxAllowed else { return false }
        return count > maxAllowed
    }
}
