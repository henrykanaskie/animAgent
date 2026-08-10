import Foundation

/// **What kind of work a character has been doing**, as the desk under it says
/// it. [ADR-006 §1]
///
/// Four kinds and an abstention — `nil` is the fifth answer and it is the one
/// this room gives most often. The vocabulary is closed: no extension point, no
/// plugin, no room for a fifth. ADR-006 §1a gives three independent ceilings
/// that all land on four, and the binding one for this file is the evidence
/// ceiling: **each of the four is decided by tool name alone.** Nothing here
/// reads a command string, a file path, a prompt or any other argument, which is
/// what keeps §6's constitutional ask down to two fields the app already
/// consumes.
///
/// # It is not the badge, and the difference is tense
///
/// The badge says *a call of this class is open right now* and goes out when the
/// call closes [ADR-003 §1]. A work kind is **dispositional** — *this is the
/// desk this agent works at* — and stays true between turns. That is why it is a
/// second slot rather than a second reading of the first, and why ADR-006 §10
/// rejects putting a work kind on the badge, on the held object, or on the
/// current tool call.
public enum WorkKind: String, Sendable, Hashable, CaseIterable {
    /// An open laptop on the desk. *This agent has been changing files.*
    /// `Edit`, `Write`, `NotebookEdit`.
    case authoring
    /// A stack of papers. *This agent has been looking things up and changing
    /// nothing.* `Read`, `Glob`, `Grep`, `ToolSearch`, `WebSearch`, `WebFetch`.
    case research
    /// A desk monitor with a lit screen. *This agent has been executing
    /// commands.* `Bash`, `BashOutput`, `KillShell`.
    case running
    /// An upright pad. *This agent has been dispatching and tracking work.*
    /// `TodoWrite`, `Agent`, `SendMessage`.
    case coordinating

    /// **The observed half of the derivation, and it reads no new payload
    /// field.** [ADR-006 §1c]
    ///
    /// A total function of `ToolBadge`, which the scene already holds: the badge
    /// is keyed off `tool_name` on `PreToolUse` and nothing else, so a work kind
    /// derived from it is keyed off `tool_name` and nothing else too. Re-checked
    /// against the committed `ToolBadge` when this was written: `badge(forTool:)`
    /// is total (its `default` arm is `questionMark`), the enum has exactly seven
    /// cases, and all seven are answered below — so this function is total over
    /// every tool name that exists or ever will.
    ///
    /// **Two of the seven abstain, and that is I1 on this layer.**
    /// `questionMark` is a tool nobody recognised: putting a *thing* on the desk
    /// for it would be the guess the question mark exists to refuse, with a
    /// bigger surface to be wrong on. `plug` is `mcp__*`, whose substrate is
    /// unknown by name for the same reason `Monitor` is a question mark — an MCP
    /// tool may read, write or run, and furniture would pick one. `HeldObject
    /// .init?(badge:)` has exactly this shape and abstains for exactly this
    /// reason on `questionMark`; this one abstains on `plug` as well, because a
    /// held object lives for one call and a desk object stands for as long as it
    /// is true. [I1]
    public init?(badge: ToolBadge) {
        switch badge {
        case .document: self = .authoring
        case .magnifier: self = .research
        case .globe: self = .research
        case .terminal: self = .running
        case .checklist: self = .coordinating
        case .plug: return nil
        case .questionMark: return nil
        }
    }

    /// The same thing from the tool name, which is the form the vote arrives in.
    public init?(toolName: String) {
        self.init(badge: ToolBadge.badge(forTool: toolName))
    }

    /// **The `room.props.roles` key this kind's object is drawn from**, or `nil`
    /// for the one kind no pack single could supply.
    ///
    /// Three of the four are pack art declared in `assets/manifest.json` in the
    /// same `{file, content_box}` shape `desk` and `chair` have, so swapping the
    /// manifest swaps the picture with no code change. `running` is `nil` and is
    /// drawn by `DeskMonitorArt` instead: every candidate in the pack's own
    /// desk-monitor band (singles 130–134) measures 30–32 px wide against the
    /// 28 px placement bound, so there is no compliant single to name — see that
    /// file for the whole account.
    public var propRole: String? {
        switch self {
        case .authoring: return "laptop"
        case .research: return "papers"
        case .running: return nil
        case .coordinating: return "pad"
        }
    }

