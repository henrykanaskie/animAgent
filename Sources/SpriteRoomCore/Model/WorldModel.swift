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
        /// What this agent was dispatched to do — the launching `Agent` call's
        /// `tool_input.description`, learned from the same `PostToolUse` and at
        /// the same instant as `parent`.
        ///
        /// `nil` for the main thread permanently: it has no dispatching call,
        /// and its absence is what *makes* it the main thread. `nil` too for a
        /// subagent whose dispatch this app never saw. Both say nothing. [I1]
        var task: String?
        /// Raised by `Notification`, cleared by this agent's next consumed
        /// event. Orthogonal to `openCalls` — see `clearsAttention(_:)`.
        var attention: AttentionKind?
        /// **ADR-001 (d) — the permission-gate marker.** `nil` is disarmed.
        /// Non-`nil` is "a gate opened for this agent, and these are the
        /// `tool_use_id`s it held open at that instant".
        ///
        /// The set may legitimately be empty: it is a snapshot of `openCalls`,
        /// not a claim about any particular call, and an empty one shortens
        /// nothing.
        ///
        /// **It lives inside `AgentState` on purpose, and that is what makes it
        /// reapable** [I4]. Every path that ends an agent — `SessionEnd`,
        /// `SubagentStop`'s departure, the 30-minute idle sweep — removes the
        /// whole `AgentState`, so this cannot outlive the character it belongs
        /// to. A parallel dictionary keyed by agent would have been one more
        /// thing to remember to clear, i.e. one more thing to leak.
        var permissionGate: Set<ToolUseID>?
        /// **ADR-005 §3 — whether this agent has a turn in progress.** The whole
        /// of what the posture channel says, and the fact `Stop` used to carry
        /// nowhere.
        ///
        /// `true` at creation, because an agent exists *because* an event for it
        /// arrived and an event for it arriving means it is in a turn — which is
        /// the same reasoning `SceneDirector` already applies at
        /// `agentAppeared`. Closed by `Stop` and re-opened by `UserPromptSubmit`
        /// or `PreToolUse`.
        ///
        /// **It lives inside `AgentState`, which is what makes it reapable**
        /// [I4]: every path that ends an agent removes the whole struct, so a
        /// turn cannot outlive the character holding it. The delta stream has a
        /// second obligation of its own — see `WorldDelta.turnChanged`.
        var hasTurn = true
    }

    /// One dispatching `PostToolUse`'s news about a child: who launched it and
    /// what it was launched to do.
    ///
    /// The two are **one record** rather than two dictionaries because they are
    /// one payload's facts, learned in the same instant from the same event.
    /// That also makes the task's reaping the parent link's reaping, which was
    /// already settled: whatever removes the pending link removes the pending
    /// task, and there is no second thing to remember to clear. [I4]
    private struct PendingLink {
        var parent: AgentID
        var task: String?
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
        ///
        /// Bounded by the session: it is a field of `SessionState`, so
        /// `SessionEnd` and the 30-minute idle sweep both remove it whole. An
        /// entry for a child that never appears lives exactly as long as the
        /// session that named it, which is the bound this model already
        /// accepts everywhere else. [I4]
        var pendingParents: [AgentID: PendingLink] = [:]
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
    /// **Same agent, not same session.** Only events with no `agent_id` say
    /// anything about the main thread. Without that restriction an async
    /// subagent churning through `Read`s would wipe the badge off a main thread
    /// that is genuinely still stuck at a dialog —
    /// `fixtures/three-subagents.jsonl` is full of exactly those interleavings
    /// — and so would the phantom `SubagentStop` the TUI's suggestion helper
    /// emits on every interactive turn.
    ///
    /// **It reads the same when the badge is on a subagent**, which it now can
    /// be — see `attentionTargets(for:of:resolved:)`. A badge raised on a gated
    /// subagent clears on *that subagent's* next consumed event, which on the
    /// approve path is the gated call's own `PostToolUse`: 5.5 s in
    /// `fixtures/subagent-permission.jsonl`, against 1.81 s for the main-thread
    /// approve path. Main-thread traffic does not clear it, and that is the
    /// point — in `fixtures/concurrent-permission-gates.jsonl` one subagent's
    /// gate is answered while a second subagent is still at its own, and only
    /// the first agent's badge comes down. The rule did not have to change to
    /// cope with this; it was already agent-scoped.
    ///
    /// **Three kinds are excluded.** `notification` itself, obviously — it is
    /// the raise. `unhandled`, which must change nothing at all, by the same
    /// rule that stops it creating a session. And `permissionRequest`, which is
    /// consumed as of ADR-001 but is the *announcement of the wait*, not
    /// evidence it ended — it arrives 6 s before the `Notification` it
    /// precedes, so clearing on it would erase a badge before it was raised,
    /// and a second gate opening while the first is still up would erase a
    /// badge that is still true. `sessionEnd` is excluded too, but only because
    /// it is redundant: it departs the character, and a badge on a character
    /// that no longer exists is not a state.
    ///
    /// Note the shape of that last exclusion: consuming an event and having it
    /// clear the badge are separate decisions, and `permissionRequest` is the
    /// first event to take one without the other.
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
        case .notification, .unhandled, .sessionEnd, .permissionRequest: return false
        default: return true
        }
    }

    /// **Which character a `PermissionRequest` marks. This one line is
    /// ADR-001's risk 3, and it is deliberately the only place the question is
    /// answered.**
    ///
    /// Attribution goes through the ordinary identity rule and nothing else:
    /// `agent_id` present → that subagent, absent → the main thread
    /// (`docs/03-EVENT-MODEL.md`, "Identity resolution", rule 3), which is
    /// precisely what `HookEvent.agentID` already computed at decode. No
    /// special case, no inference, no fallback of our own.
    ///
    /// **Risk 3 is settled, in this rule's favour, and it is now a cited fact
    /// rather than an assumption.** `fixtures/subagent-permission.jsonl`: a
    /// `general-purpose` subagent's gated `Bash` produces a `PermissionRequest`
    /// carrying `agent_id: ab2378e6a85dea269`, matching the `SubagentStart`
    /// 2.76 s earlier and the gated `PreToolUse` 18 ms earlier. M6c saw eight
    /// more `PermissionRequest`s across six sessions and every subagent gate
    /// carried its agent's id.
    ///
    /// **That is load-bearing, not incidental.** Per-agent scoping is what makes
    /// the synchronous-`Agent` case safe: in the same fixture the main thread's
    /// `Agent` call is open from t=3.504 to t=19.805 *while* the child's dialog
    /// is on screen, so a session-scoped mark — the natural simplification,
    /// since the mark holds no `tool_use_id` — would mark the parent's `Agent`
    /// call and let a synthetic `UserPromptSubmit` shorten it. ADR-001 states
    /// that exclusion as structural and it is not; this scoping is the reason it
    /// holds. Do not widen it.
    ///
    /// It still returns an optional, and callers still handle `nil`: this is the
    /// one place the question is asked, so a future capture that complicates it
    /// is a new body for this function rather than a hunt.
    private static func gateOwner(of event: HookEvent) -> AgentRef? {
        AgentRef(project: event.cwd, session: event.sessionID, agent: event.agentID)
    }

    /// **Which characters a `Notification` badges.**
    ///
    /// The problem this answers: `PermissionRequest` carries `agent_id`, and the
    /// `Notification` that follows it 6.0 s later **does not**
    /// (`fixtures/subagent-permission.jsonl`, verified at M6c — a subagent's
    /// gate, then a `Notification` with no `agent_id` at all). Read through the
    /// identity rule alone it is therefore a main-thread event, so the badge
    /// landed on the main character while the agent actually blocked at the
    /// dialog was a subagent. The room was asserting something the data does not
    /// say, which is the one thing it may never do. [I1]
    ///
    /// We hold the information to do better, because ADR-001's marker already
    /// records exactly which agents have an open gate:
    ///
    /// - **`permission_prompt`** badges **every agent in this session currently
    ///   marked with an open permission gate.** Each of them genuinely is
    ///   waiting on a human, so each badge is true. It is deliberately a *set*:
    ///   `fixtures/concurrent-permission-gates.jsonl` holds two subagents' gates
    ///   open together for 31.8 s, so "the single marked agent" is not a thing
    ///   that always exists.
    /// - **No agent marked → the main thread**, as before. The notification did
    ///   happen and we cannot say whose it is; the main agent is the honest
    ///   default and the one `docs/03-EVENT-MODEL.md` already falls back to
    ///   elsewhere. This is also the ordinary path for a plain main-thread gate,
    ///   where the main thread *is* the marked agent — so nothing about the
    ///   required fixtures moves.
    /// - **`idle_prompt`** is about the session sitting at the prompt, not about
    ///   a gated call, so it stays on the main thread whatever is marked. Same
    ///   for any `notification_type` we do not recognise: we know an alert
    ///   fired, we do not know it is a gate, and inferring one would be a guess.
    ///
    /// The first check is the identity rule, which outranks all of this: if a
    /// future release ever puts an `agent_id` on a `Notification`, the data has
    /// answered and no inference is wanted.
    private func attentionTargets(
        for attention: AttentionKind, of event: HookEvent, resolved ref: AgentRef
    ) -> [AgentRef] {
        guard ref.agent == .mainThread else { return [ref] }
        guard attention == .permissionPrompt else { return [ref] }
        let marked = markedAgents(project: event.cwd, session: event.sessionID)
        return marked.isEmpty ? [ref] : marked
    }

    /// Every agent of one session whose permission-gate mark is armed, in
    /// deterministic order (main thread first, subagents lexicographically).
    private func markedAgents(project: String, session: String) -> [AgentRef] {
        guard let sessionState = projects[project]?.sessions[session] else { return [] }
        return sessionState.agents
            .filter { $0.value.permissionGate != nil }
            .keys
            .sorted()
            .map { AgentRef(project: project, session: session, agent: $0) }
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
            // already created. A turn that produces no tool call still gets a
            // character, and that character is idle, which is what actually
            // happened. [I2]
            //
            // ADR-001 (d) rule 3 — and *only* when this agent's gate is still
            // armed. A prompt on its own means nothing: rule (b), "the next
            // `UserPromptSubmit` closes stragglers", was rejected because a
            // subagent's result reaches the main thread as a synthetic prompt
            // and two calls in `three-subagents` are genuinely still running
            // when one arrives. The mark is what tells the two apart.
            answerPermissionGate(ref: ref, at: now, into: &deltas)
            // ADR-005 §3 — the main thread's turn opener. Behind the gate answer
            // so the stream reads in the order the facts happened: the wait
            // ended, then the next turn began. Silent unless a `Stop` closed the
            // last one, which is what makes a mid-turn synthetic prompt free.
            beginTurn(ref: ref, into: &deltas)

        case .subagentStart:
            ensureAgent(ref, agentType: event.agentType, lifecycle: .spawning, into: &deltas)
            // Named by ADR-005 §3 as a subagent's opener, and silent in every
            // capture: nothing closes a subagent's turn in this model, because
            // `SubagentStop` says that as `dormancyChanged`. It is here so the
            // three openers read in one place rather than two.
            beginTurn(ref: ref, into: &deltas)

        case let .preToolUse(toolUseID, toolName, task):
            ensureAgent(ref, agentType: event.agentType, lifecycle: .active, into: &deltas)
            // Ahead of the call it opens: the character sits down and then
            // starts working, which is the order the two facts happen in.
            beginTurn(ref: ref, into: &deltas)
            open(
                toolUseID: toolUseID, toolName: toolName, task: task,
                ref: ref, at: now, into: &deltas)

        case let .postToolUse(toolUseID, _, spawnedAgentID):
            ensureAgent(ref, agentType: event.agentType, lifecycle: .active, into: &deltas)
            // The closed call is read, not discarded: an `Agent` dispatch
            // carried its child's task on `tool_input.description`, and this is
            // the instant both halves of that payload's news are in hand — the
            // call still holding the description, and the response naming the
            // child it belongs to.
            let closed = close(toolUseID, ref: ref, outcome: .succeeded, into: &deltas)
            // The parent→child link, and the only place it exists. The child's
            // `SubagentStart` has almost always arrived already, so this is
            // applied retroactively to a character that is on screen.
            if let spawnedAgentID {
                link(
                    child: .subagent(spawnedAgentID), to: ref,
                    task: closed?.dispatchedTask, into: &deltas)
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
            // to walk it off screen would be fiction, and the TUI's suggestion
            // helper emits six of these for agents that never started in this
            // one capture. [I1]
            guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else {
                break
            }
            abandonAll(ref: ref, reason: .agentStopped, into: &deltas)
            goDormant(ref: ref, into: &deltas)

        case .permissionRequest:
            // ADR-001 (d) rule 1. An agent-level marker: it opens no call,
            // closes no call, and names no `tool_use_id` — it has none to name.
            // What it records is this agent's open-call set at this instant,
            // which the model already holds. That performs no join, so it cannot
            // join wrongly. [I3]
            //
            // **It emits one delta, and only the `Bool`.** It used to emit none
            // at all, on the grounds that a marker is not a fact about the room.
            // The marker is not; *being stopped at a gate* is, and it is the one
            // fact in this model that answers "is any agent stuck" — so the body
            // stops moving for as long as it holds, which is 9 to 249 s of the
            // corpus's eight gates. The marked set stays interior for the
            // original reason. [ADR-005 §7]
            if let owner = Self.gateOwner(of: event) {
                armPermissionGate(ref: owner, into: &deltas)
            }

        case .stop:
            // Fires once per assistant message stream — four times in one turn
            // in `three-subagents`. Not end-of-session, not a reap trigger, and
            // the character's idleness is already implied by an empty open-call
            // set. [I1]
            //
            // ADR-001 (d) rule 2, second half: the turn completed, so whatever
            // the gate was waiting for is no longer pending. Disarming here is
            // what stops a mark left by an approved-then-finished turn being
            // acted on by an unrelated prompt much later.
            //
            // **`Stop` now says two things and they are different things.**
            // The gate clear puts a stopped character back in *motion*; the turn
            // end stands it *up*. One is ADR-001 (d) rule 2 and fires for the one
            // `Stop` in the corpus that had a gate open; the other is ADR-005 §3
            // and fires for all 26. Ordered wait-ended-then-turn-ended, the same
            // way the attention clear leads every other arm.
            //
            // **It ends the turn whatever the open-call set holds.** See
            // `endTurn` for the measurement behind that and for why `Stop` firing
            // several times in one user turn does not put the strobe back.
            disarmPermissionGate(ref: ref, into: &deltas)
            endTurn(ref: ref, into: &deltas)

        case .sessionEnd:
            endSession(project: event.cwd, session: event.sessionID, into: &deltas)

        case .notification(let attention):
            // Badge-only. No body animation for this exists in the pack and
            // repurposing an unrelated one would be fiction; the badge is the
            // whole representation. [I1]
            //
            // *Which* character (or characters) it lands on is the one
            // interesting question, and it is answered in exactly one place —
            // `attentionTargets(for:of:resolved:)`. A `permission_prompt` badges
            // every agent with an open gate; everything else badges `ref`.
            for target in attentionTargets(for: attention, of: event, resolved: ref) {
                setAttention(attention, ref: target, into: &deltas)
            }
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

    /// Advance the model's notion of "now" to `instant`, closing each expired
    /// call **at the instant its own deadline falls** rather than all together
    /// on arrival. Returns one entry per sweep that changed something. [I4]
    ///
    /// `sweep(at:)` answers "what is expired *now*", which is the right question
    /// for a live clock ticking once a second and the wrong one for a replay,
    /// which jumps from one captured event to the next. A deadline falling in
    /// the gap gets reported at the far end of the jump — or, if a `SessionEnd`
    /// closes the call first, never reported at all. That is not a cosmetic
    /// difference: ADR-001's shortened deadline for
    /// `fixtures/denial-then-work.jsonl` falls at t=94.98 with 157 s of real
    /// session activity still to come, so a replay that only sweeps at the end
    /// cannot distinguish the shipped 60 s from the 900 s it replaced.
    ///
    /// **It cannot reap anything early**, which is the property the whole thing
    /// rests on: each step is one ordinary `sweep(at:)` at an instant this
    /// method never invents — every instant is some open call's own deadline,
    /// and never past `instant`. No new close path exists here; this only
    /// chooses when the existing sweep runs. `fixtures/tool-failure.jsonl` is
    /// the regression that proves it, because every call in it closes through
    /// the event stream well inside its deadline, so stepping the clock across
    /// it must still produce no sweep at all.
    ///
    /// Deliberately *not* wired into `LiveDriver`: against a real clock the
    /// 1 s tick already runs far finer than the shortest deadline in the table,
    /// and there is no gap to step across.
    public func advance(to instant: Date) -> [SweepStep] {
        var steps: [SweepStep] = []
        while let due = earliestDeadline(), due <= instant {
            let deltas = sweep(at: due)
            // A sweep at the earliest deadline closes at least the call that
            // owns it, so the next one is strictly later and this terminates.
            // The guard is belt and braces: a step that moved nothing would
            // move nothing forever.
            if deltas.isEmpty { break }
            steps.append(SweepStep(instant: due, deltas: deltas))
        }
        return steps
    }

    /// The soonest deadline any open call in the world still carries.
    ///
    /// Asked of the model rather than remembered by the caller on purpose:
    /// ADR-001's shortening rewrites a deadline and **emits no delta**, so
    /// anything reconstructing deadlines from the delta stream would still
    /// believe the denied `Bash` expires at 900 s.
    private func earliestDeadline() -> Date? {
        var earliest: Date?
        for project in projects.values {
            for session in project.sessions.values {
                for agent in session.agents.values {
                    for call in agent.openCalls.values
                    where earliest == nil || call.deadline < earliest! {
                        earliest = call.deadline
                    }
                }
            }
        }
        return earliest
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
                        task: agentState.task,
                        openCalls: agentState.openCalls.values.sorted(),
                        attention: agentState.attention,
                        isGated: agentState.permissionGate != nil,
                        hasTurn: agentState.hasTurn))
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
    ///
    /// **Creation is idempotent, and for a known id it is also the revival
    /// path.** A background subagent resumed with `SendMessage` emits a *second*
    /// `SubagentStart` ~20 ms after that call's `PreToolUse` — six starts across
    /// four agents in `fixtures/four-subagents.jsonl` — so "not once per agent"
    /// is the observed shape and every path here funnels through `revive`.
    private func ensureAgent(
        _ ref: AgentRef, agentType: String?, lifecycle: AgentLifecycle,
        into deltas: inout [WorldDelta]
    ) {
        guard projects[ref.project]?.sessions[ref.session] != nil else { return }
        if projects[ref.project]!.sessions[ref.session]!.agents[ref.agent] != nil {
            if let agentType {
                projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.agentType = agentType
            }
            revive(ref, into: &deltas)
            return
        }
        let pending = projects[ref.project]!.sessions[ref.session]!
            .pendingParents.removeValue(forKey: ref.agent)
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent] =
            AgentState(
                agentType: agentType, lifecycle: lifecycle,
                parent: pending?.parent, task: pending?.task)
        deltas.append(.agentAppeared(agent: ref, agentType: agentType, lifecycle: lifecycle))
        if let pending {
            deltas.append(.agentLinked(agent: ref, parent: pending.parent))
            // Behind the link, in the order the one payload said them.
            if let task = pending.task {
                deltas.append(.agentTasked(agent: ref, task: task))
            }
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
    ///
    /// **`task` rides here because it is the same news.** It is the launching
    /// `Agent` call's `tool_input.description`, taken off the `OpenCall` this
    /// same `PostToolUse` just closed, and this is the first moment anything
    /// knows which `agent_id` it describes. It is `nil` far more often than not
    /// — a `SendMessage` resume returns an `agentId` and carries no
    /// `description`, and a dispatch whose call was reaped before its close
    /// took the description with it — and `nil` means say nothing. [I1]
    ///
    /// The two facts are recorded independently, not as a pair: a child already
    /// linked by one event may be told its task by another, and neither is
    /// allowed to restate itself.
    private func link(
        child: AgentID, to parent: AgentRef, task: String?, into deltas: inout [WorldDelta]
    ) {
        guard child != parent.agent else { return }
        guard projects[parent.project]?.sessions[parent.session] != nil else { return }
        let childRef = AgentRef(project: parent.project, session: parent.session, agent: child)

        guard projects[parent.project]!.sessions[parent.session]!.agents[child] != nil else {
            // Not there yet — the app attached mid-session and missed the
            // child's `SubagentStart`. Both halves wait together, and
            // `ensureAgent` plays them out when the character arrives.
            var pending = projects[parent.project]!.sessions[parent.session]!
                .pendingParents[child] ?? PendingLink(parent: parent.agent)
            // The parent keeps the behaviour it has always had — the most
            // recent writer — and the task takes the first one that said
            // anything, which is what makes its eventual delta at-most-once
            // regardless of how many dispatches named this child before it
            // appeared. A later `nil` is silence, not a retraction, so it may
            // not erase a task we hold.
            pending.parent = parent.agent
            if pending.task == nil { pending.task = task }
            projects[parent.project]!.sessions[parent.session]!.pendingParents[child] = pending
            return
        }
        // Emitted at most once. A repeated `PostToolUse` for the same dispatch
        // is the same fact, not a second one.
        if projects[parent.project]!.sessions[parent.session]!.agents[child]!.parent == nil {
            projects[parent.project]!.sessions[parent.session]!.agents[child]!.parent = parent.agent
            deltas.append(.agentLinked(agent: childRef, parent: parent.agent))
        }
        if let task,
           projects[parent.project]!.sessions[parent.session]!.agents[child]!.task == nil {
            projects[parent.project]!.sessions[parent.session]!.agents[child]!.task = task
            deltas.append(.agentTasked(agent: childRef, task: task))
        }
    }

    /// Raises or clears the attention badge, emitting a delta only on a real
    /// change.
    ///
    /// Idempotent in both directions, and it may not assume any notification
    /// arrives at most once. `idle_prompt` fires once per *idle stretch*, not
    /// once per session — `fixtures/denial-then-work.jsonl` has two, 60 s after
    /// each of two `Stop`s — and a second identical `permission_prompt` is the
    /// same fact. Neither may produce a second badge change: a delta stream that
    /// repeats itself makes the scene's suppression memory the only thing
    /// standing between a stable badge and a flicker. A repeat *after* a clear
    /// is a new fact and does emit, which is what the two idle stretches in that
    /// fixture look like.
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

    // MARK: The permission gate marker — ADR-001 (d)

    /// Rule 1. Record that a gate is open for this agent, and which calls it
    /// held open at that instant.
    ///
    /// Re-arming over an existing mark is deliberate, and it is now the
    /// conservative reading of something observed rather than of something
    /// merely untested. ADR-001 refused to assume "at most one gate at a time"
    /// and M6c refuted it: `fixtures/concurrent-permission-gates.jsonl` holds
    /// two gates open together for 31.8 s. They are on two *different* agents —
    /// one agent holding two at once has still never been seen, which follows
    /// from the TUI serialising a batch's tool calls — so this path is the
    /// unobserved one, and taking the later snapshot is the safe answer for it:
    /// the agent's open-call set as of the most recent thing we know it is
    /// blocked on.
    ///
    /// **The delta is a change, never a repeat**, which is what the re-arm above
    /// makes worth saying: re-snapshotting the marked set for an agent already
    /// at a gate changes which calls a later prompt would shorten, and changes
    /// nothing whatever about *whether* a gate is open. The scene is told the
    /// second fact and only the second fact. [ADR-005 §7]
    private func armPermissionGate(ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard let state = projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] else {
            // No character to mark. Conjuring one out of a gate is not this
            // function's job, and `ensureSession` has already made the main
            // agent for any session this event could belong to.
            return
        }
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!
            .permissionGate = Set(state.openCalls.keys)
        if state.permissionGate == nil {
            deltas.append(.gateChanged(agent: ref, isGated: true))
        }
    }

    /// Rule 2. The gate is no longer pending, so nothing may act on the mark.
    ///
    /// **Every path that clears the mark comes through here, and every one of
    /// them now says so out loud** [I4]. There are five — a marked call closing
    /// or being abandoned (`removeCall`), `Stop`, `SubagentStop`, and the
    /// `UserPromptSubmit` that answers the dialog — and the sixth, departure,
    /// deliberately does not: it deletes the whole `AgentState`, and the
    /// `agentDeparted` riding with it takes the character the fact was about.
    /// That is the same division `dormancyChanged` already makes.
    ///
    /// The guard is what keeps it a change rather than a repeat: disarming a
    /// gate that was never armed is silent, which is the ordinary case — every
    /// `Stop` in a session that saw no dialog, and every close of every call.
    private func disarmPermissionGate(ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard projects[ref.project]?.sessions[ref.session]?
            .agents[ref.agent]?.permissionGate != nil else { return }
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.permissionGate = nil
        deltas.append(.gateChanged(agent: ref, isGated: false))
    }

    /// Rule 3. A `UserPromptSubmit` reached an agent whose gate is still armed,
    /// so the human answered and the answer was **no** — an approval closes the
    /// gated call, and that close disarms the mark before any prompt can reach
    /// here.
    ///
    /// Every still-open call in the marked set has its deadline pulled in to
    /// `now + G`. **Shortened, not closed.** No call is removed here, no delta
    /// is emitted here, and no close path is involved: the reaper closes these
    /// on its next sweep past the new deadline and emits `.callAbandoned`
    /// exactly as it always has, so the character simply returns to idle. [I4]
    ///
    /// The mark is spent either way — this is the answer it was waiting for.
    ///
    /// **What this can still get wrong**, stated rather than hidden: the marked
    /// set is *all* of the agent's open calls, because nothing in the event
    /// names the gated one. A main-thread batch mixing a gated call with a
    /// sibling that legitimately runs past 60 s therefore reaps the sibling
    /// early, which is fiction. It needs a shape no capture contains, and it is
    /// ADR-001's one acknowledged hazard.
    private func answerPermissionGate(ref: AgentRef, at now: Date, into deltas: inout [WorldDelta]) {
        guard let marked = projects[ref.project]?.sessions[ref.session]?
            .agents[ref.agent]?.permissionGate else { return }
        defer { disarmPermissionGate(ref: ref, into: &deltas) }

        for toolUseID in marked {
            guard let call = projects[ref.project]!.sessions[ref.session]!
                .agents[ref.agent]!.openCalls[toolUseID] else { continue }
            let pulledIn = reaper.shortenedDeadline(call.deadline, answeredAt: now)
            guard pulledIn != call.deadline else { continue }
            projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!
                .openCalls[toolUseID] = OpenCall(
                    toolUseID: call.toolUseID,
                    toolName: call.toolName,
                    startedAt: call.startedAt,
                    deadline: pulledIn)
        }
    }

    /// The marked set for one agent, or `nil` when the gate is disarmed.
    ///
    /// Internal, not public. **The *set* drives no drawing and belongs in no
    /// delta** — it decides deadlines, it names no gated call because the event
    /// names none, and a scene given it could only guess. Whether the gate is
    /// open at all is a different question and it does leave, as
    /// `WorldDelta.gateChanged`; `AgentSnapshot.isGated` is the same `Bool` as a
    /// standing value. This accessor exists so the tests can assert the mark
    /// arms, disarms and is reaped, rather than inferring all three from
    /// deadlines.
    func permissionGateMark(_ ref: AgentRef) -> Set<ToolUseID>? {
        projects[ref.project]?.sessions[ref.session]?.agents[ref.agent]?.permissionGate
    }

    // MARK: The turn — ADR-005 §3

    /// **The main thread's turn boundary, and the only path that closes one
    /// without also removing the character.**
    ///
    /// `Stop` fires once per assistant message stream and can fire several times
    /// in one user turn, which `docs/03-EVENT-MODEL.md` has always warned makes
    /// it an unreliable *end-of-turn* signal — and which ADR-005 §9 risk 3 names
    /// as the one thing that could put the strobe back on a different key. The
    /// measurement over all seventeen captures, taken before this was built:
    ///
    /// - **No `Stop` in the corpus is followed by more work in the same turn.**
    ///   Not one of the 26 is followed by a `PreToolUse` or a `SubagentStart`
    ///   before something re-opens the turn. Every one is followed either by a
    ///   `UserPromptSubmit` (12 of them; 4.23 s at the shortest) or by the
    ///   session ending (14).
    /// - **That is structural rather than lucky.** The way an async subagent
    ///   wakes the main thread — the very shape §9 worried about — is a
    ///   *synthetic* `UserPromptSubmit`, which is itself an opener. So "several
    ///   `Stop`s in one user turn" always has a prompt between them, and the room
    ///   draws the same picture either way: the main thread stopped, then was
    ///   handed something.
    /// - The residual risk is a subagent that returns in milliseconds, which
    ///   `fixtures/` does not contain. ADR-005 §10 item 2 is the guard, and it is
    ///   a live capture rather than anything in this function.
    ///
    /// **It closes the turn whatever the open-call set holds**, and the corpus
    /// says that matters five times: three `Stop`s in `denial-then-work` and one
    /// each in `parallel-denial` and `permission-prompt` arrive with a `Bash`
    /// still open. Every one of those five is an interactively denied call that
    /// **nothing in its stream will ever close** — the shape ADR-001 exists for —
    /// so standing that character up is the truer picture, not the less true one.
    /// Consulting the open-call set here would also re-couple the two channels
    /// ADR-005 §3 separated, on the side where the set is known to be stale.
    private func endTurn(ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent]?.hasTurn == true
        else { return }
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.hasTurn = false
        deltas.append(.turnChanged(agent: ref, hasTurn: false))
    }

    /// The openers ADR-005 §3 names: `UserPromptSubmit`, `SubagentStart`, and any
    /// `PreToolUse`. An agent doing something is in a turn.
    ///
    /// Silent for an agent already in one, which is the ordinary case — every
    /// `PreToolUse` of every fixture but the eleven that follow a `Stop`. The
    /// guard is what keeps this a change rather than a repeat.
    private func beginTurn(ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent]?.hasTurn == false
        else { return }
        projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.hasTurn = true
        deltas.append(.turnChanged(agent: ref, hasTurn: true))
    }

    private func setLifecycle(_ lifecycle: AgentLifecycle, ref: AgentRef) {
        projects[ref.project]?.sessions[ref.session]?.agents[ref.agent]?.lifecycle = lifecycle
    }

    // MARK: Dormancy — `SubagentStop` is a turn boundary, not a death

    /// **A subagent that stops does not leave the room. It goes dormant and
    /// stays on screen.**
    ///
    /// `SubagentStop` means "this subagent finished and its result went to its
    /// parent". Departing on it made the room assert *this agent is gone* out of
    /// data that says only *this agent finished a turn*, and
    /// `fixtures/four-subagents.jsonl` is the captured proof that the two are
    /// different claims: two of its four agents stop, are resumed by the parent
    /// with `SendMessage`, and come back. Between the fourth spawn and the last
    /// stop the departing lifecycle held all four for 56% of the elapsed time,
    /// dropping to two for 7.3 s and to one for 6.7 s, while the parent had four
    /// assigned throughout. For a surface whose one sentence is "you glance at
    /// the notch and know what your agents are doing", that is the [I1]
    /// violation — not the fix for one. A dormant character is the honest
    /// rendering of a fact we actually hold.
    ///
    /// **The `.reporting` beat is untouched.** `reportDelivered` is still
    /// emitted, still on the same event, and it still licenses the one
    /// dramatisation this project allows — walk to the anchor, deliver. What
    /// changed is only where the character ends up afterwards: its own seat,
    /// idle, instead of off screen.
    ///
    /// **Visually distinct from an idle-but-live agent.** This
    /// paragraph used to say the opposite, and the reversal is worth stating in
    /// full because the old argument was half right.
    ///
    /// The old argument: "finished and might come back" and "between tool calls"
    /// are different facts and the room would be better for separating them, but
    /// nothing we own can draw the difference — there are six body states and
    /// none means dormant, and the single badge anchor held one non-tool glyph,
    /// `attention`, which asserts "the room needs you" and would be a lie here.
    /// Inventing a pose is what [I1] forbids, so both rendered `idle` and no
    /// delta carried the lifecycle.
    ///
    /// The half that survives is the **body**: M6b cut the pack's `sleep` row
    /// and measured it — six frames of a head on a pillow, drawn from above,
    /// with no body, to be composited onto a top-down bed. On a character
    /// sitting side-on in an office chair it is a floating head. There is still
    /// no dormant body state and there must not be one.
    ///
    /// The half that does not is the **badge**, because the premise "the single
    /// badge anchor holds one non-tool glyph" stopped being true. Modern
    /// Interiors' UI sheet carries a blue `Z` bubble — the same component, in
    /// the same frame, as `attention` — and `badges.states` exists precisely for
    /// badge states that answer to no tool. It ships as `badges.states.sleep`,
    /// it needs no new manifest key and no new `BodyState`, and it asserts
    /// exactly what this flag knows: *this character finished a turn and is
    /// still here*. That is not a pose invented to fill a gap; it is real art
    /// saying a true thing. [I1]
    ///
    /// So `dormancyChanged` is emitted here and cleared in `revive`, and the
    /// seam the old paragraph named — "if a scene ever earns an honest treatment
    /// for dormancy, that delta is the seam" — is the delta that now exists.
    ///
    /// **Reapable, with no deadline of its own.** [I4] Dormancy lives inside
    /// `AgentState`, so the two paths that genuinely mean *gone* — `SessionEnd`
    /// and the 30-minute session-idle sweep — remove it with the character, by
    /// construction and not by remembering to. A third timer was considered and
    /// rejected: "depart after N minutes dormant" would be a number with nothing
    /// behind it, and it would reintroduce the bug for any agent resumed later
    /// than N. The bound that exists is the right one — an assignment is live
    /// for exactly as long as its session is.
    private func goDormant(ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else { return }
        // ADR-001 (d) rule 2, read for a subagent. `Stop` disarms the main
        // thread's mark because the turn completed; `SubagentStop` is that same
        // fact for a subagent, so the mark cannot survive it. This is load-
        // bearing now rather than incidental: departure used to clear the mark
        // by deleting the whole `AgentState`, and an agent that stops holding an
        // *empty* marked set — a legal snapshot — would otherwise carry an armed
        // gate into dormancy forever and be badged by a later `permission_prompt`
        // it has nothing to do with. [I1/I4]
        //
        // The ordinary case is already disarmed by the `abandonAll` above, which
        // removes marked calls; this catches the empty mark, and the delta it
        // emits is suppressed for the ordinary case by `disarmPermissionGate`'s
        // own change-not-repeat guard.
        disarmPermissionGate(ref: ref, into: &deltas)
        let wasDormant =
            projects[ref.project]!.sessions[ref.session]!.agents[ref.agent]!.lifecycle == .dormant
        setLifecycle(.dormant, ref: ref)
        deltas.append(.reportDelivered(agent: ref))
        // A *change*, never a repeat. A second `SubagentStop` for an agent that
        // is already dormant is the same fact, and a delta stream that restates
        // it would make the scene re-set a badge it already has.
        if !wasDormant { deltas.append(.dormancyChanged(agent: ref, isDormant: true)) }
    }

    /// **A second `SubagentStart` for a known `agent_id` revives that character
    /// in place.** No second character, no second seat, no re-spawn walk.
    ///
    /// Reached from `ensureAgent`, so *every* consumed event for a dormant agent
    /// revives it, not only the lifecycle one. That is deliberate and it is the
    /// stricter half: `SubagentStart` is not guaranteed — the app can attach
    /// mid-session and a resumed agent's first evidence is then its own
    /// `PreToolUse` — and an agent left dormant while it is demonstrably working
    /// would be a second lie in the other direction.
    ///
    /// It restores `.active` and never the caller's requested lifecycle, which
    /// is the whole difference between reviving and re-spawning: `SubagentStart`
    /// asks for `.spawning`, and `.spawning` means "walk in from the room edge".
    /// A revived agent never left it.
    ///
    /// **Emits `dormancyChanged(isDormant: false)` and nothing else.** The
    /// character is already on screen in its own seat, in the right variant,
    /// under the right plate; the one thing that changes is that the `sleep`
    /// badge comes down, because the agent is answering to events again. It used
    /// to emit nothing at all, which was correct while dormant and idle drew
    /// identically and is not any more.
    ///
    /// The guard is what keeps it a change rather than a repeat: an agent that
    /// was not dormant produces no delta, so the ordinary case — every consumed
    /// event of a live agent passing through `ensureAgent` — is still silent.
    ///
    /// It fires *before* the event's own effect, so an event that both revives
    /// and opens a call emits the wake first and the `callOpened` behind it,
    /// which is the order the facts happened in.
    private func revive(_ ref: AgentRef, into deltas: inout [WorldDelta]) {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent]?.lifecycle == .dormant
        else { return }
        setLifecycle(.active, ref: ref)
        deltas.append(.dormancyChanged(agent: ref, isDormant: false))
    }

    private func open(
        toolUseID: ToolUseID, toolName: String, task: String?, ref: AgentRef, at now: Date,
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
            deadline: reaper.deadline(forTool: toolName, startedAt: now),
            // Held on the call, not in a table beside it: the call is already
            // keyed by `tool_use_id` and already reaped by every path, so this
            // adds no open state of its own. [I3/I4]
            dispatchedTask: task)
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
    ///
    /// Returns the call it removed, so a caller that needs something the call
    /// was carrying does not have to read it out of the model first and hope
    /// the two agree. Exactly one caller does: the `Agent` dispatch's
    /// `PostToolUse`, which wants the `dispatchedTask` off the very call it is
    /// closing. `nil` therefore means "there was no such open call", which is
    /// the already-closed case and is a no-op for everyone.
    @discardableResult
    private func close(
        _ toolUseID: ToolUseID, ref: AgentRef, outcome: CallOutcome,
        into deltas: inout [WorldDelta]
    ) -> OpenCall? {
        guard let call = removeCall(toolUseID, ref: ref, into: &deltas) else { return nil }
        deltas.append(.callClosed(
            agent: ref, toolUseID: toolUseID, toolName: call.toolName, outcome: outcome))
        return call
    }

    private func abandon(
        _ toolUseID: ToolUseID, ref: AgentRef, reason: AbandonReason,
        into deltas: inout [WorldDelta]
    ) {
        guard let call = removeCall(toolUseID, ref: ref, into: &deltas) else { return }
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

    /// The one point at which a call leaves an agent's open set, whichever path
    /// asked. Every close and every abandonment funnels through here.
    ///
    /// ADR-001 (d) rule 2 lives here for that reason, and *only* that reason:
    /// the three close paths are verified and load-bearing and are not being
    /// changed — `PostToolUse`, `PostToolUseFailure` and `PostToolBatch` still
    /// close exactly the ids they always closed and emit exactly the deltas they
    /// always emitted. What the marker needs is to notice that a marked call
    /// went away, and there is exactly one place where that happens.
    ///
    /// **Any close of any marked call disarms the whole mark**, which is the
    /// approve path: the gated call closes normally, so the human said yes and
    /// no later prompt may shorten anything. Abandonment counts too — a call
    /// already reaped is not one a deadline change could still help.
    ///
    /// The `gateChanged(isGated: false)` that disarm now emits lands **ahead of**
    /// the `.callClosed` or `.callAbandoned` its caller appends, which is the
    /// order `clearsAttention` already reads in: the wait ended, then the work
    /// did. Both are in one batch, so nothing on screen depends on it; the delta
    /// stream is easier to read for it.
    private func removeCall(
        _ toolUseID: ToolUseID, ref: AgentRef, into deltas: inout [WorldDelta]
    ) -> OpenCall? {
        guard projects[ref.project]?.sessions[ref.session]?.agents[ref.agent] != nil else {
            return nil
        }
        if projects[ref.project]!.sessions[ref.session]?.agents[ref.agent]?
            .permissionGate?.contains(toolUseID) == true {
            disarmPermissionGate(ref: ref, into: &deltas)
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
