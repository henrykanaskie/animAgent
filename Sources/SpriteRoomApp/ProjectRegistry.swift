import Foundation
import SpriteRoomCore

/// Which projects exist, and what each one's room currently looks like.
///
/// **This is a projection, not a query.** Everything in here is folded out of
/// the delta stream on its way past; nothing in this file ever asks
/// `WorldModel` anything. That matters because the panel needs to answer a
/// question the deltas do not directly answer — *what does project B look like
/// right now, given that I have been rendering project A?* — and the honest way
/// to answer it downstream is to have been keeping score all along.
///
/// The reconstruction it emits is made only of deltas that really happened, so
/// nothing invented reaches the scene. [I1]
///
/// **Time is injected, never observed.** Two of the things the menu shows —
/// that a project has ended, and that it is old enough to stop showing — are
/// functions of an elapsed interval, and there is no clock inside this type.
/// `absorb` and `sweep` are handed the instant, the way `Reaper` is handed one
/// by `WorldModel.sweep(at:)`. That is what makes the ageing testable without a
/// `sleep`, and it keeps the arrow pointing one way: deltas plus a number in,
/// menu contents out.
struct ProjectRegistry: Sendable {

    /// Whether the menu should still present this project as something that is
    /// happening.
    ///
    /// Derived state, but stored rather than computed at read time, so that
    /// `entries` is a pure function of the registry and never sneaks a clock
    /// reading into a getter.
    enum Liveness: Sendable, Hashable {
        /// Someone is in the room, or was recently enough that we are not
        /// prepared to call it.
        case live
        /// Every session under this `cwd` has ended and none has come back.
        case ended
    }

    /// One project, as the menu bar shows it.
    struct Entry: Sendable, Hashable {
        /// The `cwd`. The identity.
        let project: String
        /// What to put in the menu — the last path component, extended
        /// leftwards until it is unambiguous.
        let displayName: String
        /// Characters currently in that room.
        let population: Int
        /// Live or ended. See `ProjectRegistry.endedAfter`.
        let liveness: Liveness

        init(project: String, displayName: String, population: Int, liveness: Liveness = .live) {
            self.project = project
            self.displayName = displayName
            self.population = population
            self.liveness = liveness
        }
    }

    // MARK: Ageing policy

    /// How long a project may sit at population 0 before the menu stops
    /// calling it live.
    ///
    /// Population 0 is a clean signal here and a short grace period is all it
    /// needs. `Stop` fires at the end of every assistant turn and emits no
    /// delta, and the main agent departs only on `SessionEnd` — so a project
    /// does *not* dip to 0 between turns. Reaching 0 means every session under
    /// that `cwd` really ended.
    ///
    /// The one case it cannot distinguish is `/clear`, which ends the session
    /// and silently starts another in the same process whose first event is an
    /// ordinary `UserPromptSubmit` (`docs/FINDINGS-M0.md`). The gap is however
    /// long the user takes to type the next prompt, so **no finite number
    /// covers it** and this one does not try to. It does not need to, because
    /// the two errors are not symmetric:
    ///
    /// - Too short, and a returning session flips the label back to live. The
    ///   entry keeps its `cwd`, its first-seen slot and its checkmark; nothing
    ///   moves, nothing is rebuilt. The cost is a word that was wrong for a
    ///   while.
    /// - Too long, and the menu says a project is running when it is not,
    ///   which is the failure this whole file exists to avoid.
    ///
    /// So: short. 90 s is the one measured quiet interval in the fixtures —
    /// `idle-notification` shows Claude Code itself calling a session idle
    /// 60.02 s after `Stop` — plus half again for headroom. It is deliberately
    /// far shorter than `Reaper.sessionIdleTimeout`, and the asymmetry is the
    /// point: the reaper guards an *animation*, where firing early invents work
    /// that was not happening [I1]; this guards a *line of text the user
    /// reads*, where firing late is the lie and firing early corrects itself.
    static let endedAfter: TimeInterval = 90

    /// How long an ended project stays in the menu before it is dropped
    /// altogether. Measured from the same instant as `endedAfter`.
    ///
    /// Keeping the corpse briefly is a status feature: "has anything finished"
    /// is one of the three things the PRD says you want at a glance. Keeping it
    /// indefinitely is a *history* feature, and history is an explicit v1
    /// non-goal — a menu that accumulates every directory you have opened today
    /// stops being glanceable, which is the only thing it is for.
    ///
    /// The number is `Reaper`'s session idle timeout rather than a new one.
    /// That interval is already this app's stated answer to "silent for this
    /// long means definitely over", and there is no reason for the menu to hold
    /// a second opinion. Read from `Reaper` rather than retyped, so the two
    /// cannot drift.
    static let forgottenAfter: TimeInterval = Reaper().sessionIdleTimeout

