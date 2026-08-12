import Foundation
import SpriteRoomCore

/// What the scene is asked to do. Value types only: the director is pure
/// policy and holds no nodes, so every rule in it is testable without a screen.
public enum SpriteIntent: Sendable, Hashable {
    /// Bring a character in. The scene plays `spawn` — the walk cycle from the
    /// room edge — and settles it at `seat`.
    ///
    /// **`station` and `costume` ride on this intent and on no other, and that
    /// is §6 rule 2 made structural.** Both are decided from `agent_id` and
    /// `agent_type` at the moment the character is created and neither has a
    /// setter anywhere: there is no `setStation`, no `setCostume`, and nothing
    /// downstream that could rewrite a character's furniture or its clothes
    /// while it is on screen. They are on the *agent* volatility band, so the
    /// only event that may move them is the one that creates the agent.
    ///
    /// Before this, `station` was resolved by `SceneDirector`, stored in the
    /// presentation record, and read by nothing: `Manifest.Station` had no
    /// caller outside `ThemeSelector` and its tests, and a manifest with six
    /// visually wild stations in all six themes rendered byte-identical to a
    /// manifest with none. The id had nowhere to go. This is where it goes.
    ///
    /// `costume` is `nil` for the main thread, for an untyped subagent, and for
    /// every agent in a manifest that declares no wardrobe — which is every
    /// manifest today, so the character drawn is exactly the one this app has
    /// always drawn.
    case spawnCharacter(
        agent: AgentRef, variant: String, nameplate: NameplateText, seat: Int,
        station: String, costume: String?)
    /// **A plate that changed after its character was drawn.** Only ever emitted
    /// when it actually changed, and never for an agent that spawned in the same
    /// batch — `spawnCharacter` already carries the plate it should have.
    ///
    /// It exists because `agentTasked` is retroactive by construction: the
    /// `Agent` call's `PostToolUse` carries the child's task, and it arrives one
    /// event *behind* the `SubagentStart` that put the child on screen. In the
    /// four captures that dispatch subagents, that is the very next event in
    /// three of them. So a character learns what it was sent to do a frame or so
    /// after it sits down, and something has to be able to tell the scene.
    ///
    /// **It is redrawing a texture, not rebuilding a character.** The plate node
    /// is anchored at its top edge, so a plate that grows a row grows downward
    /// and nothing already on screen moves. `agentAppeared` arriving a second
    /// time with an `agent_type` we did not have the first time comes through
    /// here too — that was previously a change the room made and never showed.
    case setNameplate(agent: AgentRef, nameplate: NameplateText)
    /// The character's resting state. Only ever emitted when it actually
    /// changed.
    case setBody(agent: AgentRef, state: BodyState, facing: Facing)
    /// The badge layer. Only ever emitted when it actually changed. [criterion 6]
    case setBadge(agent: AgentRef, selection: BadgeSelection)
    /// **What kind of work this character's desk says it has been doing.** Only
    /// ever emitted when the drawn kind actually changes — the discipline
    /// `setNameplate` already follows. [ADR-006 §5b]
    ///
    /// A **second furniture slot**, on the desk surface, keyed to the work; the
    /// station keeps its own key (`agent_type`) and its own `let`. Two slots, two
    /// keys, two tenses: the station is *what kind of worker this is* and never
    /// moves, the badge is *what it is doing right now* and moves per call, and
    /// this is *what kind of work this has been* and moves at most once per
    /// `SceneDirector.deskObjectDwell`.
    ///
    /// **There is no take-down, and that is §4b made structural.** `kind` is not
    /// optional and no value of this intent clears the desk: when a turn ends the
    /// tally resets and the object stays, to be replaced only when a later turn's
    /// tally clears the gate with a *different* kind. Clearing on `Stop` would
    /// rearrange the furniture every time an agent finished something, which is a
    /// furniture change carrying no news — and ADR-005 measured those intervals
    /// at a 9.6 s median, so the room would spend all of them redecorating.
    ///
    /// The character's node is unaffected: this is furniture standing on the desk
    /// beside it, outside its canvas by construction (`RoomScene
    /// .deskObjectNearEdgeX(manifest:)`), so nothing here can cover a head.
    case setDeskObject(agent: AgentRef, kind: WorkKind)
    /// **Whether this character's desk screen is on.** Only ever emitted when it
    /// actually changed. [ADR-006 §12]
    ///
    /// A fourth channel beside `setBody`, `setBadge` and `setGated`, and it is
    /// its own intent for the same reason `setGated` is: it is keyed to
    /// something none of the others is keyed to. The screen is lit while the
    /// agent **has a turn** — the interval ADR-005 keys the posture to — and
    /// dark when it does not, which is a fact about the desk rather than about
    /// the body, and it outlives every call in the turn.
    ///
    /// **It is not the open-call set.** ADR-005 measured the median tool call at
    /// 23 ms and the median gap between two calls of one turn at 2.35 s. A
    /// screen keyed to a call would flash at syscall rate, which is the strobe
    /// ADR-006 §10 already refused for the object itself.
    ///
    /// **`.dark` reaches two of the four kinds** — `WorkKind.hasScreen` — and
    /// the intent is emitted for every seated character regardless, including
    /// ones whose desk is bare. The alternative is a rule that has to know what
    /// is on the desk before it can say what the desk is doing, and the scene
    /// would then need the two facts to arrive in a particular order.
    case setDeskScreen(agent: AgentRef, screen: DeskScreen)
    /// **Whether this character is stopped at a permission gate.** Only ever
    /// emitted when it actually changed. [ADR-005 §7]
    ///
    /// A third channel beside `setBody` and `setBadge`, and it is its own intent
    /// rather than a field on either of them for the reason §7 gives: the gate
    /// stops the **motion**, and motion is neither the posture (`setBody`
    /// carries `working` throughout — a blocked agent is at its desk, in a turn)
    /// nor the slot (`setBadge` carries whatever the badge layer decided, which
    /// is the tool glyph for the first six seconds and the attention bubble
    /// after). Folding it into `BadgeSelection` would put a fact the badge layer
    /// must ignore inside the value that *is* the badge layer, and give the room
    /// two representations of one gate — one drawn, one not — for a later reader
    /// to conflate.
    ///
    /// It carries no marked call set. Nothing in the payload names the gated
    /// call, so there is nothing truthful to name here. [I3]
    case setGated(agent: AgentRef, isGated: Bool)
    /// The `SubagentStop` choreography, and **a round trip**: step into the
    /// aisle, walk to the anchor, `deliver`, walk back, sit down again.
    ///
    /// This is what drives the report beat now. It used to be carried by the
    /// `agentDeparted` that `SubagentStop` emitted right behind
    /// `reportDelivered` — the walk was the front half of an exit and the
    /// character never came back. A subagent that stops no longer departs
    /// (it goes `dormant` and stays in its seat), so the beat has to be driven
    /// by `reportDelivered` itself or it disappears from the room entirely.
    ///
    /// `anchorSeat` is the seat of the character this one reports to — its
    /// parent, when `tool_response.agentId` linked them, and seat 0 otherwise.
    /// Seat 0 is the documented fallback rather than a guess: an unlinked
    /// subagent reports to the main agent. [I1]
    ///
    /// It can arrive several times for one character. Two of the four agents in
    /// `fixtures/four-subagents.jsonl` stop, are resumed, and stop again.
    case deliverReport(agent: AgentRef, anchorSeat: Int)
    /// Take a character out. `.report` is the same choreography truncated: the
    /// walk to the anchor, `deliver`, then off screen instead of home.
    case exitCharacter(agent: AgentRef, style: ExitStyle)
    /// Integer render scale. [I6]
    case setScale(Int)
    /// **How many agents exist that the room has no seat for.** `0` takes the
    /// indicator down. Only ever emitted when it actually changed.
    ///
    /// The room has `RoomLayout.seatCapacity` seats and that number cannot be
    /// raised — the arithmetic is in `seatCapacity`'s own documentation. Before
    /// this intent existed the eighth agent was seated anyway, on top of the
    /// first, and the room drew seven characters while eight were running: a
    /// false population, which is fiction of exactly the kind I1 forbids, and
    /// S5 — *a cold observer watching 15 s can say how many agents are
    /// running* — failing at the first population past the seat count.
    ///
    /// **Not drawing them at all would be the same lie**, only with nothing on
    /// screen to catch it. So the room shows the seats it has and says how many
    /// more there are. Seven plus "+1" is still a count.
    case setOverflow(Int)

    public enum ExitStyle: Sendable, Hashable {
        /// A character that reported **and departed in the same frame**.
        ///
        /// `SubagentStop` no longer departs anyone, so this is not the ordinary
        /// report route any more — that is `deliverReport`. It survives for the
        /// one shape that still produces both facts at once: a `SessionEnd` (or
        /// an idle sweep) landing in the same batch as the stop. The character
        /// genuinely both reported and is genuinely gone, so it leaves by the
        /// report route rather than being yanked off screen mid-beat.
        ///
        /// `anchorSeat` as for `deliverReport`.
        case report(anchorSeat: Int)
        /// Everything else — session end, idle sweep, **and eviction**. Straight
        /// `depart`.
        ///
        /// The first two mean the agent is gone. The third does not: a dormant
        /// character gives its seat up to a live agent that has none, walks out,
        /// and is carried by `setOverflow` in the same frame. Both are the room
        /// taking a character off screen, which is all this style says, and the
        /// population is asserted by `setOverflow` rather than by this. See
        /// `SceneDirector.settleSeats`. [I1]
        case walkOff
    }
}

