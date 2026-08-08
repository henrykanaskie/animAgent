import Foundation

/// A character's address in the world: project → session → agent.
///
/// Self-contained on purpose. A delta carries everything the scene needs to act
/// on it; nothing downstream ever calls back into the model.
public struct AgentRef: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// `cwd`. Routes the event to a project bucket.
    public let project: String
    /// `session_id`.
    public let session: String
    public let agent: AgentID

    public init(project: String, session: String, agent: AgentID) {
        self.project = project
        self.session = session
        self.agent = agent
    }

    public var description: String {
        "\(session.prefix(8))/\(agent)"
    }

    public static func < (lhs: AgentRef, rhs: AgentRef) -> Bool {
        if lhs.project != rhs.project { return lhs.project < rhs.project }
        if lhs.session != rhs.session { return lhs.session < rhs.session }
        return lhs.agent < rhs.agent
    }
}

/// Where a character is in its life. Interior to the model except on
/// `agentAppeared`, which can only ever carry `spawning` or `active`.
public enum AgentLifecycle: String, Sendable, Hashable {
    /// Created by `SubagentStart`. Walks in from the room edge.
    case spawning
    /// On screen and answering to events. Working or idle is *not* this — that
    /// is decided by the open-call set alone, and by nothing here. [I2/I3]
    case active
    /// The handing-over beat `reportDelivered` licenses: walk to the anchor,
    /// deliver. Named here because it is a real state a character passes
    /// through, but the **model never rests in it** — it holds no clock and so
    /// has no way to know when the walk ends. `SubagentStop` sets `dormant`,
    /// which is where the beat finishes.
    case reporting
    /// **Finished a turn, still assigned, still in the room.**
    ///
    /// `SubagentStop` means "this subagent finished and its result went to its
    /// parent". It does not mean the agent is gone: `fixtures/four-subagents.jsonl`
    /// has two agents stopped and then resumed by the parent with
    /// `SendMessage`, each resume emitting a second `SubagentStart`. Departing
    /// on a turn boundary made the room assert *this agent is gone* out of data
    /// that says only *this agent finished a turn* — the room drew one character
    /// where the parent had four assigned. A dormant character is the honest
    /// rendering of the fact we actually hold. [I1]
    ///
    /// It is **not** visually distinct from an idle-but-live agent, and that is
    /// deliberate: see `WorldModel.goDormant(ref:into:)`.
    ///
    /// Reapable like everything else [I4]: dormancy lives inside `AgentState`,
    /// so `SessionEnd` and the 30-minute idle sweep both take it with the
    /// character. It carries no deadline of its own — see the same doc for why
    /// inventing one would recreate the bug it fixes.
    case dormant
    /// Set on the way out, for the instant before the state is removed.
    case departed
}

/// How a call ended. `reconciled` means a `PostToolBatch` was the only close we
/// ever saw — true of every permission-denied call — so we know it ended but
/// not whether it succeeded. Saying more than that would be fiction. [I1]
public enum CallOutcome: String, Sendable, Hashable {
    case succeeded
    case failed
    case reconciled
}

/// Why an open call was force-closed. An abandoned call is our blind spot, not
/// the user's failure, so the character just returns to idle. [I4]
public enum AbandonReason: String, Sendable, Hashable {
    case deadlineExpired
    case sessionEnded
    case sessionIdle
    case agentStopped
}

/// One open `tool_use_id`. An agent holds a *set* of these, never one. [I3]
public struct OpenCall: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let toolUseID: ToolUseID
    public let toolName: String
    public let startedAt: Date
    /// Wall-clock instant past which the reaper closes this call. [I4]
    public let deadline: Date

    public init(toolUseID: ToolUseID, toolName: String, startedAt: Date, deadline: Date) {
        self.toolUseID = toolUseID
        self.toolName = toolName
        self.startedAt = startedAt
        self.deadline = deadline
    }

    public var description: String { "\(toolName)(\(toolUseID))" }

    public static func < (lhs: OpenCall, rhs: OpenCall) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.toolUseID < rhs.toolUseID
    }
}

/// One sweep of `WorldModel.advance(to:)`, and the fixture instant it ran at.
///
/// The instant is the point: it is always some open call's own deadline, so a
/// replay can say when an abandonment actually happened instead of when the
/// harness got round to noticing.
public struct SweepStep: Sendable, Hashable {
    public let instant: Date
    public let deltas: [WorldDelta]

    public init(instant: Date, deltas: [WorldDelta]) {
        self.instant = instant
        self.deltas = deltas
    }
}

