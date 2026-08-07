import Foundation

/// The world. `World → Project(cwd) → Session(session_id) → Agent(agent_id ??
/// .mainThread)`, where each agent's tool state is a **set** of open calls
/// keyed by `tool_use_id`. [I3]
///
/// An `actor`, and the sole writer. Deltas are the only thing that leaves it.
///
/// Time is a parameter, never a reading. `ingest(_:at:)` and `sweep(at:)` both
/// take the instant to use, so the model is deterministic and every
/// time-dependent behaviour is testable without waiting for one. [I4]
public actor WorldModel {

    // MARK: Interior state

    private struct AgentState {
        var agentType: String?
        var lifecycle: AgentLifecycle
        /// Keyed by `tool_use_id`. A set, never a single current tool. [I3]
        var openCalls: [ToolUseID: OpenCall] = [:]
        /// Who launched this agent, once the `Agent` call's `PostToolUse` told
        /// us. `nil` until then, and `nil` forever if we never see it.
        var parent: AgentID?
        /// Raised by `Notification`, cleared by this agent's next consumed
        /// event. Orthogonal to `openCalls` — see `clearsAttention(_:)`.
        var attention: AttentionKind?
    }

    private struct SessionState {
        var lastEventAt: Date
        /// `SessionStart` decoration. Never a precondition.
        var source: String?
        var agents: [AgentID: AgentState] = [:]
        /// Links learned before the child existed. `SubagentStart` normally
        /// arrives *first*, so this is the rare direction — but the app can
        /// attach mid-session and see the `PostToolUse` without the
        /// `SubagentStart` that preceded it.
        var pendingParents: [AgentID: AgentID] = [:]
    }

    private struct ProjectState {
        var sessions: [String: SessionState] = [:]
        var agentCount: Int { sessions.values.reduce(0) { $0 + $1.agents.count } }
    }

    private var projects: [String: ProjectState] = [:]
    private var unhandled: [String: Int] = [:]
    private var abandonedCount = 0
    private let reaper: Reaper

    public init(reaper: Reaper = Reaper()) {
        self.reaper = reaper
    }

    // MARK: Counters

    /// `hook_event_name` → how many arrived that we do not consume. A rising
    /// count is how we notice the hook surface has grown.
    public var unhandledCounts: [String: Int] { unhandled }
    public var unhandledTotal: Int { unhandled.values.reduce(0, +) }
    /// Open calls force-closed by a sweep or by `SessionEnd`. Non-zero means a
    /// close path is missing or a session died. [I4]
    public var abandonedTotal: Int { abandonedCount }

    // MARK: Ingest

    @discardableResult
    public func ingest(_ event: HookEvent, at now: Date) -> [WorldDelta] {
        var deltas: [WorldDelta] = []
        let project = event.cwd
        let before = projects[project]?.agentCount ?? 0

        apply(event, at: now, into: &deltas)

        let after = projects[project]?.agentCount ?? 0
        if before != after {
            deltas.append(.populationChanged(project: project, count: after))
        }
        return deltas
    }

    @discardableResult
    public func ingest(_ events: [HookEvent], at now: Date) -> [WorldDelta] {
        events.flatMap { ingest($0, at: now) }
    }

    /// Whether this kind of event is allowed to bring a session into
    /// existence.
    ///
    /// Nothing waits for a lifecycle event: the session and its main-thread
    /// agent exist from the first *consumed* event carrying this `session_id`,
    /// because `SessionStart` never fired once in five captured headless
    /// sessions.
    ///
    /// Two kinds are excluded. `sessionEnd` is pure teardown — it can only
    /// remove what is there. And an `unhandled` event must change nothing at
    /// all: `fixtures/unknown-events.jsonl` replays seven of them *after* the
    /// session's `SessionEnd`, and creating state from one would resurrect a
    /// dead session. See the report accompanying M1 — this is the one place
    /// `docs/03-EVENT-MODEL.md` ("first event of any kind") and
    /// `fixtures/README.md` ("none of them changes the world") disagree, and
    /// the fixture is ground truth.
    private static func createsSession(_ kind: HookEvent.Kind) -> Bool {
        switch kind {
        case .sessionEnd, .unhandled: return false
        default: return true
        }
    }

    /// Whether this kind of event, arriving for an agent, is evidence that the
    /// agent is no longer waiting on a human.
    ///
    /// **The clear rule, and it is the whole of it: the next consumed event
    /// from the same agent clears that agent's attention badge.**
    ///
    /// There is no "notification answered" event. Nothing in 2.1.224 observes
    /// the click — `PermissionDenied` has never fired, on either denial path.
    /// So the badge has to be cleared by inference, and the only honest
    /// inference available is *the session moved*. Both captured
    /// `notification_type`s mean "blocked on the human": while a permission
    /// dialog is up the main thread emits nothing at all, and while a session
    /// sits at the prompt it emits nothing at all. A main-thread event is
    /// therefore evidence the human acted — the fixtures show exactly that.
    /// In `fixtures/permission-prompt.jsonl` the approved call's `Notification`
    /// is followed 1.81 s later by its `PostToolUse`, and the denied call's is
    /// followed by the user's next `UserPromptSubmit`.
    ///
    /// **Same agent, not same session.** A `Notification` carries no
    /// `agent_id`, so it is the main thread's; symmetrically only events with
    /// no `agent_id` say anything about the main thread. Without that
    /// restriction an async subagent churning through `Read`s would wipe the
    /// badge off a main thread that is genuinely still stuck at a dialog —
    /// `fixtures/three-subagents.jsonl` is full of exactly those interleavings
    /// — and so would the phantom `SubagentStop` the TUI's suggestion helper
    /// emits on every interactive turn.
    ///
    /// **Two kinds are excluded.** `notification` itself, obviously — it is the
    /// raise. And `unhandled`, which must change nothing at all, by the same
    /// rule that stops it creating a session; `PermissionRequest` arrives
    /// unhandled and clearing on it would erase the badge 6 s before the
    /// `Notification` that raises it. `sessionEnd` is excluded too, but only
    /// because it is redundant: it departs the character, and a badge on a
    /// character that no longer exists is not a state.
    ///
    /// **Erring early is the deliberate direction.** M4's rule — *a late reap
    /// is a blind spot, an early one is fiction* — is about closing a state
    /// that asserts "working", so it points at a long deadline. This badge has
    /// the opposite polarity: it is a *positive* assertion, so a late clear is
    /// the fiction ("Claude needs your permission" when it does not) and an
    /// early clear is only a blind spot. The same principle therefore points
    /// the other way here, at the earliest defensible signal.
    ///
    /// **What it can still get wrong**, stated rather than papered over: a
    /// main-thread batch holding several calls where one is gated and the
    /// others complete would clear the badge while the dialog is still up. No
    /// capture shows that shape — every observed `PermissionRequest` is a lone
    /// call — and the failure is a miss, not a lie.
    private static func clearsAttention(_ kind: HookEvent.Kind) -> Bool {
        switch kind {
        case .notification, .unhandled, .sessionEnd: return false
        default: return true
        }
    }

    private func apply(_ event: HookEvent, at now: Date, into deltas: inout [WorldDelta]) {
        if Self.createsSession(event.kind) {
            ensureSession(project: event.cwd, session: event.sessionID, at: now, into: &deltas)
        }
        // An unhandled event still proves the session is alive, which keeps the
        // idle sweep honest. That is not a change to the world.
        touch(project: event.cwd, session: event.sessionID, at: now)

        let ref = AgentRef(project: event.cwd, session: event.sessionID, agent: event.agentID)

        // Before the event's own effect, so the delta stream reads in the order
        // the facts happened: the wait ended, then the work resumed.
        if Self.clearsAttention(event.kind) {
            setAttention(nil, ref: ref, into: &deltas)
        }

        switch event.kind {
        case .unhandled(let name):
            // Counted, never dropped, and nothing else: an unrecognised event
            // must not move tool state and must not conjure a character out of
            // an `agent_id` we do not understand.
            unhandled[name, default: 0] += 1

        case .sessionStart(let source):
            projects[event.cwd]?.sessions[event.sessionID]?.source = source

        case .userPromptSubmit:
            // Consumed for the session and main agent `ensureSession` has
            // already created, and for nothing else. A turn that produces no
            // tool call still gets a character, and that character is idle,
            // which is what actually happened. [I2]
            break

        case .subagentStart:
            ensureAgent(ref, agentType: event.agentType, lifecycle: .spawning, into: &deltas)

        case let .preToolUse(toolUseID, toolName):
            ensureAgent(ref, agentType: event.agentType, lifecycle: .active, into: &deltas)
            open(toolUseID: toolUseID, toolName: toolName, ref: ref, at: now, into: &deltas)

        case let .postToolUse(toolUseID, _, spawnedAgentID):
            ensureAgent(ref, agentType: event.agentType, lifecycle: .active, into: &deltas)
            close(toolUseID, ref: ref, outcome: .succeeded, into: &deltas)
            // The parent→child link, and the only place it exists. The child's
            // `SubagentStart` has almost always arrived already, so this is
            // applied retroactively to a character that is on screen.
            if let spawnedAgentID {
                link(child: .subagent(spawnedAgentID), to: ref, into: &deltas)
            }

        case let .postToolUseFailure(toolUseID, _, _):
            ensureAgent(ref, agentType: event.agentType, lifecycle: .active, into: &deltas)
            close(toolUseID, ref: ref, outcome: .failed, into: &deltas)

        case .postToolBatch(let calls):
            // A primary close path, not tidying. A call refused at the
            // permission gate emits `PreToolUse` and then neither
            // `PostToolUse` nor `PostToolUseFailure`; this is its only close.
            ensureAgent(ref, agentType: event.agentType, lifecycle: .active, into: &deltas)
            for call in calls {
                close(call.toolUseID, ref: ref, outcome: .reconciled, into: &deltas)
            }

        case .subagentStop:
            // Only ever acts on a character we already have. Spawning one just
            // to walk it off screen would be fiction. [I1]
            guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else {
                break
            }
            abandonAll(ref: ref, reason: .agentStopped, into: &deltas)
            setLifecycle(.reporting, ref: ref)
            deltas.append(.reportDelivered(agent: ref))
            depart(ref: ref, into: &deltas)

        case .stop:
            // Fires once per assistant message stream — four times in one turn
            // in `three-subagents`. Not end-of-session, not a reap trigger, and
            // the character's idleness is already implied by an empty open-call
            // set. Nothing to emit. [I1]
            break

        case .sessionEnd:
            endSession(project: event.cwd, session: event.sessionID, into: &deltas)

        case .notification(let attention):
            // Badge-only. No body animation for this exists in the pack and
            // repurposing an unrelated one would be fiction; the badge is the
            // whole representation. [I1]
            //
            // The event carries no `agent_id`, so `ref` is the main thread by
            // the identity rule rather than by a special case here.
            setAttention(attention, ref: ref, into: &deltas)
        }
    }

    // MARK: Sweeps [I4]

    /// Close every call whose deadline has passed, then close every session
    /// that has been silent past the idle timeout.
    @discardableResult
    public func sweep(at now: Date) -> [WorldDelta] {
        var deltas: [WorldDelta] = []
        var touchedProjects: Set<String> = []

        // Deterministic order so replay output and tests are reproducible.
        for (project, projectState) in projects.sorted(by: { $0.key < $1.key }) {
            for (session, sessionState) in projectState.sessions.sorted(by: { $0.key < $1.key }) {
                for (agent, agentState) in sessionState.agents.sorted(by: { $0.key < $1.key }) {
                    let ref = AgentRef(project: project, session: session, agent: agent)
                    let expired = agentState.openCalls.values
                        .filter { reaper.isExpired($0, at: now) }
                        .sorted()
                    for call in expired {
                        abandon(call.toolUseID, ref: ref, reason: .deadlineExpired, into: &deltas)
                    }
                }
            }
        }

        for (project, projectState) in projects.sorted(by: { $0.key < $1.key }) {
            for (session, sessionState) in projectState.sessions.sorted(by: { $0.key < $1.key })
            where reaper.isIdle(lastEventAt: sessionState.lastEventAt, at: now) {
                let before = projects[project]?.agentCount ?? 0
                endSession(project: project, session: session, reason: .sessionIdle, into: &deltas)
                if before != (projects[project]?.agentCount ?? 0) { touchedProjects.insert(project) }
            }
        }

        for project in touchedProjects.sorted() {
            deltas.append(.populationChanged(project: project, count: projects[project]?.agentCount ?? 0))
        }
        return deltas
    }

    // MARK: Snapshot

    public func snapshot() -> WorldSnapshot {
        var agents: [AgentSnapshot] = []
        for (project, projectState) in projects {
            for (session, sessionState) in projectState.sessions {
                for (agent, agentState) in sessionState.agents {
                    agents.append(AgentSnapshot(
                        ref: AgentRef(project: project, session: session, agent: agent),
                        agentType: agentState.agentType,
                        lifecycle: agentState.lifecycle,
                        parent: agentState.parent,
                        openCalls: agentState.openCalls.values.sorted(),
                        attention: agentState.attention))
                }
            }
        }
        return WorldSnapshot(agents: agents.sorted { $0.ref < $1.ref })
    }

    // MARK: - Interior helpers

    private func ensureSession(
        project: String, session: String, at now: Date, into deltas: inout [WorldDelta]
    ) {
        if projects[project]?.sessions[session] != nil { return }
        projects[project, default: ProjectState()].sessions[session] =
            SessionState(lastEventAt: now)
        let main = AgentRef(project: project, session: session, agent: .mainThread)
        ensureAgent(main, agentType: nil, lifecycle: .active, into: &deltas)
    }

    private func touch(project: String, session: String, at now: Date) {
        projects[project]?.sessions[session]?.lastEventAt = now
    }

    /// Creates an agent if we have not seen it. A subagent whose
    /// `SubagentStart` we missed — because the app attached mid-session —
    /// still gets a character on its first tool call.
    private func ensureAgent(
        _ ref: AgentRef, agentType: String?, lifecycle: AgentLifecycle,
        into deltas: inout [WorldDelta]
    ) {
        guard projects[ref.project]?.sessions[ref.session] != nil else { return }
        if projects[ref.project]!.sessions[ref.session]!.agents[ref.agent] != nil {
            if let agentType {
                projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.agentType = agentType
            }
            return
        }
        let pending = projects[ref.project]!.sessions[ref.session]!
            .pendingParents.removeValue(forKey: ref.agent)
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent] =
            AgentState(agentType: agentType, lifecycle: lifecycle, parent: pending)
        deltas.append(.agentAppeared(agent: ref, agentType: agentType, lifecycle: lifecycle))
        if let pending {
            deltas.append(.agentLinked(agent: ref, parent: pending))
        }
    }

    /// Records `tool_response.agentId`: this parent's `tool_use_id` launched
    /// that child.
    ///
    /// Retroactive by construction — `SubagentStart` fires before the
    /// `PostToolUse` that carries the link — so the normal case is that the
    /// child is already a character and gets told who it reports to a
    /// millisecond later. If the child does not exist yet (the app attached
    /// mid-session and missed its `SubagentStart`) the link waits for it rather
    /// than conjuring a character out of an id. [I1]
    private func link(child: AgentID, to parent: AgentRef, into deltas: inout [WorldDelta]) {
        guard child != parent.agent else { return }
        guard projects[parent.project]?.sessions[parent.session] != nil else { return }
        let childRef = AgentRef(project: parent.project, session: parent.session, agent: child)

        guard projects[parent.project]!.sessions[parent.session]!.agents[child] != nil else {
            projects[parent.project]!.sessions[parent.session]!.pendingParents[child] = parent.agent
            return
        }
        // Emitted at most once. A repeated `PostToolUse` for the same dispatch
        // is the same fact, not a second one.
        guard projects[parent.project]!.sessions[parent.session]!
            .agents[child]!.parent == nil else { return }
        projects[parent.project]!.sessions[parent.session]!.agents[child]!.parent = parent.agent
        deltas.append(.agentLinked(agent: childRef, parent: parent.agent))
    }

    /// Raises or clears the attention badge, emitting a delta only on a real
    /// change.
    ///
    /// Idempotent in both directions. `idle_prompt` fires exactly once so a
    /// repeat is not expected, but a second identical `permission_prompt` is
    /// the same fact and must not produce a second badge change — a delta
    /// stream that repeats itself makes the scene's suppression memory the only
    /// thing standing between a stable badge and a flicker.
    private func setAttention(
        _ attention: AttentionKind?, ref: AgentRef, into deltas: inout [WorldDelta]
    ) {
        // No such agent: nothing to raise a badge on, and conjuring a character
        // out of a notification is not this function's job.
        guard var state = projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] else {
            return
        }
        guard state.attention != attention else { return }
        state.attention = attention
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent] = state
        deltas.append(.attentionChanged(agent: ref, attention: attention))
    }

    private func setLifecycle(_ lifecycle: AgentLifecycle, ref: AgentRef) {
        projects[ref.project]?.sessions[ref.session]?.agents[ref.agent]?.lifecycle = lifecycle
    }

    private func open(
        toolUseID: ToolUseID, toolName: String, ref: AgentRef, at now: Date,
        into deltas: inout [WorldDelta]
    ) {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else { return }
        // Opening is idempotent too: a repeated `PreToolUse` for a live id is
        // the same call, not a second one.
        if projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!
            .openCalls[toolUseID] != nil { return }

        let call = OpenCall(
            toolUseID: toolUseID,
            toolName: toolName,
            startedAt: now,
            deadline: reaper.deadline(forTool: toolName, startedAt: now))
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!
            .openCalls[toolUseID] = call
        if projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.lifecycle == .spawning {
            projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.lifecycle = .active
        }
        deltas.append(.callOpened(agent: ref, call: call))
    }

    /// Closing is idempotent. `PostToolBatch` re-reports calls the other two
    /// paths already closed — both happen for the same `tool_use_id` in
    /// `fixtures/tool-failure.jsonl`. A second `.callClosed` would drive the
    /// scene's open-call count negative.
    private func close(
        _ toolUseID: ToolUseID, ref: AgentRef, outcome: CallOutcome,
        into deltas: inout [WorldDelta]
    ) {
        guard let call = removeCall(toolUseID, ref: ref) else { return }
        deltas.append(.callClosed(
            agent: ref, toolUseID: toolUseID, toolName: call.toolName, outcome: outcome))
    }

    private func abandon(
        _ toolUseID: ToolUseID, ref: AgentRef, reason: AbandonReason,
        into deltas: inout [WorldDelta]
    ) {
        guard let call = removeCall(toolUseID, ref: ref) else { return }
        abandonedCount += 1
        deltas.append(.callAbandoned(
            agent: ref, toolUseID: toolUseID, toolName: call.toolName, reason: reason))
    }

    private func abandonAll(ref: AgentRef, reason: AbandonReason, into deltas: inout [WorldDelta]) {
        guard let agent = projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] else {
            return
        }
        for call in agent.openCalls.values.sorted() {
            abandon(call.toolUseID, ref: ref, reason: reason, into: &deltas)
        }
    }

    private func removeCall(_ toolUseID: ToolUseID, ref: AgentRef) -> OpenCall? {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else {
            return nil
        }
        return projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!
            .openCalls.removeValue(forKey: toolUseID)
    }

    private func depart(ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else { return }
        setLifecycle(.departed, ref: ref)
        projects[ref.project]!.sessions[ref.session]!.agents.removeValue(forKey: ref.agent)
        deltas.append(.agentDeparted(agent: ref))
    }

    /// `SessionEnd` closes everything under the session and empties it of
    /// characters. [I4]
    private func endSession(
        project: String, session: String, reason: AbandonReason = .sessionEnded,
        into deltas: inout [WorldDelta]
    ) {
        guard let sessionState = projects[project]?.sessions[session] else { return }
        for agent in sessionState.agents.keys.sorted() {
            let ref = AgentRef(project: project, session: session, agent: agent)
            abandonAll(ref: ref, reason: reason, into: &deltas)
            depart(ref: ref, into: &deltas)
        }
        projects[project]?.sessions.removeValue(forKey: session)
        if projects[project]?.sessions.isEmpty == true {
            projects.removeValue(forKey: project)
        }
    }
}
