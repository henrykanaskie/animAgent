import Foundation

/// A Claude Code `tool_use_id`. The only legal join key between a `PreToolUse`
/// and its close. Never pair by tool name, never by recency. [I3]
public typealias ToolUseID = String

/// Which character an event belongs to.
///
/// `agent_id` is present **only** inside a subagent; its *absence* is the main
/// thread. `agent_type` is not a subagent marker — it also appears on the main
/// thread of an `--agent` session — so it is never consulted here.
/// See `docs/03-EVENT-MODEL.md`, "Identity resolution".
public enum AgentID: Hashable, Sendable, Comparable, CustomStringConvertible {
    case mainThread
    case subagent(String)

    public var description: String {
        switch self {
        case .mainThread: return "main"
        case .subagent(let id): return id
        }
    }

    /// Deterministic ordering so delta streams are reproducible: the main
    /// thread sorts first, subagents lexicographically after it.
    public static func < (lhs: AgentID, rhs: AgentID) -> Bool {
        switch (lhs, rhs) {
        case (.mainThread, .mainThread): return false
        case (.mainThread, .subagent): return true
        case (.subagent, .mainThread): return false
        case let (.subagent(a), .subagent(b)): return a < b
        }
    }
}

/// One entry of a `PostToolBatch`'s `tool_calls[]`.
public struct BatchedCall: Hashable, Sendable {
    public let toolUseID: ToolUseID
    public let toolName: String?

    public init(toolUseID: ToolUseID, toolName: String?) {
        self.toolUseID = toolUseID
        self.toolName = toolName
    }
}

/// A decoded hook payload: the common input fields plus the per-event fields
/// the world model actually uses.
///
/// An unrecognised — or structurally unusable — `hook_event_name` becomes
/// `.unhandled(name:)`. It is never an error. The hook surface grows (2.1.224
/// defines at least sixteen event names we do not consume) and a new event must
/// never crash the app.
public struct HookEvent: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        /// Decoration only. Never a precondition — it did not fire once in five
        /// captured headless sessions.
        case sessionStart(source: String?)
        case subagentStart
        case preToolUse(toolUseID: ToolUseID, toolName: String)
        case postToolUse(toolUseID: ToolUseID, toolName: String?)
        /// Fires *instead of* `postToolUse`, never alongside it. The message is
        /// in `error`, not `tool_response`.
        case postToolUseFailure(toolUseID: ToolUseID, toolName: String?, error: String?)
        /// A primary close path, not a sweep: a call refused at the permission
        /// gate has no other close at all.
        case postToolBatch(calls: [BatchedCall])
        case subagentStop
        /// One assistant message stream ended. **Not** "turn over."
        case stop
        case sessionEnd(reason: String?)
        case notification
        case unhandled(name: String)

        /// The `hook_event_name` this kind came from. Used for counting.
        public var name: String {
            switch self {
            case .sessionStart: return "SessionStart"
            case .subagentStart: return "SubagentStart"
            case .preToolUse: return "PreToolUse"
            case .postToolUse: return "PostToolUse"
            case .postToolUseFailure: return "PostToolUseFailure"
            case .postToolBatch: return "PostToolBatch"
            case .subagentStop: return "SubagentStop"
            case .stop: return "Stop"
            case .sessionEnd: return "SessionEnd"
            case .notification: return "Notification"
            case .unhandled(let name): return name
            }
        }

        public var isUnhandled: Bool {
            if case .unhandled = self { return true }
            return false
        }
    }

    public let sessionID: String
    public let cwd: String
    public let agentID: AgentID
    public let agentType: String?
    public let permissionMode: String?
    public let kind: Kind
}

// MARK: - Decoding

extension HookEvent: Decodable {

