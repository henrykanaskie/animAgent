import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

struct SceneDirectorTests {

    static let cast = ["06", "07", "09", "10", "17", "19"]

    static func director() -> SceneDirector {
        SceneDirector(variantIDs: cast)
    }

    static func ref(_ agent: AgentID) -> AgentRef {
        AgentRef(project: "/p", session: "s", agent: agent)
    }

    static func call(_ id: String, _ tool: String, at seconds: TimeInterval = 0) -> OpenCall {
        let start = Date(timeIntervalSince1970: seconds)
        return OpenCall(
            toolUseID: id, toolName: tool, startedAt: start,
            deadline: start.addingTimeInterval(60))
    }

    // MARK: Appearance — criterion 1

    @Test func everyAgentInTheFixtureGetsExactlyOneCharacter() async throws {
        var director = Self.director()
        var spawned: [AgentRef] = []
        var appeared: Set<AgentRef> = []

        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for delta in batch {
                if case let .agentAppeared(agent, _, _) = delta { appeared.insert(agent) }
            }
            for intent in director.apply(batch) {
                if case let .spawnCharacter(agent, _, _, _) = intent { spawned.append(agent) }
            }
        }

        #expect(!appeared.isEmpty)
        #expect(Set(spawned) == appeared)
        #expect(spawned.count == Set(spawned).count, "a character was spawned twice")
    }

    @Test func everyFixtureProducesACharacterForEveryAgent() async throws {
        for name in ["single-agent-simple", "parallel-tools", "three-subagents",
                     "killed-session", "tool-failure"] {
            var director = Self.director()
            var spawned: Set<AgentRef> = []
            var appeared: Set<AgentRef> = []
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for delta in batch {
                    if case let .agentAppeared(agent, _, _) = delta { appeared.insert(agent) }
                }
                for intent in director.apply(batch) {
                    if case let .spawnCharacter(agent, _, _, _) = intent { spawned.insert(agent) }
                }
            }
            #expect(spawned == appeared, "\(name)")
        }
    }

    /// An event stream we do not understand must not conjure a character.
    @Test func unknownEventsSpawnNobody() async throws {
        var director = Self.director()
        var spawned = 0
        for batch in try await SceneFixtures.batchedDeltas("unknown-events") {
            for intent in director.apply(batch) {
                if case .spawnCharacter = intent { spawned += 1 }
            }
        }
        // The session's own main agent is legitimate; nothing beyond it.
        #expect(spawned <= 1)
    }

    // MARK: Body state — criterion 2, and [I2]

    @Test func aCharacterIsWorkingExactlyWhileItsOpenCallSetIsNonEmpty() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        #expect(director.bodyState(agent) == .idle)

        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Bash"))])
        #expect(director.bodyState(agent) == .working)

        _ = director.apply([.callOpened(agent: agent, call: Self.call("b", "Read"))])
        #expect(director.bodyState(agent) == .working)

        _ = director.apply([
            .callClosed(agent: agent, toolUseID: "a", toolName: "Bash", outcome: .succeeded)])
        #expect(director.bodyState(agent) == .working, "one call still open")

        _ = director.apply([
            .callClosed(agent: agent, toolUseID: "b", toolName: "Read", outcome: .succeeded)])
        #expect(director.bodyState(agent) == .idle)
    }

    /// An abandoned call is our blind spot, not the user's failure. The
    /// character returns to idle and shows nothing else. [I4]
    @Test func anAbandonedCallClosesLikeAnyOther() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Bash")),
        ])
        let intents = director.apply([
            .callAbandoned(
                agent: agent, toolUseID: "a", toolName: "Bash", reason: .deadlineExpired)])
        #expect(director.bodyState(agent) == .idle)
        #expect(intents.contains { intent in
            if case let .setBadge(_, selection) = intent { return selection.badge == nil }
            return false
        })
    }

    /// All six states have to be reachable from a real fixture: four from the
    /// director's resting states and the choreography, two from the exits.
    @Test func theSixStatesAreAllReachableFromTheFixture() async throws {
        var director = Self.director()
        var restingStates: Set<BodyState> = []
        var sawSpawn = false
        var exitStyles: Set<SpriteIntent.ExitStyle> = []

        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for intent in director.apply(batch) {
                switch intent {
                case .spawnCharacter: sawSpawn = true
                case let .setBody(_, state, _): restingStates.insert(state)
                case let .exitCharacter(_, style): exitStyles.insert(style)
                default: break
                }
            }
        }
        // `spawn` (walk in), `idle`, `working` from the roster;
        // `walk` + `deliver` + `depart` from a `.report` exit.
        #expect(sawSpawn)
        #expect(restingStates.contains(.idle))
        #expect(restingStates.contains(.working))
        #expect(exitStyles.contains(.report))
    }

    /// A seated character can only face sideways. Asking for `working` facing
    /// up or down is asking for art nobody drew.
    @Test func seatedCharactersAlwaysFaceSideways() async throws {
        var director = Self.director()
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for intent in director.apply(batch) {
                if case let .setBody(_, state, facing) = intent, state == .working {
                    #expect(facing.isSideView)
                }
            }
        }
    }

    // MARK: Badge — criterion 3

    @Test func theBadgeAppearsOnOpenAndDisappearsOnTheMatchingClose() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        #expect(director.badge(agent).badge == nil)

        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Read"))])
        #expect(director.badge(agent).badge == .magnifier)
        #expect(director.badge(agent).count == 1)

        _ = director.apply([
            .callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)])
        #expect(director.badge(agent).badge == nil)
    }

    @Test func theBadgeShowsTheLowestOrdinalPlusTheTotal() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Bash")),
            .callOpened(agent: agent, call: Self.call("b", "Write")),
            .callOpened(agent: agent, call: Self.call("c", "Grep")),
        ])
        #expect(director.badge(agent).badge == .document)
        #expect(director.badge(agent).count == 3)
    }

    /// The `parallel-tools` fixture holds five concurrent `Bash` calls and
    /// closes them out of order. The badge must never move while they do.
    @Test func fiveConcurrentCallsProduceOneBadgeAndOneCount() async throws {
        var director = Self.director()
        var badgeIntents: [BadgeSelection] = []
        for batch in try await SceneFixtures.batchedDeltas("parallel-tools") {
            for intent in director.apply(batch) {
                if case let .setBadge(_, selection) = intent { badgeIntents.append(selection) }
            }
        }
        let nonEmpty = badgeIntents.filter { $0.badge != nil }
        #expect(nonEmpty.allSatisfy { $0.badge == .terminal })
        #expect(nonEmpty.map(\.count).max() == 5)
    }

    // MARK: Criterion 6 — no flicker

    /// The badge may change at most once per change of the open-call set, for
    /// every character, over the whole fixture. Anything more is flicker.
    @Test func noCharacterChangesBadgeMoreOftenThanItsOpenCallSetChanges() async throws {
        for name in ["three-subagents", "parallel-tools", "single-agent-simple",
                     "tool-failure", "killed-session"] {
            var director = Self.director()
            var openCallChanges: [AgentRef: Int] = [:]
            var badgeChanges: [AgentRef: Int] = [:]
            var lastBadge: [AgentRef: BadgeSelection] = [:]

            for batch in try await SceneFixtures.batchedDeltas(name) {
                for delta in batch {
                    switch delta {
                    case let .callOpened(agent, _),
                         let .callClosed(agent, _, _, _),
                         let .callAbandoned(agent, _, _, _):
                        openCallChanges[agent, default: 0] += 1
                    default: break
                    }
                }
                for intent in director.apply(batch) {
                    guard case let .setBadge(agent, selection) = intent else { continue }
                    #expect(
                        lastBadge[agent] != selection,
                        "\(name): \(agent) was re-sent the badge it already had")
                    lastBadge[agent] = selection
                    badgeChanges[agent, default: 0] += 1
                }
            }

            for (agent, changes) in badgeChanges {
                let allowed = openCallChanges[agent] ?? 0
                #expect(
                    changes <= allowed,
                    "\(name): \(agent) changed badge \(changes)× for \(allowed) open-call changes")
            }
        }
    }

    @Test func aBodyStateIsNeverReEmittedWithTheValueItAlreadyHad() async throws {
        for name in ["three-subagents", "parallel-tools", "tool-failure"] {
            var director = Self.director()
            var lastBody: [AgentRef: BodyState] = [:]
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for intent in director.apply(batch) {
                    guard case let .setBody(agent, state, _) = intent else { continue }
                    #expect(lastBody[agent] != state, "\(name): \(agent) re-sent \(state)")
                    lastBody[agent] = state
                }
            }
        }
    }

    // MARK: Same-frame coalescing

    /// An agent that appears and opens a call in the same batch must not be
    /// told to idle first. This is the whole reason deltas are applied in
    /// batches rather than one at a time.
    @Test func appearingAndWorkingInOneFrameProducesOneBodyIntent() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        let intents = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Bash")),
        ])
        let bodies = intents.compactMap { intent -> BodyState? in
            if case let .setBody(_, state, _) = intent { return state }
            return nil
        }
        #expect(bodies == [.working])
    }

    /// `SubagentStop` emits `reportDelivered` and `agentDeparted` in the same
    /// batch. The character must leave by the report route, not be yanked off
    /// screen.
    @Test func reportAndDepartureInOneFrameBecomeTheReportExit() {
        var director = Self.director()
        let agent = Self.ref(.subagent("child"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning)])
        let intents = director.apply([
            .reportDelivered(agent: agent),
            .agentDeparted(agent: agent),
        ])
        let exits = intents.compactMap { intent -> SpriteIntent.ExitStyle? in
            if case let .exitCharacter(_, style) = intent { return style }
            return nil
        }
        #expect(exits == [.report])
    }

    @Test func aDepartureWithoutAReportIsAPlainWalkOff() {
        var director = Self.director()
        let agent = Self.ref(.subagent("child"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning)])
        let intents = director.apply([.agentDeparted(agent: agent)])
        let exits = intents.compactMap { intent -> SpriteIntent.ExitStyle? in
            if case let .exitCharacter(_, style) = intent { return style }
            return nil
        }
        #expect(exits == [.walkOff])
    }

    // MARK: Casting

    @Test func theMainAgentTakesSeatZeroAndTheFirstVariant() {
        var director = Self.director()
        let main = Self.ref(.mainThread)
        let intents = director.apply([
            .agentAppeared(agent: main, agentType: nil, lifecycle: .active)])
        guard case let .spawnCharacter(_, variant, nameplate, seat) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        #expect(seat == 0)
        #expect(variant == Self.cast[0])
        #expect(nameplate == "main")
    }

    /// Two simultaneous `Explore`s must not wear the same body. This art
    /// carries almost no identity in silhouette, so a reused variant would make
    /// them genuinely indistinguishable. [M0]
    @Test func concurrentSubagentsNeverShareAVariantOrASeat() async throws {
        var director = Self.director()
        var liveVariants: [AgentRef: String] = [:]
        var liveSeats: [AgentRef: Int] = [:]

        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for intent in director.apply(batch) {
                switch intent {
                case let .spawnCharacter(agent, variant, _, seat):
                    #expect(!liveVariants.values.contains(variant), "variant \(variant) reused")
                    #expect(!liveSeats.values.contains(seat), "seat \(seat) reused")
                    liveVariants[agent] = variant
                    liveSeats[agent] = seat
                case let .exitCharacter(agent, _):
                    liveVariants.removeValue(forKey: agent)
                    liveSeats.removeValue(forKey: agent)
                default: break
                }
            }
        }
    }

    @Test func theNameplateIsTheAgentTypeAndItsAbsenceIsTheMainAgent() {
        var director = Self.director()
        let child = Self.ref(.subagent("c1"))
        let intents = director.apply([
            .agentAppeared(agent: child, agentType: "security-reviewer", lifecycle: .spawning)])
        guard case let .spawnCharacter(_, _, nameplate, _) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        #expect(nameplate == "security-reviewer")
    }

    // MARK: Scale [I6]

    @Test func theDirectorOnlyEmitsIntegerScalesAndOnlyOnChange() async throws {
        var director = Self.director()
        var scales: [Int] = []
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for intent in director.apply(batch) {
                if case let .setScale(scale) = intent { scales.append(scale) }
            }
        }
        #expect(!scales.isEmpty)
        #expect(scales.allSatisfy { [3, 2, 1].contains($0) })
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 != $1 }, "scale re-emitted")
    }

    // MARK: Determinism

    @Test func replayingTheSameFixtureTwiceProducesIdenticalIntents() async throws {
        func run() async throws -> [SpriteIntent] {
            var director = Self.director()
            var intents: [SpriteIntent] = []
            for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
                intents += director.apply(batch)
            }
            return intents
        }
        let first = try await run()
        let second = try await run()
        #expect(first == second)
    }

    @Test func unmappedToolsAreCountedNotGuessedAt() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "AToolFromTheFuture")),
        ])
        #expect(director.unmappedTools["AToolFromTheFuture"] == 1)
        #expect(director.badge(agent).badge == .questionMark)
    }
}
