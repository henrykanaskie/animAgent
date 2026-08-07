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
        #expect(exitStyles.contains(.report(anchorSeat: 0)))
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
        #expect(exits == [.report(anchorSeat: 0)])
    }

    /// A linked child reports to *its parent's* seat, not to seat 0.
    ///
    /// The link is applied retroactively — `SubagentStart` arrives before the
    /// `PostToolUse` that carries it — so the character is drawn first and told
    /// who it reports to afterwards. This is the only moment that knowledge
    /// changes anything visible.
    @Test func aLinkedChildReportsToItsParentsSeatRatherThanTheMainAgents() {
        var director = Self.director()
        let main = Self.ref(.mainThread)
        let middle = Self.ref(.subagent("middle"))
        let child = Self.ref(.subagent("child"))

        _ = director.apply([
            .agentAppeared(agent: main, agentType: nil, lifecycle: .active),
            .agentAppeared(agent: middle, agentType: "Explore", lifecycle: .spawning),
            .agentAppeared(agent: child, agentType: "Explore", lifecycle: .spawning),
        ])
        // Retroactive, one batch later.
        _ = director.apply([.agentLinked(agent: child, parent: .subagent("middle"))])

        let middleSeat = try! #require(director.seats[middle])
        #expect(middleSeat != 0, "the anchor under test must not be seat 0")

        let intents = director.apply([
            .reportDelivered(agent: child),
            .agentDeparted(agent: child),
        ])
        let exits = intents.compactMap { intent -> SpriteIntent.ExitStyle? in
            if case let .exitCharacter(_, style) = intent { return style }
            return nil
        }
        #expect(exits == [.report(anchorSeat: middleSeat)])
    }

    /// A parent that has already left the room is not a place to walk to. The
    /// anchor falls back to the main agent, which is the documented fallback
    /// for an unlinked subagent too. [I1]
    @Test func aChildWhoseParentHasDepartedFallsBackToTheMainAnchor() {
        var director = Self.director()
        let middle = Self.ref(.subagent("middle"))
        let child = Self.ref(.subagent("child"))

        _ = director.apply([
            .agentAppeared(agent: Self.ref(.mainThread), agentType: nil, lifecycle: .active),
            .agentAppeared(agent: middle, agentType: "Explore", lifecycle: .spawning),
            .agentAppeared(agent: child, agentType: "Explore", lifecycle: .spawning),
            .agentLinked(agent: child, parent: .subagent("middle")),
        ])
        _ = director.apply([.agentDeparted(agent: middle)])

        let intents = director.apply([
            .reportDelivered(agent: child),
            .agentDeparted(agent: child),
        ])
        let exits = intents.compactMap { intent -> SpriteIntent.ExitStyle? in
            if case let .exitCharacter(_, style) = intent { return style }
            return nil
        }
        #expect(exits == [.report(anchorSeat: 0)])
    }

    /// Every subagent in the capture is a child of the main thread, so the
    /// link and the fallback agree — which is exactly why implementing it
    /// changed no pixel of the existing fixtures.
    @Test func everyReportInTheCaptureStillAnchorsAtSeatZero() async throws {
        var director = Self.director()
        var anchors: [Int] = []
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for intent in director.apply(batch) {
                if case let .exitCharacter(_, .report(anchorSeat)) = intent {
                    anchors.append(anchorSeat)
                }
            }
        }
        #expect(anchors == [0, 0, 0])
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
        let child = Self.ref(.subagent("a894ded5b0c4b18de"))
        let intents = director.apply([
            .agentAppeared(agent: child, agentType: "security-reviewer", lifecycle: .spawning)])
        guard case let .spawnCharacter(_, _, nameplate, _) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        #expect(nameplate.hasPrefix("SECURIT"))
        #expect(nameplate.hasSuffix(":8DE"))

        var mainDirector = Self.director()
        let mainIntents = mainDirector.apply([
            .agentAppeared(agent: Self.ref(.mainThread), agentType: nil, lifecycle: .active)])
        guard case let .spawnCharacter(_, _, mainPlate, _) = mainIntents[0] else {
            Issue.record("expected a spawn"); return
        }
        // No `agent_id`, so no discriminator. That is the identity rule, not a
        // special case. [CLAUDE.md]
        #expect(mainPlate == "main")
    }

    /// The failure this whole change exists for: three subagents of one type,
    /// dispatched together, used to render three identical `GENERAL-P…` plates
    /// and were then distinguishable only by seat. [M4, S4]
    @Test func sameTypedSubagentsGetDifferentPlates() {
        var director = Self.director()
        let ids = ["a894ded5b0c4b18de", "a3b448736697956e7", "a793beae9fa532d0f"]
        var plates: [String] = []
        for id in ids {
            let intents = director.apply([
                .agentAppeared(agent: Self.ref(.subagent(id)),
                               agentType: "general-purpose", lifecycle: .spawning)])
            for case let .spawnCharacter(_, _, plate, _) in intents { plates.append(plate) }
        }
        #expect(plates.count == 3)
        #expect(Set(plates).count == 3, "same-typed subagents share a plate: \(plates)")
        #expect(plates.allSatisfy { $0.hasPrefix("GENERAL") })
    }

    /// The plate is decided once, at spawn, and never rewritten. Showing the
    /// discriminator only when a twin turns up would change a character's
    /// identity while the user is looking at it.
    @Test func theDiscriminatorIsPresentEvenWhenTheTypeIsUnique() {
        var director = Self.director()
        let intents = director.apply([
            .agentAppeared(agent: Self.ref(.subagent("a1c0ffee0badf00d1")),
                           agentType: "Explore", lifecycle: .spawning)])
        guard case let .spawnCharacter(_, _, plate, _) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        #expect(plate == "EXPLORE:0D1")
    }

    @Test func theDiscriminatorIsTheTailOfTheAgentIDAndSurvivesOddIDs() {
        // Every observed id is `a` + 16 hex, so a leading slice would spend a
        // third of its budget on a constant.
        #expect(SceneDirector.discriminator("a894ded5b0c4b18de") == "8DE")
        #expect(SceneDirector.discriminator("a3b448736697956e7") == "6E7")
        // Shorter than the budget, and punctuation, degrade rather than crash.
        #expect(SceneDirector.discriminator("c1") == "C1")
        #expect(SceneDirector.discriminator("x-y-z") == "XYZ")
        #expect(SceneDirector.discriminator("---") == nil)
        #expect(SceneDirector.discriminator("") == nil)
    }

    /// Whatever the type is, the plate must stay inside the glyph budget or two
    /// neighbours' plates overlap and neither reads.
    @Test func noPlateExceedsTheGlyphBudget() {
        var director = Self.director()
        for (index, type) in ["general-purpose", "Explore", "claude-code-guide",
                              "statusline-setup", "a", ""].enumerated() {
            let id = String(format: "a%016x", index + 0x1000)
            let intents = director.apply([
                .agentAppeared(agent: Self.ref(.subagent(id)),
                               agentType: type, lifecycle: .spawning)])
            for case let .spawnCharacter(_, _, plate, _) in intents {
                #expect(plate.count <= SceneBitmaps.nameplateGlyphLimit,
                        "\(plate) is \(plate.count) glyphs")
            }
        }
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