/// Maps `WorldDelta` values onto sprite intents.
///
/// This is the only place that holds policy about *how* a delta looks: which
/// badge a tool maps to, which seat a character takes, which variant it wears,
/// and what happens when two deltas for one character land in the same frame.
///
/// **Deltas are applied in batches, once per frame**, and intents are derived
/// from the state *after* the whole batch. That is what makes the same-frame
/// case well defined: an agent that appears and opens a call in one batch gets
/// one `spawnCharacter` and one `setBody(.working)`, never an `idle` that is
/// overwritten a microsecond later.
///
/// **Animate state, not events.** Nothing here reacts to the *arrival* of an
/// event, which is why a 3 ms `Read` and a four-minute `Bash` both render
/// correctly with no queue and no minimum-duration hack. [I2/I3]
///
/// Two states, on two channels, and ADR-005 is the whole of the difference
/// between them:
///
/// - **motion** — a character animates if and only if its open-call set is
///   non-empty *and it is not stopped at a permission gate*, keyed on the badge
///   class [`AmbientMotion`, ADR-005 §7];
/// - **posture** — a character is seated (`working`) while it has a turn in
///   progress and standing (`idle`) otherwise [`Presentation.isInTurn`].
///
/// The gate is on the first of those and on neither of the others: a blocked
/// agent is at its desk (posture unchanged) wearing whatever the badge layer
/// decided (slot unchanged), and it is **still**.
///
/// **What this implementation cannot yet say, named rather than left to be
/// discovered.** ADR-005 §3 closes the turn on `Stop` for the main agent, and
/// `WorldModel` emits **no delta at all** for `Stop` — `03-EVENT-MODEL.md` says
/// so in as many words and `spriteroom-replay` over `denial-then-work` shows a
/// stream with four prompts and three `Stop`s in it and not one delta from any
/// of them. Nor does a second `UserPromptSubmit` emit one, since the main agent
/// already exists by then. So the three turn boundaries this scene can see are
/// `dormancyChanged`, departure and a rebuild, and all three are subagent or
/// session events: **the main character sits down at its session's first event
/// and stands up only when it leaves.** That is a blind spot rather than a
/// fiction — the room declines to draw a boundary it was not told about — and
/// closing it is one `turnEnded(agent:)` delta in `SpriteRoomCore`, which is a
/// second module and a separate change.
public struct SceneDirector: Sendable {

    // MARK: Per-character state

    struct Presentation: Sendable, Hashable {
        let ref: AgentRef
        var agentType: String?
        var variant: String
        var seat: Int
        /// **The order this agent walked into the project, and it never
        /// changes.** Seats are handed out lowest-free, so before eviction
        /// existed a waiting agent's *seat number* was also its place in the
        /// queue and "who has waited longest" was a comparison of seats with no
        /// second list to keep in step.
        ///
        /// Eviction broke that identity: a seat number now goes up as well as
        /// down, so it records where an agent is rather than when it got here.
        /// This is the number that means when. It is a monotonic counter rather
        /// than a `Date` because two agents can appear in one batch, under one
        /// `now`, and the tie still has to break the same way on every run.
        let arrival: Int
        /// Which station this character works at, from
        /// `ThemeSelector.station(agentID:agentType:in:)`.
        ///
        /// **`let`, and that is the enforcement of §6 rule 2**: the station is
        /// decided at spawn and never rewritten. `agentAppeared` can arrive
        /// again carrying an `agent_type` we did not have the first time, and it
        /// updates `agentType` — the nameplate's business — without touching
        /// this. Rewriting a character's furniture while it is on screen would
        /// change its identity under the user's eye at exactly the moment the
        /// room got busy and they are looking at it, which is M5's argument for
        /// the always-on nameplate suffix applied verbatim.
        ///
        /// A theme change recomputes it from the same inputs by the same
        /// function in a *new* director, so every agent lands on the
        /// corresponding station of the new theme. That is §6 rule 4's rebuild,
        /// not a rule 2 rewrite.
        let station: String
        /// What this character is wearing, from
        /// `ThemeSelector.costume(agentID:agentType:in:)`. `nil` is the cast's
        /// own clothes, which is what the main thread wears, what an untyped
        /// subagent wears, and what everybody wears until costume art exists.
        ///
        /// **`let`, for the identical reason `station` is one.** It is on the
        /// agent band. A character that changed clothes because a later
        /// `agentAppeared` carried a type we did not have the first time would
        /// be changing *who it is* under the user's eye.
        let costume: String?
        /// Keyed by `tool_use_id`, never a single current tool. [I3]
        var openCalls: [ToolUseID: String] = [:]
        /// Set by `reportDelivered` and **cleared at the end of the batch that
        /// set it**. It answers "did this character report *in this frame*",
        /// which is the only question anything asks of it.
        ///
        /// It used to answer "has this character ever reported", and stayed true
        /// forever because the departure that consumed it always arrived in the
        /// same batch — until `SubagentStop` stopped departing anyone. Then
        /// three characters carried a stale `reported` all the way to
        /// `SessionEnd` and exited by walking back to the anchor and delivering
        /// a report that had happened minutes earlier. A room that replays a
        /// beat is telling a lie about when it happened, and it converged three
        /// bodies and their nameplates on one spot to do it. [I1]
        var reportedThisBatch = false
        /// Who this character reports to, from `.agentLinked`. `nil` until the
        /// link arrives, and `nil` forever when it never does — in which case
        /// the anchor is the main agent.
        var parent: AgentID?
        /// From `.agentTasked` — the `Agent` dispatch's own
        /// `tool_input.description`, **carried whole and stored whole**.
        ///
        /// The shortening happens at `nameplate(for:)`, not here, so this field
        /// keeps the string the payload actually carried and a test can see what
        /// the rule was handed. `nil` for the main thread permanently, and for
        /// any subagent whose dispatch this app never saw. [I1]
        var task: String?
        /// From `.attentionChanged`. Orthogonal to `openCalls`: a character can
        /// be holding calls *and* be blocked at a permission gate, which is
        /// exactly what a `Bash` sitting at the dialog looks like.
        var attention: AttentionKind?
        /// From `.dormancyChanged`. This subagent finished a turn and is still
        /// assigned. Orthogonal to `openCalls` in the type but not in the data —
        /// `SubagentStop` abandons every open call in the same batch that sets
        /// this, so a dormant character is an empty-handed one.
        var isDormant = false
        /// When `isDormant` last went true, and `nil` whenever it is false.
        ///
        /// **The only thing it is for is ordering evictions**: when a live agent
        /// needs a seat the room does not have, the dormant character that has
        /// been dormant longest gives one up. Nothing is drawn from it and no
        /// deadline is derived from it — dormancy still carries no clock of its
        /// own, which is the decision `03-EVENT-MODEL.md` takes deliberately and
        /// this does not reopen. A rank is not a deadline: no amount of elapsed
        /// dormancy removes an agent from the room by itself, and an agent that
        /// has been asleep for an hour in a quiet room keeps its seat forever.
        var dormantSince: Date?
        /// From `.gateChanged`: this character is stopped at a permission gate,
        /// waiting on a human. **Orthogonal to `attention` and to `openCalls`,
        /// and it is the reason both of those were insufficient.**
        ///
        /// Not `attention`: the `Notification` that raises the bubble arrives
        /// 6.0 s after the `PermissionRequest` that sets this, so a stillness
        /// keyed on the bubble would leave the room asserting hard work through
        /// the first six seconds of every block. Not `openCalls`: a gated call
        /// *is* open — that is the whole defect — so the set says the agent is
        /// working while the human is the only thing that can move it.
        ///
        /// **[I4] It needs no reaper of its own**, for the same structural
        /// reason `isInTurn` does not: it is a field of a presentation that
        /// `agentDeparted` removes, and every path that ends the gate without
        /// ending the character — a marked call closing or being abandoned,
        /// `Stop`, `SubagentStop`, the answering `UserPromptSubmit` — arrives
        /// here as `gateChanged(isGated: false)`.
        var isGated = false
        /// **The votes this agent has cast in the turn it is in.** [ADR-006 §3,
        /// §4a]
        ///
        /// Reset at every turn boundary — `dormancyChanged(true)` for a subagent,
        /// `turnChanged(false)` for the main thread — and **never** consulted for
        /// anything but the desk object. It is per-agent state inside the
        /// presentation, so every path that already removes a presentation reaps
        /// it: departure, `SessionEnd`, the idle sweep, project switch, scene
        /// rebuild. It adds no open state and no new reaping obligation. [I4]
        var workTally = WorkTally()
        /// Whether this turn's opening claim has been counted yet.
        ///
        /// The claim is seeded **lazily**, at the first settle of a turn, rather
        /// than eagerly in each of the five arms that can open one. That is not
        /// tidiness: `agentTasked` is retroactive by construction — the `Agent`
        /// call's `PostToolUse` carries the child's task and arrives *behind* the
        /// `SubagentStart` that seated it — so an eager seed at turn-open would
        /// miss the description for every subagent in `fixtures/`, which is all
        /// of them. Seeding where the tally is read instead means the claim is
        /// counted the first time it exists and once per turn thereafter.
        var openingClaimCounted = false
        /// **What is drawn on this character's desk**, or `nil` for the bare
        /// desk. Set from the tally and **never cleared** — §4b's whole argument:
        /// the badge is present tense and goes out when the call closes, the desk
        /// is dispositional and is as true between turns as during one.
        var deskObject: WorkKind?
        /// When `deskObject` was last set. The dwell floor is measured from here,
        /// and it is an absolute instant rather than a frame budget for
        /// `ClosingBeat.until`'s reason: a retracted panel stops rendering, and a
        /// dwell counted in frames would freeze while hidden.
        var deskObjectSetAt: Date?
        /// **A change the tally has earned and the dwell floor has refused, so
        /// far.**
        ///
        /// Without it the refusal would be permanent rather than a delay: votes
        /// only arrive on deltas, so an agent whose last call of a turn earned a
        /// change would never be looked at again and the change would be dropped
        /// rather than deferred. This flag is what puts the character back in
        /// `touched` on a later frame, in the same shape the closing beat's own
        /// expiry sweep already does — and it is cleared the moment the change
        /// lands or stops being earned, so it cannot keep a character permanently
        /// in the frame-rate path.
        var deskObjectDeferred = false
        /// ADR-003's closing beat: the badge that was on screen at the instant
        /// this agent's open-call set emptied by a real close, and when it comes
        /// down. `nil` almost always.
        ///
        /// **It is scene-side dwell over a delta that already arrived.** The
        /// call really closed; `WorldModel` knows nothing about this field and
        /// must not, because holding a call open in the true layer would be
        /// fiction in the one place that may not have any and would break the
        /// replay harness's no-orphaned-state property. [ADR-003 §13]
        var closingBeat: ClosingBeat?

        /// **Whether this agent has a turn in progress**, which is the whole of
        /// what the posture channel says. [ADR-005 §3]
        ///
        /// It is an interval between two real events, the same shape
        /// `isDormant` is, and it is opened and closed in `apply(_:at:)` — see
        /// the `.agentAppeared`, `.callOpened`, `.dormancyChanged` and
        /// `.turnChanged` arms, which are the only four places it moves.
        ///
        /// **Two deltas close it and they belong to different casts.**
        /// `dormancyChanged` is a subagent's `SubagentStop`; `turnChanged` is the
        /// main thread's `Stop`. No agent can receive both, because `Stop` never
        /// carries an `agent_id` and `SubagentStop` always does.
        ///
        /// **It is not a second copy of `openCalls`.** A turn contains many
        /// calls and the gaps between them: over `fixtures/` the median tool
        /// call is 23 ms and the median gap between two calls of one turn is
        /// 2.35 s, so keying the posture to the call put the room's loudest
        /// channel on the timescale of a syscall. The distinction is only
        /// legible because the events are different events.
        ///
        /// **[I4] It needs no reaper of its own.** It is a field of a
        /// presentation that `agentDeparted` removes, and `SessionEnd`, the
        /// idle sweep and eviction all arrive as that delta or as a rebuild.
        var isInTurn = false