    private struct AgentState: Sendable {
        var agentType: String?
        var lifecycle: AgentLifecycle
        /// Keyed by `tool_use_id`, never a single current tool. [I3]
        var openCalls: [ToolUseID: OpenCall] = [:]
        /// From `.agentLinked`. Kept so that switching to this project
        /// reconstructs the link too — otherwise a character that was linked
        /// while off screen would report to the wrong anchor once shown.
        var parent: AgentID?
        /// From `.agentTasked`: what this subagent was dispatched to do. Same
        /// reason as `parent`, and it arrives the same way — retroactively,
        /// once the dispatching call's `PostToolUse` names the child. A task
        /// learned while this project was off screen must survive the switch,
        /// or the plate comes back blank for an agent we do know about.
        var task: String?
        /// From `.attentionChanged`. Same reason as `parent`: it is live state,
        /// so a switch back to this project must not lose it.
        var attention: AttentionKind?
    }

    private struct ProjectState: Sendable {
        var agents: [AgentRef: AgentState] = [:]
        /// When this project's population last became 0. `nil` while anyone is
        /// in the room. The only clock reading the registry retains, and it is
        /// one it was handed.
        var emptySince: Date?
        /// Set by `sweep` once `emptySince` is older than `endedAfter`,
        /// cleared by `absorb` the moment anybody walks back in.
        var hasEnded = false
    }

    private var states: [String: ProjectState] = [:]
    /// First-seen order. Stable, so the menu does not reshuffle under the
    /// pointer when a project's population changes.
    private(set) var order: [String] = []

    // MARK: Folding

    /// Absorbs one frame's deltas. Returns `true` when the *roster* changed —
    /// a project appeared, or a population moved, or one that had ended came
    /// back — which is the only thing the menu bar needs to redraw for.
    @discardableResult
    mutating func absorb(_ deltas: [WorldDelta], at now: Date) -> Bool {
        var rosterChanged = false
        for delta in deltas {
            let project = delta.projectKey
            if states[project] == nil {
                // Born empty. A project's first delta is usually the one that
                // populates it, in which case this stamp is cleared on the very
                // next line; when it is not — a stray close for an agent that
                // is already gone — the clock starts here rather than never.
                states[project] = ProjectState(emptySince: now)
                order.append(project)
                rosterChanged = true
            }
            let before = states[project]?.agents.count ?? 0

            switch delta {
            case let .agentAppeared(agent, agentType, lifecycle):
                var state = states[project]?.agents[agent]
                    ?? AgentState(agentType: agentType, lifecycle: lifecycle)
                state.agentType = agentType ?? state.agentType
                state.lifecycle = lifecycle
                states[project]?.agents[agent] = state
            case let .agentLinked(agent, parent):
                states[project]?.agents[agent]?.parent = parent
            case let .agentTasked(agent, task):
                states[project]?.agents[agent]?.task = task
            case let .agentDeparted(agent):
                states[project]?.agents.removeValue(forKey: agent)
            case let .callOpened(agent, call):
                states[project]?.agents[agent]?.openCalls[call.toolUseID] = call
            case let .callClosed(agent, toolUseID, _, _),
                 let .callAbandoned(agent, toolUseID, _, _):
                states[project]?.agents[agent]?.openCalls.removeValue(forKey: toolUseID)
            case let .attentionChanged(agent, attention):
                // Live state, so it is kept and replayed: a character that was
                // waiting on a human while off screen must still be waiting
                // when you switch to its room. Does not touch population.
                states[project]?.agents[agent]?.attention = attention
            case let .dormancyChanged(agent, isDormant):
                // Live state, same as `attention` and for the same reason: a
                // subagent that finished its turn while you were looking at
                // another project must still be asleep when you come back. It
                // is folded into the lifecycle the entry already carries rather
                // than stored twice. Does not touch population — a dormant
                // agent is still in the room, which is the whole point of it.
                states[project]?.agents[agent]?.lifecycle = isDormant ? .dormant : .active
            case .reportDelivered, .populationChanged:
                break
            }

            let after = states[project]?.agents.count ?? 0
            if after != before { rosterChanged = true }

            if after > 0 {
                // Alive again. `/clear` lands here: same `cwd`, new
                // `session_id`, and the entry keeps its slot in `order` because
                // the identity the menu is keyed on never changed.
                if states[project]?.hasEnded == true { rosterChanged = true }
                states[project]?.emptySince = nil
                states[project]?.hasEnded = false
            } else if states[project]?.emptySince == nil {
                states[project]?.emptySince = now
            }
        }
        return rosterChanged
    }