/// The only thing that leaves `WorldModel`. Value types, ordered,
/// self-contained.
public enum WorldDelta: Sendable, Hashable, CustomStringConvertible {
    case agentAppeared(agent: AgentRef, agentType: String?, lifecycle: AgentLifecycle)
    /// Which character this one reports to. Emitted separately from
    /// `agentAppeared` because it cannot be known at that moment: the link
    /// lives on the `Agent` tool's `PostToolUse`, and `SubagentStart` arrives
    /// *before* it. So the link is always applied retroactively, and a scene
    /// that has already drawn the character has to be told afterwards.
    ///
    /// Emitted at most once per agent. Its absence is not an error — a subagent
    /// whose link we never saw anchors to the main agent, which is the
    /// documented fallback, not a guess. [I1]
    case agentLinked(agent: AgentRef, parent: AgentID)
    case agentDeparted(agent: AgentRef)
    case callOpened(agent: AgentRef, call: OpenCall)
    case callClosed(agent: AgentRef, toolUseID: ToolUseID, toolName: String, outcome: CallOutcome)
    case callAbandoned(agent: AgentRef, toolUseID: ToolUseID, toolName: String, reason: AbandonReason)
    /// This subagent finished a turn and its result went to its parent.
    /// `SubagentStop`, and nothing else, licenses the one dramatisation this
    /// project allows: walk to the anchor, deliver.
    ///
    /// **It is no longer followed by an `agentDeparted`.** It used to be, on the
    /// same event, and the walk-off was carried by that departure. The agent now
    /// goes `dormant` and stays in its seat, so this delta is the *whole* signal
    /// for the beat — a report is a round trip that ends where it started, not
    /// an exit. It can fire several times for one character: two of the four
    /// agents in `fixtures/four-subagents.jsonl` report twice.
    case reportDelivered(agent: AgentRef)
    /// This character is, or is no longer, waiting on a human. `nil` clears it.
    ///
    /// Raised by `Notification`. The event carries no `agent_id`, so *which*
    /// character it names is inferred — from the permission-gate marks, which do
    /// carry one — rather than read; see
    /// `WorldModel.attentionTargets(for:of:resolved:)`. One `Notification` can
    /// therefore produce several of these, one per agent genuinely at a gate.
    /// **Cleared by the next consumed event from the same agent** — see
    /// `WorldModel.clearsAttention(_:)` for why that is the rule and what it
    /// costs.
    ///
    /// A *change*, never a repeat: two identical notifications are one fact.
    case attentionChanged(agent: AgentRef, attention: AttentionKind?)
    case populationChanged(project: String, count: Int)

    public var description: String {
        switch self {
        case let .agentAppeared(agent, agentType, lifecycle):
            return "agentAppeared    \(agent) type=\(agentType ?? "-") \(lifecycle.rawValue)"
        case let .agentLinked(agent, parent):
            return "agentLinked      \(agent) parent=\(parent)"
        case let .agentDeparted(agent):
            return "agentDeparted    \(agent)"
        case let .callOpened(agent, call):
            return "callOpened       \(agent) \(call)"
        case let .callClosed(agent, toolUseID, toolName, outcome):
            return "callClosed       \(agent) \(toolName)(\(toolUseID)) \(outcome.rawValue)"
        case let .callAbandoned(agent, toolUseID, toolName, reason):
            return "callAbandoned    \(agent) \(toolName)(\(toolUseID)) \(reason.rawValue)"
        case let .reportDelivered(agent):
            return "reportDelivered  \(agent)"
        case let .attentionChanged(agent, attention):
            return "attentionChanged \(agent) \(attention.map(String.init(describing:)) ?? "cleared")"
        case let .populationChanged(project, count):
            let leaf = project.split(separator: "/").last.map(String.init) ?? project
            return "populationChanged \(leaf)=\(count)"
        }
    }
}

// MARK: - Snapshots

/// A read-only view of one agent. Produced for tests and for a scene that
/// attaches after the fact; it is never a channel back into the actor.
public struct AgentSnapshot: Sendable, Hashable {
    public let ref: AgentRef
    public let agentType: String?
    /// Where this character is in its life. `dormant` means it finished a turn
    /// and is still assigned — it draws exactly like an idle live agent, and
    /// this field is the only place the difference is held. No delta carries it.
    public let lifecycle: AgentLifecycle
    /// Who this agent reports to, when the `Agent` call that launched it told
    /// us. `nil` means unlinked — anchor to the main agent. [I1]
    public let parent: AgentID?
    /// Sorted by start time. A *set* of calls — never a single current tool.
    public let openCalls: [OpenCall]
    /// Raised by `Notification`, cleared by this agent's next consumed event.
    /// Orthogonal to `openCalls`: a character can be working *and* blocked at a
    /// permission gate, which is exactly what a denied `Bash` looks like.
    public let attention: AttentionKind?

    /// An agent is working if and only if its open-call set is non-empty. [I2]
    public var isWorking: Bool { !openCalls.isEmpty }
}

public struct WorldSnapshot: Sendable, Hashable {
    /// Sorted by `AgentRef`.
    public let agents: [AgentSnapshot]

    public var totalOpenCalls: Int { agents.reduce(0) { $0 + $1.openCalls.count } }

    public func agent(_ ref: AgentRef) -> AgentSnapshot? {
        agents.first { $0.ref == ref }
    }

    public func agents(inProject project: String) -> [AgentSnapshot] {
        agents.filter { $0.ref.project == project }
    }

    public var openCalls: [(agent: AgentRef, call: OpenCall)] {
        agents.flatMap { snapshot in snapshot.openCalls.map { (snapshot.ref, $0) } }
    }
}
