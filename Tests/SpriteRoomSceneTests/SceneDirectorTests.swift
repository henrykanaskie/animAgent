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
                if case let .spawnCharacter(agent, _, _, _, _, _) = intent { spawned.append(agent) }
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
                    if case let .spawnCharacter(agent, _, _, _, _, _) = intent { spawned.insert(agent) }
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

    /// **`agent is working ⟺ !openCalls.isEmpty` is unchanged, and it is a
    /// statement about the *motion*.** [I2, ADR-005 §6]
    ///
    /// It was written when the two channels were one: the body state was
    /// `openCalls.isEmpty ? .idle : .working` and `idle` was a standing pose, so
    /// the same expression decided both whether the character moved and whether
    /// it was at its desk. ADR-005 split them, because keying the *posture* on
    /// the call meant a character stood up in the walkway for the 2.35 s between
    /// two calls of one turn. The motion is what carries "working" now, and this
    /// test follows it there: the sequence the scene will play is the one held
    /// frame `AmbientMotion` returns for an empty set, and a phrase exactly when
    /// there is a call to play it for.
    @Test func aCharacterMovesExactlyWhileItsOpenCallSetIsNonEmpty() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)

        /// What the scene will draw: the composition `Character` performs, off
        /// the two values the director emits.
        func isMoving() -> Bool {
            guard let state = director.bodyState(agent) else { return false }
            return AmbientMotion.sequence(
                for: director.badge(agent).badge, state: state,
                openCalls: director.openCallCount(agent), frameCount: 3).count > 1
        }

        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)])
        #expect(director.bodyState(agent) == .working, "the agent's first event seats it")
        #expect(!isMoving(), "a character with no open call moved")

        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Bash"))])
        #expect(director.bodyState(agent) == .working)
        #expect(isMoving())

        _ = director.apply([.callOpened(agent: agent, call: Self.call("b", "Read"))])
        #expect(isMoving())

        _ = director.apply([
            .callClosed(agent: agent, toolUseID: "a", toolName: "Bash", outcome: .succeeded)])
        #expect(isMoving(), "one call still open")

        _ = director.apply([
            .callClosed(agent: agent, toolUseID: "b", toolName: "Read", outcome: .succeeded)])
        #expect(!isMoving(), "the set emptied and the body kept moving")
        #expect(director.bodyState(agent) == .working,
                "the character left its desk because a call returned")
    }

    /// An abandoned call is our blind spot, not the user's failure. The badge
    /// comes down, the motion stops, and nothing else is shown — in particular
    /// the character does not get up, because a reap says nothing about where
    /// the agent is. [I4, ADR-005 §3]
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
        #expect(director.openCallCount(agent) == 0)
        #expect(director.bodyState(agent) == .working)
        #expect(intents.contains { intent in
            if case let .setBadge(_, selection) = intent { return selection.badge == nil }
            return false
        })
    }

    /// All six states have to be reachable from a real fixture: four from the
    /// director's resting states and the choreography, two from the report beat.
    @Test func theSixStatesAreAllReachableFromTheFixture() async throws {
        var director = Self.director()
        var restingStates: Set<BodyState> = []
        var sawSpawn = false
        var sawReport = false
        var exitStyles: Set<SpriteIntent.ExitStyle> = []

        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for intent in director.apply(batch) {
                switch intent {
                case .spawnCharacter: sawSpawn = true
                case let .setBody(_, state, _): restingStates.insert(state)
                case .deliverReport: sawReport = true
                case let .exitCharacter(_, style): exitStyles.insert(style)
                default: break
                }
            }
        }
        // `spawn` (walk in), `idle`, `working` from the roster; `walk` +
        // `deliver` from the report round trip; `depart` from the exits.
        #expect(sawSpawn)
        #expect(restingStates.contains(.idle))
        #expect(restingStates.contains(.working))
        #expect(sawReport)
        #expect(exitStyles.contains(.walkOff))
        // And nothing exits by the report route, because nothing in this
        // capture reports and departs in the same frame. `SubagentStop` no
        // longer departs anyone — the three subagents report at 34.5 s, 37.4 s
        // and 40.9 s and are still in their seats when `SessionEnd` clears the
        // room at 42.7 s.
        #expect(!exitStyles.contains { if case .report = $0 { return true } else { return false } })
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

    // MARK: The permission gate — ADR-005 §7

    /// **The gate is its own channel, and it moves neither of the other two.**
    ///
    /// A blocked character is seated (it is in a turn, at its desk — standing it
    /// up would say it walked away from a dialog it is stopped at) and wears
    /// whatever the badge layer decided (its tool glyph for the first six
    /// seconds, the attention bubble after). What changes is that it stops
    /// moving, and `setGated` is the only intent that says so.
    @Test func aGateEmitsItsOwnIntentAndMovesNeitherTheBodyNorTheBadge() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Bash")),
        ])

        let intents = director.apply([.gateChanged(agent: agent, isGated: true)])
        #expect(intents == [.setGated(agent: agent, isGated: true)])
        #expect(director.isGated(agent))
        #expect(director.bodyState(agent) == .working, "the gate stood the character up")
        #expect(director.badge(agent).badge == .terminal, "the gate took the badge down")
        #expect(director.badge(agent).count == 1, "the gate closed the call")

        // A change, never a repeat, on the same suppression memory every other
        // channel uses.
        #expect(director.apply([.gateChanged(agent: agent, isGated: true)]).isEmpty)
        #expect(director.apply([.gateChanged(agent: agent, isGated: false)])
            == [.setGated(agent: agent, isGated: false)])
        #expect(!director.isGated(agent))
    }

    /// **A character that is never gated is never told about a gate**, which is
    /// every character in fifteen of the seventeen fixtures. The memory is
    /// seeded at spawn, exactly as `emittedBadge` is seeded with `.none`.
    @Test func anUngatedRoomEmitsNoGateIntents() async throws {
        for name in ["three-subagents", "four-subagents", "single-agent-simple"] {
            var director = Self.director()
            var gates = 0
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for intent in director.apply(batch) {
                    if case .setGated = intent { gates += 1 }
                }
            }
            #expect(gates == 0, "\(name) emitted \(gates) gate intents and holds no gate")
        }
    }

    /// **[I4] Nobody is left gated once the reaper has had its say.** The
    /// scene-side half of the balance the model keeps: a `setGated(true)` that is
    /// never answered is a character frozen forever, which is the sign-flipped
    /// twin of the character that types forever.
    ///
    /// **The sweep is part of the test rather than an afterthought**, because two
    /// of the corpus's gates are still open when their event stream ends — the
    /// pair in `concurrent-permission-gates`, one of which never sees a human at
    /// all. A character stopped at a dialog nobody ever answered is *correctly*
    /// still at the end of the stream; what may not happen is for it to be still
    /// after the session has been presumed dead. So this drives the model
    /// itself, and then the 30-minute idle sweep, which is exactly the two
    /// stages `LiveDriver` runs.
    @Test func noCharacterIsLeftGatedOnceTheReaperHasHadItsSay() async throws {
        var everGated = 0
        for name in ["concurrent-permission-gates", "permission-prompt",
                     "subagent-permission", "denial-then-work"] {
            let entries = try HookLog.load(contentsOf: SceneFixtures.url(name))
            let model = WorldModel()
            var director = Self.director()
            var gated: Set<AgentRef> = []

            func consume(_ deltas: [WorldDelta], at now: Date) {
                for intent in director.apply(deltas, at: now) {
                    switch intent {
                    case let .setGated(agent, isGated):
                        if isGated { gated.insert(agent); everGated += 1 }
                        else { gated.remove(agent) }
                    // **An exit is an ending too, and it is the one the corpus
                    // actually takes.** The model clears the gate and departs
                    // the agent in one batch — the idle sweep abandons the
                    // marked call, which disarms — and the director suppresses
                    // the clear for a character it is removing in the same
                    // frame, because there is no body left to unfreeze. The
                    // node goes with the walk-off.
                    case let .exitCharacter(agent, _):
                        gated.remove(agent)
                    default:
                        break
                    }
                }
            }

            for entry in entries {
                guard let event = entry.event else { continue }
                consume(await model.ingest(event, at: entry.receivedAt), at: entry.receivedAt)
            }
            let last = try #require(entries.last?.receivedAt)
            let after = last.addingTimeInterval(Reaper().sessionIdleTimeout + 1)
            consume(await model.sweep(at: after), at: after)

            #expect(gated.isEmpty, Comment(rawValue:
                "\(name): \(gated.count) character(s) still stopped at a permission gate after"
                + " the idle sweep — a character frozen forever [I4]"))
            // And nothing is holding a gated presentation either, which is the
            // same claim read off the director rather than off its output.
            for agent in director.seats.keys {
                #expect(!director.isGated(agent), "\(name): \(agent) is still gated")
            }
        }
        #expect(everGated >= 4, "the gated fixtures stopped producing gates: \(everGated)")
    }

    // MARK: Badge — criterion 3

    /// **The close no longer takes the badge down at the close.** ADR-003 leaves
    /// it up for `D` and then clears it, so the assertion this test has always
    /// made — "the badge disappears on the matching close" — is now an assertion
    /// about the instant `D` later. The clock is injected, so nothing waits.
    ///
    /// The `count` half is checked at both instants because it is the half that
    /// did *not* move: the `×N` annotates the open set, the open set is empty
    /// from the close onwards, and the beat carries `count: 0` for every frame
    /// of its life. [ADR-003 §5]
    @Test func theBadgeAppearsOnOpenAndSurvivesTheCloseByExactlyTheBeat() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        _ = director.apply(
            [.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)], at: t0)
        #expect(director.badge(agent).badge == nil)

        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Read"))], at: t0)
        #expect(director.badge(agent).badge == .magnifier)
        #expect(director.badge(agent).count == 1)

        let closedAt = t0.addingTimeInterval(0.006)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: closedAt)
        #expect(director.badge(agent).badge == .magnifier, "the beat did not arm")
        #expect(director.badge(agent).count == 0, "the ×N is suppressed for the whole beat")

        // One frame short of `D`: still up.
        _ = director.apply(
            [], at: closedAt.addingTimeInterval(SceneDirector.closingBeatDuration - 1.0 / 60.0))
        #expect(director.badge(agent).badge == .magnifier)

        // Exactly `D`: gone.
        _ = director.apply([], at: closedAt.addingTimeInterval(SceneDirector.closingBeatDuration))
        #expect(director.badge(agent).badge == nil)
        #expect(director.closingBeat(agent) == nil)
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
    ///
    /// **The bound is measured on what is drawn, and ADR-003 is why.** It used
    /// to compare whole `BadgeSelection` values, which was the same thing when
    /// every field of one was visible. It is not any more: the close that
    /// empties an agent's set moves `count` from 1 to 0 while the glyph stays
    /// put, and the `×N` is drawn only above one, so that transition is a change
    /// in the value and no change at all in the picture. Counting it would
    /// report a flicker nobody can see and would fail a test named for one.
    ///
    /// **This is not the bound being relaxed to accommodate the beat.**
    /// Everything the old comparison caught it still catches: a `×3` becoming a
    /// `×2` with no call closing is still a visible change and still counted,
    /// and a re-sent identical value is asserted against below on *exact*
    /// equality, unchanged.
    ///
    /// **The beat does add drawn badge changes, and ADR-003 §3 item 2 is wrong
    /// to say it adds none.** Measured on the M7a capture, drawn changes go from
    /// 108 to 128. Every one of the twenty is a *pair* belonging to a call whose
    /// open and close landed inside one 1/60 frame: the badge was suppressed
    /// before it was ever emitted, so that call's previous contribution was
    /// **zero** badge changes rather than two, and the ADR's "the sequence is
    /// what it is today with one transition delayed" holds only for calls that
    /// spanned a frame. All ten were `magnifier`. The bound below is unaffected,
    /// and that is the point: a sub-frame call still changes the open-call set
    /// twice, so two badge changes is inside its allowance. A call that drew
    /// nothing now draws something, which is the ADR working rather than
    /// flicker.
    ///
    /// It also replays in fixture time at 1/60 rather than one batch per step,
    /// because a beat that ends by the clock cannot be measured against a clock
    /// that only moves when an event arrives.
    @Test func noCharacterChangesBadgeMoreOftenThanItsOpenCallSetChanges() async throws {
        for name in ["three-subagents", "parallel-tools", "single-agent-simple",
                     "tool-failure", "killed-session"] {
            var director = Self.director()
            var openCallChanges: [AgentRef: Int] = [:]
            var badgeChanges: [AgentRef: Int] = [:]
            var lastDrawn: [AgentRef: BadgeSelection.Drawn] = [:]
            var lastBadge: [AgentRef: BadgeSelection] = [:]

            let entries = try HookLog.load(contentsOf: SceneFixtures.url(name))
            let origin = try #require(entries.first?.receivedAt)
            let end = try #require(entries.last?.receivedAt)
            let model = WorldModel()
            var index = entries.startIndex
            var time = 0.0
            let step = 1.0 / 60.0

            while time <= end.timeIntervalSince(origin) + 10 {
                var pending: [WorldDelta] = []
                let cutoff = origin.addingTimeInterval(time)
                while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                    if let event = entries[index].event {
                        pending += await model.ingest(event, at: entries[index].receivedAt)
                    }
                    index += 1
                }
                for delta in pending {
                    switch delta {
                    case let .callOpened(agent, _),
                         let .callClosed(agent, _, _, _),
                         let .callAbandoned(agent, _, _, _):
                        openCallChanges[agent, default: 0] += 1
                    default: break
                    }
                }
                // Unguarded: the frames with nothing in them are the frames a
                // beat ends on.
                for intent in director.apply(pending, at: cutoff) {
                    guard case let .setBadge(agent, selection) = intent else { continue }
                    #expect(
                        lastBadge[agent] != selection,
                        "\(name): \(agent) was re-sent the badge it already had")
                    lastBadge[agent] = selection
                    if lastDrawn[agent] != selection.drawn {
                        lastDrawn[agent] = selection.drawn
                        badgeChanges[agent, default: 0] += 1
                    }
                }
                time += step
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

    // MARK: The report beat

    /// **`reportDelivered` drives the beat now, and it is a round trip.**
    ///
    /// `SubagentStop` used to emit `reportDelivered` *and* `agentDeparted`, and
    /// the walk was carried by the departure. A subagent that stops goes dormant
    /// in its seat instead, so nothing follows the report — if this delta did
    /// not produce the choreography, the one dramatisation the project allows
    /// would silently vanish from the room.
    @Test func aReportIsAWalkOnItsOwnAndTakesNobodyOutOfTheRoom() {
        var director = Self.director()
        let agent = Self.ref(.subagent("child"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .agentAppeared(agent: Self.ref(.mainThread), agentType: nil, lifecycle: .active),
        ])
        let intents = director.apply([.reportDelivered(agent: agent)])
        #expect(intents.contains(.deliverReport(agent: agent, anchorSeat: 0)))
        #expect(!intents.contains { if case .exitCharacter = $0 { return true } else { return false } })
        #expect(director.population == 2, "a report is a turn boundary, not a departure")
        #expect(director.seats[agent] != nil, "the reporter kept its seat")
    }

    /// **The bug this change exists to close.** `reported` was set by
    /// `reportDelivered` and cleared by nothing, because the departure that
    /// consumed it always arrived in the same batch. Once `SubagentStop` stopped
    /// departing anyone, a character that had reported at any point in the
    /// session carried the flag to `SessionEnd` and exited by walking back to
    /// the anchor to deliver a report that had happened minutes earlier. [I1]
    @Test func aReportInAnEarlierFrameDoesNotReplayItselfAtDeparture() {
        var director = Self.director()
        let agent = Self.ref(.subagent("child"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning)])
        _ = director.apply([.reportDelivered(agent: agent)])
        // Anything at all in between; the flag must not survive its own batch.
        _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Read"))])
        let intents = director.apply([.agentDeparted(agent: agent)])
        let exits = intents.compactMap { intent -> SpriteIntent.ExitStyle? in
            if case let .exitCharacter(_, style) = intent { return style }
            return nil
        }
        #expect(exits == [.walkOff])
        #expect(!intents.contains { if case .deliverReport = $0 { return true } else { return false } })
    }

    /// One `agent_id` can produce several full turns: two of the four agents in
    /// `fixtures/four-subagents.jsonl` stop, are resumed with `SendMessage`, and
    /// stop again. Each stop is a real hand-over and gets its own beat.
    @Test func aCharacterThatReportsTwiceGetsTheBeatTwice() {
        var director = Self.director()
        let agent = Self.ref(.subagent("child"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning)])
        var beats = 0
        for _ in 0..<2 {
            for intent in director.apply([.reportDelivered(agent: agent)]) {
                if case .deliverReport = intent { beats += 1 }
            }
            _ = director.apply([.callOpened(agent: agent, call: Self.call("a", "Read"))])
            _ = director.apply([
                .callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)])
        }
        #expect(beats == 2)
    }

    /// A `reportDelivered` for a character the scene does not have is not a
    /// reason to invent one. The model already refuses to spawn on an unknown
    /// `SubagentStop` — the TUI's suggestion helper emits those on ordinary
    /// turns — and this is the same refusal one layer down. [I1]
    @Test func aReportForACharacterThatIsNotOnScreenDrawsNothing() {
        var director = Self.director()
        let intents = director.apply([.reportDelivered(agent: Self.ref(.subagent("ghost")))])
        #expect(!intents.contains { if case .deliverReport = $0 { return true } else { return false } })
    }

    /// `reportDelivered` and `agentDeparted` in one batch is no longer what
    /// `SubagentStop` produces, but `SessionEnd` can still land on top of a stop.
    /// The character must leave by the report route, not be yanked off screen —
    /// and must not *also* be sent on a round trip to a seat it no longer has.
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
        #expect(!intents.contains { if case .deliverReport = $0 { return true } else { return false } })
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
                if case let .deliverReport(_, anchorSeat) = intent { anchors.append(anchorSeat) }
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
        guard case let .spawnCharacter(_, variant, nameplate, seat, _, _) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        #expect(seat == 0)
        #expect(variant == Self.cast[0])
        #expect(nameplate == NameplateText(lead: "main"))
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
                case let .spawnCharacter(agent, variant, _, seat, _, _):
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
        guard case let .spawnCharacter(_, _, nameplate, _, _, _) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        // No dispatch has been seen, so the type is what the one line carries.
        #expect(nameplate.role == "security-reviewer")
        #expect(nameplate.headline == "security-reviewer")
        // And nothing is carried that the plate does not draw: the `agent_id`
        // discriminator used to live here.
        #expect(nameplate.lead.isEmpty)

        var mainDirector = Self.director()
        let mainIntents = mainDirector.apply([
            .agentAppeared(agent: Self.ref(.mainThread), agentType: nil, lifecycle: .active)])
        guard case let .spawnCharacter(_, _, mainPlate, _, _, _) = mainIntents[0] else {
            Issue.record("expected a spawn"); return
        }
        // No `agent_id`. That is the identity rule, not a special case.
        // [CLAUDE.md]
        #expect(mainPlate == NameplateText(lead: "main"))
        #expect(mainPlate.role == nil, "the main agent has no type to draw")
    }

    /// **Three subagents of one type, with no dispatch between them, are now one
    /// plate — and this is the regression the one-row instruction bought.**
    ///
    /// M4 watched exactly this happen live and M5 fixed it with an `agent_id`
    /// discriminator on a row of its own. The maintainer has since asked for the
    /// plate to carry the summary of what the agent is doing *and that's it*, so
    /// the row is gone and so is the fix. Recorded as an assertion rather than
    /// left to be rediscovered: three characters, one plate, separable only by
    /// seat.
    ///
    /// It bites only where the room has nothing else to say. A dispatch gives
    /// each of them its own line — `threeSubagentsEndUpWithThreeDifferentHeadlines`
    /// is the same three agents in the real capture — so what is lost is the
    /// untasked case and the case where two tasks shorten alike.
    @Test func sameTypedSubagentsWithNoDispatchNowShareOnePlate() {
        var director = Self.director()
        let ids = ["a894ded5b0c4b18de", "a3b448736697956e7", "a793beae9fa532d0f"]
        var plates: [NameplateText] = []
        for id in ids {
            let intents = director.apply([
                .agentAppeared(agent: Self.ref(.subagent(id)),
                               agentType: "general-purpose", lifecycle: .spawning)])
            for case let .spawnCharacter(_, _, plate, _, _, _) in intents { plates.append(plate) }
        }
        #expect(plates.count == 3)
        #expect(Set(plates).count == 1, "something is still separating them: \(plates)")
        #expect(plates.allSatisfy { $0.role == "general-purpose" })

        // Down to the pixels, because a value that compares equal could still
        // have drawn differently — and it does not.
        let accent = Bitmap.RGBA(255, 136, 77)
        let drawn = plates.map { SceneBitmaps.nameplate($0, accent: accent).pixels }
        #expect(Set(drawn).count == 1)
    }

    /// The plate is decided once, at spawn, and rewritten only when a task
    /// lands. What it says at spawn is the type, because that is all the room
    /// has been told.
    @Test func aSubagentWithNoDispatchYetWearsItsType() {
        var director = Self.director()
        let intents = director.apply([
            .agentAppeared(agent: Self.ref(.subagent("a1c0ffee0badf00d1")),
                           agentType: "Explore", lifecycle: .spawning)])
        guard case let .spawnCharacter(_, _, plate, _, _, _) = intents[0] else {
            Issue.record("expected a spawn"); return
        }
        #expect(plate == NameplateText(lead: "", role: "Explore"))
    }

    /// Whatever the type is, the drawn plate must stay inside the seat pitch or
    /// two neighbours' plates overlap and neither reads.
    ///
    /// Checked as **pixels**, not glyphs: `agent_type` is arbitrary
    /// user-defined text and the plate is what has to fit, so a glyph count is
    /// one indirection away from the thing that matters.
    @Test func noPlateExceedsTheSeatPitch() {
        var director = Self.director()
        let layout = RoomLayout()
        for (index, type) in ["general-purpose", "Explore", "claude-code-guide",
                              "statusline-setup", "a", "",
                              "an-agent-type-nobody-anticipated-at-all"].enumerated() {
            let id = String(format: "a%016x", index + 0x1000)
            let intents = director.apply([
                .agentAppeared(agent: Self.ref(.subagent(id)),
                               agentType: type, lifecycle: .spawning)])
            for case let .spawnCharacter(_, _, plate, _, _, _) in intents {
                let bitmap = SceneBitmaps.nameplate(plate, accent: Bitmap.RGBA(255, 0, 0))
                #expect(bitmap.width <= SceneBitmaps.maximumNameplateWidth,
                        "\(plate) drew \(bitmap.width) px")
                #expect(bitmap.width < layout.seatSpacingTiles * layout.tile)
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

    // MARK: Overflow — the room says what it cannot seat [I1, S5]

    /// `count` agents appearing in one batch: the main thread and `count - 1`
    /// subagents.
    static func arrival(_ count: Int) -> [WorldDelta] {
        (0..<count).map { index in
            .agentAppeared(
                agent: ref(index == 0
                           ? .mainThread
                           : .subagent(String(format: "a%016x", index))),
                agentType: index == 0 ? nil : "general-purpose",
                lifecycle: .active)
        }
    }

    static func spawnedSeats(_ intents: [SpriteIntent]) -> [AgentRef: Int] {
        var seats: [AgentRef: Int] = [:]
        for intent in intents {
            if case let .spawnCharacter(agent, _, _, seat, _, _) = intent { seats[agent] = seat }
        }
        return seats
    }

    static func overflows(_ intents: [SpriteIntent]) -> [Int] {
        intents.compactMap { if case let .setOverflow(n) = $0 { n } else { nil } }
    }

    /// **The defect this exists for.** `RoomLayout.seatColumn` and `ring` both
    /// wrap mod `seatCapacity`, so seat 7 is seat 0's column *and* — the two-row
    /// fold keys on ring parity — seat 0's row. Before this, the eighth agent
    /// was seated on top of the first and the room drew seven characters while
    /// eight were running: a false population [I1] and S5 failing at the first
    /// crowd past the seat count.
    ///
    /// It fails against the old director on the first assertion: eight spawns.
    @Test func theEighthAgentIsCountedRatherThanDrawnOnTopOfTheFirst() {
        var director = Self.director()
        let intents = director.apply(Self.arrival(8))
        let seats = Self.spawnedSeats(intents)

        #expect(seats.count == 7, "the room has seven seats and drew \(seats.count) characters")
        #expect(Set(seats.values).count == seats.count, "two characters share a seat")
        #expect(seats.values.allSatisfy { director.layout.isSeatable($0) })
        #expect(director.population == 8, "all eight agents are still known")
        #expect(director.overflowCount == 1)
        #expect(Self.overflows(intents) == [1], "the room never said what it could not seat")
    }

    /// The count is right at every population the room can be handed, and no
    /// two drawn characters ever land on the same spot — position, not seat
    /// index, because the index is what the wrap made a liar.
    @Test func everyPopulationIsEitherDrawnOrCountedAndNeverBoth() {
        let layout = RoomLayout()
        for population in 1...16 {
            var director = Self.director()
            let intents = director.apply(Self.arrival(population))
            let seats = Self.spawnedSeats(intents)
            let drawn = min(population, layout.seatCapacity)

            #expect(seats.count == drawn, "population \(population)")
            #expect(director.overflowCount == population - drawn, "population \(population)")
            #expect(director.seatedPopulation + director.overflowCount == population)

            var spots: Set<ScenePoint> = []
            for seat in seats.values { spots.insert(layout.seatPosition(seat)) }
            #expect(spots.count == drawn, Comment(rawValue:
                "population \(population): \(drawn) characters on \(spots.count) spots"))
        }
    }

    /// A room that never fills never says anything, so nothing about the
    /// ordinary picture moves. Over every fixture, `setOverflow` is silent.
    @Test func aRoomThatNeverFillsNeverSaysAnything() async throws {
        for name in ["single-agent-simple", "parallel-tools", "three-subagents",
                     "four-subagents", "killed-session"] {
            var director = Self.director()
            var said: [Int] = []
            for batch in try await SceneFixtures.batchedDeltas(name) {
                said += Self.overflows(director.apply(batch))
            }
            #expect(said.isEmpty, "\(name) emitted \(said)")
        }
    }

    /// **A seat that frees goes to whoever has waited longest, and they walk
    /// in.** Without this the overflow would be permanent: seats are released on
    /// departure and reused by *new* arrivals, so an agent that found the room
    /// full would still be undrawn after everyone on screen had left — a room of
    /// empty desks under a plate reading "+3", which is true and useless.
    @Test func aFreedSeatGoesToWhoeverHasWaitedLongest() {
        var director = Self.director()
        let arrivals = Self.arrival(10)
        _ = director.apply(arrivals)
        #expect(director.overflowCount == 3)

        // Whoever is waiting, in the order they arrived.
        let waiting = arrivals.compactMap { delta -> AgentRef? in
            guard case let .agentAppeared(agent, _, _) = delta,
                  !director.isSeated(agent) else { return nil }
            return agent
        }
        #expect(waiting.count == 3)

        // Take a seated subagent out of the room.
        let leaver = try! #require(arrivals.compactMap { delta -> AgentRef? in
            guard case let .agentAppeared(agent, _, _) = delta,
                  director.isSeated(agent), agent.agent != .mainThread else { return nil }
            return agent
        }.max { (director.seats[$0] ?? 0) < (director.seats[$1] ?? 0) })
        let freed = try! #require(director.seats[leaver])

        let intents = director.apply([.agentDeparted(agent: leaver)])
        let spawned = Self.spawnedSeats(intents)

        #expect(spawned == [waiting[0]: freed], "the longest wait did not take the seat")
        #expect(director.isSeated(waiting[0]))
        #expect(director.overflowCount == 2)
        #expect(Self.overflows(intents) == [2])
        #expect(director.population == 9)
    }

    /// An agent that was never drawn is never walked off, and one that was is.
    /// A departing character the scene has no node for would be an exit intent
    /// nothing could carry out.
    @Test func nobodyWalksOutOfASeatTheyNeverHad() {
        var director = Self.director()
        let arrivals = Self.arrival(9)
        _ = director.apply(arrivals)
        let waiting = try! #require(arrivals.compactMap { delta -> AgentRef? in
            guard case let .agentAppeared(agent, _, _) = delta,
                  !director.isSeated(agent) else { return nil }
            return agent
        }.last)

        let intents = director.apply([.agentDeparted(agent: waiting)])
        #expect(!intents.contains { if case .exitCharacter = $0 { true } else { false } })
        #expect(Self.overflows(intents) == [1])
        #expect(director.population == 8)
    }

    /// The promoted character's body and badge are emitted **after** its spawn,
    /// so it walks in doing what it is actually doing rather than idling until
    /// its next event. Nothing is emitted for it while it is waiting, which is
    /// what leaves the suppression memory clear for this.
    @Test func aPromotedCharacterArrivesShowingTheWorkItWasAlreadyDoing() {
        var director = Self.director()
        let arrivals = Self.arrival(8)
        _ = director.apply(arrivals)
        let waiting = try! #require(arrivals.compactMap { delta -> AgentRef? in
            guard case let .agentAppeared(agent, _, _) = delta,
                  !director.isSeated(agent) else { return nil }
            return agent
        }.first)
        let leaver = try! #require(arrivals.compactMap { delta -> AgentRef? in
            guard case let .agentAppeared(agent, _, _) = delta,
                  director.isSeated(agent), agent.agent != .mainThread else { return nil }
            return agent
        }.first)

        // It opens a call while it has no seat: nothing at all is said about it.
        let silent = director.apply([.callOpened(agent: waiting, call: Self.call("t", "Bash"))])
        #expect(!silent.contains {
            switch $0 {
            case let .setBody(agent, _, _), let .setBadge(agent, _): agent == waiting
            default: false
            }
        })

        let intents = director.apply([.agentDeparted(agent: leaver)])
        let spawnIndex = try! #require(intents.firstIndex {
            if case let .spawnCharacter(agent, _, _, _, _, _) = $0 { agent == waiting } else { false }
        })
        let bodyIndex = try! #require(intents.firstIndex {
            if case let .setBody(agent, state, _) = $0 { agent == waiting && state == .working }
            else { false }
        })
        let badgeIndex = try! #require(intents.firstIndex {
            if case let .setBadge(agent, selection) = $0 {
                agent == waiting && selection.badge == .terminal
            } else { false }
        })
        #expect(spawnIndex < bodyIndex)
        #expect(spawnIndex < badgeIndex)
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

    // MARK: The task reaches the plate — M7e

    static func plates(_ intents: [SpriteIntent]) -> [(AgentRef, NameplateText)] {
        intents.compactMap {
            switch $0 {
            case let .spawnCharacter(agent, _, plate, _, _, _): return (agent, plate)
            case let .setNameplate(agent, plate): return (agent, plate)
            default: return nil
            }
        }
    }

    /// **A task arriving behind a character already on screen redraws its plate
    /// and nothing else.** No second spawn, no exit and re-entry: the intent
    /// that carries it is `setNameplate`, and the character it names is the one
    /// that is already seated.
    @Test func aTaskLandingAfterTheSpawnRedrawsThePlateWithoutRebuildingAnyone() {
        var director = Self.director()
        let child = Self.ref(.subagent("a793beae9fa532d0f"))
        _ = director.apply([
            .agentAppeared(agent: child, agentType: "Explore", lifecycle: .active)])

        let intents = director.apply([
            .agentTasked(agent: child, task: "Read alpha.txt and sleep")])
        #expect(intents.count == 1, "\(intents)")
        guard case let .setNameplate(agent, plate) = intents[0] else {
            Issue.record("the task did not produce a setNameplate: \(intents)")
            return
        }
        #expect(agent == child)
        #expect(plate.headline == "READ ALPH…")
        // The type is still carried — it is the rung under the task, and it is
        // what this character wore a moment ago — but it is no longer drawn.
        #expect(plate.role == "Explore")
    }

    /// A character that appears and is tasked in one batch is spawned once, with
    /// the task already on it. The plate the scene builds is the plate the
    /// character should have, so there is nothing to restate.
    @Test func anAgentTaskedInItsOwnBatchIsSpawnedWithTheTaskAndNotToldTwice() {
        var director = Self.director()
        let child = Self.ref(.subagent("ab69ae01f1e4353c6"))
        let intents = director.apply([
            .agentAppeared(agent: child, agentType: "general-purpose", lifecycle: .active),
            .agentTasked(agent: child, task: "Read one.txt sleep"),
        ])
        let plates = Self.plates(intents)
        #expect(plates.count == 1, "the plate was stated twice: \(intents)")
        #expect(plates.first?.1.headline == "READ ONE…")
        #expect(!intents.contains { if case .setNameplate = $0 { true } else { false } })
    }

    /// **Nothing restates a plate that did not change.** The suppression memory
    /// is what keeps `setNameplate` off the ordinary frame: a task is emitted at
    /// most once per agent, so after it lands the plate is fixed for the rest of
    /// that character's life however busy the room gets.
    @Test func noFixtureEverRestatesAPlateItAlreadyDrew() async throws {
        for name in ["three-subagents", "four-subagents", "concurrent-permission-gates",
                     "subagent-permission", "parallel-tools", "killed-session"] {
            var director = Self.director()
            var seen: [AgentRef: [NameplateText]] = [:]
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for (agent, plate) in Self.plates(director.apply(batch)) {
                    seen[agent, default: []].append(plate)
                }
            }
            for (agent, plates) in seen {
                #expect(plates.count == Set(plates).count,
                        "\(name): \(agent) had a plate restated with a value it already had")
                #expect(plates.count <= 2,
                        "\(name): \(agent) changed plate \(plates.count) times")
            }
        }
    }

    /// **The main agent has no task and cannot be given one.** Its absence of an
    /// `agent_id` is what makes it the main agent, and `nameplate(for:)` returns
    /// before it can reach a task. Asserted against a delta that should never
    /// exist, because "the model will not emit it" is not the same guarantee as
    /// "the plate could not draw it". [I1]
    @Test func theMainAgentShowsNoTaskEvenIfOneIsHandedToIt() {
        var director = Self.director()
        let main = Self.ref(.mainThread)
        let spawn = director.apply([
            .agentAppeared(agent: main, agentType: nil, lifecycle: .active)])
        #expect(Self.plates(spawn).first?.1.headline == "main")

        let after = director.apply([.agentTasked(agent: main, task: "Rework the report beat")])
        #expect(!after.contains { if case .setNameplate = $0 { true } else { false } },
                "the main agent's plate changed: \(after)")
    }

    /// **The real capture, end to end: three subagents, three headlines.** This
    /// is what the feature is for — before it, every plate in this room read
    /// `EXPLORE` or `GENERAL-P…` and the seat was the only thing that told them
    /// apart. The main agent is in the same room with no task, which is the
    /// other half of the picture.
    @Test func threeSubagentsEndUpWithThreeDifferentHeadlines() async throws {
        var director = Self.director()
        var latest: [AgentRef: NameplateText] = [:]
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for (agent, plate) in Self.plates(director.apply(batch)) { latest[agent] = plate }
        }
        let subagents = latest.filter { if case .subagent = $0.key.agent { true } else { false } }
        #expect(subagents.count == 3)
        #expect(Set(subagents.values.map(\.headline))
                == ["READ ALPH…", "READ BETA…", "READ DELT…"])

        let main = latest.first { if case .mainThread = $0.key.agent { true } else { false } }
        #expect(main?.value.headline == "main")
        #expect(main?.value.role == nil, "the main agent grew a type")
    }

    /// **Two dispatches whose first two words agree now produce two identical
    /// plates.** `concurrent-permission-gates` sends `Touch file s1` and
    /// `Touch file s2`; ten glyphs cannot hold the third word, so both read
    /// `TOUCH FIL…`, and with the discriminator row gone there is nothing under
    /// them to say which is which.
    ///
    /// **This is a regression in S4 and it is the price of the one-row plate.**
    /// It is pinned rather than fixed so that it stays a known property: if this
    /// test starts failing, either the shortening changed or something was put
    /// back on the plate, and both are decisions somebody has to make on
    /// purpose. Asserted down to the pixels, because the plate is what the user
    /// sees.
    ///
    /// A wider line does not rescue it — `TOUCH FILE S1` needs thirteen glyphs
    /// and the seat pitch cannot afford them. See
    /// `SceneBitmaps.nameplateGlyphLimit`.
    @Test func twoNearlyIdenticalDispatchesNowShareAPlateEntirely() async throws {
        var director = Self.director()
        var latest: [AgentRef: NameplateText] = [:]
        for batch in try await SceneFixtures.batchedDeltas("concurrent-permission-gates") {
            for (agent, plate) in Self.plates(director.apply(batch)) { latest[agent] = plate }
        }
        let subagents = latest.filter { if case .subagent = $0.key.agent { true } else { false } }
        #expect(subagents.count == 2)
        #expect(Set(subagents.values.map(\.headline)) == ["TOUCH FIL…"],
                "the collapse this test records has stopped happening: \(subagents.values)")
        #expect(Set(subagents.values).count == 1,
                "the two plates differ again: \(subagents.values)")

        let accent = Bitmap.RGBA(77, 195, 255)
        let drawn = Set(subagents.values.map { SceneBitmaps.nameplate($0, accent: accent).pixels })
        #expect(drawn.count == 1, "the two plates draw differently after all")
    }

    /// **Every plate collision in `fixtures/`, enumerated.**
    ///
    /// The list rather than the one case, because "which pairs of characters are
    /// now indistinguishable" is the question the one-row plate raises and it
    /// should be answerable by running the suite. A fixture appears here when
    /// two agents that are on screen *at the same moment* end up with the same
    /// `NameplateText`; agents that never overlap cannot be confused with each
    /// other and are not counted.
    ///
    /// **Exactly one pair in the whole corpus collides**:
    /// `concurrent-permission-gates`, whose two dispatches `Touch file s1` and
    /// `Touch file s2` shorten alike to `TOUCH FIL…`.
    ///
    /// Everything else separates. The other two multi-agent fixtures are
    /// `three-subagents` (`READ ALPH…`, `READ BETA…`, `READ DELT…`, `main`) and
    /// `four-subagents` (`READ ONE…`, `READ TWO…`, `READ THRE…`, `READ FOUR…`,
    /// `main`); the remaining thirteen have one character each.
    /// `subagent-permission`'s only subagent also reads `TOUCH FIL…`, from
    /// `Touch a file via bash`, but there is nobody in that room to confuse it
    /// with.
    @Test func everySimultaneousPlateCollisionInTheCorpusIsListed() async throws {
        // Every fixture that produces more than one character.
        let names = ["three-subagents", "four-subagents", "concurrent-permission-gates",
                     "subagent-permission", "parallel-tools", "killed-session",
                     "denial-then-work", "denied-batch-cancel", "interactive-batch-serial",
                     "interactive-session", "parallel-denial", "permission-prompt",
                     "queued-prompt", "single-agent-simple", "tool-failure",
                     "idle-notification", "unknown-events"]
        var collisions: [String: Int] = [:]
        for name in names {
            var director = Self.director()
            var live: [AgentRef: NameplateText] = [:]
            var worst = 0
            for batch in try await SceneFixtures.batchedDeltas(name) {
                let intents = director.apply(batch)
                for (agent, plate) in Self.plates(intents) { live[agent] = plate }
                for case let .exitCharacter(agent, _) in intents { live.removeValue(forKey: agent) }
                // Pairs of *simultaneously visible* characters wearing one plate.
                let plates = Array(live.values)
                var pairs = 0
                for (index, plate) in plates.enumerated() {
                    pairs += plates[plates.index(after: index)...].count { $0 == plate }
                }
                worst = max(worst, pairs)
            }
            if worst > 0 { collisions[name] = worst }
        }
        #expect(collisions == ["concurrent-permission-gates": 1], Comment(rawValue:
            "the corpus's plate collisions moved: \(collisions.sorted { $0.key < $1.key })"))
    }
}
