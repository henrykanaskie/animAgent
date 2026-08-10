import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **A live agent always outranks a finished one for a seat.**
///
/// Seats were freed on `agentDeparted` and on nothing else, and a subagent
/// departs only at `SessionEnd` or the 30-minute session-idle sweep. So the
/// seven seats filled with **dormant** subagents over the life of an ordinary
/// session and stayed that way: a strictly serial ten-subagent run — one worker
/// at a time — drew the main agent plus six characters all wearing the `Z`, the
/// oldest finished three minutes earlier, over a plate reading `+4`, with the
/// only agent doing anything at that instant inside that `+4` and off screen.
///
/// This is the suite for the rule that replaced it: when a live agent has no
/// seat, the longest-dormant character gives one up, walks out, and is carried
/// by the overflow count instead. Lazily — a quiet room keeps showing its
/// sleepers, which is what `03-EVENT-MODEL.md`'s dormancy decision is for and
/// what this deliberately does not overturn.
struct SeatEvictionTests {

    static let cast = ["06", "07", "09", "10", "17", "19"]

    static func director() -> SceneDirector { SceneDirector(variantIDs: cast) }

    static func ref(_ n: Int) -> AgentRef {
        AgentRef(project: "/p", session: "s", agent: .subagent(String(format: "a%016x", n)))
    }

    static let main = AgentRef(project: "/p", session: "s", agent: .mainThread)

    static func call(_ id: String, _ tool: String = "Bash") -> OpenCall {
        let start = Date(timeIntervalSince1970: 0)
        return OpenCall(
            toolUseID: id, toolName: tool, startedAt: start,
            deadline: start.addingTimeInterval(60))
    }

    static func spawned(_ intents: [SpriteIntent]) -> [AgentRef] {
        intents.compactMap {
            if case let .spawnCharacter(agent, _, _, _, _, _) = $0 { agent } else { nil }
        }
    }

    static func walkedOff(_ intents: [SpriteIntent]) -> [AgentRef] {
        intents.compactMap {
            if case let .exitCharacter(agent, .walkOff) = $0 { agent } else { nil }
        }
    }

    /// One worker at a time: it appears, works, stops, and the next one starts.
    /// `t` advances a second per step so "longest dormant" is a real ordering
    /// rather than a tie.
    ///
    /// - Returns: the director after `workers` complete cycles, plus the refs in
    ///   the order they arrived.
    static func serialSession(workers: Int) -> (SceneDirector, [AgentRef]) {
        var director = Self.director()
        var refs: [AgentRef] = []
        var t = Date(timeIntervalSince1970: 1000)
        director.apply([.agentAppeared(agent: Self.main, agentType: nil, lifecycle: .active)], at: t)
        for i in 0..<workers {
            let agent = Self.ref(i)
            refs.append(agent)
            t += 1
            director.apply([
                .agentAppeared(agent: agent, agentType: "worker", lifecycle: .spawning),
                .callOpened(agent: agent, call: Self.call("u\(i)")),
            ], at: t)
            t += 1
            director.apply([
                .callAbandoned(agent: agent, toolUseID: "u\(i)", toolName: "Bash", reason: .agentStopped),
                .reportDelivered(agent: agent),
                .dormancyChanged(agent: agent, isDormant: true),
            ], at: t)
        }
        return (director, refs)
    }

    // MARK: The defect

    /// **The defect, in the shape it was found in.** Ten workers, strictly
    /// serial, nobody departing. Against the old director every one of the seven
    /// seats held a dormant character by the fourth worker and the live one was
    /// never drawn again.
    @Test func aWorkingAgentIsAlwaysOnScreenHoweverManyHaveFinished() {
        for workers in 1...12 {
            var (director, refs) = Self.serialSession(workers: workers)
            let live = Self.ref(workers)
            let t = Date(timeIntervalSince1970: 9000)
            director.apply([
                .agentAppeared(agent: live, agentType: "worker", lifecycle: .spawning),
                .callOpened(agent: live, call: Self.call("live")),
            ], at: t)

            #expect(director.isSeated(live), "\(workers) finished workers hid the live one")
            #expect(director.bodyState(live) == .working)
            #expect(director.isSeated(Self.main), "the anchor was evicted")
            // Nobody was lost to make room: the room's own arithmetic still
            // accounts for every agent it knows about.
            #expect(director.population == workers + 2)
            #expect(director.seatedPopulation + director.overflowCount == director.population)
            _ = refs
        }
    }

