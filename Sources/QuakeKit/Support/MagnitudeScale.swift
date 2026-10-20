import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// A color as red, green and blue components from 0 to 1, independent of any UI framework.
public struct QuakeColor: Hashable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// A color from a hex value such as `0xF6A13A`.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// `#F6A13A`.
    public var hexString: String {
        String(format: "#%02X%02X%02X", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    public var description: String { hexString }

    /// Relative luminance (WCAG), 0 for black and 1 for white.
    public var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Whether black text reads better on this color than white text.
    public var prefersDarkText: Bool {
        // Contrast with black: (L + 0.05) / 0.05; with white: 1.05 / (L + 0.05).
        (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05)
    }

    /// The color `fraction` of the way from this one to `other`.
    public func mix(with other: QuakeColor, fraction: Double) -> QuakeColor {
        let t = Self.clamp(fraction)
        return QuakeColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func byte(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }
}

/// The classes seismologists use for magnitudes, from micro to great.
public enum MagnitudeClass: Int, CaseIterable, Sendable, Comparable, CustomStringConvertible {
    /// Below 3.0: recorded, rarely felt.
    case micro
    /// 3.0 to 3.9: often felt, rarely causes damage.
    case minor
    /// 4.0 to 4.9: felt by most people nearby, shaking indoors.
    case light
    /// 5.0 to 5.9: can damage poorly built structures.
    case moderate
    /// 6.0 to 6.9: destructive in populated areas.
    case strong
    /// 7.0 to 7.9: serious damage over large areas.
    case major
    /// 8.0 and above: can destroy communities near the epicenter.
    case great

    public init(magnitude: Double) {
        switch magnitude {
        case ..<3: self = .micro
        case ..<4: self = .minor
        case ..<5: self = .light
        case ..<6: self = .moderate
        case ..<7: self = .strong
        case ..<8: self = .major
        default: self = .great
        }
    }

    /// The lowest magnitude of the class (`nil` for micro, which has no floor).
    public var lowerBound: Double? {
        self == .micro ? nil : Double(rawValue + 2)
    }

    public var name: String {
        switch self {
        case .micro: "Micro"
        case .minor: "Minor"
        case .light: "Light"
        case .moderate: "Moderate"
        case .strong: "Strong"
        case .major: "Major"
        case .great: "Great"
        }
    }

    /// `"4.0–4.9"`, `"< 3.0"`, `"8.0+"`.
    public var rangeLabel: String {
        switch self {
        case .micro: "< 3.0"
        case .great: "8.0+"
        default: String(format: "%.1f–%.1f", Double(rawValue + 2), Double(rawValue + 2) + 0.9)
        }
    }

    public var description: String { name }

    public static func < (lhs: MagnitudeClass, rhs: MagnitudeClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Colors and marker sizes for magnitudes: a scale from teal for small events through yellow and
/// orange to red and purple for great ones, and circle sizes that grow with the magnitude.
public enum MagnitudeScale {
    /// The color stops of the scale: a magnitude and the color at it.
    public static let stops: [(magnitude: Double, color: QuakeColor)] = [
        (1, QuakeColor(hex: 0x5FB8A8)),
        (2, QuakeColor(hex: 0x9CCB5B)),
        (3, QuakeColor(hex: 0xF2D338)),
        (4, QuakeColor(hex: 0xF6A13A)),
        (5, QuakeColor(hex: 0xEC6A2E)),
        (6, QuakeColor(hex: 0xD7263D)),
        (7, QuakeColor(hex: 0xA51C5E)),
        (8, QuakeColor(hex: 0x5E2A84)),
    ]

    /// The color of a magnitude, blended between the stops. Below 1 is the first stop's color,
    /// 8 and above the last one's.
    public static func color(for magnitude: Double) -> QuakeColor {
        guard magnitude.isFinite else { return stops[0].color }
        guard let first = stops.first, let last = stops.last else { return QuakeColor(hex: 0x808080) }
        if magnitude <= first.magnitude { return first.color }
        if magnitude >= last.magnitude { return last.color }
        for index in 1..<stops.count {
            let lower = stops[index - 1], upper = stops[index]
            if magnitude == upper.magnitude { return upper.color }
            if magnitude < upper.magnitude {
                let fraction = (magnitude - lower.magnitude) / (upper.magnitude - lower.magnitude)
                return lower.color.mix(with: upper.color, fraction: fraction)
            }
        }
        return last.color
    }

    /// The color of a whole class: the scale's color at the class's lower bound (1.0 for micro).
    public static func color(for magnitudeClass: MagnitudeClass) -> QuakeColor {
        color(for: magnitudeClass.lowerBound ?? 1)
    }

    /// The diameter in points of a map marker: 8 points at magnitude 1 and below, then growing
    /// exponentially (×1.45 per magnitude unit) up to 64 points.
    public static func markerDiameter(for magnitude: Double, minimum: Double = 8, maximum: Double = 64) -> Double {
        guard magnitude.isFinite else { return minimum }
        let size = minimum * pow(1.45, max(0, magnitude - 1))
        return min(maximum, max(minimum, size))
    }

    /// A radius in meters for a circle drawn on the map in real distance, growing tenfold every two
    /// magnitude units: 2 km at magnitude 2, 20 km at 4, 200 km at 6. Useful at regional zoom
    /// levels; ``markerDiameter(for:minimum:maximum:)`` suits world maps.
    public static func radiusMeters(for magnitude: Double) -> Double {
        guard magnitude.isFinite else { return 1000 }
        return 2000 * pow(10, (max(0, magnitude) - 2) / 2)
    }

    /// The energy released, in joules, from the Gutenberg–Richter relation log E = 1.5 M + 4.8.
    public static func energyJoules(for magnitude: Double) -> Double {
        pow(10, 1.5 * magnitude + 4.8)
    }

    /// How many times more energy `magnitude` releases than `other` (about 32 per unit).
    public static func energyRatio(_ magnitude: Double, to other: Double) -> Double {
        pow(10, 1.5 * (magnitude - other))
    }
}

#if canImport(SwiftUI)
extension QuakeColor {
    /// The color for SwiftUI.
    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

extension Color {
    /// The scale's color for a magnitude.
    public static func magnitude(_ magnitude: Double) -> Color {
        MagnitudeScale.color(for: magnitude).color
    }
}
#endif