        /// **The body carries tense, and the tense it carries is the turn.**
        /// [ADR-005 §3]
        ///
        /// `working` is the seated pose and `idle` is a **standing** one, so
        /// this property decides whether the room asserts that an agent is at
        /// its workstation. It used to read `openCalls.isEmpty`, which made
        /// that assertion track a syscall: a character sat down for the 23 ms of
        /// a `Read` and stood in the walkway for the seconds between calls, and
        /// the swap changes 4 924 px against 1 384 for one step of the seated
        /// ambient loop — the loudest body event in the room, firing twice per
        /// call, saying something no event said.
        ///
        /// **Motion is unchanged, to the frame.** A character animates if and
        /// only if it holds an open tool call; that rule now lives wholly in
        /// `AmbientMotion.sequence(for:state:openCalls:frameCount:)`, keyed on
        /// the same badge class it always was. A seated character with an empty
        /// set holds one still frame and moves 0 px/s, which is exactly what a
        /// standing one did. So this changes *which still frame is drawn in dead
        /// air* and nothing else about the motion budget. [I2, ADR-005 §6]
        ///
        /// It reads `isInTurn` and nothing else — not `openCalls`, not
        /// `attention`, not `isDormant` (which closes the turn where it is set
        /// rather than being consulted here), and **not `closingBeat`**.
        ///
        /// **The body does not change for attention.** The pack ships no
        /// animation for "waiting on a human" and repurposing an unrelated one
        /// would be fiction; the badge is the whole representation.
        var body: BodyState { isInTurn ? .working : .idle }

        /// **The desk screen carries the turn**, which is the same fact the
        /// posture carries and the reason both are keyed to `isInTurn`.
        /// [ADR-006 §12]
        ///
        /// # Why `!isDormant` is here as well, having checked rather than assumed
        ///
        /// The obvious reading is that this second term is redundant, because
        /// the `dormancyChanged` arm of `apply(_:at:)` sets `isInTurn =
        /// !isDormant` itself. The brief asked whether
        /// `turnChanged(hasTurn: false)` is *guaranteed* to have fired for an
        /// agent that `dormancyChanged(isDormant: true)` reports, and the answer
        /// found in the code is **no, and not marginally**: `turnChanged` is the
        /// **main thread's** boundary — it comes from `Stop`, which never
        /// carries an `agent_id` — and `dormancyChanged` is a **subagent's**,
        /// from `SubagentStop`, which always does. No agent receives both. So
        /// for the entire dormant cast the `turnChanged` delta never arrives at
        /// all, and what closes the turn is the dormancy arm's own assignment.
        ///
        /// That assignment is one line in one of eleven arms of a batch loop,
        /// and the ordering within a batch is what makes it hold. Reading both
        /// facts here costs nothing and means this value states the thing it
        /// means — *this agent is working right now* — rather than depending on
        /// an invariant maintained elsewhere. `theScreenIsDarkForADormantAgent
        /// EvenIfSomethingReopenedItsTurn` pins it against the case the ordering
        /// does not cover.
        var deskScreen: DeskScreen { isInTurn && !isDormant ? .lit : .dark }
        /// **The badge carries kind.** The beat is passed in as the slot's
        /// lowest-precedence source; `BadgeSelection.select` reaches it only
        /// when the open set is empty.
        var badge: BadgeSelection {
            BadgeSelection.select(
                openToolNames: openCalls.values, attention: attention, isDormant: isDormant,
                closingBeat: closingBeat?.badge)
        }
    }

    /// The badge left on screen by a close that emptied an agent's open-call
    /// set, and the instant it clears. [ADR-003 §3]
    ///
    /// **`until` is an absolute instant, never a frame budget.** A retracted
    /// panel stops rendering, so a beat counted in frames would freeze while
    /// hidden and be presented stale on reveal; compared against a `Date`, a
    /// beat that expired while the panel was down is already gone when it comes
    /// back up. This is the one detail that is cheap to get wrong and expensive
    /// to notice. [ADR-003 §8 item 4]
    public struct ClosingBeat: Sendable, Hashable {
        public let badge: ToolBadge
        public let until: Date
    }

    /// `D` — how long the badge that was on screen survives the close that
    /// emptied the set. [ADR-003 §4]
    ///
    /// **500 ms, and the derivation rather than the taste**, in the shape
    /// `Reaper.permissionGateGraceInterval` already uses. Four constants
    /// already in the repository bound it, and the binding one is the room's own
    /// animation:
    ///
    /// - **Floor A — one rendered frame.** 1/60 s = 16.7 ms. Necessary and
    ///   useless alone; this is the value at which the strobe lives.
    /// - **Floor B — the room's animation grain.** `assets/manifest.json` runs
    ///   every character state at 8 fps: 125 ms per animation frame. A badge
    ///   whose life is not a whole number of these is shorter than the smallest
    ///   unit of change the room draws.
    /// - **Floor C — the shortest complete gesture, and this is the binding
    ///   one.** `working` is 3 frames at 8 fps = 375 ms per ambient loop. A
    ///   badge up for less than that is on screen for less time than one
    ///   complete gesture of the character wearing it.
    /// - **Floor D — S1, corroborating.** `01-PRD.md` accepts up to 250 ms
    ///   between the hook firing and the call appearing, which is this
    ///   project's own ruling that 250 ms of *absence* passes unnoticed.
    ///
    /// 500 ms is the first value on B's grid above C: four animation frames,
    /// 1⅓ working loops, twice S1's budget, thirty render frames.
    ///
    /// The ceilings push the other way. It is 2.7% of the measured 18.5 s mean
    /// gap between calls, so it cannot make an intermittent agent read as
    /// continuously busy; it is under `LiveDriver.sweepInterval` (1 s), so it
    /// never interacts with a deadline, an abandon or the idle sweep; and
    /// "just did a read" has to still be true, which five seconds makes
    /// arguable and thirty makes a lie.
    ///
    /// **The floor comes from perception and the ceiling from truth, and they
    /// squeeze from opposite directions.** The band is roughly [375 ms, 2 s] and
    /// this sits at its bottom on purpose: every millisecond above the floor is
    /// bought from honesty, so the right value is the smallest one that clears
    /// it. A longer `D` is rejected in ADR-003 §13, not merely unchosen.
    public static let closingBeatDuration: TimeInterval = 0.5

    /// `S` — **the shortest interval in which a character's desk object may
    /// change twice.** [ADR-006 §4c]
    ///
    /// **4 s, and it is not a new number.** ADR-005 measured every standing
    /// interval in `fixtures/` and found the minimum at 4.226 s, with none under
    /// 4 s at all — the room's demonstrated human-scale floor. `S` is the largest
    /// whole second not exceeding it, so nothing on a character changes faster
    /// than the slowest channel already changes. The number was taken rather than
    /// tasted, in the shape ADR-004 §4 took `LiveDriver.sweepInterval`.
    ///
    /// **Why a clock is needed when the tally already supplies hysteresis.**
    /// Because tool calls are machine-scale: ADR-005 measured the median call at
    /// 0.023 s with 71% under 375 ms, so an entire vote sequence can land inside
    /// a quarter of a second. The vote rule bounds *how many* changes; only a
    /// clock bounds *how fast*. It matters more since the adoption floor came
    /// down, not less — a cheaper adoption is a top kind that changes hands more
    /// easily, and flicker is the failure mode this channel has to be protected
    /// from.
    ///
    /// **It is asymmetric on purpose.** A bare desk may be furnished the instant
    /// the votes allow it; only a *replacement* waits. Appearing is the room
    /// learning something and costs nothing to watch; changing is the room
    /// correcting itself and is the loud event.
    ///
    /// **And it is not the fiction ADR-004 §2 rejects.** There the objection was
    /// to a signal whose *content* came from `Date()`. Here the content is the
    /// tally and the clock only *delays* a change that real events have already
    /// earned. Delaying a true change is not asserting a false one.
    public static let deskObjectDwell: TimeInterval = 4

    // MARK: Stored

    public let layout: RoomLayout
    public let camera: RoomCamera
    /// Variant ids in manifest order. The cast, chosen at M0 by measurement.
    public let variantIDs: [String]
    /// The theme whose stations this director seats agents at. Bindings, not an
    /// id: the director needs the numbered-station pool and nothing else.
    public let theme: Manifest.Theme
    /// `characters.poses.working`, badge key → seated state. Empty in the
    /// shipped manifest, which makes the lookup below constant — §5b item 2's
    /// "inert with no code path to delete".
    let workingPoses: [String: String]
    /// `characters.costumes` — the wardrobe this director dresses agents from.
    /// Empty in the shipped manifest, so every agent resolves to `nil` and wears
    /// what the cast came in.
    public let costumes: Manifest.Costumes

    private var presentations: [AgentRef: Presentation] = [:]
    /// Last intent actually emitted per agent — the suppression memory that
    /// keeps the badge from being re-set with the value it already has.
    private var emittedBody: [AgentRef: BodyState] = [:]
    private var emittedBadge: [AgentRef: BadgeSelection] = [:]
    /// Seeded at spawn with `false`, the same idiom as `emittedBadge`'s `.none`,
    /// so a character that is never gated — which is every character in fifteen
    /// of the seventeen fixtures — never receives the intent at all.
    private var emittedGated: [AgentRef: Bool] = [:]
    /// Seeded at spawn with the plate `spawnCharacter` carried, so the only
    /// `setNameplate` a character ever gets is one that says something the plate
    /// on screen does not.
    private var emittedNameplate: [AgentRef: NameplateText] = [:]
    /// Not seeded at spawn, unlike `emittedBadge` and `emittedGated`: a character
    /// walks in with a bare desk and `setDeskObject` has no value that means
    /// "bare", so there is nothing to seed it with. The absence *is* the seed.
    private var emittedDeskObject: [AgentRef: WorkKind] = [:]
    /// Seeded at spawn with `.lit`, the same idiom as `emittedGated`'s `false`:
    /// a character exists because an event for it arrived, an event arriving
    /// means it is in a turn, and `RoomScene` draws a lit screen until told
    /// otherwise. So a character that never goes dormant — the main agent in
    /// every fixture — never receives this intent at all.
    private var emittedDeskScreen: [AgentRef: DeskScreen] = [:]
    private var emittedScale: Int?
    /// Seeded at zero rather than `nil` so a room that never overflows never
    /// emits the intent at all — the same idiom as seeding `emittedBadge` with
    /// `.none` at spawn.
    private var emittedOverflow = 0
    private var occupiedSeats: Set<Int> = []
    /// Hands out `Presentation.arrival`. Never reused, never reset.
    private var nextArrival = 0
    private var assignedVariants: [AgentRef: String] = [:]
    /// Tool names that fell through the mapping table. Counted, never guessed
    /// at. [I1]
    public private(set) var unmappedTools: [String: Int] = [:]

