import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

/// A point on the Earth in degrees (WGS 84), with great-circle distance and bearing helpers.
public struct GeoCoordinate: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Degrees north of the equator, -90 to 90.
    public var latitude: Double
    /// Degrees east of Greenwich, -180 to 180.
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The mean radius of the Earth used for distances, 6371.0088 km (IUGG).
    public static let earthRadiusKilometers = 6371.0088

    /// Whether the latitude is within ±90° and the longitude within ±180°.
    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// The great-circle distance to `other` in kilometers (haversine formula).
    public func distance(to other: GeoCoordinate) -> Double {
        let lat1 = latitude.radians, lat2 = other.latitude.radians
        let dLat = (other.latitude - latitude).radians
        let dLon = (other.longitude - longitude).radians
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return Self.earthRadiusKilometers * c
    }

    /// The initial bearing from this point to `other`, in degrees clockwise from north, 0 up to 360.
    public func bearing(to other: GeoCoordinate) -> Double {
        let lat1 = latitude.radians, lat2 = other.latitude.radians
        let dLon = (other.longitude - longitude).radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    /// The point `kilometers` away along `bearing` (degrees clockwise from north).
    public func destination(kilometers: Double, bearing: Double) -> GeoCoordinate {
        let angular = kilometers / Self.earthRadiusKilometers
        let theta = bearing.radians
        let lat1 = latitude.radians, lon1 = longitude.radians
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        var longitude = lon2 * 180 / .pi
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeoCoordinate(latitude: lat2 * 180 / .pi, longitude: longitude)
    }

    /// Whether `other` is within `radiusKilometers` of this point.
    public func isWithin(_ radiusKilometers: Double, of other: GeoCoordinate) -> Bool {
        distance(to: other) <= radiusKilometers
    }

    /// `35.6812° N, 139.7671° E`.
    public var description: String {
        let ns = latitude >= 0 ? "N" : "S"
        let ew = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", abs(latitude), ns, abs(longitude), ew)
    }
}

/// The sixteen points of the compass.
public enum CompassPoint: String, CaseIterable, Sendable {
    case n = "N", nne = "NNE", ne = "NE", ene = "ENE"
    case e = "E", ese = "ESE", se = "SE", sse = "SSE"
    case s = "S", ssw = "SSW", sw = "SW", wsw = "WSW"
    case w = "W", wnw = "WNW", nw = "NW", nnw = "NNW"

    /// The point nearest to a bearing in degrees.
    public init(bearing: Double) {
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int((positive / 22.5).rounded()) % 16
        self = CompassPoint.allCases[index]
    }
}

/// A distance with conversions and a short label.
public struct QuakeDistance: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var kilometers: Double

    public init(kilometers: Double) {
        self.kilometers = kilometers
    }

    public init(miles: Double) {
        self.kilometers = miles * 1.609344
    }

    public var miles: Double { kilometers / 1.609344 }
    public var meters: Double { kilometers * 1000 }

    /// `850 m`, `12.4 km`, `1,240 km`, or the same in miles.
    public func formatted(miles useMiles: Bool = false) -> String {
        if useMiles {
            return Self.label(miles, unit: "mi")
        }
        if kilometers < 1 {
            return String(format: "%.0f m", meters)
        }
        return Self.label(kilometers, unit: "km")
    }

    public var description: String { formatted() }

    public static func < (lhs: QuakeDistance, rhs: QuakeDistance) -> Bool {
        lhs.kilometers < rhs.kilometers
    }

    private static func label(_ value: Double, unit: String) -> String {
        if value < 100 {
            return String(format: "%.1f %@", value, unit)
        }
        let rounded = Int(value.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        let text = formatter.string(from: NSNumber(value: rounded)) ?? String(rounded)
        return text + " " + unit
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
}

#if canImport(CoreLocation)
extension GeoCoordinate {
    /// The same point as a Core Location coordinate, for MapKit.
    public var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
#endif
