import Foundation

/// The alert level of the USGS PAGER system (Prompt Assessment of Global Earthquakes for
/// Response): the expected fatalities and economic losses, from green to red.
public enum AlertLevel: String, CaseIterable, Sendable, Codable, Comparable, CustomStringConvertible {
    case green
    case yellow
    case orange
    case red

    /// Reads `"green"`, `"Yellow"`, `" RED "`; nil for anything else.
    public init?(text: String) {
        self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let level = AlertLevel(text: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown alert level \(text)"))
        }
        self = level
    }

    public var name: String { rawValue.capitalized }

    /// What the level means for the response, as PAGER defines it.
    public var response: String {
        switch self {
        case .green: "No response needed"
        case .yellow: "Local or regional response"
        case .orange: "National response"
        case .red: "International response"
        }
    }

    /// The estimated fatalities that set the level.
    public var estimatedFatalities: String {
        switch self {
        case .green: "0"
        case .yellow: "1–99"
        case .orange: "100–999"
        case .red: "1,000+"
        }
    }

    /// The estimated losses in US dollars that set the level.
    public var estimatedLosses: String {
        switch self {
        case .green: "< $1 million"
        case .yellow: "$1 million – $100 million"
        case .orange: "$100 million – $1 billion"
        case .red: "$1 billion+"
        }
    }

    /// The color of the level.
    public var color: QuakeColor {
        switch self {
        case .green: QuakeColor(hex: 0x2EA44F)
        case .yellow: QuakeColor(hex: 0xF2C200)
        case .orange: QuakeColor(hex: 0xF07F13)
        case .red: QuakeColor(hex: 0xD0202E)
        }
    }

    public var description: String { name }

    private var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        lhs.order < rhs.order
    }
}

/// Whether an event was reviewed by a seismologist or located automatically.
public enum ReviewStatus: String, Sendable, Codable, CustomStringConvertible {
    case automatic
    case reviewed
    case deleted

    public var description: String { rawValue }
}