    /// Stable key for the texture cache, for the kind whose art is authored.
    var textureKey: String { "deskobject:" + rawValue }

    // MARK: - The lexicon [ADR-006 §3 step 1, §6c rule 5]

    /// **The closed keyword lexicon, and the only free text this app
    /// classifies.**
    ///
    /// It is read from `tool_input.description` on an `Agent` dispatch and on no
    /// other tool — the field `WorldModel` already decodes, `AgentSnapshot.task`
    /// already carries and `SceneDirector.taskLine(_:)` already draws on the
    /// nameplate. Classifying it is strictly less exposing than the echoing that
    /// already ships: the output is one of five closed values instead of ten
    /// glyphs of the user's own words. [ADR-006 §6a]
    ///
    /// **Whole words, exact matches, no regex and no stemming.** A word counts
    /// only if it is in one of the four lists below, spelled the way the list
    /// spells it. Inflections are listed where they are wanted rather than
    /// derived by a rule, because a stemming rule is the thing that turns a
    /// closed lexicon back into a guess: `PLANNING` would have to reach `PLAN`
    /// through a doubled consonant, and whatever handles that also turns
    /// `TESTING` into `TEST` and `INTERESTING` into it as well.
    ///
    /// The four lists are **disjoint**, checked by `WorkKindLexiconTests
    /// .theFourKeywordListsShareNoWord`, so a single word can never vote twice.
    static let keywords: [WorkKind: Set<String>] = [
        // Changing files. Every word here names the act of editing something
        // that stays edited.
        .authoring: [
            "WRITE", "WRITES", "WRITING", "WRITTEN", "REWRITE", "REWRITES",
            "EDIT", "EDITS", "EDITING",
            "IMPLEMENT", "IMPLEMENTS", "IMPLEMENTING",
            "REFACTOR", "REFACTORS", "REFACTORING",
            "RENAME", "RENAMES", "RENAMING",
            "PATCH", "PATCHES", "DRAFT", "DRAFTS",
            "FIX", "FIXES", "FIXING",
        ],
        // Looking things up and changing nothing.
        .research: [
            "READ", "READS", "READING",
            "FIND", "FINDS", "FINDING",
            "SEARCH", "SEARCHES", "SEARCHING", "GREP",
            "LOOK", "LOOKS", "LOOKING",
            "INSPECT", "INSPECTS", "INSPECTING",
            "INVESTIGATE", "INVESTIGATES", "INVESTIGATING",
            "EXPLORE", "EXPLORES", "EXPLORING",
            "AUDIT", "AUDITS", "AUDITING",
            "REVIEW", "REVIEWS", "REVIEWING",
            "LOCATE", "LOCATES", "SURVEY", "SURVEYS", "STUDY",
        ],
        // Executing commands. `verifying` is folded in here — ADR-006 §1b —
        // because separating "ran the tests" from "ran a script" needs the Bash
        // command string, which §6 refuses to read.
        .running: [
            "RUN", "RUNS", "RUNNING",
            "BUILD", "BUILDS", "BUILDING",
            "TEST", "TESTS", "TESTING",
            "EXECUTE", "EXECUTES", "EXECUTING",
            "COMPILE", "COMPILES", "COMPILING",
            "BASH", "SHELL", "INSTALL", "INSTALLS", "LINT", "BENCHMARK", "DEPLOY",
        ],
        // Dispatching and tracking work.
        .coordinating: [
            "PLAN", "PLANS",
            "DISPATCH", "DISPATCHES", "DISPATCHING",
            "DELEGATE", "DELEGATES", "DELEGATING",
            "COORDINATE", "COORDINATES", "COORDINATING",
            "ORCHESTRATE", "ORCHESTRATES",
            "ASSIGN", "ASSIGNS", "SCHEDULE", "SUPERVISE", "TODO",
            "TRACK", "TRACKS", "TRACKING",
        ],
    ]

