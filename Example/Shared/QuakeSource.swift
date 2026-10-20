import Foundation
import QuakeKit

/// What the sidebar can select: a live summary feed by magnitude, or a catalog search.
enum SidebarItem: Hashable {
    case feed(FeedMagnitude)
    case catalog(CatalogSearch)
}

/// Searches of the whole catalog through the FDSN event service.
enum CatalogSearch: String, CaseIterable, Identifiable, Hashable {
    /// Magnitude 6 and above anywhere, in the past year.
    case strongYear
    /// Magnitude 4.5 and above within 600 km of Tokyo, in the past 90 days.
    case japan
    /// Magnitude 2.5 and above within 250 km of San Francisco, in the past 30 days.
    case california
    /// Events with a significance of 600 or more, in the past two years.
    case significant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strongYear: "M6+ · Past Year"
        case .japan: "Near Tokyo · 90 Days"
        case .california: "Bay Area · 30 Days"
        case .significant: "Significant · 2 Years"
        }
    }

    var systemImage: String {
        switch self {
        case .strongYear: "bolt.fill"
        case .japan: "mappin.and.ellipse"
        case .california: "mappin.and.ellipse"
        case .significant: "star.fill"
        }
    }

    static let tokyo = GeoCoordinate(latitude: 35.6812, longitude: 139.7671)
    static let sanFrancisco = GeoCoordinate(latitude: 37.7749, longitude: -122.4194)

    /// The query, at most 400 events.
    func query(now: Date = Date()) -> EventQuery {
        switch self {
        case .strongYear:
            return EventQuery.recent(days: 365, minMagnitude: 6, limit: 400, now: now)
        case .japan:
            return EventQuery.around(Self.tokyo, radiusKilometers: 600, days: 90, minMagnitude: 4.5, limit: 400, now: now)
        case .california:
            return EventQuery.around(Self.sanFrancisco, radiusKilometers: 250, days: 30, minMagnitude: 2.5, limit: 400, now: now)
        case .significant:
            var query = EventQuery.recent(days: 730, limit: 400, now: now)
            query.minSignificance = 600
            return query
        }
    }
}
