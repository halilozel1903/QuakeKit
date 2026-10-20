import Foundation

/// The Modified Mercalli Intensity scale, I to X+, used by "Did You Feel It?" (`cdi`) and
/// ShakeMap (`mmi`).
public enum MercalliIntensity {
    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
    private static let shakingNames = [
        "Not felt", "Weak", "Weak", "Light", "Moderate",
        "Strong", "Very strong", "Severe", "Violent", "Extreme",
    ]

    /// The roman numeral of an intensity, rounded to the nearest level: 5.6 is `VI`. Values from
    /// 10 up are `X+`.
    public static func roman(_ intensity: Double) -> String {
        let level = self.level(intensity)
        return level >= 10 && intensity >= 10.5 ? "X+" : numerals[level - 1]
    }

    /// The perceived shaking of an intensity, such as `"Strong"` for VI.
    public static func shaking(_ intensity: Double) -> String {
        shakingNames[level(intensity) - 1]
    }

    /// The intensity rounded and clamped to 1...10.
    public static func level(_ intensity: Double) -> Int {
        guard intensity.isFinite else { return 1 }
        return min(10, max(1, Int(intensity.rounded())))
    }
}
