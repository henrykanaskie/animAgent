import Foundation

/// Writes every hook body the listener receives to a `.jsonl` file, in the exact
/// shape `fixtures/` uses, so a live session can become a replayable capture.
///
/// # Why this exists
///
/// All 17 fixtures were captured at M0 to exercise ingest, and they exercise
/// `sleep`, `touch` and reading a file. Between them they hold **zero** `Edit`,
/// `Write`, `NotebookEdit`, `Grep` and `Glob` calls, which means `authoring` —
/// the laptop, the maintainer's leading example of what the room should show —
/// cannot fire anywhere in the corpus and has never once been observed on real
/// data. Every claim about it rests on unit tests of the derivation.
///
/// There was no way to capture a new one: the app could replay a `.jsonl` and
/// bind a listener, and nothing wrote a `.jsonl` back out. This is that missing
/// half.
///
/// # It records the **raw body**, before decoding
///
/// `HookEvent` is a decoded struct and does not retain the JSON it came from, so
/// recording at the drain would mean re-encoding a subset of the fields and
/// calling the result ground truth. `fixtures/` is ground truth — the one
/// directory in this repository that is never edited — so a capture has to be
/// byte-faithful to what Claude Code actually sent. The line is assembled by
/// wrapping the untouched body:
///
///     {"_receivedAt": "<stamp>", "payload": <the bytes, verbatim>}
///
/// No re-serialisation, so field order, unknown keys and unusual escaping all
/// survive exactly as sent — including the fields this app does not read, which
/// are precisely the ones a future version might need.
///
/// # I5: the handler still never does work
///
/// `record(_:at:)` is called from `HookListener.handle`, which I5 requires to
/// read, decode, enqueue and return. So it does **no I/O on that path**: it
/// takes the bytes, stamps them, and hands them to its own serial queue. The
/// file is opened once and appended to off the hot path, exactly as
/// `EventQueue.enqueue` hands off to the drain. A recorder that wrote inline
/// would turn every hook POST into a disk write and would be the I5 violation
/// this comment exists to prevent someone reintroducing.
public final class HookRecorder: @unchecked Sendable {

    private let url: URL
    private let queue = DispatchQueue(label: "com.spriteroom.recorder", qos: .utility)
    private var handle: FileHandle?
    private var failed = false
    /// Lines written, for the summary the app prints on quit.
    private var count = 0

    public init(url: URL) {
        self.url = url
    }

    /// Creates or truncates the file. Called once, before the listener binds, so
    /// a capture that cannot be written fails immediately rather than after a
    /// session's worth of events have been silently dropped.
    public func open() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    /// Stamps and enqueues one raw body. **Never blocks the caller.**
    public func record(_ body: Data, at instant: Date = Date()) {
        guard !body.isEmpty else { return }
        let stamp = Self.stamp(instant)
        queue.async { [weak self] in
            self?.append(body, stamp: stamp)
        }
    }

    /// Flushes and closes. Returns how many lines were written, so the caller
    /// can say so rather than leaving the user to `wc -l` a file that may be
    /// empty for an interesting reason.
    @discardableResult
    public func close() -> Int {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
            return count
        }
    }

    public var lineCount: Int { queue.sync { count } }

    private func append(_ body: Data, stamp: String) {
        guard let handle, !failed else { return }
        // Assembled as bytes rather than through `JSONSerialization`, because
        // round-tripping the payload is exactly what this must not do.
        var line = Data("{\"_receivedAt\": \"\(stamp)\", \"payload\": ".utf8)
        line.append(body)
        line.append(Data("}\n".utf8))
        do {
            try handle.write(contentsOf: line)
            count += 1
        } catch {
            // One failure is enough: a full disk will not un-fill itself, and a
            // recorder that logged per event would drown the session it is
            // meant to be capturing.
            failed = true
        }
    }

    /// `2026-08-07T08:14:06.645Z` — UTC, with fractional seconds.
    ///
    /// **Not `+00:00`, and that is the formatter's choice rather than ours.**
    /// `ISO8601DateFormatter` writes a zero offset as `Z` even with
    /// `.withColonSeparatorInTimeZone`, which governs numeric offsets only. The
    /// M0 fixtures were written by a different logger and carry `+00:00`; both
    /// are ISO 8601, `HookLog.date(from:)` accepts either, and
    /// `HookRecorderTests` proves the round trip rather than the spelling.
    ///
    /// Built per call for the reason `HookLog` gives: the formatter is a
    /// non-`Sendable` class and a shared instance would need an escape hatch
    /// this project does not allow.
    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone,
        ]
        return formatter.string(from: date)
    }
}
