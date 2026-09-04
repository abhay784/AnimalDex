import Foundation

/// Where the backend lives.
enum APIConfig {
    /// The Simulator shares the host's network stack, so `localhost` reaches the
    /// services running on the Mac. A real device needs the Mac's LAN address,
    /// which is why this is overridable rather than hard-coded.
    static var coreAPI: URL {
        if let override = ProcessInfo.processInfo.environment["ANIMALDEX_API"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    static var mediaAPI: URL {
        if let override = ProcessInfo.processInfo.environment["ANIMALDEX_MEDIA"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8081")!
    }

    /// Decoder shared by every response.
    ///
    /// Postgres returns timestamps with microsecond precision
    /// (`2026-09-04T00:33:53.129949Z`), which `.iso8601` rejects outright — it
    /// only accepts whole seconds. Hence the custom strategy that tries the
    /// fractional formatter first.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) ?? plain.date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date: \(text)")
            )
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()
}
