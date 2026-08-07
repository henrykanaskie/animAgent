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

    /// **G — the grace a call gets once its agent's permission gate is known to
    /// have been answered.** `docs/ADR-001-denied-calls.md` (d), accepted
    /// 2026-08-07.
    ///
    /// Click "No" on a permission prompt and *nothing ever closes that tool
    /// call*: no `PostToolUse`, no `PostToolUseFailure`, no mention in the
    /// following `PostToolBatch`, not even a `Stop` for the turn. `Bash` carries
    /// the 15-minute deadline — rightly, since a shorter one abandons real
    /// long-running commands mid-run — so a two-second interaction used to leave
    /// that character typing for **900 s**. This is the number that replaces it,
    /// applied only to calls the model marked at a `PermissionRequest` and only
    /// once a `UserPromptSubmit` says the human answered. The call is
    /// *shortened*, never closed here: the reaper still does the closing and
    /// still emits `.callAbandoned`.
    ///
    /// **Why 60 s, and it is a measurement rather than a taste.** The only thing
    /// G has to survive is the gap between a synthetic `UserPromptSubmit` — a
    /// subagent's result arriving at the main thread — and the close of a call
    /// that is genuinely still running. That gap is measured, twice, in
    /// `fixtures/three-subagents.jsonl`: `toolu_017StzPCoy…` runs **8.05 s**
    /// across one such prompt and `toolu_01NDyNkE17…` runs **15.05 s** across
    /// two. 60 s is four times the largest observed, so it keeps four times the
    /// head-room while cutting the worst case 15×.
    ///
    /// **It is a number to revisit with more captures, not a constant of
    /// nature.** Two straddles from one fixture is the whole evidence base. If a
    /// capture ever shows a longer straddle, this is the line to change — and
    /// the direction that matters is that shortening it too far is an *early*
    /// reap, which is fiction, while leaving it long is only a blind spot. [I1]
    public static let permissionGateGraceInterval: TimeInterval = 60

    public func deadline(forTool toolName: String, startedAt: Date) -> Date {
        startedAt.addingTimeInterval(Self.deadlineInterval(forTool: toolName))
    }

    /// The deadline a marked call carries once the gate has been answered:
    /// `now + G`, **or its existing deadline if that is already sooner**.
    ///
    /// ADR-001 says "pulled in to `now + G`", and pulled *in* is the operative
    /// word — this may only ever shorten. A `Read` marked at a gate carries a
    /// 30 s deadline of its own, and moving that out to 60 s because a prompt
    /// arrived would be this rule making a call live *longer* than the ordinary
    /// table allows, which is the opposite of the thing it exists to do.
    public func shortenedDeadline(_ existing: Date, answeredAt now: Date) -> Date {
        min(existing, now.addingTimeInterval(Self.permissionGateGraceInterval))
    }

    public func isExpired(_ call: OpenCall, at now: Date) -> Bool {
        now >= call.deadline
    }

    public func isIdle(lastEventAt: Date, at now: Date) -> Bool {
        now.timeIntervalSince(lastEventAt) >= sessionIdleTimeout
    }
}
