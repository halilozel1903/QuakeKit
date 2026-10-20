import Foundation

/// A query of the FDSN event web service,
/// `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&…`, which searches the whole
/// ComCat catalog.
///
/// ```swift
/// var query = EventQuery(start: .now.addingTimeInterval(-30 * 86_400), minMagnitude: 5)
/// query.area = .circle(center: GeoCoordinate(latitude: 35.68, longitude: 139.77), radiusKilometers: 500)
/// query.orderBy = .magnitude
/// query.limit = 50
/// ```
public struct EventQuery: Hashable, Sendable {
    /// Events at or after this time. The service's default is 30 days ago.
    public var startTime: Date?
    /// Events at or before this time. The service's default is now.
    public var endTime: Date?
    public var minMagnitude: Double?
    public var maxMagnitude: Double?
    /// In kilometers; -100 to 1000.
    public var minDepth: Double?
    public var maxDepth: Double?
    /// A circle or rectangle the epicenters must be in.
    public var area: Area?
    /// At most this many events, 1 to 20,000.
    public var limit: Int?
    /// The first event to return, counting from 1.
    public var offset: Int?
    public var orderBy: Order?
    /// Only events with this PAGER alert level.
    public var alertLevel: AlertLevel?
    /// Only events with at least this many "Did You Feel It?" reports.
    public var minFelt: Int?
    /// Only events of this type, such as `earthquake` or `explosion`.
    public var eventType: String?
    /// Only events that have a product of this type, such as `shakemap`.
    public var productType: String?
    /// Only events with at least this significance.
    public var minSignificance: Int?

    public init(
        start: Date? = nil,
        end: Date? = nil,
        minMagnitude: Double? = nil,
        maxMagnitude: Double? = nil,
        area: Area? = nil,
        limit: Int? = nil,
        orderBy: Order? = nil
    ) {
        startTime = start
        endTime = end
        self.minMagnitude = minMagnitude
        self.maxMagnitude = maxMagnitude
        self.area = area
        self.limit = limit
        self.orderBy = orderBy
    }

    /// Events of the last `days` days, newest first.
    public static func recent(days: Double, minMagnitude: Double? = nil, limit: Int? = nil, now: Date = Date()) -> EventQuery {
        EventQuery(start: now.addingTimeInterval(-days * 86_400), end: nil, minMagnitude: minMagnitude, limit: limit, orderBy: .time)
    }

    /// Events within `radiusKilometers` of `center` in the last `days` days.
    public static func around(_ center: GeoCoordinate, radiusKilometers: Double, days: Double = 30, minMagnitude: Double? = nil, limit: Int? = nil, now: Date = Date()) -> EventQuery {
        EventQuery(
            start: now.addingTimeInterval(-days * 86_400),
            minMagnitude: minMagnitude,
            area: .circle(center: center, radiusKilometers: radiusKilometers),
            limit: limit,
            orderBy: .time
        )
    }

    /// The region epicenters must lie in.
    public enum Area: Hashable, Sendable {
        /// Within `radiusKilometers` (up to 20,001.6 km) of `center`.
        case circle(center: GeoCoordinate, radiusKilometers: Double)
        /// Between two latitudes and two longitudes. A rectangle may cross the antimeridian with
        /// `minLongitude` greater than `maxLongitude`.
        case rectangle(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double)
    }

    /// The order of the results.
    public enum Order: String, Sendable, CaseIterable {
        /// Newest first (the default).
        case time
        /// Oldest first.
        case timeAscending = "time-asc"
        /// Largest first.
        case magnitude
        /// Smallest first.
        case magnitudeAscending = "magnitude-asc"
    }

    /// The most events one query may return.
    public static let maximumLimit = 20_000
    /// Half the Earth's circumference: the largest useful search radius.
    public static let maximumRadiusKilometers = 20_001.6

    /// Why the service would refuse this query, or nil when it is valid.
    public var problem: String? {
        if let startTime, let endTime, startTime > endTime {
            return "The start time is after the end time."
        }
        if let minMagnitude, let maxMagnitude, minMagnitude > maxMagnitude {
            return "The minimum magnitude is larger than the maximum."
        }
        if let minDepth, !(-100...1000).contains(minDepth) {
            return "The minimum depth must be between -100 and 1000 km."
        }
        if let maxDepth, !(-100...1000).contains(maxDepth) {
            return "The maximum depth must be between -100 and 1000 km."
        }
        if let minDepth, let maxDepth, minDepth > maxDepth {
            return "The minimum depth is larger than the maximum."
        }
        if let limit, !(1...Self.maximumLimit).contains(limit) {
            return "The limit must be between 1 and \(Self.maximumLimit)."
        }
        if let offset, offset < 1 {
            return "The offset counts from 1."
        }
        if let minFelt, minFelt < 1 {
            return "The minimum number of felt reports must be at least 1."
        }
        switch area {
        case let .circle(center, radius):
            if !center.isValid {
                return "The center of the search circle is not a valid coordinate."
            }
            if !(radius > 0 && radius <= Self.maximumRadiusKilometers) {
                return "The radius must be more than 0 and at most 20,001.6 km."
            }
        case let .rectangle(minLatitude, maxLatitude, minLongitude, maxLongitude):
            if !(-90...90).contains(minLatitude) || !(-90...90).contains(maxLatitude) || minLatitude > maxLatitude {
                return "The rectangle's latitudes must be between -90 and 90, the minimum first."
            }
            if !(-360...360).contains(minLongitude) || !(-360...360).contains(maxLongitude) {
                return "The rectangle's longitudes must be between -360 and 360."
            }
        case nil:
            break
        }
        return nil
    }

    /// The query parameters, without `format`. `includePaging` adds `limit`, `offset` and
    /// `orderby`, which the `count` method does not take.
    public func queryItems(includePaging: Bool = true) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value { items.append(URLQueryItem(name: name, value: value)) }
        }
        add("starttime", startTime.map(QuakeTime.queryString))
        add("endtime", endTime.map(QuakeTime.queryString))
        add("minmagnitude", minMagnitude.map(Self.number))
        add("maxmagnitude", maxMagnitude.map(Self.number))
        add("mindepth", minDepth.map(Self.number))
        add("maxdepth", maxDepth.map(Self.number))
        switch area {
        case let .circle(center, radius):
            add("latitude", Self.number(center.latitude))
            add("longitude", Self.number(center.longitude))
            add("maxradiuskm", Self.number(radius))
        case let .rectangle(minLatitude, maxLatitude, minLongitude, maxLongitude):
            add("minlatitude", Self.number(minLatitude))
            add("maxlatitude", Self.number(maxLatitude))
            add("minlongitude", Self.number(minLongitude))
            add("maxlongitude", Self.number(maxLongitude))
        case nil:
            break
        }
        add("alertlevel", alertLevel?.rawValue)
        add("minfelt", minFelt.map { String($0) })
        add("eventtype", eventType)
        add("producttype", productType)
        add("minsig", minSignificance.map { String($0) })
        if includePaging {
            add("limit", limit.map { String($0) })
            add("offset", offset.map { String($0) })
            add("orderby", orderBy?.rawValue)
        }
        return items
    }

    /// A number without trailing zeros and in the C locale: `4.5`, `500`, `-122.4194`.
    static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