    public init(layout: RoomLayout = RoomLayout(), camera: RoomCamera = .default,
                variantIDs: [String],
                theme: Manifest.Theme = .unbound,
                workingPoses: [String: String] = [:],
                costumes: Manifest.Costumes = .none) {
        self.layout = layout
        self.camera = camera
        self.variantIDs = variantIDs.isEmpty ? ["00"] : variantIDs
        self.theme = theme
        self.workingPoses = workingPoses
        self.costumes = costumes
    }

    /// - Parameter themeID: the theme the room is dressed in, so that stations
    ///   are drawn from *its* pool. `nil` is `manifest.room`, which §14a
    ///   establishes is the resolved default theme.
    public init(manifest: Manifest, themeID: String? = nil, layout: RoomLayout = RoomLayout()) {
        self.init(layout: layout,
                  camera: RoomCamera(manifest: manifest),
                  variantIDs: manifest.characters.orderedVariantIDs,
                  theme: manifest.themeBindings(themeID),
                  workingPoses: manifest.characters.workingPoses,
                  costumes: manifest.characters.costumes)
    }

    // MARK: Query

    public var population: Int { presentations.count }
    public var seats: [AgentRef: Int] { presentations.mapValues(\.seat) }

    /// **Whether this agent has a seat, and therefore whether it is drawn.**
    ///
    /// A seat number past `layout.seatCapacity` is a place in the queue rather
    /// than a place in the room: every position function in `RoomLayout` wraps,
    /// so drawing on one would put two characters on one spot. The agent is
    /// counted instead, by `overflowCount`, and takes the first seat that frees.
    public func isSeated(_ agent: AgentRef) -> Bool {
        presentations[agent].map { layout.isSeatable($0.seat) } ?? false
    }

    /// How many of this room's agents are actually drawn.
    public var seatedPopulation: Int {
        presentations.values.lazy.filter { self.layout.isSeatable($0.seat) }.count
    }

    /// How many are not. The number the room says out loud.
    public var overflowCount: Int { population - seatedPopulation }
    public var currentScale: Int { emittedScale ?? camera.scale(forPopulation: population) }

    public func openCallCount(_ agent: AgentRef) -> Int {
        presentations[agent]?.openCalls.count ?? 0
    }

    public func badge(_ agent: AgentRef) -> BadgeSelection {
        presentations[agent]?.badge ?? .none
    }

    /// Whether this character is stopped at a permission gate. [ADR-005 §7]
    public func isGated(_ agent: AgentRef) -> Bool {
        presentations[agent]?.isGated ?? false
    }

    public func bodyState(_ agent: AgentRef) -> BodyState? {
        guard let presentation = presentations[agent] else { return nil }
        return body(for: presentation, badge: presentation.badge)
    }

    /// Which station this character works at. Decided at spawn; this only
    /// reads it. [§8 item 6]
    public func station(_ agent: AgentRef) -> String? {
        presentations[agent]?.station
    }

    /// What this character is wearing. Decided at spawn; this only reads it.
    /// `nil` is the cast's own clothes.
    public func costume(_ agent: AgentRef) -> String? {
        presentations[agent]?.costume ?? nil
    }

    /// The resting state to draw: `idle`, or the seated pose the badge class
    /// selects.
    ///
    /// **Keyed on the badge class, not on `tool_name`.** That is the whole of
    /// §5a: the badge mapping is already *total* — every unmapped tool is
    /// `question_mark` — so a tool name nobody has heard of maps to a badge maps
    /// to a pose, forever, with no new art. The extensibility property
    /// `04-ART-DIRECTION.md` protects by saying "the body is always the sitting
    /// pose" is preserved exactly, and it is preserved by the table being total
    /// rather than by the answer being constant.
    ///
    /// The tool badge is read even while `attention` outranks it in the badge
    /// slot, because the character is still holding those calls — the attention
    /// glyph is about the *badge*, and the body is about the work.
    ///
    /// **During an ADR-003 closing beat the `guard` below returns first.** The
    /// badge argument may name a class; the open set is empty, so the lookup
    /// into `workingPoses` is never reached and a lingering glyph cannot put a
    /// badge-keyed working pose on a character that has stopped. That is
    /// ADR-003 §2's third bullet, held structurally.
    ///
    /// **The second condition is the fact, not the state name.** [ADR-005 §5]
    /// It used to be enough that the resting state was `working`, because the
    /// resting state was `openCalls.isEmpty ? .idle : .working` and so said the
    /// same thing. Under ADR-005 a seated-and-still character *is* `working` by
    /// name with an empty set, so the guard has moved onto the set itself —
    /// the same correction `Character.heldObject` needed and for the same
    /// reason. A pose that a badge class selects is a claim about the work being
    /// done, and there is no work being done.
    func body(for presentation: Presentation, badge: BadgeSelection) -> BodyState {
        let resting = presentation.body
        guard resting == .working, !presentation.openCalls.isEmpty else { return resting }
        let named = badge.badge.flatMap { workingPoses[$0.manifestKey] }
            ?? workingPoses[Manifest.Characters.defaultPoseKey]
        return named.flatMap(BodyState.init(rawValue:)) ?? resting
    }

    /// The badge left on screen by the close that emptied this agent's set, if
    /// one is up. `nil` almost always; read by tests.
    public func closingBeat(_ agent: AgentRef) -> ClosingBeat? {
        presentations[agent]?.closingBeat
    }

    /// **What is standing on this character's desk**, or `nil` for the bare desk.
    /// [ADR-006]
    public func deskObject(_ agent: AgentRef) -> WorkKind? {
        presentations[agent]?.deskObject
    }

    /// **Whether this character's desk screen is on.** [ADR-006 §12]
    ///
    /// `.dark` for an agent this director has never heard of, which is the same
    /// answer it gives for one that is not in a turn: nothing is running.
    public func deskScreen(_ agent: AgentRef) -> DeskScreen {
        presentations[agent]?.deskScreen ?? .dark
    }

    /// This agent's votes so far **in the turn it is in**. Read by tests; nothing
    /// in the room draws it.
    public func workTally(_ agent: AgentRef) -> WorkTally {
        presentations[agent]?.workTally ?? WorkTally()
    }

    // MARK: Apply

