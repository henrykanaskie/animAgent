import Foundation
import Testing

@testable import SpriteRoomCore

/// Replay of all six fixtures. These are the M1 exit criteria expressed as
/// assertions; a red one here is information, not something to soften.
@Suite struct WorldModelReplayTests {

    // MARK: single-agent-simple — the baseline a regression breaks first

    @Test func singleAgentSimpleProducesTheExpectedDeltaSequence() async throws {
        let (model, deltas, _) = try await Fixtures.replay("single-agent-simple")

        #expect(deltas.map(\.tag) == [
            "agentAppeared",      // lazily, on the first consumed event
            "callOpened",         // Read alpha.txt
            "populationChanged",
            "callClosed",
            "callOpened",         // Read beta.txt
            "callClosed",
            "callOpened",         // Bash echo done
            "callClosed",
            "agentDeparted",      // SessionEnd
            "populationChanged",
        ])

        // Every close is a PostToolUse; the three PostToolBatches re-report
        // ids already closed and must add nothing.
        let closes = deltas.compactMap { delta -> CallOutcome? in
            if case let .callClosed(_, _, _, outcome) = delta { return outcome }
            return nil
        }
        #expect(closes == [.succeeded, .succeeded, .succeeded])

        let snapshot = await model.snapshot()
        #expect(snapshot.agents.isEmpty)
        #expect(snapshot.totalOpenCalls == 0)
        #expect(await model.abandonedTotal == 0)
    }

    /// `SessionStart` never fires. A model that waits for it starts empty and
    /// stays empty forever.
    @Test func sessionAndMainAgentAreCreatedWithoutASessionStart() async throws {
        let entries = try Fixtures.entries("single-agent-simple")
        #expect(!entries.contains { $0.event?.kind.name == "SessionStart" })

        let model = WorldModel()
        // Feed only the very first consumed event.
        let first = try #require(entries.first { $0.event?.kind.isUnhandled == false })
        let deltas = await model.ingest(try #require(first.event), at: first.receivedAt)
        #expect(deltas.contains { delta in
            if case let .agentAppeared(agent, _, _) = delta { return agent.agent == .mainThread }
            return false
        })
    }

    // MARK: parallel-tools — I3

    /// Five concurrent `tool_use_id`s on one agent, closing in a different
    /// order from the one they opened in. Any model holding a single current
    /// tool per agent gets this wrong.
    @Test func parallelToolsHoldsFiveConcurrentCallsOnOneAgent() async throws {
        let entries = try Fixtures.entries("parallel-tools")
        let model = WorldModel()

        var peakPerAgent = 0
        var sawMoreThanOne = false
        for entry in entries {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            for agent in await model.snapshot().agents {
                peakPerAgent = max(peakPerAgent, agent.openCalls.count)
                if agent.openCalls.count > 1 { sawMoreThanOne = true }
                // The set never collapses to one representative call.
                #expect(Set(agent.openCalls.map(\.toolUseID)).count == agent.openCalls.count)
            }
        }

        #expect(peakPerAgent == 5, "expected a set of five open calls, saw \(peakPerAgent)")
        #expect(sawMoreThanOne, "the agent never held more than one open call")
        #expect(await model.snapshot().totalOpenCalls == 0)
    }

    @Test func parallelToolsClosesOutOfOrderByToolUseIDAlone() async throws {
        let (_, deltas, _) = try await Fixtures.replay("parallel-tools")
        let opened = deltas.compactMap { delta -> ToolUseID? in
            if case let .callOpened(_, call) = delta { return call.toolUseID }
            return nil
        }
        let closed = deltas.compactMap { delta -> ToolUseID? in
            if case let .callClosed(_, id, _, _) = delta { return id }
            return nil
        }
        #expect(opened.count == 5)
        #expect(Set(opened) == Set(closed))
        #expect(opened != closed, "the fixture's whole point is that the orders differ")
    }

    // MARK: three-subagents — identity and the async spawn

    @Test func threeSubagentsAreThreeCharactersKeyedByAgentID() async throws {
        let (model, deltas, _) = try await Fixtures.replay("three-subagents")

        let appeared = deltas.compactMap { delta -> AgentRef? in
            if case let .agentAppeared(agent, _, _) = delta { return agent }
            return nil
        }
        let subagents = appeared.filter { $0.agent != .mainThread }
        #expect(subagents.count == 3)
        #expect(Set(subagents.map(\.agent)).count == 3)

        let reports = deltas.compactMap { delta -> AgentRef? in
            if case let .reportDelivered(agent) = delta { return agent }
            return nil
        }
        #expect(Set(reports.map(\.agent)) == Set(subagents.map(\.agent)))

        #expect(await model.snapshot().agents.isEmpty)
        #expect(await model.abandonedTotal == 0)
    }

    /// The `Agent` call's own Pre/Post pair closes in ~16 ms while the subagent
    /// it launched runs for seconds. Never time a subagent off its spawning
    /// call.
    @Test func agentToolCallClosesLongBeforeItsSubagentStops() async throws {
        let entries = try Fixtures.entries("three-subagents")
        var openedAt: [ToolUseID: Date] = [:]
        var agentCallDurations: [TimeInterval] = []
        for entry in entries {
            switch entry.event?.kind {
            case let .preToolUse(id, tool) where tool == "Agent":
                openedAt[id] = entry.receivedAt
            case let .postToolUse(id, _):
                if let start = openedAt[id] {
                    agentCallDurations.append(entry.receivedAt.timeIntervalSince(start))
                }
            default:
                break
            }
        }
        #expect(agentCallDurations.count == 3)
        #expect(agentCallDurations.allSatisfy { $0 < 0.1 })

        var starts: [AgentID: Date] = [:]
        var lifetimes: [TimeInterval] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            switch event.kind {
            case .subagentStart: starts[event.agentID] = entry.receivedAt
            case .subagentStop:
                if let start = starts[event.agentID] {
                    lifetimes.append(entry.receivedAt.timeIntervalSince(start))
                }
            default: break
            }
        }
        #expect(lifetimes.count == 3)
        #expect(lifetimes.allSatisfy { $0 > 10 })
    }

    /// `Stop` fires four times in this one turn. It is not end-of-session and
    /// it emits nothing.
    @Test func stopFiresRepeatedlyAndChangesNothing() async throws {
        let entries = try Fixtures.entries("three-subagents")
        let stops = entries.filter { $0.event?.kind.name == "Stop" }
        #expect(stops.count == 4)

        let model = WorldModel()
        for entry in entries.prefix(while: { $0.event?.kind.name != "SessionEnd" }) {
            guard let event = entry.event else { continue }
            if case .stop = event.kind {
                let before = await model.snapshot()
                let deltas = await model.ingest(event, at: entry.receivedAt)
                #expect(deltas.isEmpty)
                #expect(await model.snapshot() == before)
            } else {
                await model.ingest(event, at: entry.receivedAt)
            }
        }
    }

    // MARK: tool-failure — the two non-PostToolUse close paths

    /// Must reach zero open calls *without* the reaper. If the sweep is needed,
    /// a close path is wrong.
    @Test func toolFailureClosesEverythingWithoutTheReaper() async throws {
        let (model, deltas, _) = try await Fixtures.replay("tool-failure")

        let outcomes = deltas.compactMap { delta -> CallOutcome? in
            if case let .callClosed(_, _, _, outcome) = delta { return outcome }
            return nil
        }
        // One close by PostToolUseFailure, one by PostToolBatch alone — the
        // permission-denied call, whose only close that is.
        #expect(outcomes == [.failed, .reconciled])
        #expect(await model.snapshot().totalOpenCalls == 0)
        #expect(await model.abandonedTotal == 0, "the reaper should not have been needed")
    }

    /// `PostToolBatch` re-reports the `Read` that `PostToolUseFailure` already
    /// closed. A second `.callClosed` would drive the scene's open-call count
    /// negative and surface later as a character stuck idle while working.
    @Test func closingIsIdempotentAndEmitsNoSecondCallClosed() async throws {
        let (_, deltas, entries) = try await Fixtures.replay("tool-failure")

        let reReported = entries.contains { entry in
            guard case let .postToolBatch(calls) = entry.event?.kind else { return false }
            return calls.contains { $0.toolUseID == "toolu_01892AQi7xemjcTio4zTtdku" }
        }
        #expect(reReported, "the fixture no longer re-reports an already-closed id")

        let closedIDs = deltas.compactMap(\.toolUseID)
        let closes = deltas.filter { $0.tag == "callClosed" || $0.tag == "callAbandoned" }
        #expect(closes.count == Set(closes.compactMap(\.toolUseID)).count,
                "an id was closed twice: \(closedIDs)")
    }

    /// Present across every fixture, not just the one that named it.
    @Test func noToolUseIDIsEverClosedTwice() async throws {
        for name in Fixtures.required {
            let (_, deltas, _) = try await Fixtures.replay(name)
            var seen: Set<ToolUseID> = []
            for delta in deltas where delta.tag == "callClosed" || delta.tag == "callAbandoned" {
                let id = try #require(delta.toolUseID)
                #expect(seen.insert(id).inserted, "\(name): \(id) closed twice")
            }
        }
    }

    /// Nothing closes that was never opened, either.
    @Test func everyCloseMatchesAnOpen() async throws {
        for name in Fixtures.required {
            let (_, deltas, _) = try await Fixtures.replay(name)
            var open: Set<ToolUseID> = []
            for delta in deltas {
                switch delta {
                case let .callOpened(_, call):
                    #expect(open.insert(call.toolUseID).inserted)
                case let .callClosed(_, id, _, _), let .callAbandoned(_, id, _, _):
                    #expect(open.remove(id) != nil, "\(name): closed \(id) that was never open")
                default:
                    break
                }
            }
        }
    }

    // MARK: unknown-events

    /// Counted, never dropped, and they change nothing. The seven synthetic
    /// lines arrive after this session's `SessionEnd`; not one of them may
    /// resurrect it, spawn a character from its `agent_id`, or move tool state.
    @Test func unknownEventsAreCountedAndChangeNothing() async throws {
        let entries = try Fixtures.entries("unknown-events")
        let model = WorldModel()

        for entry in entries where !entry.synthetic {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }
        let before = await model.snapshot()
        let unhandledBefore = await model.unhandledTotal

        for entry in entries where entry.synthetic {
            guard let event = entry.event else { continue }
            let deltas = await model.ingest(event, at: entry.receivedAt)
            #expect(deltas.isEmpty, "\(event.kind.name) produced \(deltas)")
        }

        #expect(await model.snapshot() == before)
        #expect(await model.unhandledTotal == unhandledBefore + 6)
    }

    @Test func unhandledCountsAreKeyedByEventName() async throws {
        let (model, _, _) = try await Fixtures.replay("unknown-events")
        let counts = await model.unhandledCounts
        #expect(counts["UserPromptSubmit"] == 1)
        #expect(counts["SomeFutureEvent"] == 1)
        #expect(counts["ToolProgress"] == 1)
        #expect(counts["SubagentHeartbeat"] == 1)
        #expect(counts["UserPromptExpansion"] == 1)
        #expect(counts["12345"] == 1)
        #expect(counts[HookEvent.missingEventName] == 1)
    }

    // MARK: expected delta sequences — the M1 exit criterion, spelled out

    /// The exact, ordered delta stream each fixture produces. Written down
    /// rather than derived, so a change in behaviour has to be argued for
    /// instead of absorbed.
    static let expectedSequences: [String: [String]] = [
        "single-agent-simple": [
            "agentAppeared", "callOpened", "populationChanged", "callClosed",
            "callOpened", "callClosed",
            "callOpened", "callClosed",
            "agentDeparted", "populationChanged",
        ],
        // Five opens before the first close. That shape is I3.
        "parallel-tools": [
            "agentAppeared", "callOpened", "populationChanged",
            "callOpened", "callOpened", "callOpened", "callOpened",
            "callClosed", "callClosed", "callClosed", "callClosed", "callClosed",
            "agentDeparted", "populationChanged",
        ],
        // Three `Agent` dispatches, each opening and closing in milliseconds
        // around a `SubagentStart` — the subagents outlive them by seconds.
        "three-subagents": [
            "agentAppeared", "callOpened", "populationChanged",
            "agentAppeared", "populationChanged", "callClosed",
            "callOpened", "agentAppeared", "populationChanged", "callClosed",
            "callOpened", "agentAppeared", "populationChanged", "callClosed",
            "callOpened", "callClosed", "callOpened",
            "callOpened", "callClosed", "callOpened", "callClosed",
            "callClosed", "callOpened", "callOpened", "callClosed",
            "callOpened", "callClosed", "callOpened",
            "reportDelivered", "agentDeparted", "populationChanged",
            "callClosed", "reportDelivered", "agentDeparted", "populationChanged",
            "callClosed", "callOpened", "callClosed",
            "reportDelivered", "agentDeparted", "populationChanged",
            "agentDeparted", "populationChanged",
        ],
        // Ends on an open `Bash` the stream will never close. No SessionEnd.
        "killed-session": [
            "agentAppeared", "callOpened", "populationChanged", "callClosed",
            "callOpened", "callClosed",
            "callOpened",
        ],
        // One close by `PostToolUseFailure`, one by `PostToolBatch` alone.
        "tool-failure": [
            "agentAppeared", "callOpened", "populationChanged", "callClosed",
            "callOpened", "callClosed",
            "agentDeparted", "populationChanged",
        ],
        // The seven synthetic unknowns after `SessionEnd` add nothing.
        "unknown-events": [
            "agentAppeared", "callOpened", "populationChanged", "callClosed",
            "agentDeparted", "populationChanged",
        ],
    ]

    @Test(arguments: Fixtures.required)
    func fixtureProducesItsExpectedDeltaSequence(name: String) async throws {
        let expected = try #require(Self.expectedSequences[name])
        let (_, deltas, _) = try await Fixtures.replay(name)
        #expect(deltas.map(\.tag) == expected, """
            \(name) delta sequence changed
            expected: \(expected)
            actual:   \(deltas.map(\.tag))
            """)
    }

    /// `killed-session` is the one fixture whose sweep does work, and it must
    /// do exactly one thing.
    @Test func killedSessionSweepAbandonsExactlyOneCall() async throws {
        let reaper = Reaper(sessionIdleTimeout: 24 * 60 * 60)
        let (model, _, entries) = try await Fixtures.replay("killed-session", reaper: reaper)
        let last = try #require(entries.last?.receivedAt)
        let swept = await model.sweep(
            at: last.addingTimeInterval(Reaper.longestDeadlineInterval + 1))
        #expect(swept.map(\.tag) == ["callAbandoned"])
    }

    // MARK: every fixture

    /// `killed-session` is the only fixture whose stream leaves an orphan. Any
    /// other one that does has a broken close path.
    @Test func onlyKilledSessionLeavesAnOrphanAtEndOfStream() async throws {
        for name in Fixtures.required {
            let (model, _, _) = try await Fixtures.replay(name)
            let open = await model.snapshot().totalOpenCalls
            if name == "killed-session" {
                #expect(open == 1, "killed-session should orphan exactly one call")
            } else {
                #expect(open == 0, "\(name) orphaned \(open) call(s)")
            }
        }
    }

    /// Every event routes to the sandbox `cwd` it was captured in.
    @Test func everyEventRoutesByCWD() async throws {
        for name in Fixtures.required {
            let entries = try Fixtures.entries(name)
            let projects = Set(entries.compactMap { $0.event?.cwd })
            #expect(projects.count == 1, "\(name) spans \(projects.count) projects")
        }
    }
}
