import Foundation

/// Errors thrown by ``QuakeClient``.
public enum QuakeError: Error, Equatable, Sendable, LocalizedError {
    /// Nothing exists at this address (HTTP 404), such as an unknown event id.
    case notFound(url: URL)
    /// The service refused the query (HTTP 400) and said why, such as
    /// `"Bad minmagnitude value 'x'"`.
    case badRequest(message: String, url: URL)
    /// Any other unsuccessful HTTP status.
    case http(statusCode: Int, message: String?, url: URL)
    /// The response was not GeoJSON of the expected shape.
    case decoding(type: String, description: String)
    /// The request could not be completed (offline, timed out, cancelled…).
    case transport(URLError)
    /// The response was not an HTTP response.
    case invalidResponse
    /// The query can't be sent as asked; nothing was sent.
    case invalidQuery(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "The USGS has no event or feed at this address."
        case let .badRequest(message, _):
            return message.isEmpty ? "The USGS refused the query." : message
        case let .http(statusCode, message, _):
            if let message, !message.isEmpty {
                return "The USGS answered with HTTP status \(statusCode): \(message)"
            }
            return "The USGS answered with HTTP status \(statusCode)."
        case let .decoding(type, _):
            return "The USGS sent data that could not be read as \(type)."
        case let .transport(error):
            return error.localizedDescription
        case .invalidResponse:
            return "The USGS sent an invalid response."
        case let .invalidQuery(reason):
            return reason
        }
    }

    /// The HTTP status of a `.notFound`, `.badRequest` or `.http` error.
    public var statusCode: Int? {
        switch self {
        case .notFound: 404
        case .badRequest: 400
        case let .http(status, _, _): status
        default: nil
        }
    }

    /// The message of an FDSN error body, which is plain text such as
    /// `"Error 400: Bad Request\n\nBad minmagnitude value \"x\".\n\nUsage details…"`: the first
    /// line after the status line.
    static func message(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.hasPrefix("<")
        else { return nil }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = lines.first, first.hasPrefix("Error "), lines.count > 1 {
            return lines[1]
        }
        return lines.first
    }
}
