import Foundation
import Testing
@testable import SpriteRoomCore

/// **A capture has to be replayable, or it is a log file with ambitions.**
///
/// The point of `--record` is to close the corpus's `authoring` blind spot: all
/// 17 fixtures hold zero `Edit`/`Write`/`NotebookEdit`/`Grep`/`Glob`, so the
/// laptop has never been observed on real data. A recorder that wrote something
/// `HookLog` could not parse back would leave that hole open while looking like
/// it had closed it, so the central test here writes a line and reads it with
/// the real parser rather than with a bespoke one.
struct HookRecorderTests {

    static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "spriteroom-recorder-\(UUID().uuidString)")
            .appending(path: "capture.jsonl")
    }

    static let samplePayload = """
        {"session_id":"s1","cwd":"/tmp/x","hook_event_name":"PreToolUse",\
        "tool_name":"Edit","tool_use_id":"t1"}
        """

    /// The whole contract in one test: what goes in comes back out through
    /// `HookLog`, decoded, with the fields intact.
    @Test func aRecordedBodyReplaysThroughTheRealParser() throws {
        let url = Self.temporaryURL()
        let recorder = HookRecorder(url: url)
        try recorder.open()
        recorder.record(Data(Self.samplePayload.utf8), at: Date(timeIntervalSince1970: 1_000_000))
        let written = recorder.close()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(written == 1)
        let entries = HookLog.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(entries.count == 1, "the capture did not parse back")
        let entry = try #require(entries.first)
        #expect(entry.receivedAt == Date(timeIntervalSince1970: 1_000_000))
        #expect(entry.synthetic == false)
        let event = try #require(entry.event, "the payload did not decode to an event")
        #expect(event.sessionID == "s1")
        #expect(event.cwd == "/tmp/x")
    }

    /// **The body is copied, not re-serialised.** Field order and keys this app
    /// does not read must survive, because the reason to capture is often the
    /// field the current version ignores.
    @Test func theRawBodySurvivesByteForByte() throws {
        let url = Self.temporaryURL()
        let odd = """
            {"zzz_unknown_field":[1,2,{"deep":"value"}],"session_id":"s1",\
            "cwd":"/tmp/x","hook_event_name":"Stop","aaa_after":"kept"}
            """
        let recorder = HookRecorder(url: url)
        try recorder.open()
        recorder.record(Data(odd.utf8))
        recorder.close()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(odd), "the payload was re-encoded rather than copied")
        // And the envelope is still valid JSON around it.
        let line = Data(text.split(separator: "\n")[0].utf8)
        let object = try #require(
            try JSONSerialization.jsonObject(with: line) as? [String: Any])
        #expect(object["_receivedAt"] is String)
        #expect(object["payload"] is [String: Any])
    }

    /// Many bodies, one line each, in arrival order. The recorder hands off to
    /// its own serial queue, so ordering is a property worth pinning rather than
    /// assuming.
    @Test func everyBodyBecomesOneLineInOrder() throws {
        let url = Self.temporaryURL()
        let recorder = HookRecorder(url: url)
        try recorder.open()
        for index in 0..<50 {
            recorder.record(Data("""
                {"session_id":"s\(index)","cwd":"/tmp/x","hook_event_name":"Stop"}
                """.utf8))
        }
        let written = recorder.close()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(written == 50)
        let entries = HookLog.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(entries.count == 50)
        #expect(entries.map { $0.event?.sessionID } == (0..<50).map { "s\($0)" })
    }

    /// An empty body is not an event and must not become a line: the listener
    /// frames a bodyless request as empty `Data`, and a `{"payload": }` line
    /// would make the whole capture unparseable from that point on.
    @Test func anEmptyBodyIsNotRecorded() throws {
        let url = Self.temporaryURL()
        let recorder = HookRecorder(url: url)
        try recorder.open()
        recorder.record(Data())
        #expect(recorder.close() == 0)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try String(contentsOf: url, encoding: .utf8).isEmpty)
    }

    /// **The stamp round-trips through the real parser**, which is the only
    /// property that matters and is deliberately not a string comparison.
    ///
    /// `ISO8601DateFormatter` writes a UTC offset as `Z`, not `+00:00`, even
    /// with `.withColonSeparatorInTimeZone` (that option governs a *numeric*
    /// offset). The existing fixtures were written by a different logger and
    /// carry `+00:00`. Both are ISO 8601 and `HookLog.date(from:)` accepts
    /// either, so a capture is replayable either way; an earlier version of this
    /// test asserted the `+00:00` spelling and was wrong about the code rather
    /// than the other way round.
    @Test func theStampRoundTripsThroughTheParser() {
        let instant = Date(timeIntervalSince1970: 1_754_000_000.645)
        let text = HookRecorder.stamp(instant)
        #expect(text.contains("."), "the stamp lost its fractional seconds: \(text)")
        let parsed = HookLog.date(from: text)
        #expect(parsed != nil, "the parser rejected our own stamp: \(text)")
        if let parsed {
            #expect(abs(parsed.timeIntervalSince(instant)) < 0.002)
        }
    }
}
