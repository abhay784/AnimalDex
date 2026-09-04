import Foundation

/// Where the backend lives.
enum APIConfig {
    /// Host the services are reachable at, without scheme or port.
    ///
    /// The Simulator shares the Mac's network stack, so `localhost` works there.
    /// On a real device `localhost` is *the phone*, so this must be the Mac's
    /// LAN address — which is why it is settable from the Trainer tab rather
    /// than compiled in.
    static var host: String {
        get { UserDefaults.standard.string(forKey: hostKey) ?? defaultHost }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            UserDefaults.standard.set(trimmed.isEmpty ? nil : trimmed, forKey: hostKey)
        }
    }

    private static let hostKey = "animaldex.serverHost"

    private static var defaultHost: String {
        ProcessInfo.processInfo.environment["ANIMALDEX_HOST"] ?? "localhost"
    }

    static var coreAPI: URL { URL(string: "http://\(host):8080")! }
    static var mediaAPI: URL { URL(string: "http://\(host):8081")! }

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