    /// The eviction takes the character that has been asleep longest, not the
    /// nearest seat or the newest sleeper.
    @Test func theLongestDormantCharacterIsTheOneThatGivesUpItsSeat() {
        var (director, refs) = Self.serialSession(workers: 6)
        // Six sleepers plus the main agent fill all seven seats.
        #expect(director.overflowCount == 0)
        #expect(refs.allSatisfy { director.isSeated($0) })

        let live = Self.ref(99)
        let intents = director.apply([
            .agentAppeared(agent: live, agentType: "worker", lifecycle: .spawning),
            .callOpened(agent: live, call: Self.call("live")),
        ], at: Date(timeIntervalSince1970: 9000))

        #expect(Self.walkedOff(intents) == [refs[0]], "the wrong sleeper left")
        #expect(Self.spawned(intents) == [live])
        #expect(!director.isSeated(refs[0]))
        #expect(director.isSeated(live))
        // One out, one in: the plate says exactly what it did not seat.
        #expect(director.overflowCount == 1)
    }

    /// **The evicted agent is still in the room's population and still counted.**
    /// Eviction is a seating decision, not a death: nothing about it says the
    /// agent ended, and `agentDeparted` — which does say that — has not arrived.
    /// [I1]
    @Test func anEvictedAgentIsCountedRatherThanForgotten() {
        var (director, refs) = Self.serialSession(workers: 6)
        let before = director.population

        var live: [AgentRef] = []
        for i in 0..<3 {
            let agent = Self.ref(50 + i)
            live.append(agent)
            director.apply([
                .agentAppeared(agent: agent, agentType: "worker", lifecycle: .spawning),
                .callOpened(agent: agent, call: Self.call("live\(i)")),
            ], at: Date(timeIntervalSince1970: 9000 + Double(i)))
        }

        #expect(director.population == before + 3)
        #expect(director.seatedPopulation == director.layout.seatCapacity)
        #expect(director.overflowCount == 3)
        #expect(live.allSatisfy { director.isSeated($0) })
        // The three oldest sleepers are the three that gave way.
        #expect(refs.prefix(3).allSatisfy { !director.isSeated($0) })
        #expect(refs.suffix(3).allSatisfy { director.isSeated($0) })
    }

    /// **Lazy, not eager.** Nothing needs the seats, so nothing is evicted: a
    /// room whose subagents have all finished keeps showing them rather than
    /// emptying itself the moment the last one stopped. This is the half of the
    /// dormancy decision that survives intact.
    @Test func aQuietRoomKeepsShowingItsSleepers() {
        var (director, refs) = Self.serialSession(workers: 6)
        // Time passes with nothing happening.
        for step in 0..<10 {
            let intents = director.apply([], at: Date(timeIntervalSince1970: 2000 + Double(step) * 600))
            #expect(intents.isEmpty, "an empty frame moved somebody")
        }
        #expect(refs.allSatisfy { director.isSeated($0) })
        #expect(director.overflowCount == 0)
    }

    /// An agent with nothing running is not a dormant one. Only
    /// `dormancyChanged` says a subagent finished its turn, and only a finished
    /// turn gives a seat up. [I1/I2]
    ///
    /// Since ADR-005 the distinction is visible on the body as well as in the
    /// seating: an agent between two calls of one turn is *seated and still*,
    /// and only a real turn boundary stands it up. The assertion below reads
    /// `working` where it used to read `idle` for that reason — these six
    /// characters have started and not stopped.
    @Test func onlyDormancyGivesUpASeatAndMerelyHavingNothingOpenDoesNot() {
        var director = Self.director()
        var refs: [AgentRef] = []
        var deltas: [WorldDelta] = [
            .agentAppeared(agent: Self.main, agentType: nil, lifecycle: .active)]
        for i in 0..<6 {
            let agent = Self.ref(i)
            refs.append(agent)
            deltas.append(.agentAppeared(agent: agent, agentType: "worker", lifecycle: .spawning))
        }
        director.apply(deltas, at: Date(timeIntervalSince1970: 1000))
        #expect(refs.allSatisfy { director.bodyState($0) == .working })
        #expect(refs.allSatisfy { director.openCallCount($0) == 0 })

        let live = Self.ref(99)
        let intents = director.apply([
            .agentAppeared(agent: live, agentType: "worker", lifecycle: .spawning),
            .callOpened(agent: live, call: Self.call("live")),
        ], at: Date(timeIntervalSince1970: 2000))

        #expect(Self.walkedOff(intents).isEmpty, "an idle character was evicted")
        #expect(!director.isSeated(live))
        #expect(director.overflowCount == 1)
    }

