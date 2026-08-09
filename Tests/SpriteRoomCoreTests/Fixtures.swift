import Foundation
import SpriteRoomCore

/// Fixtures over mocks. Every test in this target drives real captured
/// payloads; `fixtures/` is ground truth and is never edited.
enum Fixtures {

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpriteRoomCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static let directory: URL = repositoryRoot.appending(path: "fixtures")

    /// The files `docs/03-EVENT-MODEL.md` requires a green run against.
    ///
    /// `permission-prompt` joined the six at ADR-001, which is the condition the
    /// doc set for it: it is the fixture that proves the interactive-denial fix,
    /// so from the moment there is a fix it is required coverage. Like
    /// `killed-session` it does **not** replay to zero open calls without the
    /// reaper, by nature — a user clicking "No" produces a call nothing in the
    /// stream ever closes. What changed is the number: 900 s became 60 s.
    static let required = [
        "single-agent-simple",
        "parallel-tools",
        "three-subagents",
        "killed-session",
        "tool-failure",
        "unknown-events",
        "permission-prompt",
        // Joined at the maintainer's decision after ADR-001 shipped. It is the
        // only fixture whose shortened deadline falls *inside* its own stream —
        // the orphan is reaped at t=94.98 and 157 s of real session activity
        // follows — so it is the only one that can demonstrate the fix rather
        // than merely be consistent with it. `parallel-denial` was considered
        // and left out: it proves the TUI serialises a batch, which is a
        // finding, not a rule this layer has to keep.
        "denial-then-work",
    ]

    /// **Every capture in `fixtures/`, read off the directory rather than
    /// listed here.**
    ///
    /// `required` is the eight the ingest layer is *signed off* against; it is
    /// not the corpus. There are seventeen files, and M6 gates on
    /// `spriteroom-replay --all` over all of them — so a rule stated over "every
    /// fixture" has to be iterated over this list, not that one. Derived from
    /// the directory on purpose: a capture added tomorrow joins every such rule
    /// on its next run instead of escaping it until somebody remembers a name.
    static let all: [String] = {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "jsonl" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    static func url(_ name: String) -> URL {
        directory.appending(path: "\(name).jsonl")
    }

    /// Whether the capture's stream contains a `SessionEnd`.
    ///
    /// The discriminator behind M6's three-orphan rule: a fixture that reaches
    /// `SessionEnd` has every open call force-closed by it [I4], and one that
    /// does not — a `kill -9`, a driver timing out at a dialog — legitimately
    /// ends with a call nothing in the stream will ever close.
    static func reachesSessionEnd(_ name: String) throws -> Bool {
        try entries(name).contains { $0.event?.kind.name == "SessionEnd" }
    }

    static func entries(_ name: String) throws -> [HookLogEntry] {
        try HookLog.load(contentsOf: url(name))
    }

    /// Drives every entry through a fresh model at its own `_receivedAt`.
    /// Returns the model plus the delta stream, in order.
    static func replay(
        _ name: String, reaper: Reaper = Reaper()
    ) async throws -> (model: WorldModel, deltas: [WorldDelta], entries: [HookLogEntry]) {
        let entries = try entries(name)
        let model = WorldModel(reaper: reaper)
        var deltas: [WorldDelta] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            deltas += await model.ingest(event, at: entry.receivedAt)
        }
        return (model, deltas, entries)
    }