    /// **The inferred half: one kind from a dispatch description, or nothing.**
    ///
    /// Total, and it abstains twice over: a description matching keywords of two
    /// kinds contributes nothing, and so does one matching none. That is the
    /// same answer the identity model already gives when attribution is
    /// ambiguous — the room shows the plain desk. [ADR-006 §3 step 1, §6c rule 5]
    ///
    /// The split is `SceneDirector.taskLine(_:)`'s own: uppercase, then cut at
    /// everything that is not a letter, a digit or a hyphen, so `alpha.txt` is
    /// `ALPHA` and `TXT` and `delta/epsilon,` is `DELTA` and `EPSILON`. One rule
    /// for the two things this app does with the same string.
    public init?(dispatchDescription description: String) {
        let words = description.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
        var matched: Set<WorkKind> = []
        for word in words {
            for (kind, list) in WorkKind.keywords where list.contains(word) {
                matched.insert(kind)
            }
        }
        guard matched.count == 1, let only = matched.first else { return nil }
        self = only
    }
}

/// **One agent's votes, for one turn.** [ADR-006 §3, §4a]
///
/// A counter over `PreToolUse` opens plus at most one opening claim — never "the
/// current tool". That is I3 held rather than restated: the tally is indifferent
/// to how many calls are open at once and to what order they opened in, so two
/// calls landing in either order produce the same desk.
///
/// It is scoped to a turn because votes only accumulate. An unscoped tally makes
/// a long-lived agent *more* rigid the longer it runs — `research` at 40 votes
/// would need 80 `authoring` votes to be corrected — so an agent that read for
/// five minutes and then coded for twenty would keep a paper stack. Per turn,
/// the desk reflects **this** turn's work, and a turn is exactly the unit of
/// "what I asked it to do".
public struct WorkTally: Sendable, Hashable {

    /// **One observed tool call furnishes a bare desk.** [ADR-006 §3, retuned —
    /// see the note appended to §3a]
    ///
    /// ADR-006 proposed **3**, on the premise that the object makes a claim a
    /// person might rely on, and predicted that 22 of 27 agents in the corpus
    /// would keep a bare desk. The maintainer redefined what the object is for
    /// while this was being built — *"it doesn't need real data, the screen isn't
    /// going to be big enough or have enough resolution for that; just needs to
    /// be a prop on the table"* — and a rule that abstains four times out of five
    /// is the wrong rule for furniture. One `Bash` really is evidence that this
    /// agent ran something, and a monitor after one `Bash` is honest.
    ///
    /// **What did not move is the abstention.** An agent with no recognisable
    /// evidence at all — nothing but `mcp__*` and unmapped tools, or no tool
    /// calls yet — still gets the bare desk, and that is not a confidence
    /// threshold: it is the difference between a fact and no fact. [I1]
    public static let adoptionFloor = 1

    /// **Replacing something already on the desk costs more than putting the
    /// first thing there**, and the asymmetry is deliberate: appearing is the
    /// room *learning* something and costs nothing to watch; changing is the room
    /// *correcting itself* and is the loud event. [ADR-006 §4c]
    ///
    /// It is what stops one stray call at the start of a new turn from
    /// rearranging a desk — the tally is turn-scoped, so an incumbent adopted
    /// last turn holds **zero** votes in this one and would otherwise be
    /// overturned by the first `Read` of the next turn. Two calls agreeing with
    /// each other is the smallest evidence that is not one event.
    public static let replacementFloor = 2

    /// **And the challenger must at least double the incumbent's own votes this
    /// turn.** The 2:1 majority ADR-006 §3 derived, moved from "top against
    /// runner-up" to "challenger against the thing it would replace", because at
    /// a change that is the comparison actually being made. An agent that has
    /// read three files and run three commands does not swap its desk on the
    /// seventh call; it takes six of one against three of the other.
    ///
    /// **This is what bounds churn, and it bounds it logarithmically.** Votes
    /// only accumulate within a turn, so each successive change has to *double*
    /// the count that beat it last time: 1, 2, 4, 8, 16. A character that spent a
    /// whole turn alternating between two kinds as fast as it could still cannot
    /// redecorate more than about `log2(calls)` times, whatever the dwell floor
    /// says. The clock is the second bound and the looser one; this is the first,
    /// and it is the one that did the work when the floor came down to a single
    /// call. `WorkTallyTests.theVoteRuleAloneBoundsChangesWithinATurnLogarithmically`
    /// is the measurement.
    public static let majorityRatio = 2

    /// Votes per kind. Kinds with no votes are absent rather than zero.
    public private(set) var votes: [WorkKind: Int] = [:]