    /// **The main agent is never evicted.** It holds seat 0, the anchor every
    /// report walks to. It is never dormant either — `Stop` sets no dormancy —
    /// and the guard says so rather than relying on that.
    @Test func theAnchorIsNeverEvictedEvenIfItIsMarkedDormant() {
        var (director, _) = Self.serialSession(workers: 6)
        // Not something the model emits; asserted anyway, because the seat this
        // protects is the one the whole report beat is aimed at.
        director.apply(
            [.dormancyChanged(agent: Self.main, isDormant: true)],
            at: Date(timeIntervalSince1970: 5000))

        for i in 0..<4 {
            let agent = Self.ref(50 + i)
            let intents = director.apply([
                .agentAppeared(agent: agent, agentType: "worker", lifecycle: .spawning),
                .callOpened(agent: agent, call: Self.call("live\(i)")),
            ], at: Date(timeIntervalSince1970: 9000 + Double(i)))
            #expect(!Self.walkedOff(intents).contains(Self.main))
        }
        #expect(director.isSeated(Self.main))
        #expect(director.seats[Self.main] == 0)
    }

    // MARK: Coming back

    /// A revived agent is live, so it outranks the sleepers that took its place.
    /// `SubagentStart` for a known `agent_id` is the revival path and the room
    /// has to be able to bring the character back.
    @Test func anEvictedAgentThatWakesUpTakesASeatBack() {
        var (director, refs) = Self.serialSession(workers: 6)
        let live = Self.ref(99)
        director.apply([
            .agentAppeared(agent: live, agentType: "worker", lifecycle: .spawning),
            .callOpened(agent: live, call: Self.call("live")),
        ], at: Date(timeIntervalSince1970: 9000))
        let evicted = refs[0]
        #expect(!director.isSeated(evicted))

        let intents = director.apply(
            [.dormancyChanged(agent: evicted, isDormant: false)],
            at: Date(timeIntervalSince1970: 9100))

        #expect(Self.spawned(intents) == [evicted], "the revived agent never came back")
        #expect(director.isSeated(evicted))
        #expect(director.isSeated(live), "the live agent gave way to a revival")
        #expect(Self.walkedOff(intents) == [refs[1]], "the next-longest sleeper did not give way")
        #expect(director.overflowCount == 1)
    }

