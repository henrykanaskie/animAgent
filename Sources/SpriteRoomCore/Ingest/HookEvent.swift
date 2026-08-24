import Foundation

/// A Claude Code `tool_use_id`. The only legal join key between a `PreToolUse`
/// and its close. Never pair by tool name, never by recency. [I3]
public typealias ToolUseID = String

/// Which character an event belongs to.
///
/// `agent_id` is present **only** inside a subagent; its *absence* is the main
/// thread. `agent_type` is not a subagent marker (it also appears on the main
/// thread of an `--agent` session), so it is never consulted here.
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

/// What a `Notification` is telling the user, from `notification_type`.
///
/// M0c captured exactly two values under a pty, in real interactive sessions:
/// `permission_prompt` ("Claude needs your permission") and `idle_prompt`
/// ("Claude is waiting for your input"). Neither carries a `tool_use_id` or an
/// `agent_id`, not even when the gate belongs to a subagent, which M6c
/// verified in `fixtures/subagent-permission.jsonl`. So a `Notification` names
/// no character of its own, and which one it badges is decided by
/// `WorldModel.attentionTargets(for:of:resolved:)` from the permission-gate
/// marks, which *do* carry an `agent_id`.
///
/// `other` keeps the raw value rather than discarding it. `Notification` is by
/// construction the hook Claude Code fires *at the user*, so a third value
/// appearing tomorrow still means "this session wants you": the same fact the
/// one attention glyph asserts. That is the question-mark badge's reasoning
/// applied to a second axis: we know an alert fired, we do not know which kind,
/// and showing the honest generic is not a guess. [I1]
public enum AttentionKind: Sendable, Hashable, CustomStringConvertible {
    /// `permission_prompt`. Fires **6.0 s after** `PermissionRequest`, not with
    /// the dialog: three occurrences within 30 ms of each other.
    case permissionPrompt
    /// `idle_prompt`. Fires **60.02 s after `Stop`**, once per *idle stretch*,
    /// not once per session. A single stretch produces exactly one however long
    /// it lasts (a further 145 s of silence produced no repeat at M0c), but a
    /// session that goes quiet again after working produces another:
    /// `fixtures/denial-then-work.jsonl` has two, 60.03 s and 60.02 s after its
    /// two `Stop`s. Nothing may expect at most one.
    ///
    /// It means "this has been waiting a while", *not* "this is waiting",
    /// `Stop` with an empty open-call set already says the latter, immediately
    /// and for free. Nothing may drive a live idle state off it.
    case idlePrompt
    /// Any other `notification_type`, verbatim. `nil` when the key was absent.
    case other(String?)

    public init(notificationType: String?) {
        switch notificationType {
        case "permission_prompt": self = .permissionPrompt
        case "idle_prompt": self = .idlePrompt
        default: self = .other(notificationType)
        }
    }

