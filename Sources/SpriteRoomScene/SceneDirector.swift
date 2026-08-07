import Foundation
import SpriteRoomCore

/// What the scene is asked to do. Value types only: the director is pure
/// policy and holds no nodes, so every rule in it is testable without a screen.
public enum SpriteIntent: Sendable, Hashable {
    /// Bring a character in. The scene plays `spawn` — the walk cycle from the
    /// room edge — and settles it at `seat`.
    case spawnCharacter(agent: AgentRef, variant: String, nameplate: String, seat: Int)
    /// The character's resting state. Only ever emitted when it actually
    /// changed.
    case setBody(agent: AgentRef, state: BodyState, facing: Facing)
    /// The badge layer. Only ever emitted when it actually changed. [criterion 6]
    case setBadge(agent: AgentRef, selection: BadgeSelection)
    /// Take a character out. `.report` is the `SubagentStop` choreography:
    /// walk to the anchor, `deliver`, then `depart`.
    case exitCharacter(agent: AgentRef, style: ExitStyle)
    /// Integer render scale. [I6]
    case setScale(Int)

    public enum ExitStyle: Sendable, Hashable {
        /// `SubagentStop`. The one dramatisation the event model licenses.
        ///
        /// `anchorSeat` is the seat of the character this one reports to —
        /// its parent, when `tool_response.agentId` linked them, and seat 0
        /// otherwise. Seat 0 is the documented fallback rather than a guess:
        /// an unlinked subagent reports to the main agent. [I1]
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
        /// Keyed by `tool_use_id`, never a single current tool. [I3]
        var openCalls: [ToolUseID: String] = [:]
        /// Set by `reportDelivered`, so the departure that follows it in the
        /// same batch becomes the walk instead of a plain exit.
        var reported = false
        /// Who this character reports to, from `.agentLinked`. `nil` until the
        /// link arrives, and `nil` forever when it never does — in which case
        /// the anchor is the main agent.
        var parent: AgentID?

        var body: BodyState { openCalls.isEmpty ? .idle : .working }
        var badge: BadgeSelection { BadgeSelection.select(openToolNames: openCalls.values) }
    }

    // MARK: Stored

    public let layout: RoomLayout
    public let camera: RoomCamera
    /// Variant ids in manifest order. The cast, chosen at M0 by measurement.
    public let variantIDs: [String]

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
                variantIDs: [String]) {
        self.layout = layout
        self.camera = camera
        self.variantIDs = variantIDs.isEmpty ? ["00"] : variantIDs
    }

    public init(manifest: Manifest, layout: RoomLayout = RoomLayout()) {
        self.init(layout: layout,
                  camera: RoomCamera(manifest: manifest),
                  variantIDs: manifest.characters.orderedVariantIDs)
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
        presentations[agent]?.body
    }

    // MARK: Apply

    /// One frame's worth of deltas in, one frame's worth of intents out.
    public mutating func apply(_ deltas: [WorldDelta]) -> [SpriteIntent] {
        var appeared: [AgentRef] = []
        var exited: [(AgentRef, SpriteIntent.ExitStyle)] = []
        var touched: [AgentRef] = []

        for delta in deltas {
            switch delta {
            case let .agentAppeared(agent, agentType, _):
                if presentations[agent] == nil {
                    let seat = claimSeat(for: agent)
                    let variant = claimVariant(for: agent)
                    presentations[agent] = Presentation(
                        ref: agent, agentType: agentType, variant: variant, seat: seat)
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

            case let .reportDelivered(agent):
                presentations[agent]?.reported = true
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
                    presentation.reported ? .report(anchorSeat: anchorSeat) : .walkOff))
                touched.removeAll { $0 == agent }
                appeared.removeAll { $0 == agent }

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
            let body = presentation.body
            if emittedBody[agent] != body {
                emittedBody[agent] = body
                intents.append(.setBody(
                    agent: agent, state: body, facing: layout.seatedFacing))
            }
            let badge = presentation.badge
            if emittedBadge[agent] != badge {
                emittedBadge[agent] = badge
                intents.append(.setBadge(agent: agent, selection: badge))
            }
        }

        for (agent, style) in exited {
            intents.append(.exitCharacter(agent: agent, style: style))
        }

        let scale = camera.scale(forPopulation: population)
        if emittedScale != scale {
            emittedScale = scale
            intents.append(.setScale(scale))
        }

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
    static func nameplate(for presentation: Presentation) -> String {
        if presentation.ref.agent == .mainThread { return "main" }
        return presentation.agentType ?? "subagent"
    }

    private func note(_ list: inout [AgentRef], _ agent: AgentRef) {
        if !list.contains(agent) { list.append(agent) }
    }
}
