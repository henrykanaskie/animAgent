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
    /// `Task`. It gets a long deadline because it dispatches **either** way:
    /// M0 captured it launching asynchronously and closing in ~16 ms, and M4
    /// observed it running synchronously, staying open for the subagent's
    /// entire life. Both are real.
    ///
    /// The short deadline it used to carry assumed the async case, and it made
    /// the synchronous case render a lie: the parent's call was abandoned at
    /// 30 s while the parent was genuinely still working, so the character went
    /// idle mid-task. A late reap is a blind spot; an early one is fiction, and
    /// fiction is the thing we do not ship. [I1]
    ///
    /// The cost of the long deadline — a genuinely lost close lingering — is
    /// already covered twice over by `SessionEnd` and the session idle sweep.
    public static func deadlineInterval(forTool toolName: String) -> TimeInterval {
        if toolName.hasPrefix("mcp__") { return 15 * 60 }
        switch toolName {
        case "Read", "Glob", "Grep", "TodoWrite":
            return 30
        case "Edit", "Write", "NotebookEdit":
            return 60
        case "Bash", "WebFetch", "Agent":
            return 15 * 60
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