    /// **How many of those votes came from a tool call this app actually
    /// consumed**, as opposed to the one opening claim read off a dispatch
    /// description.
    ///
    /// It exists because the floor is now 1, and a floor of 1 without this would
    /// let a *description* furnish a desk on its own — an agent dispatched to
    /// "read the logs" would get a paper stack before it had done anything at
    /// all. The description is inference about intent written *before* the agent
    /// acted [ADR-006 §3 step 1]; it is admissible as a vote and it is not
    /// admissible as the *only* vote. `adopted(incumbent:)` refuses to put
    /// anything on a bare desk until this is at least 1.
    public private(set) var observedVotes = 0

    public init() {}

    public var isEmpty: Bool { votes.isEmpty }
    public func count(_ kind: WorkKind) -> Int { votes[kind] ?? 0 }
    /// Every vote cast this turn, including the opening claim.
    public var total: Int { votes.values.reduce(0, +) }

    /// One observed vote, from one `PreToolUse`. `nil` is an abstention and costs
    /// nothing — an unmapped tool and an `mcp__*` tool add no evidence rather
    /// than adding a guess. [I1]
    public mutating func record(_ kind: WorkKind?) {
        guard let kind else { return }
        votes[kind, default: 0] += 1
        observedVotes += 1
    }

    /// **The opening claim: exactly one vote, and never the deciding one.**
    /// [ADR-006 §3 step 1]
    ///
    /// The dispatch description is worth exactly as much as one real observed
    /// call, so it gets exactly as much — that is what makes the maintainer's
    /// honest case work: an agent *told to plan* that is in fact editing files
    /// ties its own brief on the second edit and beats it on the third. It does
    /// not count towards `observedVotes`, so it can break a tie and add weight
    /// and it cannot furnish a desk by itself.
    public mutating func seedOpeningClaim(_ kind: WorkKind?) {
        guard let kind else { return }
        votes[kind, default: 0] += 1
    }

    /// The turn ended. **The tally resets and the drawn object does not** — that
    /// separation is ADR-006 §4b and it lives at the call site, because this
    /// type does not know what is on the desk.
    public mutating func clear() {
        votes.removeAll()
        observedVotes = 0
    }

    /// **What the desk should show, given what is on it now.**
    ///
    /// Returns `incumbent` unchanged whenever the tally has not earned a change,
    /// and `nil` only while the desk is bare and has not earned anything — so
    /// **nothing this function returns ever takes an object away.** That is
    /// ADR-006 §4b held structurally rather than by a rule at the call site.
    ///
    /// The steps, in order:
    ///
    /// 1. **No evidence, no change.** An empty tally keeps whatever is there,
    ///    which for a bare desk is the bare desk. [I1]
    /// 2. **The candidate** is the kind with the most votes. A tie is broken in
    ///    favour of the incumbent, and a tie with no incumbent in it changes
    ///    nothing. No recency, no ordering dependence, no most-recent-wins: the
    ///    three properties ADR-003 §5 protects for the badge, kept here for the
    ///    same reasons — and load-bearing now in a way they were not under the
    ///    original threshold, because a tie is reachable at one vote each.
    /// 3. **A bare desk adopts on `adoptionFloor` votes**, provided at least one
    ///    of them was observed rather than read off the dispatch description.
    /// 4. **An occupied desk is replaced only on `replacementFloor` votes *and*
    ///    `majorityRatio` times what the incumbent has scored this turn.**
    ///
    /// The change is additionally rate-limited by `SceneDirector
    /// .deskObjectDwell`, which this type knows nothing about: the counts are
    /// honest and the clock is what keeps them glanceable. [ADR-006 §4c]
    public func adopted(incumbent: WorkKind?) -> WorkKind? {
        guard let top = votes.values.max(), top > 0 else { return incumbent }
        let leaders = votes.filter { $0.value == top }.map(\.key)
        let winner: WorkKind
        if leaders.count == 1 {
            winner = leaders[0]
        } else if let incumbent, leaders.contains(incumbent) {
            winner = incumbent
        } else {
            return incumbent
        }
        if winner == incumbent { return incumbent }
        guard let incumbent else {
            // A bare desk. One observed call is enough, and a description on its
            // own is not.
            return top >= Self.adoptionFloor && observedVotes >= 1 ? winner : nil
        }
        let held = count(incumbent)
        guard top >= Self.replacementFloor, top >= Self.majorityRatio * held else {
            return incumbent
        }
        return winner
    }
}
