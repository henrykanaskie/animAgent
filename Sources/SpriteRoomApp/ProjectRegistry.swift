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
struct ProjectRegistry: Sendable {

    /// One project, as the menu bar shows it.
    struct Entry: Sendable, Hashable {
        /// The `cwd`. The identity.
        let project: String
        /// What to put in the menu — the last path component, extended
        /// leftwards until it is unambiguous.
        let displayName: String
        /// Characters currently in that room.
        let population: Int
    }

    private struct AgentState: Sendable {
        var agentType: String?
        var lifecycle: AgentLifecycle
        /// Keyed by `tool_use_id`, never a single current tool. [I3]
        var openCalls: [ToolUseID: OpenCall] = [:]
    }

    private var agents: [String: [AgentRef: AgentState]] = [:]
    /// First-seen order. Stable, so the menu does not reshuffle under the
    /// pointer when a project's population changes.
    private(set) var order: [String] = []

    // MARK: Folding

    /// Absorbs one frame's deltas. Returns `true` when the *roster* changed —
    /// a project appeared, or a population moved — which is the only thing the
    /// menu bar needs to redraw for.
    @discardableResult
    mutating func absorb(_ deltas: [WorldDelta]) -> Bool {
        var rosterChanged = false
        for delta in deltas {
            let project = delta.projectKey
            if agents[project] == nil {
                agents[project] = [:]
                order.append(project)
                rosterChanged = true
            }
            let before = agents[project]?.count ?? 0

            switch delta {
            case let .agentAppeared(agent, agentType, lifecycle):
                var state = agents[project]?[agent]
                    ?? AgentState(agentType: agentType, lifecycle: lifecycle)
                state.agentType = agentType ?? state.agentType
                state.lifecycle = lifecycle
                agents[project]?[agent] = state
            case let .agentDeparted(agent):
                agents[project]?.removeValue(forKey: agent)
            case let .callOpened(agent, call):
                agents[project]?[agent]?.openCalls[call.toolUseID] = call
            case let .callClosed(agent, toolUseID, _, _),
                 let .callAbandoned(agent, toolUseID, _, _):
                agents[project]?[agent]?.openCalls.removeValue(forKey: toolUseID)
            case .reportDelivered, .populationChanged:
                break
            }

            if agents[project]?.count != before { rosterChanged = true }
        }
        return rosterChanged
    }

    // MARK: Reading

    var projects: [String] { order }
    var isEmpty: Bool { order.isEmpty }

    func population(of project: String) -> Int { agents[project]?.count ?? 0 }

    /// The menu's contents, in first-seen order.
    var entries: [Entry] {
        let names = Self.displayNames(for: order)
        return order.map {
            Entry(
                project: $0,
                displayName: names[$0] ?? $0,
                population: population(of: $0))
        }
    }

    /// The deltas that would bring an empty room to this project's current
    /// state, in an order a fresh `SceneDirector` accepts.
    ///
    /// Used when the selection changes: the scene is rebuilt from nothing and
    /// fed this. Sorted, so switching to a project twice produces the same
    /// seating both times.
    func reconstruct(_ project: String) -> [WorldDelta] {
        guard let roster = agents[project] else { return [] }
        var deltas: [WorldDelta] = []
        for ref in roster.keys.sorted() {
            guard let state = roster[ref] else { continue }
            deltas.append(
                .agentAppeared(
                    agent: ref, agentType: state.agentType, lifecycle: state.lifecycle))
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
        case let .agentDeparted(agent): return agent.project
        case let .callOpened(agent, _): return agent.project
        case let .callClosed(agent, _, _, _): return agent.project
        case let .callAbandoned(agent, _, _, _): return agent.project
        case let .reportDelivered(agent): return agent.project
        case let .populationChanged(project, _): return project
        }
    }
}