    /// One frame's worth of deltas in, one frame's worth of intents out.
    ///
    /// **`now` is the instant this frame happened, and it is a parameter rather
    /// than a clock this type owns.** That is the discipline
    /// `WorldModel.sweep(at:)` and `ProjectRegistry.absorb(_:at:)` already keep,
    /// and it is what lets ADR-003's beat be tested without waiting and
    /// replayed deterministically by the offscreen renderer, which runs fixture
    /// time far faster than wall time.
    ///
    /// **It must be called on every frame, including frames carrying no
    /// deltas.** The beat ends by the clock passing its expiry, and a frame with
    /// nothing in it is exactly the frame that usually happens next: an agent
    /// whose set has just emptied is, by definition, not producing deltas. A
    /// caller that only applies when deltas arrive would leave the last badge
    /// up until the agent's next event — 18.5 s on average in the M7a capture,
    /// which is the lie this rule is bounded to 500 ms precisely to avoid.
    @discardableResult
    public mutating func apply(_ deltas: [WorldDelta], at now: Date) -> [SpriteIntent] {
        var appeared: [AgentRef] = []
        var exited: [(AgentRef, SpriteIntent.ExitStyle)] = []
        var touched: [AgentRef] = []
        var reported: [AgentRef] = []
        /// Still in the population, no longer in a seat. See `settleSeats`.
        var evicted: [AgentRef] = []

        // Expiry, before the deltas: a beat armed by *this* batch is armed at
        // `now + D` and so cannot be expired by the same `now`. Ordered by seat
        // rather than by the dictionary, because a dictionary's order is not
        // stable across runs and the intent stream is read by a harness that
        // diffs it.
        //
        // The `contains` is the frame-rate path: this runs 60 times a second on
        // every character, and almost none of those frames has a beat on any of
        // them. It allocates nothing; the walk below allocates only when there
        // is something to clear.
        if presentations.contains(where: { $0.value.closingBeat != nil }) {
            let expiring = presentations
                .filter { $0.value.closingBeat.map { $0.until <= now } ?? false }
                .keys
                .sorted { (presentations[$0]?.seat ?? 0) < (presentations[$1]?.seat ?? 0) }
            for agent in expiring {
                presentations[agent]?.closingBeat = nil
                note(&touched, agent)
            }
        }

        // A desk change the tally earned and the dwell floor refused. Same shape
        // as the sweep above and for the same reason: it is a change that becomes
        // due by the clock passing, on a frame that may carry no deltas at all.
        // Almost no frame has one of these on any character, so the `contains`
        // keeps the frame-rate path allocation-free. [ADR-006 §4c]
        if presentations.contains(where: { $0.value.deskObjectDeferred }) {
            let due = presentations
                .filter { $0.value.deskObjectDeferred }
                .keys
                .sorted { (presentations[$0]?.seat ?? 0) < (presentations[$1]?.seat ?? 0) }
            for agent in due { note(&touched, agent) }
        }

        for delta in deltas {
            switch delta {
            case let .agentAppeared(agent, agentType, _):
                if presentations[agent] == nil {
                    let seat = claimSeat(for: agent)
                    let variant = claimVariant(for: agent)
                    let arrival = nextArrival
                    nextArrival += 1
                    presentations[agent] = Presentation(
                        ref: agent, agentType: agentType, variant: variant, seat: seat,
                        arrival: arrival,
                        // Decided here and nowhere else. §6 rule 2, and the
                        // `let` on the field is what keeps it true.
                        station: ThemeSelector.station(
                            agentID: agent.agent.subagentID,
                            agentType: agentType,
                            in: theme),
                        // Same inputs, same band, same `let`. Both are decided
                        // here and nowhere else.
                        costume: ThemeSelector.costume(
                            agentID: agent.agent.subagentID,
                            agentType: agentType,
                            in: costumes),
                        // **A character exists because an event for it arrived,
                        // and an event for it arriving means it is in a turn.**
                        // For the main agent that event is its session's first
                        // — a `UserPromptSubmit`, or the `PreToolUse` of a
                        // session we attached to mid-flight. For a subagent it
                        // is `SubagentStart`. Both are the openers ADR-005 §3
                        // names, and this is where they land. [ADR-005 §3]
                        //
                        // On the project-switch reconstruction path this arm
                        // replays first and a dormant agent's
                        // `dormancyChanged(true)` follows in the same batch, so
                        // a sleeper comes back standing.
                        isInTurn: true)
                    // A character that has just walked in wears no badge, so
                    // "set the badge to none" is an instruction to do nothing.
                    // Seeding the memory here is what keeps the badge-change
                    // count equal to the open-call-change count now that an
                    // agent can appear idle — `UserPromptSubmit` creates the
                    // main character before its first tool call. [criterion 6]
                    emittedBadge[agent] = BadgeSelection.none
                    // A character that has just walked in is not at a dialog,
                    // and `Character` is built ungated, so "set gated to false"
                    // is an instruction to do nothing. On the project-switch
                    // reconstruction path a `gateChanged(true)` follows in the
                    // same batch for an agent that really is blocked, and this
                    // seeding is what makes that one intent rather than none.
                    emittedGated[agent] = false
                    // A character that has just walked in is in a turn — the
                    // comment on `isInTurn` above is the argument — and the
                    // scene draws a lit screen on an unseeded desk, so "set the
                    // screen to lit" is an instruction to do nothing. On the
                    // project-switch reconstruction path a `dormancyChanged(true)`
                    // follows in the same batch for a sleeper, and this seeding
                    // is what makes that one intent rather than none.
                    emittedDeskScreen[agent] = .lit
                    appeared.append(agent)
                } else if let agentType {
                    presentations[agent]?.agentType = agentType
                }
                note(&touched, agent)

            case let .agentLinked(agent, parent):
                // Retroactive by construction: the character is already on
                // screen when this arrives. It changes nothing visible until
                // the character reports, which is the only moment the anchor
                // is used.
                presentations[agent]?.parent = parent

            case let .callOpened(agent, call):
                if ToolBadge.isUnmapped(call.toolName) {
                    unmappedTools[call.toolName, default: 0] += 1
                }
                // A beat is a statement about work that has stopped. Work has
                // restarted, so the normal rule resumes and the open set decides
                // the glyph. [ADR-003 §3]
                presentations[agent]?.closingBeat = nil
                // **Any `PreToolUse` opens the turn.** An agent doing something
                // is in one, and this is also the revival path for a character
                // whose `SubagentStart` we never saw. It is almost always
                // already true — the turn opened at the agent's first event —
                // and the one shape that needs it is a dormant subagent resumed
                // by a `SendMessage`, whose `dormancyChanged(false)` arrives in
                // this same batch. [ADR-005 §3]
                presentations[agent]?.isInTurn = true
                presentations[agent]?.openCalls[call.toolUseID] = call.toolName
                // **One vote per `PreToolUse`, on the open rather than on the
                // close.** [ADR-006 §6e, I3] The tally counts opens because that
                // is what makes it a counter over events rather than a reading of
                // "the current tool": an agent holding three calls at once has
                // cast three votes and has no single current tool to read. An
                // unmapped or `mcp__*` tool records nothing — abstention, never a
                // guess. [I1]
                presentations[agent]?.workTally.record(WorkKind(toolName: call.toolName))
                note(&touched, agent)

            // **The two close paths are split here, and the beat is the first
            // thing that ever needed them apart.** [ADR-003 §3]
            case let .callClosed(agent, toolUseID, _, _):
                guard var presentation = presentations[agent] else { break }
                // The glyph that was on screen at this instant: literally the
                // last value `BadgeSelection.select` returned for a non-empty
                // set. No new selection rule — lowest-ordinal is untouched, and
                // it never sees a lingering call because a beat exists only
                // while the count is zero. [ADR-003 §3 item 1, §5]
                let onScreen = BadgeSelection.select(
                    openToolNames: presentation.openCalls.values).badge
                let removed = presentation.openCalls.removeValue(forKey: toolUseID) != nil
                // Three conditions, all of them load-bearing. `removed` keeps a
                // duplicate close — `PostToolBatch` re-reports ids a
                // `PostToolUse` already closed — from arming or re-arming, so a
                // beat can be cancelled but never extended. `isEmpty` is the
                // transition to zero: a close into a still-occupied set gets
                // nothing, because the slot is occupied and the character is
                // visibly working anyway.
                if removed, presentation.openCalls.isEmpty, let onScreen {
                    presentation.closingBeat = ClosingBeat(
                        badge: onScreen, until: now + Self.closingBeatDuration)
                }
                presentations[agent] = presentation
                note(&touched, agent)

            case let .callAbandoned(agent, toolUseID, _, _):
                // An abandoned call is our blind spot, not the user's failure:
                // it closes exactly like a normal one and the character just
                // returns to idle. No error is shown. [I4]
                //
                // **And it arms no beat, including when it empties the set.**
                // An abandon is the reaper closing that blind spot rather than a
                // completed action, and it fires up to fifteen minutes after the
                // fact — a `magnifier` beat at t+900 saying "just did a read"
                // about a call we lost track of is fiction of the plainest kind.
                // [I1, ADR-003 §3]
                presentations[agent]?.openCalls.removeValue(forKey: toolUseID)
                note(&touched, agent)

            case let .attentionChanged(agent, attention):
                // Nothing but the badge. The existing suppression memory then
                // does the rest: `setBadge` is emitted only if this actually
                // changed what is on the character's head.
                //
                // A rising attention **cancels** a beat rather than merely
                // outranking it: it outranks a live tool badge for three
                // reasons, and it beats a finished one more strongly still.
                // [ADR-003 §3]
                if attention != nil { presentations[agent]?.closingBeat = nil }
                presentations[agent]?.attention = attention
                note(&touched, agent)

            case let .dormancyChanged(agent, isDormant):
                // Nothing but the badge, exactly like `attentionChanged`. The
                // suppression memory below decides whether that is a visible
                // change at all, so a wake that arrives in the same batch as
                // the `callOpened` that caused it produces one `setBadge`
                // carrying the tool glyph, not two.
                //
                // Going dormant cancels a beat: the `Z` is a fact about now and
                // the beat is not. [ADR-003 §3]
                if isDormant { presentations[agent]?.closingBeat = nil }
                // The instant it *became* dormant, not the last time we were
                // told it is: `SubagentStop` can arrive twice for one sleep and
                // restamping would keep pushing a long sleeper down the eviction
                // order for events that changed nothing.
                if let presentation = presentations[agent], presentation.isDormant != isDormant {
                    presentations[agent]?.dormantSince = isDormant ? now : nil
                }
                presentations[agent]?.isDormant = isDormant
                // **A subagent's turn boundary.** `dormancyChanged` *is*
                // `SubagentStop` for a subagent — the model's own name for "this
                // one finished a turn and is still assigned" — so the posture and
                // the `Z` tab say the same thing on the same frame instead of the
                // tab sitting over a body that disagrees with it. A revival is
                // the same fact inverted and seats the character again.
                //
                // The main agent's is `turnChanged`, below. This arm is never
                // reached for one: `SubagentStop` carries an `agent_id` by
                // construction and `Stop` never does. [ADR-005 §3]
                presentations[agent]?.isInTurn = !isDormant
                // **A subagent's turn boundary is a tally boundary.** [ADR-006
                // §4a] The votes go and the desk object stays: the tally is about
                // this turn's work and the object is about what this agent's desk
                // is, which is as true between turns as during one. [§4b]
                if isDormant { endTally(for: agent) }
                note(&touched, agent)

            case let .gateChanged(agent, isGated):
                // **Nothing but the motion.** It takes no badge — the slot is
                // the attention bubble's business and that arrives six seconds
                // later on its own delta — and it takes no posture: a blocked
                // agent is at its workstation with a turn in progress, which is
                // exactly what `working` means since ADR-005 §3, and standing it
                // up would assert that it walked away from a dialog it is
                // stopped at. What changes is that the body stops moving.
                // [ADR-005 §7]
                //
                // It does **not** cancel a closing beat. The two cannot coexist:
                // a beat exists only while the open set is empty, and the mark
                // is disarmed by the close of any marked call — so by the time a
                // beat could be armed the gate that named its calls is gone.
                presentations[agent]?.isGated = isGated
                note(&touched, agent)

            case let .turnChanged(agent, hasTurn):
                // **The main thread's turn boundary, and nothing but the
                // posture.** It takes no badge — a `Stop` is not a notification
                // and not a `Z` — and no motion, because motion is the open-call
                // set's business and this says nothing about it. [ADR-005 §3]
                //
                // It is the other half of the `dormancyChanged` arm above: that
                // one is a subagent's turn boundary and this one is the main
                // agent's, and no agent ever receives both, because `Stop`
                // carries no `agent_id` and `SubagentStop` always does.
                //
                // **It does not cancel a closing beat.** A beat says *the last
                // thing this agent did was a read*, which stays true across the
                // turn boundary — and ADR-003 §6, as ADR-005 §5 restated it,
                // needs only that the body assert no ongoing work for every
                // frame of it. A standing body asserts less than a seated one,
                // not more.
                presentations[agent]?.isInTurn = hasTurn
                // **The main thread's turn boundary is its tally boundary**, the
                // other half of the `dormancyChanged` arm above. [ADR-006 §4a]
                //
                // ADR-006 was written before this delta existed and its §5d
                // planned for its absence: "subagents get per-turn tallies; the
                // main agent gets one tally for its whole life". That degradation
                // is not needed — `50a385d` shipped the boundary — so the main
                // agent is scoped exactly like every subagent and §5d's fallback
                // is dead text rather than the shipped behaviour.
                if !hasTurn { endTally(for: agent) }
                note(&touched, agent)

            case let .reportDelivered(agent):
                guard presentations[agent] != nil else { break }
                presentations[agent]?.reportedThisBatch = true
                note(&reported, agent)
                note(&touched, agent)

            case let .agentDeparted(agent):
                guard let presentation = presentations.removeValue(forKey: agent) else { break }
                let anchorSeat = anchorSeat(for: presentation)
                occupiedSeats.remove(presentation.seat)
                assignedVariants.removeValue(forKey: agent)
                emittedBody.removeValue(forKey: agent)
                emittedBadge.removeValue(forKey: agent)
                emittedGated.removeValue(forKey: agent)
                emittedNameplate.removeValue(forKey: agent)
                emittedDeskObject.removeValue(forKey: agent)
                emittedDeskScreen.removeValue(forKey: agent)
                // An agent that never had a seat was never spawned, so there is
                // no node to walk off. It leaves the overflow count instead,
                // which is the only thing that was ever showing it.
                if layout.isSeatable(presentation.seat) {
                    exited.append((
                        agent,
                        presentation.reportedThisBatch
                            ? .report(anchorSeat: anchorSeat) : .walkOff))
                }
                touched.removeAll { $0 == agent }
                appeared.removeAll { $0 == agent }
                // The exit *is* the beat for this character. Emitting a round
                // trip as well would ask the scene to walk a node home that it
                // is about to remove.
                reported.removeAll { $0 == agent }

            case .populationChanged:
                // The director counts its own characters. `populationChanged`
                // is per project and the scene shows one project; deriving the
                // scale from what is actually on screen cannot disagree with
                // itself.
                break

            case let .agentTasked(agent, task):
                // The nameplate's headline. Stored whole; `nameplate(for:)`
                // shortens it, because that is where the plate's width is
                // known. Retroactive by construction — the character is
                // already seated when this lands — so what draws it is the
                // `setNameplate` the touched loop emits, not a respawn.
                //
                // At most once per agent, so this is not a channel that can
                // flicker: a plate gains a task and then never changes again.
                presentations[agent]?.task = task
                note(&touched, agent)
            }
        }

        // Who is in the seven seats. After the deltas rather than inside them,
        // so a batch that departs three agents and appears one settles once
        // instead of three times.
        settleSeats(appeared: &appeared, touched: &touched, evicted: &evicted)

        var intents: [SpriteIntent] = []

        // Before the spawns, because an eviction and the arrival that caused it
        // share a seat and therefore a column. The leaver walks upstage out of
        // it and the newcomer walks upstage into it: same direction, same
        // speed, a convoy — which is the property `RoomLayout.entranceRoute`
        // already rests on for a departure-and-refill. Emitting the exit second
        // would not change what the scene does, since both animations start in
        // the same frame; it would only make the intent stream read backwards.
        for agent in evicted {
            intents.append(.exitCharacter(agent: agent, style: .walkOff))
        }

        for agent in appeared {
            // **An agent with no seat is counted, not drawn.** There is no
            // eighth seat to put it in: every position function in `RoomLayout`
            // wraps, so seat 7 is seat 0's column and seat 0's row. It is
            // carried by `setOverflow` below until a seat frees.
            guard let presentation = presentations[agent],
                  layout.isSeatable(presentation.seat) else { continue }
            let plate = Self.nameplate(for: presentation)
            // The spawn intent *is* the first `setNameplate`, so the memory is
            // seeded from it. Without this the touched loop below — which every
            // appearing agent is also in — would emit a second intent restating
            // the plate the character was built with.
            emittedNameplate[agent] = plate
            intents.append(.spawnCharacter(
                agent: agent,
                variant: presentation.variant,
                nameplate: plate,
                seat: presentation.seat,
                station: presentation.station,
                costume: presentation.costume))
        }

        // The desk object, before anything is emitted and for **every** touched
        // character rather than only the seated ones. The tally is a fact about
        // an agent and not about a seat, so an agent waiting in the overflow
        // queue keeps counting; what it does not get is an intent, exactly as it
        // gets no body and no badge.
        for agent in touched { settleDeskObject(agent, at: now) }

        for agent in touched {
            // Nothing is emitted for an unseated agent, and the *memory* is left
            // alone with it. That is what makes a promotion correct: the agent
            // that walks in when a seat frees has never had a body or a badge
            // set, so the first pass after its spawn emits whatever it is
            // actually doing rather than suppressing it as unchanged.
            guard let presentation = presentations[agent],
                  layout.isSeatable(presentation.seat) else { continue }
            // The badge class is computed here already, so the pose is looked up
            // here already. **No new trigger, no new timer, no new state** —
            // §8 item 7 — which is also what makes §6 rule 3 true for free: the
            // pose changes exactly when the badge changes, because it is a pure
            // function of the badge and is read at the same instant.
            //
            // **ADR-003 puts a dwell in the slot above and the pose still does
            // not follow it**, which is the sentence ADR-002 §6 rule 3 was
            // written to protect and the condition ADR-003 §2 makes
            // non-negotiable: *the pose follows the body, not the badge.*
            // `body(for:badge:)` returns before it reaches `workingPoses` unless
            // the resting state is `working`, and the resting state is `idle`
            // for every frame of a beat because `Presentation.body` reads
            // `openCalls` alone. A lingering `magnifier` therefore cannot select
            // a seated working pose — not by policy, but because the lookup is
            // not reached. [ADR-002 §6 rule 3, ADR-003 §2]
            // **Before the body and the badge**, so that in the one batch where
            // a character both learns its task and opens its first call, the
            // intent stream reads identity-then-activity rather than the other
            // way round. Neither ordering changes a pixel — the scene applies
            // the whole batch before the next frame — and this one is easier to
            // read in `SPRITEROOM_DEBUG` output.
            let plate = Self.nameplate(for: presentation)
            if emittedNameplate[agent] != plate {
                emittedNameplate[agent] = plate
                intents.append(.setNameplate(agent: agent, nameplate: plate))
            }
            // Beside the plate rather than beside the badge, because it belongs
            // to the same half of the stream: the plate says what this character
            // was sent to do and the desk says what it has been doing, and both
            // are slower than anything below them. Ordering only; the scene
            // applies the whole batch before the next frame. [ADR-006 §5b]
            if let kind = presentation.deskObject, emittedDeskObject[agent] != kind {
                emittedDeskObject[agent] = kind
                intents.append(.setDeskObject(agent: agent, kind: kind))
            }
            // Beside the object it lights, and after it, so that a character
            // that adopts a kind and ends its turn in one batch is told what is
            // on its desk before it is told the desk is dark. Ordering only —
            // the scene applies the whole batch before the next frame, and
            // `RoomScene` holds the screen state whether an object is drawn yet
            // or not. [ADR-006 §12]
            let screen = presentation.deskScreen
            if emittedDeskScreen[agent] != screen {
                emittedDeskScreen[agent] = screen
                intents.append(.setDeskScreen(agent: agent, screen: screen))
            }
            let badge = presentation.badge
            let body = body(for: presentation, badge: badge)
            if emittedBody[agent] != body {
                emittedBody[agent] = body
                intents.append(.setBody(
                    agent: agent, state: body, facing: layout.seatedFacing))
            }
            if emittedBadge[agent] != badge {
                emittedBadge[agent] = badge
                intents.append(.setBadge(agent: agent, selection: badge))
            }
            // Behind the badge, because the badge is what the phrase is keyed
            // on: a character that opens a gated call in one batch learns its
            // class and then that it is not to play it, rather than the reverse.
            // Both land before the next frame, so this orders the stream and
            // nothing else. [ADR-005 §7]
            if emittedGated[agent] != presentation.isGated {
                emittedGated[agent] = presentation.isGated
                intents.append(.setGated(agent: agent, isGated: presentation.isGated))
            }
        }

        // After the badge and body loop, deliberately: `SubagentStop` abandons
        // the agent's open calls, so the same batch carries the `callAbandoned`
        // that takes the badge down. The character walks to the anchor
        // empty-handed rather than carrying a tool badge through the beat, and
        // it does so because the *data* said the calls ended — nothing here
        // reaches in and clears a badge on its own account. [I2/I3]
        for agent in reported {
            guard let presentation = presentations[agent],
                  layout.isSeatable(presentation.seat) else { continue }
            intents.append(.deliverReport(
                agent: agent, anchorSeat: anchorSeat(for: presentation)))
        }

        for (agent, style) in exited {
            intents.append(.exitCharacter(agent: agent, style: style))
        }

        // Last, because everything above can move an agent between the two
        // sides of it: an arrival that found no seat, a departure that freed
        // one, and the promotion that followed.
        let overflow = overflowCount
        if emittedOverflow != overflow {
            emittedOverflow = overflow
            intents.append(.setOverflow(overflow))
        }

        let scale = camera.scale(forPopulation: population)
        if emittedScale != scale {
            emittedScale = scale
            intents.append(.setScale(scale))
        }

        // The flag is a fact about *this* frame and nothing outlives the frame
        // holding it. Clearing here rather than at the top of the next `apply`
        // means it is impossible to observe stale from outside, whatever order
        // batches arrive in.
        for agent in reported { presentations[agent]?.reportedThisBatch = false }

        return intents
    }

