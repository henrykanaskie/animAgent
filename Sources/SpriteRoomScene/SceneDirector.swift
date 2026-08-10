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
/// **Animate state, not events.** A character is `working` while its open-call
/// set is non-empty and `idle` otherwise. Nothing here reacts to the *arrival*
/// of an event, which is why a 3 ms `Read` and a four-minute `Bash` both render
/// correctly with no queue and no minimum-duration hack. [I2/I3]
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

        /// **The body carries tense.** [ADR-003 §1]
        ///
        /// It reads `openCalls` and nothing else — not `attention`, not
        /// `isDormant`, and **not `closingBeat`**. That last omission is the
        /// load-bearing one and it is enforced here rather than asserted
        /// elsewhere: ADR-003 is *void*, not degraded, if the body is held in
        /// `working` for the beat, because an idle body under a `magnifier`
        /// bubble reads "not working; the last thing was a read" — which is
        /// true — while a `working` body under it asserts the agent is still
        /// reading, which is false. There is no expression below that could
        /// make the beat visible on the body, which is why the guarantee lives
        /// in this property and not in a rule someone has to keep.
        ///
        /// **The body does not change for attention, and it does not change for
        /// dormancy either.** The pack ships no animation for "waiting on a
        /// human" and none for "finished a turn" — M6b cut the `sleep` row and
        /// measured it as a head on a pillow drawn for a top-down bed — and
        /// repurposing an unrelated one would be fiction. In both cases the
        /// badge is the whole representation. A character blocked at a
        /// permission gate still has an open call and so is still `working`; a
        /// dormant one has none and so is `idle`. Both are what the data says.
        /// [I1/I2]
        var body: BodyState { openCalls.isEmpty ? .idle : .working }
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
    /// Seeded at spawn with the plate `spawnCharacter` carried, so the only
    /// `setNameplate` a character ever gets is one that says something the plate
    /// on screen does not.
    private var emittedNameplate: [AgentRef: NameplateText] = [:]
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
    /// badge argument may name a class; the resting state is `idle` because the
    /// open set is empty, so the lookup into `workingPoses` is never reached and
    /// a lingering glyph cannot put a working pose on an idle character. That is
    /// ADR-003 §2's third bullet, held structurally.
    func body(for presentation: Presentation, badge: BadgeSelection) -> BodyState {
        let resting = presentation.body
        guard resting == .working else { return resting }
        let named = badge.badge.flatMap { workingPoses[$0.manifestKey] }
            ?? workingPoses[Manifest.Characters.defaultPoseKey]
        return named.flatMap(BodyState.init(rawValue:)) ?? resting
    }

    /// The badge left on screen by the close that emptied this agent's set, if
    /// one is up. `nil` almost always; read by tests.
    public func closingBeat(_ agent: AgentRef) -> ClosingBeat? {
        presentations[agent]?.closingBeat
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
                            in: costumes))
                    // A character that has just walked in wears no badge, so
                    // "set the badge to none" is an instruction to do nothing.
                    // Seeding the memory here is what keeps the badge-change
                    // count equal to the open-call-change count now that an
                    // agent can appear idle — `UserPromptSubmit` creates the
                    // main character before its first tool call. [criterion 6]
                    emittedBadge[agent] = BadgeSelection.none
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
                presentations[agent]?.openCalls[call.toolUseID] = call.toolName
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
                emittedNameplate.removeValue(forKey: agent)
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
