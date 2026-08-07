import Foundation
import SpriteRoomCore

/// The badge above a character's head — the layer that carries *which tool*.
///
/// Declaration order **is** the ordinal used to pick a badge when several calls
/// are open. Reordering these cases changes on-screen behaviour. [I3]
public enum ToolBadge: String, Sendable, Hashable, CaseIterable, Comparable {
    case document
    case magnifier
    case terminal
    case globe
    case checklist
    case plug
    case questionMark

    /// Position in the mapping table. Lower wins when several calls are open —
    /// deterministic ordering is what keeps the badge stable while calls
    /// interleave. Most-recent-wins flickers.
    public var ordinal: Int {
        ToolBadge.allCases.firstIndex(of: self) ?? ToolBadge.allCases.count
    }

    public static func < (lhs: ToolBadge, rhs: ToolBadge) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// The key this badge has in `assets/manifest.json`.
    public var manifestKey: String {
        switch self {
        case .questionMark: return "question_mark"
        default: return rawValue
        }
    }

    public init?(manifestKey: String) {
        if manifestKey == "question_mark" { self = .questionMark; return }
        guard let badge = ToolBadge(rawValue: manifestKey) else { return nil }
        self = badge
    }

    /// The mapping table from `docs/03-EVENT-MODEL.md`. Collapsed aggressively:
    /// a user cannot distinguish twelve icons at `2x`.
    ///
    /// Anything unrecognised is the question mark, never a guess. A new tool
    /// name appearing tomorrow must not need new art. [I1]
    public static func badge(forTool toolName: String) -> ToolBadge {
        if toolName.hasPrefix("mcp__") { return .plug }
        switch toolName {
        case "Edit", "Write", "NotebookEdit":
            return .document
        case "Read", "Glob", "Grep":
            return .magnifier
        case "Bash", "BashOutput", "KillShell":
            return .terminal
        case "WebSearch", "WebFetch":
            return .globe
        // `Agent` is the hook-payload name for subagent dispatch. `Task` is the
        // model-facing name and never appears in a payload — it is accepted
        // here only because `docs/04-ART-DIRECTION.md` still lists it, and
        // accepting a name we will never see costs nothing.
        case "TodoWrite", "Agent", "Task":
            return .checklist
        default:
            return .questionMark
        }
    }

    /// Whether this badge was reached by falling through the table. The caller
    /// logs these — an unmapped tool is a fact worth noticing, not an error.
    public static func isUnmapped(_ toolName: String) -> Bool {
        badge(forTool: toolName) == .questionMark
    }
}

/// What the badge layer shows for one character, given its whole open-call set
/// and whether it is waiting on a human.
///
/// `nil` badge means no open calls, which means no badge. There is no "idle
/// badge". [I2]
public struct BadgeSelection: Sendable, Hashable {
    public let badge: ToolBadge?
    /// Total open calls. Rendered as `×N` beside the badge when above one, so
    /// three concurrent calls read as three without needing three icons. [I3]
    public let count: Int
    /// Set while a `Notification` is outstanding for this character. **It wins
    /// the badge slot** — see `isAttention`.
    public let attention: AttentionKind?

    public static let none = BadgeSelection(badge: nil, count: 0, attention: nil)

    public init(badge: ToolBadge?, count: Int, attention: AttentionKind? = nil) {
        self.badge = badge
        self.count = count
        self.attention = attention
    }

    /// **Attention outranks every tool badge, and it suppresses the `×N`.**
    ///
    /// Three reasons, in the order they decided it:
    ///
    /// 1. It is the only badge a glance can *act* on. The tool badge says what
    ///    is happening; the attention badge says the room needs you. For a
    ///    surface whose one sentence is "you glance at the notch and know what
    ///    your agents are doing", letting an unactionable icon hide an
    ///    actionable one inverts the product.
    /// 2. It is the *more* truthful of the two. A call parked at a permission
    ///    gate is not running — `PermissionRequest` lands ~16 ms after
    ///    `PreToolUse` and the call then sits there — so drawing `terminal`
    ///    over a gated `Bash` asserts work that is not happening, while the
    ///    attention glyph asserts a wait that is. [I1]
    /// 3. Showing both would need a second badge position, and the manifest
    ///    carries exactly one badge anchor (bottom-centre, tail pointing at the
    ///    head). A second slot would be an eyeballed offset dressed as data —
    ///    the same reason M5 left the monitors unplaced. [I1]
    ///
    /// The `×N` goes because it annotates a *tool* badge: "N calls, of which
    /// this is the lowest ordinal". Pinned to the attention glyph it would read
    /// as N notifications, which is never true — `idle_prompt` fires once and
    /// we count notifications nowhere.
    ///
    /// Determinism is unaffected: attention is a single flag, so the badge is
    /// still a pure function of the character's state, and it still changes at
    /// most once per change of that state. [I3]
    public var isAttention: Bool { attention != nil }

    /// Lowest-ordinal badge across the open set, plus the total.
    ///
    /// Order of `toolNames` is irrelevant by construction — that is the whole
    /// point. Two calls opening in either order produce the same badge, so the
    /// badge changes at most once per change of the open-call set.
    ///
    /// The open-call set is kept even when `attention` overrides it, so that
    /// answering the prompt restores the tool badge without needing the model
    /// to re-announce the calls.
    public static func select(
        openToolNames toolNames: some Collection<String>,
        attention: AttentionKind? = nil
    ) -> BadgeSelection {
        guard !toolNames.isEmpty else {
            return BadgeSelection(badge: nil, count: 0, attention: attention)
        }
        let badge = toolNames.map(ToolBadge.badge(forTool:)).min()
        return BadgeSelection(badge: badge, count: toolNames.count, attention: attention)
    }
}