    // MARK: The desk object [ADR-006]

    /// **A turn ended: the votes go, the object stays.** [ADR-006 §4a, §4b]
    ///
    /// One function for both casts' boundaries — `dormancyChanged(true)` is a
    /// subagent's and `turnChanged(false)` is the main thread's, and no agent
    /// ever receives both — so the two arms cannot drift into clearing different
    /// things.
    private mutating func endTally(for agent: AgentRef) {
        presentations[agent]?.workTally.clear()
        presentations[agent]?.openingClaimCounted = false
    }

    /// **Re-derives what stands on one character's desk**, and is the only place
    /// `Presentation.deskObject` is written.
    ///
    /// Three things happen here, in order, and the last two are the ones with
    /// arguments behind them:
    ///
    /// 1. **The opening claim is counted**, once per turn, the first time this
    ///    runs with a description available. See `Presentation.openingClaimCounted`
    ///    for why it is lazy rather than seeded at the turn's opening event.
    /// 2. **The tally decides**, via `WorkTally.adopted(incumbent:)`, which never
    ///    returns `nil` over a non-`nil` incumbent — so nothing here can take an
    ///    object off a desk. [§4b]
    /// 3. **The dwell floor rate-limits a *change* and never an appearance.**
    ///    A refused change is remembered rather than dropped
    ///    (`deskObjectDeferred`), so it lands when the floor expires rather than
    ///    waiting for the agent's next event — which may never come.
    ///
    /// `now` is the frame's instant, passed in as a parameter exactly as
    /// ADR-003's beat takes it, so this is testable without waiting and
    /// replayable deterministically by the offscreen renderer.
    private mutating func settleDeskObject(_ agent: AgentRef, at now: Date) {
        guard var presentation = presentations[agent] else { return }
        if !presentation.openingClaimCounted, presentation.isInTurn, let task = presentation.task {
            // The room may **classify** the dispatch description into a closed,
            // total vocabulary whose unmatched case is *say nothing*. It reads
            // this field and `tool_name`, and no other field of `tool_input` —
            // not `prompt`, not `command`, not `file_path`. [ADR-006 §6b]
            presentation.workTally.seedOpeningClaim(WorkKind(dispatchDescription: task))
            presentation.openingClaimCounted = true
        }

        let incumbent = presentation.deskObject
        let adopted = presentation.workTally.adopted(incumbent: incumbent)
        if adopted == incumbent {
            presentation.deskObjectDeferred = false
        } else if incumbent == nil {
            presentation.deskObject = adopted
            presentation.deskObjectSetAt = now
            presentation.deskObjectDeferred = false
        } else if let setAt = presentation.deskObjectSetAt,
                  now.timeIntervalSince(setAt) >= Self.deskObjectDwell {
            presentation.deskObject = adopted
            presentation.deskObjectSetAt = now
            presentation.deskObjectDeferred = false
        } else {
            presentation.deskObjectDeferred = true
        }
        presentations[agent] = presentation
    }

