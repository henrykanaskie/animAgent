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

public enum AgentLifecycle: String, Sendable, Hashable {
    case spawning
    case active
    case reporting
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

/// The only thing that leaves `WorldModel`. Value types, ordered,
/// self-contained.
public enum WorldDelta: Sendable, Hashable, CustomStringConvertible {
    case agentAppeared(agent: AgentRef, agentType: String?, lifecycle: AgentLifecycle)
    case agentDeparted(agent: AgentRef)
    case callOpened(agent: AgentRef, call: OpenCall)
    case callClosed(agent: AgentRef, toolUseID: ToolUseID, toolName: String, outcome: CallOutcome)
    case callAbandoned(agent: AgentRef, toolUseID: ToolUseID, toolName: String, reason: AbandonReason)
    case reportDelivered(agent: AgentRef)
    case populationChanged(project: String, count: Int)

    public var description: String {
        switch self {
        case let .agentAppeared(agent, agentType, lifecycle):
            return "agentAppeared    \(agent) type=\(agentType ?? "-") \(lifecycle.rawValue)"
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
    public let lifecycle: AgentLifecycle
    /// Sorted by start time. A *set* of calls — never a single current tool.
    public let openCalls: [OpenCall]

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
