import Foundation
import SpriteRoomCore

/// What the scene is asked to do. Value types only: the director is pure
/// policy and holds no nodes, so every rule in it is testable without a screen.
public enum SpriteIntent: Sendable, Hashable {
    /// Bring a character in. The scene plays `spawn` — the walk cycle from the
    /// room edge — and settles it at `seat`.
    case spawnCharacter(agent: AgentRef, variant: String, nameplate: NameplateText, seat: Int)
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
        /// Everything else — session end, idle sweep. Straight `depart`.
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
        /// From `.attentionChanged`. Orthogonal to `openCalls`: a character can
        /// be holding calls *and* be blocked at a permission gate, which is
        /// exactly what a `Bash` sitting at the dialog looks like.
        var attention: AttentionKind?

        /// **The body does not change for attention.** The pack ships no
        /// animation for "waiting on a human" and repurposing an unrelated one
        /// would be fiction, so the badge is the whole representation. A
        /// character blocked at a permission gate still has an open call and so
        /// is still `working`, which is what the data says. [I1/I2]
        var body: BodyState { openCalls.isEmpty ? .idle : .working }
        var badge: BadgeSelection {
            BadgeSelection.select(openToolNames: openCalls.values, attention: attention)
        }
    }

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

    private var presentations: [AgentRef: Presentation] = [:]
    /// Last intent actually emitted per agent — the suppression memory that
    /// keeps the badge from being re-set with the value it already has.
    private var emittedBody: [AgentRef: BodyState] = [:]
    private var emittedBadge: [AgentRef: BadgeSelection] = [:]
    private var emittedScale: Int?
    private var occupiedSeats: Set<Int> = []
    private var assignedVariants: [AgentRef: String] = [:]
    /// Tool names that fell through the mapping table. Counted, never guessed
    /// at. [I1]
    public private(set) var unmappedTools: [String: Int] = [:]

    public init(layout: RoomLayout = RoomLayout(), camera: RoomCamera = .default,
                variantIDs: [String],
                theme: Manifest.Theme = .unbound,
                workingPoses: [String: String] = [:]) {
        self.layout = layout
        self.camera = camera
        self.variantIDs = variantIDs.isEmpty ? ["00"] : variantIDs
        self.theme = theme
        self.workingPoses = workingPoses
    }

    /// - Parameter themeID: the theme the room is dressed in, so that stations
    ///   are drawn from *its* pool. `nil` is `manifest.room`, which §14a
    ///   establishes is the resolved default theme.
    public init(manifest: Manifest, themeID: String? = nil, layout: RoomLayout = RoomLayout()) {
        self.init(layout: layout,
                  camera: RoomCamera(manifest: manifest),
                  variantIDs: manifest.characters.orderedVariantIDs,
                  theme: manifest.themeBindings(themeID),
                  workingPoses: manifest.characters.workingPoses)
    }

    // MARK: Query

    public var population: Int { presentations.count }
    public var seats: [AgentRef: Int] { presentations.mapValues(\.seat) }
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
    func body(for presentation: Presentation, badge: BadgeSelection) -> BodyState {
        let resting = presentation.body
        guard resting == .working else { return resting }
        let named = badge.badge.flatMap { workingPoses[$0.manifestKey] }
            ?? workingPoses[Manifest.Characters.defaultPoseKey]
        return named.flatMap(BodyState.init(rawValue:)) ?? resting
    }

    // MARK: Apply

    /// One frame's worth of deltas in, one frame's worth of intents out.
    public mutating func apply(_ deltas: [WorldDelta]) -> [SpriteIntent] {
        var appeared: [AgentRef] = []
        var exited: [(AgentRef, SpriteIntent.ExitStyle)] = []
        var touched: [AgentRef] = []
        var reported: [AgentRef] = []

        for delta in deltas {
            switch delta {
            case let .agentAppeared(agent, agentType, _):
                if presentations[agent] == nil {
                    let seat = claimSeat(for: agent)
                    let variant = claimVariant(for: agent)
                    presentations[agent] = Presentation(
                        ref: agent, agentType: agentType, variant: variant, seat: seat,
                        // Decided here and nowhere else. §6 rule 2, and the
                        // `let` on the field is what keeps it true.
                        station: ThemeSelector.station(
                            agentID: agent.agent.subagentID,
                            agentType: agentType,
                            in: theme))
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
                presentations[agent]?.openCalls[call.toolUseID] = call.toolName
                note(&touched, agent)

            case let .callClosed(agent, toolUseID, _, _),
                 let .callAbandoned(agent, toolUseID, _, _):
                // An abandoned call is our blind spot, not the user's failure:
                // it closes exactly like a normal one and the character just
                // returns to idle. No error is shown. [I4]
                presentations[agent]?.openCalls.removeValue(forKey: toolUseID)
                note(&touched, agent)

            case let .attentionChanged(agent, attention):
                // Nothing but the badge. The existing suppression memory then
                // does the rest: `setBadge` is emitted only if this actually
                // changed what is on the character's head.
                presentations[agent]?.attention = attention
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
                exited.append((
                    agent,
                    presentation.reportedThisBatch ? .report(anchorSeat: anchorSeat) : .walkOff))
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
            }
        }

        var intents: [SpriteIntent] = []

        for agent in appeared {
            guard let presentation = presentations[agent] else { continue }
            intents.append(.spawnCharacter(
                agent: agent,
                variant: presentation.variant,
                nameplate: Self.nameplate(for: presentation),
                seat: presentation.seat))
        }

        for agent in touched {
            guard let presentation = presentations[agent] else { continue }
            // The badge class is computed here already, so the pose is looked up
            // here already. **No new trigger, no new timer, no new state** —
            // §8 item 7 — which is also what makes §6 rule 3 true for free: the
            // pose changes exactly when the badge changes, because it is a pure
            // function of the badge and is read at the same instant. A dwell
            // timer would make the body assert a tool class the badge above it
            // says has ended. [§6 rule 3]
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
            guard let presentation = presentations[agent] else { continue }
            intents.append(.deliverReport(
                agent: agent, anchorSeat: anchorSeat(for: presentation)))
        }

        for (agent, style) in exited {
            intents.append(.exitCharacter(agent: agent, style: style))
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
    private func anchorSeat(for presentation: Presentation) -> Int {
        guard let parent = presentation.parent else { return 0 }
        let ref = AgentRef(
            project: presentation.ref.project,
            session: presentation.ref.session,
            agent: parent)
        return presentations[ref]?.seat ?? 0
    }

    /// `agent_type` names the character. Its absence is the main agent — that
    /// is the identity rule, not a fallback. [CLAUDE.md, Identity model]
    ///
    /// **A subagent's plate also carries a discriminator from its `agent_id`,
    /// always.** Three `general-purpose` subagents dispatched together all read
    /// `GENERAL-P…` and are then distinguishable only by which seat they took —
    /// M4 watched that happen live. With silhouette refuted at M0 (the best
    /// six-variant subset differs by 7.3% of outline; several premades are
    /// identical) and accent hue refuted at M2, the plate *text* is the only
    /// channel left, so S4 fails for the most ordinary case there is unless the
    /// text separates them.
    ///
    /// `agent_id` is the only field that actually distinguishes two subagents of
    /// one type. It is real data we already hold, so showing three characters of
    /// it is not fiction; an invented index or an assigned colour would be. [I1]
    ///
    /// **Always on, never conditional.** The alternative — show it only while
    /// two visible agents share a type — was rejected: it mutates a plate that
    /// is already on screen the moment a second agent arrives, which is a change
    /// of *identity* under the user's eye, and it fires precisely when the room
    /// got busy and they are looking at it. It would also flicker, since the
    /// visible set changes on every arrival, departure and report walk. A stable
    /// plate is worth more than the glyphs it costs. The main agent has no
    /// `agent_id` and therefore no suffix, which is not an exception: absence of
    /// `agent_id` *is* the main agent.
    ///
    /// **The discriminator now leads instead of trailing.** M5 put it last, in
    /// the same 5×7 as the type, after an ellipsis — so three `general-purpose`
    /// plates agreed for eight glyphs and disagreed in the three smallest ones
    /// at the far end. The information is the same; the ordering was backwards.
    /// The plate draws `lead` large on the accent band and `role` small beneath,
    /// so what differs is what you see first. See `SceneBitmaps.nameplate`.
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
        guard case let .subagent(id) = presentation.ref.agent else {
            return NameplateText(lead: "main")
        }
        // M0c found `agent_type` can arrive as the empty string, so absent has
        // to mean empty as well as nil or the plate draws a blank row.
        let type = presentation.agentType.flatMap { $0.isEmpty ? nil : $0 } ?? "subagent"
        guard let discriminator = discriminator(id) else {
            // No usable characters in the `agent_id`, so there is nothing that
            // differs and the plate says so by having no lead: the type alone,
            // on one row. The type does *not* get promoted to the lead line —
            // a five-glyph 2× line would truncate `general-purpose` to `GENE…`
            // and lose more than the layout buys. [I1]
            return NameplateText(lead: "", role: type)
        }
        return NameplateText(lead: discriminator, role: type)
    }

    /// Characters of `agent_id` the lead line carries.
    ///
    /// Three rather than two because two is not enough to be safe: over six
    /// same-typed agents, two hex characters collide about 5.5% of the time and
    /// three about 0.4%, and a collision here is exactly the failure S4 names.
    /// A fourth would buy 0.03% and cost 12 px of a plate whose width is the
    /// axis under pressure.
    static let nameplateDiscriminatorGlyphs = 3

    /// The **last** three alphanumerics of `agent_id`, uppercased.
    ///
    /// The last rather than the first: every `agent_id` observed is `a` plus 16
    /// hex characters, so a leading slice spends a third of its budget on a
    /// constant. Taking from the end is also robust to any future prefix
    /// convention, and it stays a plain slice of the real id rather than a hash
    /// — someone comparing the plate against a transcript can see the same
    /// characters there.
    static func discriminator(_ agentID: String) -> String? {
        let usable = agentID.filter { $0.isLetter || $0.isNumber }
        guard !usable.isEmpty else { return nil }
        return String(usable.suffix(nameplateDiscriminatorGlyphs)).uppercased()
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
