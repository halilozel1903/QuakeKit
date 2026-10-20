import Foundation

/// One of the USGS real-time summary feeds,
/// `…/earthquakes/feed/v1.0/summary/{magnitude}_{period}.geojson`. They are regenerated every
/// minute.
public struct SummaryFeed: Hashable, Sendable, Identifiable, CustomStringConvertible {
    public var magnitude: FeedMagnitude
    public var period: FeedPeriod

    public init(_ magnitude: FeedMagnitude, _ period: FeedPeriod) {
        self.magnitude = magnitude
        self.period = period
    }

    /// `"4.5_week"`.
    public var id: String { magnitude.rawValue + "_" + period.rawValue }

    /// `"4.5_week.geojson"`.
    public var fileName: String { id + ".geojson" }

    /// `"M4.5+ · Past Week"`.
    public var title: String { magnitude.title + " · " + period.title }

    public var description: String { id }

    /// The feed's URL below `base`.
    public func url(base: URL = QuakeConfiguration.defaultFeedBaseURL) -> URL {
        base.appendingPathComponent(fileName)
    }

    /// Every combination: 5 magnitudes × 4 periods.
    public static var all: [SummaryFeed] {
        FeedMagnitude.allCases.flatMap { magnitude in FeedPeriod.allCases.map { SummaryFeed(magnitude, $0) } }
    }

    public static let significantMonth = SummaryFeed(.significant, .month)
    public static let m45Week = SummaryFeed(.m4_5, .week)
    public static let m25Day = SummaryFeed(.m2_5, .day)
    public static let allHour = SummaryFeed(.all, .hour)
}

/// The magnitude threshold of a summary feed.
public enum FeedMagnitude: String, CaseIterable, Sendable, Identifiable {
    /// Every event, of any magnitude.
    case all = "all"
    /// Events the USGS deems significant (a significance of 600 or more).
    case significant = "significant"
    /// Magnitude 4.5 and above.
    case m4_5 = "4.5"
    /// Magnitude 2.5 and above.
    case m2_5 = "2.5"
    /// Magnitude 1.0 and above.
    case m1_0 = "1.0"

    public var id: String { rawValue }

    /// The lowest magnitude in the feed, nil for `all` and `significant`.
    public var minimumMagnitude: Double? {
        switch self {
        case .all, .significant: nil
        case .m4_5: 4.5
        case .m2_5: 2.5
        case .m1_0: 1.0
        }
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .significant: "Significant"
        case .m4_5: "M4.5+"
        case .m2_5: "M2.5+"
        case .m1_0: "M1.0+"
        }
    }
}

/// The time span of a summary feed.
public enum FeedPeriod: String, CaseIterable, Sendable, Identifiable {
    case hour
    case day
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hour: "Past Hour"
        case .day: "Past Day"
        case .week: "Past 7 Days"
        case .month: "Past 30 Days"
        }
    }

    /// The span in seconds.
    public var duration: TimeInterval {
        switch self {
        case .hour: 3600
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }
}
