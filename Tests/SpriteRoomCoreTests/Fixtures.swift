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

    /// The six files `docs/03-EVENT-MODEL.md` requires a green run against.
    static let required = [
        "single-agent-simple",
        "parallel-tools",
        "three-subagents",
        "killed-session",
        "tool-failure",
        "unknown-events",
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
}

extension WorldDelta {
    /// The delta's case name, for terse sequence assertions.
    var tag: String {
        switch self {
        case .agentAppeared: return "agentAppeared"
        case .agentDeparted: return "agentDeparted"
        case .callOpened: return "callOpened"
        case .callClosed: return "callClosed"
        case .callAbandoned: return "callAbandoned"
        case .reportDelivered: return "reportDelivered"
        case .populationChanged: return "populationChanged"
        }
    }

    var agentRef: AgentRef? {
        switch self {
        case let .agentAppeared(agent, _, _): return agent
        case let .agentDeparted(agent): return agent
        case let .callOpened(agent, _): return agent
        case let .callClosed(agent, _, _, _): return agent
        case let .callAbandoned(agent, _, _, _): return agent
        case let .reportDelivered(agent): return agent
        case .populationChanged: return nil
        }
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