    // MARK: Policy

    /// The main agent always holds seat 0 — the anchor everything reports to.
    /// Subagents take the lowest free seat, so the room fills outward from the
    /// centre and a given arrival order always produces the same picture.
    ///
    /// **It still counts past `layout.seatCapacity`, and those numbers are a
    /// queue rather than a room.** `layout.isSeatable(_:)` is the line: at or
    /// past it the agent is not drawn — it is carried by `setOverflow` and waits
    /// for `settleSeats` to find it one.
    ///
    /// A number past the seats is a *slot*, not a rank. It used to be both —
    /// lowest-free meant a smaller waiting number was an earlier arrival, so the
    /// queue ordered itself. Eviction ended that, because a seat number now goes
    /// up as well as down; `Presentation.arrival` is what orders the queue and
    /// all this has to do is hand out something unique and unseatable.
    private mutating func claimSeat(for agent: AgentRef) -> Int {
        if agent.agent == .mainThread, !occupiedSeats.contains(0) {
            occupiedSeats.insert(0)
            return 0
        }
        var seat = agent.agent == .mainThread ? 0 : 1
        while occupiedSeats.contains(seat) { seat += 1 }
        occupiedSeats.insert(seat)
        return seat
    }

    /// **Decides who is in the seven seats, once per batch.**
    ///
    /// Two passes, and the second one is the whole of the fix:
    ///
    /// 1. **Every genuinely free seat is filled**, longest wait first, live
    ///    agents ahead of dormant ones. Without this the overflow would be
    ///    permanent: seats are released on departure and reused by *new*
    ///    arrivals, so an agent that found the room full when it appeared would
    ///    still be uncounted-and-undrawn after every character on screen had
    ///    left. A room of empty desks over a plate reading "+3" is true and
    ///    useless.
    /// 2. **A live agent with no seat evicts the longest-dormant agent that has
    ///    one.**
    ///
    /// ## Why pass 2 exists
    ///
    /// Seats were freed on `agentDeparted` and on nothing else, and a subagent
    /// departs only at `SessionEnd` or the 30-minute session-idle sweep. So over
    /// one ordinary session the seven seats silently filled with **finished**
    /// subagents and stayed that way: a strictly serial ten-subagent session —
    /// one worker at a time, the plainest shape there is — drew the main agent
    /// and six characters all wearing the dormant `Z`, the oldest of them
    /// finished three minutes earlier, over a plate reading `+4`; and the single
    /// agent that was actually doing something at that instant was inside that
    /// `+4`, not on screen.
    ///
    /// That is S5 — *a cold observer watching 15 s can say how many agents are
    /// running* — failing at the one thing the room is for. The count was
    /// honest; **what the seven seats were spent on was not.** A seat is the
    /// scarcest thing this room has and it was being held by the agents with the
    /// least to show.
    ///
    /// ## Why it does not overturn dormancy
    ///
    /// `03-EVENT-MODEL.md` establishes that `SubagentStop` is a turn boundary
    /// and not a death, so a stopped subagent keeps a presence in the room. That
    /// argument is correct and survives intact — *stays visible* and *outranks a
    /// working agent for a seat* are separable claims and only the second was
    /// doing damage. A dormant agent is still in the room's population, still
    /// counted, still revivable in place, and still departs only on the paths
    /// that genuinely mean gone. It is simply no longer allowed to keep a
    /// working agent off screen.
    ///
    /// ## Why lazily, rather than freeing the seat on dormancy
    ///
    /// Freeing on `dormancyChanged(true)` is a one-line change and it is wrong:
    /// a session whose subagents have all finished would empty its room the
    /// moment the last one stopped, leaving the main agent alone under `+6`
    /// while six unoccupied desks stood there. Nothing needed those seats. The
    /// pressure is what makes an eviction worth making, so the eviction waits
    /// for the pressure — a quiet room keeps showing its sleepers, exactly as
    /// the dormancy decision intends, and a busy one spends its seats on the
    /// agents that are working.
    ///
    /// ## What the eviction asserts
    ///
    /// The evicted character walks out, and the overflow plate goes up by one in
    /// the same frame. That is the same sentence the room already says about
    /// every agent it has no seat for: *this one exists, it is counted, it is
    /// not drawn.* The walk asserts that the character has left the room, which
    /// is exactly true, and it does not assert that the agent ended — that
    /// claim belongs to `agentDeparted`, which is not what happened here and
    /// which alone removes the agent from the population. [I1]
    ///
    /// **The main agent is never evicted.** It holds seat 0, which is the anchor
    /// every report walks to, and it is never dormant in the first place — `Stop`
    /// sets no dormancy. The guard below says so rather than relying on that.
    ///
    /// **A seated agent walks in.** That is the same `spawn` every character
    /// gets and it claims nothing about when the agent started: the walk is the
    /// room seating somebody it was already counting, driven by a real event —
    /// the departure that freed the chair, or the arrival that needed one. The
    /// alternative — a character that blinks into a seat — is a beat the room
    /// has no art for and would read as a glitch. [I1]
    ///
    /// **It cannot oscillate.** Pass 1 leaves no free seat behind it, and pass 2
    /// puts a live agent into every seat it takes, so nothing this function does
    /// creates work for its own next iteration. A later swap needs a *new* real
    /// event — a dormancy, a revival, an arrival or a departure.
    private mutating func settleSeats(
        appeared: inout [AgentRef], touched: inout [AgentRef], evicted: inout [AgentRef]
    ) {
        while let free = freeSeat(), let next = firstWaiting() {
            take(next, into: free, appeared: &appeared, touched: &touched)
        }
        while let waiting = firstWaiting(dormant: false), let sleeper = longestDormantSeated(),
              let freed = presentations[sleeper]?.seat {
            unseat(sleeper, appeared: &appeared, touched: &touched, evicted: &evicted)
            take(waiting, into: freed, appeared: &appeared, touched: &touched)
        }
    }

    /// The lowest seat nobody holds, or `nil` when the room is full.
    private func freeSeat() -> Int? {
        (0..<layout.seatCapacity).first { !occupiedSeats.contains($0) }
    }

    /// Whoever has waited longest without a seat: live agents before dormant
    /// ones, and within each group the earliest arrival.
    ///
    /// - Parameter dormant: `false` restricts it to agents that are not dormant,
    ///   which is what pass 2 asks for — a sleeper never evicts another sleeper.
    ///   `nil` considers everyone.
    private func firstWaiting(dormant: Bool? = nil) -> AgentRef? {
        presentations
            .filter { _, presentation in
                guard !layout.isSeatable(presentation.seat) else { return false }
                guard let dormant else { return true }
                return presentation.isDormant == dormant
            }
            .min { a, b in
                if a.value.isDormant != b.value.isDormant { return !a.value.isDormant }
                return a.value.arrival < b.value.arrival
            }?.key
    }

    /// The seated character that has been dormant longest, and never the main
    /// agent. `nil` when every seat holds someone the room can still say
    /// something about.
    private func longestDormantSeated() -> AgentRef? {
        presentations
            .filter {
                $0.value.isDormant && layout.isSeatable($0.value.seat)
                    && $0.key.agent != .mainThread
            }
            .min { a, b in
                let (x, y) = (a.value.dormantSince, b.value.dormantSince)
                if x != y { return (x ?? .distantPast) < (y ?? .distantPast) }
                return a.value.arrival < b.value.arrival
            }?.key
    }

    /// Puts `agent` in `seat` and queues its walk-in.
    private mutating func take(
        _ agent: AgentRef, into seat: Int, appeared: inout [AgentRef], touched: inout [AgentRef]
    ) {
        guard let held = presentations[agent]?.seat else { return }
        occupiedSeats.remove(held)
        occupiedSeats.insert(seat)
        presentations[agent]?.seat = seat
        // `note`, not `append`: an agent that appeared into the queue and was
        // seated inside the same batch is already on this list, and spawning it
        // twice would put two intents on the stream for one character.
        note(&appeared, agent)
        note(&touched, agent)
    }

    /// Takes `agent` out of its seat and back into the queue, still in the
    /// population and still counted by `overflowCount`.
    ///
    /// The queue number is the lowest free one past the seats. It is a slot
    /// rather than a rank — `arrival` is what orders the queue — so all it has
    /// to be is unique and unseatable.
    ///
    /// The suppression memory goes with the seat, for the same reason it is
    /// never seeded for an agent that arrived into the queue: nothing is emitted
    /// for an unseated character, so when this one is seated again its body and
    /// badge must be stated afresh rather than suppressed as unchanged.
    private mutating func unseat(
        _ agent: AgentRef, appeared: inout [AgentRef], touched: inout [AgentRef],
        evicted: inout [AgentRef]
    ) {
        guard let held = presentations[agent]?.seat else { return }
        var queued = layout.seatCapacity
        while occupiedSeats.contains(queued) { queued += 1 }
        occupiedSeats.remove(held)
        occupiedSeats.insert(queued)
        presentations[agent]?.seat = queued
        emittedBody.removeValue(forKey: agent)
        emittedBadge.removeValue(forKey: agent)
        emittedNameplate.removeValue(forKey: agent)
        // The character's node goes with its seat and so does the desk object
        // standing beside it. The *tally* and the adopted kind stay on the
        // presentation, so an evicted agent that is seated again brings its own
        // desk back rather than starting from a bare one.
        emittedDeskObject.removeValue(forKey: agent)
        emittedDeskScreen.removeValue(forKey: agent)
        touched.removeAll { $0 == agent }
        // An agent seated and evicted inside one batch was never spawned, so
        // there is no node to walk off and nothing to say about it at all. It
        // simply drops off both lists.
        if appeared.contains(agent) {
            appeared.removeAll { $0 == agent }
        } else {
            note(&evicted, agent)
        }
    }

    /// The main agent always wears the first variant of the cast. Subagents
    /// take the lowest unused one so two simultaneous `Explore`s never look
    /// alike — this art carries almost no identity in silhouette, so reusing a
    /// variant while both are on screen would make them genuinely
    /// indistinguishable. [M0]
    private mutating func claimVariant(for agent: AgentRef) -> String {
        if agent.agent == .mainThread {
            assignedVariants[agent] = variantIDs[0]
            return variantIDs[0]
        }
        let inUse = Set(assignedVariants.values)
        let variant = variantIDs.first { !inUse.contains($0) }
            ?? variantIDs[assignedVariants.count % variantIDs.count]
        assignedVariants[agent] = variant
        return variant
    }