    /// A character that comes back is stated afresh rather than suppressed as
    /// unchanged — the suppression memory goes out of the room with the seat.
    /// The same property `aPromotedCharacterArrivesShowingTheWorkItWasAlreadyDoing`
    /// asserts for a promotion, for the case that reaches it by eviction.
    @Test func aReseatedCharacterArrivesShowingWhatItIsActuallyDoing() throws {
        var (director, refs) = Self.serialSession(workers: 6)
        let live = Self.ref(99)
        director.apply([
            .agentAppeared(agent: live, agentType: "worker", lifecycle: .spawning),
            .callOpened(agent: live, call: Self.call("live")),
        ], at: Date(timeIntervalSince1970: 9000))
        let evicted = refs[0]

        // It wakes and opens a call in one batch, so it comes back working.
        let intents = director.apply([
            .dormancyChanged(agent: evicted, isDormant: false),
            .callOpened(agent: evicted, call: Self.call("again", "Read")),
        ], at: Date(timeIntervalSince1970: 9100))

        let spawn = try #require(intents.firstIndex {
            if case let .spawnCharacter(a, _, _, _, _, _) = $0 { a == evicted } else { false }
        })
        let body = try #require(intents.firstIndex {
            if case let .setBody(a, state, _) = $0 { a == evicted && state == .working } else { false }
        })
        let badge = try #require(intents.firstIndex {
            if case let .setBadge(a, selection) = $0 {
                a == evicted && selection.badge == .magnifier
            } else { false }
        })
        #expect(spawn < body)
        #expect(spawn < badge)
    }

    // MARK: Stability

    /// **Settling is a fixed point.** Empty frames must not shuffle the room:
    /// pass 1 leaves no free seat and pass 2 puts a live agent in every seat it
    /// takes, so nothing the seating pass does creates work for its own next
    /// run. A later swap needs a new real event.
    @Test func settlingTwiceChangesNothing() {
        var (director, _) = Self.serialSession(workers: 10)
        for i in 0..<4 {
            director.apply([
                .agentAppeared(agent: Self.ref(50 + i), agentType: "worker", lifecycle: .spawning),
                .callOpened(agent: Self.ref(50 + i), call: Self.call("live\(i)")),
            ], at: Date(timeIntervalSince1970: 9000 + Double(i)))
        }
        let settled = director.seats
        for step in 0..<20 {
            let intents = director.apply([], at: Date(timeIntervalSince1970: 9500 + Double(step)))
            #expect(intents.isEmpty, "frame \(step) moved somebody with no delta to move them")
        }
        #expect(director.seats == settled)
    }

    /// Two characters never share a seat, and everyone the room knows about is
    /// either drawn or counted — over a long run of arrivals, sleeps, revivals
    /// and departures mixed together.
    @Test func theRoomNeverDoubleBooksASeatOrLosesAnAgent() {
        var director = Self.director()
        var t = Date(timeIntervalSince1970: 1000)
        var known: Set<AgentRef> = []
        director.apply([.agentAppeared(agent: Self.main, agentType: nil, lifecycle: .active)], at: t)
        known.insert(Self.main)

        // Deterministic pseudo-random, so a failure is reproducible.
        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }

        for step in 0..<600 {
            t += 1
            let agent = Self.ref(next(20))
            var deltas: [WorldDelta] = []
            switch next(5) {
            case 0:
                deltas.append(.agentAppeared(
                    agent: agent, agentType: "worker", lifecycle: .spawning))
                known.insert(agent)
            case 1 where known.contains(agent):
                deltas.append(.callOpened(agent: agent, call: Self.call("u\(step)")))
                deltas.append(.dormancyChanged(agent: agent, isDormant: false))
            case 2 where known.contains(agent):
                deltas.append(.dormancyChanged(agent: agent, isDormant: true))
            case 3 where known.contains(agent) && agent != Self.main:
                deltas.append(.agentDeparted(agent: agent))
                known.remove(agent)
            default:
                break
            }
            director.apply(deltas, at: t)

            let seats = director.seats
            #expect(Set(seats.keys) == known, "step \(step): the population drifted")
            let drawn = seats.values.filter { director.layout.isSeatable($0) }
            #expect(Set(drawn).count == drawn.count, "step \(step): two characters on one seat")
            #expect(Set(seats.values).count == seats.count, "step \(step): a queue slot was reused")
            #expect(drawn.count == min(known.count, director.layout.seatCapacity),
                    "step \(step): a seat stood empty with somebody waiting")
            #expect(director.seatedPopulation + director.overflowCount == director.population)
            // The rule this suite exists for, checked at every single step.
            let waitingLive = known.filter {
                !director.isSeated($0) && !director.badge($0).isDormant
            }
            let seatedDormant = known.filter {
                director.isSeated($0) && director.badge($0).isDormant && $0 != Self.main
            }
            #expect(waitingLive.isEmpty || seatedDormant.isEmpty,
                    "step \(step): a live agent waited while a sleeper held a seat")
        }
    }

    /// Nothing about a room that never fills changes. Every required fixture
    /// stays byte-identical in its intent stream, dormancy and all.
    @Test func noFixtureIsDisturbed() async throws {
        for name in ["single-agent-simple", "parallel-tools", "three-subagents",
                     "four-subagents", "killed-session", "tool-failure",
                     "permission-prompt", "denial-then-work"] {
            var director = Self.director()
            var evictions = 0
            for batch in try await SceneFixtures.batchedDeltas(name) {
                for intent in director.apply(batch) {
                    if case .exitCharacter = intent { evictions += 1 }
                }
            }
            // Every fixture is well under seven agents, so no seat is ever
            // contested and the only exits are real departures.
            #expect(director.overflowCount == 0, "\(name) overflowed")
            _ = evictions
        }
    }
}
