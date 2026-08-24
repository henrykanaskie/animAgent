import Foundation

/// One line of a `fixtures/*.jsonl` capture.
///
/// `_receivedAt` is the logger's arrival timestamp and is *ours*, not Claude
/// Code's. It is what lets replay reconstruct relative timing without a wall
/// clock. `_synthetic` marks a payload POSTed to the logger by hand.
public struct HookLogEntry: Sendable, Hashable {
    public let receivedAt: Date
    public let synthetic: Bool
    /// The request body exactly as captured. Never normalised.
    public let payload: Data
    /// `nil` when the payload is not routable: not JSON, or no `session_id` /
    /// `cwd`. Counted as malformed; never an error.
    public let event: HookEvent?
}

/// Reads a captured hook log. Fixtures are ground truth: read them, never
/// edit them.
public enum HookLog {

    public enum LoadError: Error, Sendable {
        case unreadable(String)
    }

    public static func load(contentsOf url: URL) throws -> [HookLogEntry] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw LoadError.unreadable(url.path)
        }
        return parse(text)
    }

    public static func parse(_ text: String) -> [HookLogEntry] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            entry(from: Data(line.utf8))
        }
    }

    private struct Envelope: Decodable {
        let receivedAt: String?
        let synthetic: Bool?

        private enum CodingKeys: String, CodingKey {
            case receivedAt = "_receivedAt"
            case synthetic = "_synthetic"
        }
    }

    private static func entry(from line: Data) -> HookLogEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payloadObject = object["payload"],
              let payload = try? JSONSerialization.data(withJSONObject: payloadObject)
        else { return nil }

        let envelope = try? JSONDecoder().decode(Envelope.self, from: line)
        guard let stamp = envelope?.receivedAt, let receivedAt = date(from: stamp) else {
            return nil
        }

        return HookLogEntry(
            receivedAt: receivedAt,
            synthetic: envelope?.synthetic ?? false,
            payload: payload,
            event: HookEventDecoder.decode(payload))
    }

    /// The logger writes `2026-08-07T08:14:10.670+00:00`: fractional seconds
    /// and a colon in the offset.
    ///
    /// The formatters are built per call rather than cached because
    /// `ISO8601DateFormatter` is a non-`Sendable` class and a shared instance
    /// would need an escape hatch this project does not allow. Replay parses a
    /// hundred lines; the cost is not measurable.
    public static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone,
        ]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return plain.date(from: string)
    }
}