    /// Age the roster against an injected instant. Returns `true` when the menu
    /// needs to redraw, and `false` on every call that changed nothing — this
    /// runs once a frame, so a sweep that reported a change every time would
    /// rebuild the menu sixty times a second.
    ///
    /// `pinned` is the project the panel is currently showing, and it is never
    /// dropped. Deleting the thing the user is looking at would change what
    /// they are looking at without their asking, and there is no surface to
    /// explain it on: the panel is pointer-only and has no text. The selection
    /// is also the one piece of state in this app the user owns, so the app
    /// taking it back is out of character for a read-only status surface. It
    /// still gets *marked* ended — that part is true and worth saying — and it
    /// becomes droppable on the first sweep after they switch away.
    @discardableResult
    mutating func sweep(at now: Date, pinning pinned: String?) -> Bool {
        var changed = false
        for project in order {
            guard var state = states[project], let emptySince = state.emptySince else { continue }
            let empty = now.timeIntervalSince(emptySince)
            if empty >= Self.forgottenAfter, project != pinned {
                states.removeValue(forKey: project)
                changed = true
                continue
            }
            if empty >= Self.endedAfter, !state.hasEnded {
                state.hasEnded = true
                states[project] = state
                changed = true
            }
        }
        if changed { order.removeAll { states[$0] == nil } }
        return changed
    }

    // MARK: Reading

    var projects: [String] { order }
    var isEmpty: Bool { order.isEmpty }

    func population(of project: String) -> Int { states[project]?.agents.count ?? 0 }

    func liveness(of project: String) -> Liveness {
        states[project]?.hasEnded == true ? .ended : .live
    }

    /// The menu's contents, in first-seen order.
    var entries: [Entry] {
        let names = Self.displayNames(for: order)
        return order.map {
            Entry(
                project: $0,
                displayName: names[$0] ?? $0,
                population: population(of: $0),
                liveness: liveness(of: $0))
        }
    }

    /// The deltas that would bring an empty room to this project's current
    /// state, in an order a fresh `SceneDirector` accepts.
    ///
    /// Used when the selection changes: the scene is rebuilt from nothing and
    /// fed this. Sorted, so switching to a project twice produces the same
    /// seating both times.
    func reconstruct(_ project: String) -> [WorldDelta] {
        guard let roster = states[project]?.agents else { return [] }
        var deltas: [WorldDelta] = []
        for ref in roster.keys.sorted() {
            guard let state = roster[ref] else { continue }
            deltas.append(
                .agentAppeared(
                    agent: ref, agentType: state.agentType, lifecycle: state.lifecycle))
            if let parent = state.parent {
                deltas.append(.agentLinked(agent: ref, parent: parent))
            }
            // Behind the link, which is the order the one payload said them in
            // and the order a live stream produces.
            if let task = state.task {
                deltas.append(.agentTasked(agent: ref, task: task))
            }
            if let attention = state.attention {
                deltas.append(.attentionChanged(agent: ref, attention: attention))
            }
            // A dormant character must still be dormant after a project switch.
            // The scene is rebuilt from nothing and fed this list, and a fresh
            // `SceneDirector` starts every presentation awake — so without this
            // line switching away and back would silently wake a subagent that
            // has not done anything since. The delta is a real one carrying a
            // fact the registry really absorbed, so nothing invented reaches
            // the scene. [I1]
            if state.lifecycle == .dormant {
                deltas.append(.dormancyChanged(agent: ref, isDormant: true))
            }
        }
        for ref in roster.keys.sorted() {
            guard let state = roster[ref] else { continue }
            for call in state.openCalls.values.sorted() {
                deltas.append(.callOpened(agent: ref, call: call))
            }
        }
        deltas.append(.populationChanged(project: project, count: roster.count))
        return deltas
    }

    // MARK: Naming

    /// Last path component, lengthened only where that collides.
    ///
    /// Two checkouts of the same repository under different parents are the
    /// case this exists for; showing both as `teamwork` would make the menu
    /// useless in exactly the situation the menu is for.
    static func displayNames(for projects: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var depth = 1
        var unresolved = Set(projects)
        while !unresolved.isEmpty, depth <= 8 {
            var byName: [String: [String]] = [:]
            for project in unresolved {
                byName[tail(project, components: depth), default: []].append(project)
            }
            for (name, owners) in byName where owners.count == 1 {
                result[owners[0]] = name
                unresolved.remove(owners[0])
            }
            depth += 1
        }
        // Anything still colliding at eight components deep is shown whole.
        for project in unresolved { result[project] = project }
        return result
    }

    private static func tail(_ path: String, components: Int) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return path }
        return parts.suffix(components).joined(separator: "/")
    }
}

extension WorldDelta {
    /// The `cwd` bucket a delta belongs to. Every delta has exactly one.
    var projectKey: String {
        switch self {
        case let .agentAppeared(agent, _, _): return agent.project
        case let .agentLinked(agent, _): return agent.project
        case let .agentTasked(agent, _): return agent.project
        case let .agentDeparted(agent): return agent.project
        case let .callOpened(agent, _): return agent.project
        case let .callClosed(agent, _, _, _): return agent.project
        case let .callAbandoned(agent, _, _, _): return agent.project
        case let .reportDelivered(agent): return agent.project
        case let .attentionChanged(agent, _): return agent.project
        case let .dormancyChanged(agent, _): return agent.project
        case let .populationChanged(project, _): return project
        }
    }
}
