import Foundation

/// An array that skips elements that fail to decode, so one malformed feature doesn't fail a
/// whole feed.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // Step past the element that failed.
                _ = try? container.decode(Skipped.self)
            }
        }
        self.elements = elements
    }

    /// Decodes from any JSON value without reading it, so the container moves to the next element.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

/// A JSON scalar of any type, read as text: USGS product properties are strings, but a number,
/// boolean or null is accepted too.
struct ScalarText: Decodable {
    var value: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : "false"
        } else {
            value = nil
        }
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or nil when it is missing, null or of another type.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// A number that may also arrive as a string, such as `"4.6"`.
    func lenientDouble(forKey key: Key) -> Double? {
        if let value = lenient(Double.self, forKey: key) { return value }
        if let text = lenient(String.self, forKey: key) { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// An integer that may also arrive as a whole double or a string.
    func lenientInt(forKey key: Key) -> Int? {
        if let value = lenient(Int.self, forKey: key) { return value }
        if let value = lenient(Double.self, forKey: key), value.rounded() == value, abs(value) < 1e15 { return Int(value) }
        if let text = lenient(String.self, forKey: key) { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// A time in milliseconds since 1970, as USGS sends `time` and `updated`.
    func lenientMilliseconds(forKey key: Key) -> Date? {
        guard let value = lenientDouble(forKey: key) else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }

    /// A URL that may be missing or empty.
    func lenientURL(forKey key: Key) -> URL? {
        guard let text = lenient(String.self, forKey: key), !text.isEmpty else { return nil }
        return URL(string: text)
    }
}

extension String {
    /// The parts of USGS's comma-wrapped lists such as `",us,ak,"`.
    var commaList: [String] {
        split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
