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
    /// **It is visually distinct from an idle-but-live agent now**, and
    /// the change of mind is recorded rather than overwritten. The old reasoning
    /// was that nothing we own can honestly draw the difference between
    /// finished-and-might-return and waiting-for-work, so both rendered `idle`
    /// and no delta carried the lifecycle at all. That was right about the body
    /// — the pack's `sleep` row is a head on a pillow drawn from above, for
    /// compositing onto a top-down bed, and it cannot be worn by a character
    /// sitting side-on — and wrong about the badge, which is one layer up.
    /// `badges.states.sleep` is real pack art, the same construction as
    /// `attention`, and a `Z` says exactly the fact this case holds and nothing
    /// more. So `dormancyChanged` exists and the scene draws it. [I1]
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
    /// `tool_input.description` from an `Agent` dispatch: the 3–5 word summary
    /// of the job the subagent this call launched was given. `nil` on every
    /// other call, which is every call but ten in the whole corpus.
    ///
    /// **It lives here, and nowhere else, because this is the only store the
    /// model keys by `tool_use_id`** — and a `tool_use_id` is what the
    /// description belongs to, since the child's `agent_id` is not known until
    /// the `PostToolUse`. A side table `toolUseID → description` would be new
    /// open state with its own reaping obligation; on the `OpenCall` there is
    /// nothing to reap, because every path that ends a call already removes the
    /// whole struct — the three close paths, the deadline sweep, `SubagentStop`,
    /// `SessionEnd` and the 30-minute idle sweep, all through
    /// `WorldModel.removeCall`. That is the argument the permission-gate mark
    /// makes for living inside `AgentState` rather than beside it. [I4]
    ///
    /// A dispatch whose call is closed before its `PostToolUse` arrives —
    /// abandoned by the reaper, or force-closed at `SessionEnd` — therefore
    /// loses its description with the call, and the child is linked with no
    /// task. That is the intended outcome: the fallback is to say nothing. [I1]
    public let dispatchedTask: String?

    public init(
        toolUseID: ToolUseID, toolName: String, startedAt: Date, deadline: Date,
        dispatchedTask: String? = nil
    ) {
        self.toolUseID = toolUseID
        self.toolName = toolName
        self.startedAt = startedAt
        self.deadline = deadline
        self.dispatchedTask = dispatchedTask
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
    /// **What this subagent was dispatched to do**, verbatim from the `Agent`
    /// call's `tool_input.description` — `Touch file s1`,
    /// `Read delta/epsilon, sleep, reread alpha`. A real string the payload
    /// carried, repeated; nothing here is derived, summarised or guessed. [I1]
    ///
    /// **Retroactive by construction, exactly as `agentLinked` is, and for the
    /// same reason.** The description belongs to the dispatching `tool_use_id`,
    /// and the child's `agent_id` is not known until that call's `PostToolUse`
    /// — which arrives *after* the child's `SubagentStart`. So the character is
    /// already on screen when it learns its task, and if the child does not
    /// exist yet the fact waits for it rather than conjuring one. It is emitted
    /// in the same batch as `agentLinked`, immediately behind it: they are two
    /// halves of one payload's news.
    ///
    /// **Emitted at most once per agent, and only when there is something to
    /// say.** Its absence is not an error and has three ordinary causes: the
    /// agent is the **main thread**, which has no dispatching `Agent` call and
    /// therefore no task; the dispatch happened before this app attached; or
    /// the link came from a `SendMessage` resume, whose `tool_input` carries no
    /// `description` at all. In every one of them the honest rendering is to
    /// say nothing — the same fallback an unlinked subagent takes when it
    /// anchors to the main agent. [I1]
    ///
    /// **The string is carried whole.** Shortening `Move the badge beside the
    /// head` to `move badge` is a display judgement about a nameplate's width
    /// and it belongs to the layer that knows the width. Doing it here would
    /// bury the real value where nothing could test it.
    case agentTasked(agent: AgentRef, task: String)
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
    /// This character has, or no longer has, **finished a turn while still
    /// assigned**. `SubagentStop` sets it; any later consumed event for the
    /// same agent clears it, because that event is the agent working again.
    ///
    /// **The narrowest delta that carries the fact, deliberately.** It is a
    /// `Bool` and not an `AgentLifecycle` because the other four cases are
    /// either already carried (`spawning` and `active`, on `agentAppeared`),
    /// never rested in (`reporting` — the model holds no clock and cannot know
    /// when the walk ends), or already have a delta of their own (`departed` is
    /// `agentDeparted`). A `lifecycleChanged` carrying the whole enum could
    /// therefore express three transitions the model never makes, and a delta
    /// that can say something untrue is a delta something downstream will
    /// eventually draw. [I1]
    ///
    /// **A *change*, never a repeat**, exactly as `attentionChanged` is: a
    /// second `SubagentStop` for an already-dormant agent is the same fact, and
    /// `revive` emits nothing for an agent that was not dormant.
    ///
    /// It rides *beside* `reportDelivered` on the same event and does not
    /// replace it: the report beat is a dramatisation of the hand-over and this
    /// is the state the character is left in afterwards. The scene therefore
    /// raises the badge and plays the walk in the same batch, which is right —
    /// the turn is over from the instant `SubagentStop` arrives, and the walk is
    /// the room saying so.
    case dormancyChanged(agent: AgentRef, isDormant: Bool)
    /// This character is, or is no longer, **stopped at a permission gate** —
    /// ADR-001 (d)'s marker, which until ADR-005 §7 left the model in no form at
    /// all.
    ///
    /// **It is the answer to "is any agent stuck", and the only one the hook
    /// stream can give.** A gate is an interval and a long one: measured
    /// lifetimes across `fixtures/` are 9.43, 13.52, 34.05, 36.60, 37.76 and
    /// 248.78 s, plus two that never close in their stream at all. The scene
    /// spends it holding the body still, because a call parked at a gate is not
    /// running and a phrase over it asserts work that is not happening — the
    /// same sentence ADR-003 §1 already used to keep the *badge* layer from
    /// drawing `terminal` over a gated `Bash`. [I1, ADR-005 §7]
    ///
    /// **Not the same fact as `attentionChanged`, and it must not be folded into
    /// it.** The `Notification` that raises attention arrives **6.0 s after** the
    /// `PermissionRequest` that arms this — four measured occurrences, 6.014 /
    /// 6.006 / 6.032 / 6.016 s — so for those six seconds this is the only
    /// signal there is. It also names its agent outright, where a `Notification`
    /// carries no `agent_id` and has to be attributed through these very marks.
    ///
    /// **A *change*, never a repeat**, exactly as `dormancyChanged` and
    /// `attentionChanged` are: a second `PermissionRequest` for an
    /// already-marked agent re-snapshots the marked call set — see
    /// `WorldModel.armPermissionGate` — but says nothing new about *whether* a
    /// gate is open, so it emits nothing. The marked set itself is interior and
    /// deliberately absent from this delta: it exists to decide deadlines, it
    /// names no gated call (the event carries none), and nothing downstream may
    /// draw from it. [I3]
    ///
    /// **Reapable, with no deadline of its own** [I4]. The mark is a field of
    /// `AgentState`, so the paths that end a character take it with them; the
    /// paths that end only the *gate* — a marked call closing or being
    /// abandoned, `Stop`, `SubagentStop`, and the `UserPromptSubmit` that
    /// answers it — each emit this delta with `false`. Departure does not, for
    /// the same reason `dormancyChanged(false)` is not emitted there: the
    /// `agentDeparted` behind it removes the character the fact belonged to.
    case gateChanged(agent: AgentRef, isGated: Bool)
    case populationChanged(project: String, count: Int)

    public var description: String {
        switch self {
        case let .agentAppeared(agent, agentType, lifecycle):
            return "agentAppeared    \(agent) type=\(agentType ?? "-") \(lifecycle.rawValue)"
        case let .agentLinked(agent, parent):
            return "agentLinked      \(agent) parent=\(parent)"
        case let .agentTasked(agent, task):
            return "agentTasked      \(agent) task=\(task)"
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
        case let .dormancyChanged(agent, isDormant):
            return "dormancyChanged  \(agent) \(isDormant ? "dormant" : "awake")"
        case let .gateChanged(agent, isGated):
            return "gateChanged      \(agent) \(isGated ? "gated" : "clear")"
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
    /// and is still assigned; the scene draws it as the `sleep` badge over an
    /// otherwise idle character. The transition is carried by
    /// `WorldDelta.dormancyChanged`; this field is the standing value.
    public let lifecycle: AgentLifecycle
    /// Who this agent reports to, when the `Agent` call that launched it told
    /// us. `nil` means unlinked — anchor to the main agent. [I1]
    public let parent: AgentID?
    /// What this agent was dispatched to do, when the `Agent` call that
    /// launched it carried a `description`. Learned at the same instant as
    /// `parent` and from the same payload.
    ///
    /// `nil` is the ordinary state, not a gap to fill: the **main thread has no
    /// dispatching call and must never be given one**, an agent whose dispatch
    /// we never saw has nothing to repeat, and a `SendMessage` resume carries
    /// no description. Say nothing. [I1]
    public let task: String?
    /// Sorted by start time. A *set* of calls — never a single current tool.
    public let openCalls: [OpenCall]
    /// Raised by `Notification`, cleared by this agent's next consumed event.
    /// Orthogonal to `openCalls`: a character can be working *and* blocked at a
    /// permission gate, which is exactly what a denied `Bash` looks like.
    public let attention: AttentionKind?
    /// **Whether this agent is stopped at a permission gate** — ADR-001 (d)'s
    /// marker, armed by `PermissionRequest`. The transition is carried by
    /// `WorldDelta.gateChanged`; this field is the standing value.
    ///
    /// The marked `tool_use_id` set behind it stays interior: it decides
    /// deadlines and nothing else, and it names no gated call because the event
    /// names none. This is the whole of what may leave the model. [I3]
    ///
    /// It is on the snapshot so that the mark's reaping can be *checked* from
    /// outside the actor rather than inferred from deadlines — an agent left
    /// gated after `SessionEnd` or the idle sweep is orphaned open state of
    /// exactly the kind I4 exists to catch, and a character frozen forever is
    /// the same class of failure as one that types forever.
    public let isGated: Bool

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
