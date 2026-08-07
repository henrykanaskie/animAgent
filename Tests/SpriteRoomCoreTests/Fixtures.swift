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
    ]

    static func url(_ name: String) -> URL {
        directory.appending(path: "\(name).jsonl")
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