    /// A payload that carries no `hook_event_name` key at all. Real: captured
    /// synthetically in `fixtures/unknown-events.jsonl`.
    public static let missingEventName = "<missing hook_event_name>"
    /// A payload whose `hook_event_name` is neither a string nor a number.
    public static let nonStringEventName = "<non-string hook_event_name>"

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cwd
        case agentID = "agent_id"
        case agentType = "agent_type"
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolUseID = "tool_use_id"
        case toolCalls = "tool_calls"
        case source
        case reason
        case error
    }

    private struct BatchEntry: Decodable {
        let toolUseID: ToolUseID?
        let toolName: String?

        private enum CodingKeys: String, CodingKey {
            case toolUseID = "tool_use_id"
            case toolName = "tool_name"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // `session_id` and `cwd` are the routing keys. Without them the event
        // cannot be attributed to anything, so it is not an event to us.
        self.sessionID = try container.decode(String.self, forKey: .sessionID)
        self.cwd = try container.decode(String.self, forKey: .cwd)

        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }

        // Rule 3: presence of `agent_id`, and nothing else, decides
        // main-vs-subagent.
        self.agentID = string(.agentID).map(AgentID.subagent) ?? .mainThread
        self.agentType = string(.agentType)
        self.permissionMode = string(.permissionMode)

        let name: String
        if let s = string(.hookEventName) {
            name = s
        } else if let i = try? container.decode(Int.self, forKey: .hookEventName) {
            name = String(i)
        } else if let d = try? container.decode(Double.self, forKey: .hookEventName) {
            name = String(d)
        } else if let b = try? container.decode(Bool.self, forKey: .hookEventName) {
            name = String(b)
        } else if container.contains(.hookEventName) {
            name = Self.nonStringEventName
        } else {
            name = Self.missingEventName
        }

        let toolUseID = string(.toolUseID)
        let toolName = string(.toolName)

        // A recognised name whose required fields are missing is downgraded to
        // `.unhandled` rather than thrown. It still gets counted, which is how
        // we would notice.
        switch name {
        case "SessionStart":
            self.kind = .sessionStart(source: string(.source))

        case "SubagentStart":
            self.kind = self.agentID == .mainThread ? .unhandled(name: name) : .subagentStart

        case "SubagentStop":
            self.kind = self.agentID == .mainThread ? .unhandled(name: name) : .subagentStop

        case "PreToolUse":
            if let toolUseID, let toolName {
                self.kind = .preToolUse(toolUseID: toolUseID, toolName: toolName)
            } else {
                self.kind = .unhandled(name: name)
            }

        case "PostToolUse":
            if let toolUseID {
                self.kind = .postToolUse(toolUseID: toolUseID, toolName: toolName)
            } else {
                self.kind = .unhandled(name: name)
            }

        case "PostToolUseFailure":
            if let toolUseID {
                self.kind = .postToolUseFailure(
                    toolUseID: toolUseID, toolName: toolName, error: string(.error))
            } else {
                self.kind = .unhandled(name: name)
            }

        case "PostToolBatch":
            if let entries = try? container.decode([BatchEntry].self, forKey: .toolCalls) {
                self.kind = .postToolBatch(calls: entries.compactMap { entry in
                    entry.toolUseID.map { BatchedCall(toolUseID: $0, toolName: entry.toolName) }
                })
            } else {
                self.kind = .unhandled(name: name)
            }

        case "Stop":
            self.kind = .stop

        case "SessionEnd":
            self.kind = .sessionEnd(reason: string(.reason))

        case "Notification":
            self.kind = .notification

        default:
            self.kind = .unhandled(name: name)
        }
    }
}

/// Decoding that cannot fail into the caller's face.
///
/// A malformed body is not an error to report back into a Claude Code session
/// — it is a counter increment and a `202`. [I5]
public enum HookEventDecoder {
    /// Returns `nil` only when the body is not JSON, or carries no `session_id`
    /// / `cwd` and therefore cannot be routed to any project.
    public static func decode(_ data: Data) -> HookEvent? {
        try? JSONDecoder().decode(HookEvent.self, from: data)
    }
}
