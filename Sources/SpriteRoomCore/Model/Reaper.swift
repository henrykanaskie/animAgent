import Foundation

/// Deadline policy. Every open state is reapable — a character that types
/// forever is the signature bug of this project. [I4]
///
/// `Reaper` holds no state and reads no clock. `WorldModel.sweep(at:)` supplies
/// the instant, so time is always injected and never observed. That is what
/// makes the `killed-session` fixture testable without a `sleep`.
public struct Reaper: Sendable, Hashable {

    /// A session with no event of any kind for this long is presumed dead.
    /// Belt and braces alongside the per-call deadline and `SessionEnd`; keep
    /// all three. [I4]
    public let sessionIdleTimeout: TimeInterval

    public init(sessionIdleTimeout: TimeInterval = 30 * 60) {
        self.sessionIdleTimeout = sessionIdleTimeout
    }

    /// The deadline table from `docs/03-EVENT-MODEL.md`.
    ///
    /// `Agent` is the subagent-dispatch tool — the hook name is `Agent`, never
    /// `Task`. It launches asynchronously and its own call closes in
    /// milliseconds, hence the short deadline; the subagent it spawned is
    /// tracked by `agent_id`, not by this call.
    public static func deadlineInterval(forTool toolName: String) -> TimeInterval {
        if toolName.hasPrefix("mcp__") { return 15 * 60 }
        switch toolName {
        case "Read", "Glob", "Grep", "TodoWrite":
            return 30
        case "Edit", "Write", "NotebookEdit":
            return 60
        case "Bash", "WebFetch":
            return 15 * 60
        case "Agent":
            return 30
        default:
            return 5 * 60
        }
    }

    /// The longest deadline any tool can be given. Used by the replay harness
    /// to pick an instant by which every orphan must have been reaped.
    public static let longestDeadlineInterval: TimeInterval = 15 * 60

    public func deadline(forTool toolName: String, startedAt: Date) -> Date {
        startedAt.addingTimeInterval(Self.deadlineInterval(forTool: toolName))
    }

    public func isExpired(_ call: OpenCall, at now: Date) -> Bool {
        now >= call.deadline
    }

    public func isIdle(lastEventAt: Date, at now: Date) -> Bool {
        now.timeIntervalSince(lastEventAt) >= sessionIdleTimeout
    }
}