    public var description: String {
        switch self {
        case .permissionPrompt: return "permission_prompt"
        case .idlePrompt: return "idle_prompt"
        case .other(let raw): return raw ?? "<no notification_type>"
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
/// An unrecognised (or structurally unusable) `hook_event_name` becomes
/// `.unhandled(name:)`. It is never an error. The hook surface grows (2.1.224
/// defines at least fifteen event names we do not consume: it was sixteen
/// until ADR-001 consumed `PermissionRequest`) and a new event must never crash
/// the app.
public struct HookEvent: Hashable, Sendable {

    public enum Kind: Hashable, Sendable {
        /// Decoration only. Never a precondition: it did not fire once in five
        /// captured headless sessions.
        case sessionStart(source: String?)
        /// The user sent a turn. Consumed for one reason only: it creates the
        /// session and its main-thread agent, so an agent that is thinking but
        /// has not yet called a tool is still a character on screen. An idle
        /// character is a truthful thing to draw. [I2]
        case userPromptSubmit
        case subagentStart
        /// `task` is `tool_input.description` **and only from the `Agent`
        /// dispatch tool**, where it is the 3–5 word summary of the job the
        /// subagent was dispatched to do: `'Touch file s1'`,
        /// `'Read three.txt sleep'`, `'Read delta/epsilon, sleep, reread alpha'`.
        /// `nil` for every other tool and for an `Agent` call that carried no
        /// description.
        ///
        /// **Restricted to `Agent` on purpose, and it is a correctness rule
        /// rather than a shortcut.** `description` is not a field of one tool:
        /// 37 of the 45 `Bash` calls in `fixtures/` carry one, and so does the
        /// single `Monitor` call. On a `Bash` it describes a shell command, not
        /// an agent's assignment, so capturing it here and letting it reach a
        /// nameplate would be the room asserting something the payload does not
        /// say. [I1] Only `Agent`'s `description` means *what this agent is
        /// tasked with*.
        ///
        /// It is also what keeps the decode off the hot path. `tool_input` is
        /// unbounded (a 5.5 MB `Edit` produces a 5.7 MB POST) and this is the
        /// only branch that opens a nested container inside it, on a tool that
        /// appears 10 times in 83 calls across the whole corpus. Every other
        /// `PreToolUse` never looks at `tool_input` at all. [I5]
        case preToolUse(toolUseID: ToolUseID, toolName: String, task: String?)
        /// `spawnedAgentID` is `tool_response.agentId`: present only on the
        /// `Agent` dispatch tool, where it maps this parent `tool_use_id` to
        /// the `agent_id` of the child it launched. There is no
        /// `parent_agent_id` field anywhere; this is the whole link.
        case postToolUse(toolUseID: ToolUseID, toolName: String?, spawnedAgentID: String?)
        /// Fires *instead of* `postToolUse`, never alongside it. The message is
        /// in `error`, not `tool_response`.
        case postToolUseFailure(toolUseID: ToolUseID, toolName: String?, error: String?)
        /// A primary close path, not a sweep: a call refused at the permission
        /// gate has no other close at all.
        case postToolBatch(calls: [BatchedCall])
        case subagentStop
        /// One assistant message stream ended. **Not** "turn over."
        case stop
        /// A permission gate opened for *this agent*. Consumed as an
        /// **agent-level marker** and nothing more,
        /// `docs/ADR-001-denied-calls.md` (d).
        ///
        /// It carries `tool_name`, `tool_input` and `permission_suggestions[]`
        /// and **no `tool_use_id`**, so it names no call and this case therefore
        /// carries no payload at all. Deliberate: reading `tool_name` off it
        /// would be the first step towards joining it to an open call by name,
        /// which the pairing rule forbids and which ADR-001 (c) rejects with
        /// data: `tool_name` + `tool_input` is not even unique within one
        /// batch, and a wrong join closes the wrong call. There is nothing here
        /// to join with. [I3]
        case permissionRequest
        case sessionEnd(reason: String?)
        /// The main agent raises an attention badge. **Badge only**: the pack
        /// ships no body animation for "waiting on a human" and repurposing an
        /// unrelated one would be fiction. [I1]
        case notification(attention: AttentionKind)
        case unhandled(name: String)

        /// The `hook_event_name` this kind came from. Used for counting.
        public var name: String {
            switch self {
            case .sessionStart: return "SessionStart"
            case .userPromptSubmit: return "UserPromptSubmit"
            case .subagentStart: return "SubagentStart"
            case .preToolUse: return "PreToolUse"
            case .postToolUse: return "PostToolUse"
            case .postToolUseFailure: return "PostToolUseFailure"
            case .postToolBatch: return "PostToolBatch"
            case .subagentStop: return "SubagentStop"
            case .stop: return "Stop"
            case .permissionRequest: return "PermissionRequest"
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

    /// The subagent-dispatch tool. Its hook name is `Agent`, never `Task`,
    /// `Task` is the model-facing name and does not appear in a payload.
    ///
    /// Used for **one** decision and no other: whether to read
    /// `tool_input.description`. It is deliberately *not* how a parent→child
    /// link is recognised: that stays keyed on `tool_response.agentId`,
    /// because `SendMessage` returns one too. The two questions are different:
    /// "which tool's input schema has a field meaning *the subagent's job*" has
    /// exactly one answer, and it is this one.
    public static let agentDispatchTool = "Agent"

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
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case source
        case reason
        case error
        case notificationType = "notification_type"
    }

    /// The only field of `tool_response` we read.
    ///
    /// `tool_response` is otherwise the tool's own output: arbitrary shape,
    /// arbitrary size, and none of our business. Decoding one key out of it
    /// keeps the payload's private half private, and means a `tool_response`
    /// that is a *string* (which most tools produce) simply yields `nil`
    /// instead of failing the whole event.
    private struct ToolResponse: Decodable {
        let agentID: String?

        private enum CodingKeys: String, CodingKey {
            case agentID = "agentId"
        }
    }

    /// The only field of `tool_input` we read, and it is read for exactly one
    /// tool.
    ///
    /// Same construction, and the same reason, as `ToolResponse` above:
    /// `tool_input` is the tool's own arguments: arbitrary shape, arbitrary
    /// size, so one key comes out and the rest stays private. A
    /// `tool_input` that is not an object yields `nil` instead of failing the
    /// whole event.
    private struct AgentDispatch: Decodable {
        let description: String?
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

        case "UserPromptSubmit":
            self.kind = .userPromptSubmit

        case "SubagentStart":
            self.kind = self.agentID == .mainThread ? .unhandled(name: name) : .subagentStart

        case "SubagentStop":
            self.kind = self.agentID == .mainThread ? .unhandled(name: name) : .subagentStop

        case "PreToolUse":
            if let toolUseID, let toolName {
                // The single gate on reading `tool_input` at all. Everything
                // that is not a subagent dispatch skips the nested container
                // entirely, however large the payload is. [I5/I1: see the
                // `task` doc on the case.]
                let task = toolName == Self.agentDispatchTool
                    ? (try? container.decodeIfPresent(
                        AgentDispatch.self, forKey: .toolInput))??.description
                    : nil
                self.kind = .preToolUse(toolUseID: toolUseID, toolName: toolName, task: task)
            } else {
                self.kind = .unhandled(name: name)
            }

        case "PostToolUse":
            if let toolUseID {
                let spawned = (try? container.decodeIfPresent(
                    ToolResponse.self, forKey: .toolResponse))??.agentID
                self.kind = .postToolUse(
                    toolUseID: toolUseID, toolName: toolName, spawnedAgentID: spawned)
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

        case "PermissionRequest":
            // No required fields, because it has none we use. Identity comes
            // from the common input fields alone, which is exactly what makes
            // it a legal *marker* rather than an illegal join.
            self.kind = .permissionRequest

        case "SessionEnd":
            self.kind = .sessionEnd(reason: string(.reason))

        case "Notification":
            self.kind = .notification(
                attention: AttentionKind(notificationType: string(.notificationType)))

        default:
            self.kind = .unhandled(name: name)
        }
    }
}

/// Decoding that cannot fail into the caller's face.
///
/// A malformed body is not an error to report back into a Claude Code session
///: it is a counter increment and a `202`. [I5]
public enum HookEventDecoder {
    /// Returns `nil` only when the body is not JSON, or carries no `session_id`
    /// / `cwd` and therefore cannot be routed to any project.
    public static func decode(_ data: Data) -> HookEvent? {
        try? JSONDecoder().decode(HookEvent.self, from: data)
    }
}