    /// Where this character walks to when it reports.
    ///
    /// Its parent's seat when `tool_response.agentId` linked them and that
    /// parent is still in the room; seat 0 — the main agent's anchor —
    /// otherwise. The fallback is documented, not invented: a subagent whose
    /// link we never saw reports to the main agent rather than to a guess. [I1]
    ///
    /// **A parent that is not on screen is not an anchor either.** Its seat
    /// number is then a place in the queue, and every position function in
    /// `RoomLayout` wraps — so seat 7 would send the reporter to seat 0's column
    /// and it would deliver its report to whoever happens to be sitting there.
    /// The fallback is the same fallback, for the same reason: with no visible
    /// parent, a subagent reports to the main agent. Eviction is what made this
    /// case ordinary rather than rare.
    private func anchorSeat(for presentation: Presentation) -> Int {
        guard let parent = presentation.parent else { return 0 }
        let ref = AgentRef(
            project: presentation.ref.project,
            session: presentation.ref.session,
            agent: parent)
        guard let seat = presentations[ref]?.seat, layout.isSeatable(seat) else { return 0 }
        return seat
    }

    /// **What the character is doing, in a word or two, and nothing else.** The
    /// plate is one row [`SceneBitmaps.nameplate`], so this is a ladder rather
    /// than a set of fields: the shortened task if a dispatch gave us one, the
    /// `agent_type` if not, and `main` for the main agent — whose absence of an
    /// `agent_id` *is* its identity. [CLAUDE.md, Identity model]
    ///
    /// Every rung is something the payload said. A subagent we attached to
    /// after its dispatch has no task, so it shows its type, which is true and
    /// is not a placeholder shaped like a task. [I1]
    ///
    /// # The `agent_id` discriminator is gone
    ///
    /// M5 added it and M7d moved it to its own row: the last three alphanumerics
    /// of `agent_id`, always on, because `agent_id` is the only field that
    /// distinguishes two subagents of one type and because silhouette (M0) and
    /// sampled accent hue (M2) had both been refuted as identity channels. It
    /// was doing real work and it is no longer produced at all.
    ///
    /// That is the maintainer's instruction — the plate takes too much space and
    /// should carry the summary and *that's it* — and the cost is exact:
    /// `fixtures/concurrent-permission-gates.jsonl` dispatches `Touch file s1`
    /// and `Touch file s2`, both shorten to `TOUCH FIL…`, and those two
    /// characters now have identical plates.
    /// `twoNearlyIdenticalDispatchesNowShareAPlateEntirely` pins it so it stays
    /// a known property rather than a bug someone rediscovers.
    ///
    /// It is not restorable in a smaller form: three glyphs of hex on the one
    /// line would take those glyphs off the task, which is the half the
    /// maintainer asked to read.
    ///
    /// **`agent_type` is not abbreviated, and that is a decision.** `GEN` for
    /// `general-purpose` needs either a table of names we made up — which is
    /// exactly what the `question_mark` badge exists to refuse — or a rule, and
    /// no rule degrades honestly over arbitrary user-defined text. "First three
    /// letters" turns `scene-engineer` and `security-reviewer` into `SCE` and
    /// `SEC`, which are *more* confusable than the truncations they replace and
    /// carry no mark that anything was dropped. "Initials of the hyphenated
    /// words" invents a code the user never wrote (`GP`, `SR`) and collapses to
    /// a single letter for a one-word type like `Explore`. Truncation with an
    /// ellipsis is lossy too, but it is lossy *visibly*, and it is the same
    /// answer this project already gives everywhere else it cannot represent
    /// something faithfully. [I1]
    static func nameplate(for presentation: Presentation) -> NameplateText {
        guard case .subagent = presentation.ref.agent else {
            // **The main agent has no task, permanently**, and this is where
            // that is structural rather than remembered: there is no dispatch
            // to carry one and this branch has nowhere to put one if there
            // were. Absence of `agent_id` *is* the main agent. [I1]
            return NameplateText(lead: "main")
        }
        // M0c found `agent_type` can arrive as the empty string, so absent has
        // to mean empty as well as nil or the plate draws a blank row.
        let type = presentation.agentType.flatMap { $0.isEmpty ? nil : $0 } ?? "subagent"
        // `lead` is the ladder's bottom rung and a subagent never reaches it:
        // `type` is non-empty by the line above. It is empty rather than
        // carrying something invisible, so that what the plate holds is what the
        // plate draws.
        return NameplateText(lead: "", role: type, task: taskLine(presentation.task))
    }

    /// Function words the task line drops.
    ///
    /// **Articles, coordinators and prepositions, and nothing else.** They are
    /// the words that are grammar rather than content: removing `the` from
    /// `Move the badge beside the head` removes nothing a person was reading,
    /// and it is the difference between a ten-glyph line that says `MOVE BADG…`
    /// and one that says `MOVE THE …`.
    ///
    /// **Quantifiers and adjectives are deliberately absent.** `all`, `any`,
    /// `each`, `every`, `new`, `old` look like filler in a list and are content
    /// in a sentence — *read all logs* is not *read logs*. The rule only removes
    /// words that cannot carry a task, and where it is not certain it keeps the
    /// word and lets the ellipsis do the work. That is the same instinct as the
    /// refusal to abbreviate `agent_type`: when a rule would have to guess, the
    /// honest fallback is visible truncation.
    static let taskStopWords: Set<String> = [
        "A", "AN", "THE",
        "AND", "OR", "THEN", "SO",
        "AT", "BY", "FOR", "FROM", "IN", "INTO", "OF", "ON", "ONTO", "TO",
        "VIA", "WITH", "WITHIN", "WITHOUT", "OVER", "UNDER", "BESIDE",
        "ACROSS", "AGAINST", "ABOUT", "AS",
        "IS", "ARE", "BE", "IT", "ITS", "THIS", "THAT",
    ]

    /// **`Move the badge beside the head` → `MOVE BADG…`.**
    ///
    /// The rule, whole:
    ///
    /// 1. cut the description into words at everything that is not a letter, a
    ///    digit or a hyphen — so `alpha.txt` is `ALPHA` and `TXT`, and
    ///    `delta/epsilon,` is `DELTA` and `EPSILON`;
    /// 2. drop `taskStopWords`, unless that would leave nothing;
    /// 3. join what is left and clip it to the plate's ten glyphs, cutting mid
    ///    word rather than at a word boundary;
    /// 4. **end in `…` unless every word of the description survived intact.**
    ///
    /// **Rule 4 is the honesty condition and it is total.** `…` on a task line
    /// means *there is more in the description than is drawn*, with no
    /// exceptions to remember — including the case the eye cannot otherwise
    /// catch, where the clipped text happens to land on a word boundary and
    /// reads as a finished phrase. `TOUCH FILE` would be a plate asserting that
    /// somebody was sent to touch a file; the description said `Touch file s1`,
    /// and `TOUCH FIL…` is the same information without the assertion. This is
    /// the convention `aTruncatedTypeStillSaysItWasTruncated` already pins for
    /// the type, applied to a line that can be cut in more ways.
    ///
    /// **Rule 3 cuts mid-word on purpose.** Clipping at a word boundary is
    /// tidier and loses the object: `MOVE BADGE HEAD` at a nine-glyph budget
    /// gives `MOVE…` whole-word and `MOVE BADG…` mid-word, and *badge* is the
    /// half of `move badge` the maintainer named. The type line has cut mid-word
    /// since M5 (`GENERAL-P…`) and nobody has misread it.
    ///
    /// **What it cannot do, and nothing else on the plate covers for it any
    /// more.** Ten glyphs is two short words, so two dispatches that differ only
    /// in their third word collapse:
    /// `fixtures/concurrent-permission-gates.jsonl` sends `Touch file s1` and
    /// `Touch file s2` and both plates read `TOUCH FIL…`. There used to be a
    /// discriminator row underneath to separate them and there is not now — the
    /// plate is one row. Those two characters are identical on screen.
    /// [`SceneDirector.nameplate(for:)`]
    ///
    /// A wider line would not rescue it: `TOUCH FILE S1` needs thirteen glyphs,
    /// and eleven or twelve clip to `TOUCH FILE…` — the same string for both.
    /// Thirteen is a plate the seat pitch cannot afford.
    /// [`SceneBitmaps.nameplateGlyphLimit`]
    ///
    /// Returns `nil` — no task row at all — for `nil` in, and for a description
    /// with no drawable word in it. Never a placeholder, never a guess. [I1]
    static func taskLine(_ task: String?, font: PixelFont = .standard) -> String? {
        guard let task else { return nil }
        // `normalise` uppercases and turns anything with no glyph into a space,
        // so the split below sees `,` and `'` as separators for free and the
        // words are already in the case they will be drawn in.
        let words = font.normalise(task)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        guard !words.isEmpty else { return nil }

        let kept = words.filter { !taskStopWords.contains($0) }
        // A description made entirely of function words has no content to
        // extract, so it is shown as it is rather than erased. `Read it` is not
        // informative, but it is what the payload said.
        let carried = kept.isEmpty ? words : kept
        let phrase = carried.joined(separator: " ")
        let limit = SceneBitmaps.nameplateGlyphLimit
        let elided = carried.count < words.count
        if !elided, phrase.count <= limit { return phrase }
        // One glyph goes to the mark, and a clip that lands on a space gives it
        // back — `READ ONE …` is a wasted glyph and a ragged line where
        // `READ ONE…` is neither.
        var clipped = String(phrase.prefix(max(0, limit - 1)))
        while clipped.last == " " { clipped.removeLast() }
        guard !clipped.isEmpty else { return nil }
        return clipped + "…"
    }

    private func note(_ list: inout [AgentRef], _ agent: AgentRef) {
        if !list.contains(agent) { list.append(agent) }
    }
}

extension AgentID {
    /// The `agent_id` this identity carries, or `nil` for the main thread.
    ///
    /// **Absence is the main agent** — the identity rule, not a fallback — and
    /// `AgentID` is where `SpriteRoomCore` already decided it. This is the
    /// adapter onto `ThemeSelector.station(agentID:agentType:in:)`, whose
    /// signature is a plain `String?` so that it can be tested without the
    /// model. [CLAUDE.md, Identity model]
    var subagentID: String? {
        if case let .subagent(id) = self { return id }
        return nil
    }
}
