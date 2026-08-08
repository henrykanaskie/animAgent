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
    ///
    /// **There are seven badges and no more are coming** — four are authored and
    /// no further art packs will be bought [04-ART-DIRECTION, M5c]. So the only
    /// question a new tool can raise is "does it belong in a bucket that
    /// exists", never "what glyph does it need". Where the answer is no, the
    /// answer is the question mark and it is permanent; `Monitor` below is one,
    /// and its reason is recorded rather than left as a shrug.
    public static func badge(forTool toolName: String) -> ToolBadge {
        if toolName.hasPrefix("mcp__") { return .plug }
        switch toolName {
        case "Edit", "Write", "NotebookEdit":
            return .document
        // `ToolSearch` queries the tool catalogue by name or keyword and hands
        // back schemas. It reads no file, but neither does `Glob`, which is in
        // this bucket for matching *names* while `Grep` is here for matching
        // *contents* — the bucket is retrieval, not the filesystem. `ToolSearch`
        // is the same act against a different index: a query in, matches out,
        // nothing mutated and nothing off-machine. Not `globe`, which is the
        // network, and `ToolSearch` never leaves the process.
        case "Read", "Glob", "Grep", "ToolSearch":
            return .magnifier
        case "Bash", "BashOutput", "KillShell":
            return .terminal
        case "WebSearch", "WebFetch":
            return .globe
        // `Agent` is the hook-payload name for subagent dispatch. `Task` is the
        // model-facing name and never appears in a payload — it is accepted
        // here only because `docs/04-ART-DIRECTION.md` still lists it, and
        // accepting a name we will never see costs nothing.
        //
        // **`SendMessage` is in this bucket on the strength of the capture, not
        // on a reading of its name.** `docs/03-EVENT-MODEL.md` already records
        // that a `SendMessage` `PreToolUse` is followed ~20 ms later by a
        // `SubagentStart` — `fixtures/four-subagents.jsonl` has it twice, at
        // 25 ms and 26 ms — which is the same event `Agent` produces and the
        // reason `SubagentStart` is not once per agent. So the room's own model
        // already treats `SendMessage` as dispatch, and badging it as anything
        // else would have the glyph disagree with the character waking up beside
        // it in the same batch.
        case "TodoWrite", "Agent", "Task", "SendMessage":
            return .checklist
        // **`Monitor` stays here on purpose.** It is the one tool in the capture
        // with two disjoint substrates and a name that does not say which: a
        // `command`, which "runs in the same shell environment as Bash", or a
        // `ws` WebSocket. The badge is keyed by name alone, so `terminal` would
        // be a claim about a shell for a call that may be a socket, and `globe`
        // the reverse. The fixtures hold one `Monitor` call — 1 of the 83 in
        // `fixtures/` — so the bucket would be right rarely and wrong rarely,
        // and when the two are that close the honest glyph wins. [I1]
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
    /// Set while this character has finished a turn and is still assigned —
    /// `WorldDelta.dormancyChanged`. **It wins the slot against a tool badge and
    /// loses it to attention** — see `isSleeping`.
    public let isDormant: Bool

    public static let none = BadgeSelection(
        badge: nil, count: 0, attention: nil, isDormant: false)

    public init(
        badge: ToolBadge?, count: Int, attention: AttentionKind? = nil, isDormant: Bool = false
    ) {
        self.badge = badge
        self.count = count
        self.attention = attention
        self.isDormant = isDormant
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

    /// **The `sleep` glyph is what the slot shows: dormant, and not also
    /// waiting on a human.**
    ///
    /// The full order in this slot is **attention > sleep > tool**, and the two
    /// comparisons have different characters, so they are argued separately.
    ///
    /// **sleep over tool is unreachable and is defined anyway.** A dormant agent
    /// has no open calls: `SubagentStop` abandons every one of them in the same
    /// batch that sets dormancy, and the only path that opens a call —
    /// `PreToolUse` — goes through `WorldModel.ensureAgent`, which revives the
    /// agent *before* the call opens. So the two are mutually exclusive in the
    /// live stream. The order is still written down rather than left to whatever
    /// the code happens to do, because "unreachable" is a property of today's
    /// model and this is a value type that anything may construct. If they ever
    /// do co-occur, sleep is the right answer for reason 2 below: the calls
    /// would be stale and the turn boundary would not be.
    ///
    /// **attention over sleep is reachable, and attention wins.** The path is
    /// narrow but real: `PermissionRequest` arms an agent's gate mark *without*
    /// going through `ensureAgent`, so it does not revive, and a
    /// `permission_prompt` `Notification` then badges every marked agent — a
    /// dormant one included. It also arrives on the reconstruction path, where
    /// `ProjectRegistry` replays both facts for a project the user switched
    /// back to. Three reasons, and they are the same three that put attention
    /// above every tool badge:
    ///
    /// 1. **It is the only badge a glance can act on.** `sleep` is a status;
    ///    attention is a request. Letting a status hide a request inverts a
    ///    product whose one sentence is "you glance at the notch and know what
    ///    your agents are doing".
    /// 2. **It is the more urgent of two true things.** Both are true at once
    ///    here, so this is not a truth question the way attention-over-tool is —
    ///    it is a question of which true thing is worth the one anchor. "Waiting
    ///    on you, now" outranks "finished a turn, might come back", because only
    ///    the first has a deadline the user owns.
    /// 3. **The manifest carries exactly one badge anchor.** A second slot would
    ///    be an eyeballed offset dressed as data, which is the reason M5 left
    ///    the monitors unplaced and the reason attention suppresses the `×N`.
    ///
    /// Nothing is lost by the loss: dormancy is a standing state, not an event,
    /// so the `Z` comes back by itself the moment the badge above it clears —
    /// the agent's next consumed event clears the attention *and* revives it,
    /// which is one delta each and both in the same batch.
    public var isSleeping: Bool { isDormant && !isAttention }

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
        attention: AttentionKind? = nil,
        isDormant: Bool = false
    ) -> BadgeSelection {
        guard !toolNames.isEmpty else {
            return BadgeSelection(
                badge: nil, count: 0, attention: attention, isDormant: isDormant)
        }
        let badge = toolNames.map(ToolBadge.badge(forTool:)).min()
        return BadgeSelection(
            badge: badge, count: toolNames.count, attention: attention, isDormant: isDormant)
    }
}