    /// The same walk as `replay(_:)`, except the model's clock is **advanced to
    /// each event on the way** rather than jumping there — `WorldModel.advance(to:)`
    /// sweeps at every deadline that falls in the gap between two captured
    /// events, at the deadline's own instant.
    ///
    /// This is exactly what `spriteroom-replay` does, and it is what lets a
    /// replay report an abandonment when it happened instead of at the end of
    /// the run. `fixtures/denial-then-work.jsonl` is the fixture that needs it:
    /// ADR-001's shortened deadline falls at t=94.98 with 157 s of real session
    /// activity still to come, and a `SessionEnd` at t=252.06 that would
    /// otherwise take the credit.
    ///
    /// Every delta comes back paired with the fixture instant it was produced
    /// at, because for these the instant *is* the claim under test.
    static func replayAdvancingTheClock(
        _ name: String, reaper: Reaper = Reaper()
    ) async throws -> (
        model: WorldModel,
        timeline: [(instant: Date, delta: WorldDelta)],
        entries: [HookLogEntry]
    ) {
        let entries = try entries(name)
        let model = WorldModel(reaper: reaper)
        var timeline: [(instant: Date, delta: WorldDelta)] = []
        for entry in entries {
            for step in await model.advance(to: entry.receivedAt) {
                timeline += step.deltas.map { (step.instant, $0) }
            }
            guard let event = entry.event else { continue }
            timeline += await model.ingest(event, at: entry.receivedAt)
                .map { (entry.receivedAt, $0) }
        }
        return (model, timeline, entries)
    }

    /// A captured payload with named top-level keys replaced.
    ///
    /// The one sanctioned way to make a synthetic event in this target. Every
    /// field it does not name stays exactly as captured, so what comes out is
    /// still a real payload shape with real values — no hand-written event has
    /// ever been allowed in here and none is now.
    ///
    /// Two uses, both of them about a fact that no single capture can contain:
    ///
    /// - replacing `hook_event_name`, to prove what an *unconsumed* event does
    ///   to a session captured before that name existed in our table;
    /// - replacing `session_id` and `cwd`, to route a real event captured in
    ///   one session into another real session's stream. That is how the
    ///   attention tests below put a genuine `Notification` payload into
    ///   `three-subagents`, which is the only capture with concurrent subagent
    ///   traffic and the only way to test that such traffic does not clear the
    ///   main thread's badge. The alternative — a live capture of a permission
    ///   prompt raised while three subagents run — needs a human at a dialog
    ///   and three agents in flight at the same moment.
    static func rewriting(_ payload: Data, _ changes: [String: String]) -> HookEvent? {
        guard var object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        for (key, value) in changes { object[key] = value }
        guard let rewritten = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return HookEventDecoder.decode(rewritten)
    }

    static func rewritingEventName(_ payload: Data, to name: String) -> HookEvent? {
        rewriting(payload, ["hook_event_name": name])
    }

    /// The first entry of `name` whose event satisfies `predicate`.
    static func firstEntry(
        _ name: String, where predicate: (HookEvent) -> Bool
    ) throws -> HookLogEntry? {
        try entries(name).first { $0.event.map(predicate) ?? false }
    }
}

extension WorldDelta {
    /// The delta's case name, for terse sequence assertions.
    var tag: String {
        switch self {
        case .agentAppeared: return "agentAppeared"
        case .agentLinked: return "agentLinked"
        case .agentDeparted: return "agentDeparted"
        case .callOpened: return "callOpened"
        case .callClosed: return "callClosed"
        case .callAbandoned: return "callAbandoned"
        case .reportDelivered: return "reportDelivered"
        case .attentionChanged: return "attentionChanged"
        case .dormancyChanged: return "dormancyChanged"
        case .populationChanged: return "populationChanged"
        }
    }

    var agentRef: AgentRef? {
        switch self {
        case let .agentAppeared(agent, _, _): return agent
        case let .agentLinked(agent, _): return agent
        case let .agentDeparted(agent): return agent
        case let .callOpened(agent, _): return agent
        case let .callClosed(agent, _, _, _): return agent
        case let .callAbandoned(agent, _, _, _): return agent
        case let .reportDelivered(agent): return agent
        case let .attentionChanged(agent, _): return agent
        case let .dormancyChanged(agent, _): return agent
        case .populationChanged: return nil
        }
    }

    /// The attention this delta carries, and whether it carries one at all.
    /// `.some(nil)` is a clear; `nil` is "not an attention delta".
    var attentionChange: AttentionKind?? {
        if case let .attentionChanged(_, attention) = self { return attention }
        return nil
    }

    var toolUseID: ToolUseID? {
        switch self {
        case let .callOpened(_, call): return call.toolUseID
        case let .callClosed(_, id, _, _): return id
        case let .callAbandoned(_, id, _, _): return id
        default: return nil
        }
    }
}
