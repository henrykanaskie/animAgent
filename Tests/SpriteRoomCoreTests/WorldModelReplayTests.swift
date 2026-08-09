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
            "agentAppeared",      // lazily, on `UserPromptSubmit`
            "populationChanged",
            "callOpened",         // Read alpha.txt
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

    // MARK: UserPromptSubmit — the agent that is thinking

    /// A turn that produces no tool call must still draw somebody.
    ///
    /// Before this event was consumed the main character appeared at the
    /// session's first *tool call*, so an agent that was thinking was invisible
    /// — a real hole in a product whose one sentence is "you glance at the
    /// notch and know what your agents are doing." The character it draws is
    /// idle, which is exactly what is happening. [I2]
    @Test func userPromptSubmitAloneCreatesTheSessionAndItsMainCharacter() async throws {
        let entries = try Fixtures.entries("single-agent-simple")
        let first = try #require(entries.first?.event)
        #expect(first.kind == .userPromptSubmit, "the fixture no longer opens on a prompt")

        let model = WorldModel()
        let deltas = await model.ingest(first, at: try #require(entries.first?.receivedAt))

        #expect(deltas.map(\.tag) == ["agentAppeared", "populationChanged"])
        let snapshot = await model.snapshot()
        #expect(snapshot.agents.count == 1)
        #expect(snapshot.agents.first?.ref.agent == .mainThread)
        // Idle, not working. Nothing has been called yet and the room must not
        // pretend otherwise. [I1/I2]
        #expect(snapshot.agents.first?.isWorking == false)
        #expect(await model.unhandledTotal == 0)
    }

    /// Consuming it must not make it a *second* creation path: the later
    /// prompts in one session change nothing at all.
    @Test func laterUserPromptsInTheSameSessionEmitNothing() async throws {
        let entries = try Fixtures.entries("three-subagents")
        let prompts = entries.filter { $0.event?.kind == .userPromptSubmit }
        #expect(prompts.count == 4, "the fixture's four prompts are the point of this test")

        let model = WorldModel()
        var promptsSeen = 0
        for entry in entries {
            guard let event = entry.event else { continue }
            if event.kind == .userPromptSubmit, promptsSeen > 0 {
                let before = await model.snapshot()
                #expect(await model.ingest(event, at: entry.receivedAt).isEmpty)
                #expect(await model.snapshot() == before)
            } else {
                await model.ingest(event, at: entry.receivedAt)
            }
            if event.kind == .userPromptSubmit { promptsSeen += 1 }
        }
        #expect(promptsSeen == 4)
    }

    // MARK: the parent→child link

    /// `tool_response.agentId` on the `Agent` tool's `PostToolUse` is the only
    /// place the link exists — there is no `parent_agent_id` field.
    @Test func agentDispatchCarriesTheChildAgentIDInItsToolResponse() throws {
        let entries = try Fixtures.entries("three-subagents")
        let spawned = entries.compactMap { entry -> String? in
            guard case let .postToolUse(_, tool, spawnedAgentID) = entry.event?.kind,
                  tool == "Agent" else { return nil }
            return spawnedAgentID
        }
        #expect(spawned.count == 3)
        #expect(Set(spawned).count == 3)

        // Nothing else carries one. A `Read`'s `tool_response` is a string, and
        // decoding one key out of it must yield nil rather than throwing.
        let others = entries.compactMap { entry -> String? in
            guard case let .postToolUse(_, tool, spawnedAgentID) = entry.event?.kind,
                  tool != "Agent" else { return nil }
            return spawnedAgentID
        }
        #expect(others.isEmpty)
    }

    /// The link is applied *retroactively*: `SubagentStart` arrives before the
    /// `PostToolUse` that carries it, so the character is already on screen
    /// when we learn who it reports to.
    @Test func theParentLinkIsAppliedAfterTheChildHasAlreadyAppeared() async throws {
        let entries = try Fixtures.entries("three-subagents")
        var appearedAt: [AgentID: Int] = [:]
        var linkedAt: [AgentID: Int] = [:]
        var links: [AgentID: AgentID] = [:]

        let model = WorldModel()
        var index = 0
        for entry in entries {
            guard let event = entry.event else { continue }
            for delta in await model.ingest(event, at: entry.receivedAt) {
                switch delta {
                case let .agentAppeared(agent, _, _):
                    appearedAt[agent.agent] = index
                case let .agentLinked(agent, parent):
                    linkedAt[agent.agent] = index
                    links[agent.agent] = parent
                default: break
                }
                index += 1
            }
        }

        #expect(links.count == 3)
        // All three are children of the main thread in this capture, which is
        // also why the documented fallback and the truth agree here.
        #expect(Set(links.values) == [.mainThread])
        for (child, at) in linkedAt {
            let appeared = try #require(appearedAt[child])
            #expect(appeared < at, "\(child) was linked before it appeared")
        }
    }

    /// Learned once, then never re-announced.
    @Test func theParentLinkIsEmittedExactlyOncePerChild() async throws {
        let (model, deltas, _) = try await Fixtures.replay("three-subagents")
        let linked = deltas.compactMap { delta -> AgentRef? in
            if case let .agentLinked(agent, _) = delta { return agent }
            return nil
        }
        #expect(linked.count == Set(linked).count)
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// A subagent whose link we never saw carries no parent. The fallback is
    /// documented — it anchors to the main agent — and inventing a parent to
    /// fill the hole would be fiction. [I1]
    @Test func aSubagentWithNoObservedLinkHasNoParent() async throws {
        let entries = try Fixtures.entries("three-subagents")
        let withoutLinks = WorldModel()
        let withLinks = WorldModel()
        // Everything up to the last `Agent` dispatch's close — by then all
        // three children exist and all three links have been seen, and none of
        // them has departed yet.
        let cut = try #require(entries.lastIndex { entry in
            guard case let .postToolUse(_, tool, spawned) = entry.event?.kind else { return false }
            return tool == "Agent" && spawned != nil
        })

        for entry in entries.prefix(through: cut) {
            guard let event = entry.event else { continue }
            await withLinks.ingest(event, at: entry.receivedAt)
            // The `Agent` dispatch's close is the only carrier of the link.
            // Drop it and the same stream produces unlinked children.
            if case let .postToolUse(_, tool, spawned) = event.kind,
               tool == "Agent", spawned != nil {
                continue
            }
            await withoutLinks.ingest(event, at: entry.receivedAt)
        }

        let unlinked = await withoutLinks.snapshot().agents.filter { $0.ref.agent != .mainThread }
        let linked = await withLinks.snapshot().agents.filter { $0.ref.agent != .mainThread }
        #expect(unlinked.count == linked.count)
        #expect(!unlinked.isEmpty)
        #expect(unlinked.allSatisfy { $0.parent == nil })
        #expect(linked.allSatisfy { $0.parent == .mainThread })
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
            case let .postToolUse(id, _, _):
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
    ///
    /// **This is also the check that the main agent needs no dormancy of its
    /// own.** `SubagentStop` had to stop departing its character; `Stop` never
    /// departed one. It emits no delta and sets no lifecycle — asserted here as
    /// an unchanged snapshot, which includes the lifecycle field — and the only
    /// caller of `depart` is `endSession`, reached by `SessionEnd` and the idle
    /// sweep. So the main character already stays in the room across a turn
    /// boundary, which is the whole of what dormancy buys a subagent, and
    /// marking it dormant would be the weaker claim besides: four `Stop`s here
    /// are four assistant message streams inside one user turn, not four turns.
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

    // MARK: four-subagents — four of one type, and the resume cycle

    /// **The regression for "only one subagent shows up though there are four".**
    ///
    /// `three-subagents` cannot catch an identity scheme that keys on
    /// `agent_type`: two of its three are `Explore` and one is `general-purpose`,
    /// so a model that merged by type would still draw two characters and look
    /// nearly right. This fixture is four subagents **of one type**, so anything
    /// keyed on the type — or on a truncated id, or on a display string derived
    /// from one — collapses all four into a single character and fails here by
    /// three.
    @Test func fourSameTypedSubagentsAreFourCharacters() async throws {
        let (_, deltas, _) = try await Fixtures.replay("four-subagents")

        let appeared = deltas.compactMap { delta -> (AgentRef, String?)? in
            if case let .agentAppeared(agent, agentType, _) = delta { return (agent, agentType) }
            return nil
        }
        let subagents = appeared.filter { $0.0.agent != .mainThread }
        // Every one of them is the same `agent_type`, which is the whole point:
        // the type cannot be the key, so `agent_id` has to be. [03-EVENT-MODEL,
        // "Identity resolution"]
        #expect(Set(subagents.map(\.1)) == ["general-purpose"])
        #expect(Set(subagents.map(\.0.agent)).count == 4)
        // No two of them share a 3-character suffix either, so this fixture also
        // exercises the case M5c's nameplate discriminator is derived for.
        let suffixes = Set(subagents.map { String("\($0.0.agent)".suffix(3)) })
        #expect(suffixes.count == 4)
    }

    /// All four are in the room **at the same time** — the claim a per-agent
    /// count cannot make on its own, because agents that never overlapped would
    /// satisfy it too.
    @Test func allFourSubagentsAreInTheRoomTogether() async throws {
        let (_, deltas, _) = try await Fixtures.replay("four-subagents")
        var live: Set<AgentRef> = []
        var peak = 0
        for delta in deltas {
            switch delta {
            case let .agentAppeared(agent, _, _): live.insert(agent)
            case let .agentDeparted(agent): live.remove(agent)
            default: break
            }
            peak = max(peak, live.filter { $0.agent != .mainThread }.count)
        }
        #expect(peak == 4)
        #expect(live.isEmpty)
    }

    /// **A subagent's character comes from its own `PreToolUse`, with no
    /// `SubagentStart` anywhere.**
    ///
    /// Creation is lazy on the first *consumed* event, so nothing waits on a
    /// lifecycle event it may never see — the app attaching mid-session misses
    /// every `SubagentStart` that already fired, and `SessionStart` is
    /// unreachable over HTTP for the same family of reasons. This drops the
    /// `SubagentStart`s rather than rewriting them: what is left is the real
    /// capture minus some lines, so no payload is invented.
    @Test func aSubagentGetsItsCharacterFromPreToolUseAlone() async throws {
        let entries = try Fixtures.entries("four-subagents")
        let model = WorldModel()
        // Which event kind was being ingested when each character was created.
        // Recorded per ingest rather than read off the delta stream, because the
        // stream cannot say what caused a delta.
        var bornOn: [AgentRef: String] = [:]
        for entry in entries {
            guard let event = entry.event else { continue }
            if case .subagentStart = event.kind { continue }
            for delta in await model.ingest(event, at: entry.receivedAt) {
                guard case let .agentAppeared(agent, _, _) = delta,
                      agent.agent != .mainThread, bornOn[agent] == nil else { continue }
                bornOn[agent] = event.kind.name
            }
        }

        #expect(bornOn.count == 4)
        #expect(Set(bornOn.values) == ["PreToolUse"])
    }

    /// A background subagent is stopped and **resumed** by its parent. It goes
    /// dormant on `SubagentStop` and is **revived in place** by the second
    /// `SubagentStart` that a `SendMessage` produces — one character, not two.
    ///
    /// This test used to be `aBackgroundSubagentDepartsAndComesBack` and it used
    /// to assert `appearances == 2` for the two resumed agents. That assertion
    /// was a faithful description of behaviour that was wrong: a second
    /// `agentAppeared` is a second character, a second seat and a second
    /// spawn-walk for an agent that never left the room. It is not softened
    /// here, it is inverted — **exactly once each, and four departures, all at
    /// `SessionEnd`.**
    ///
    /// The capture's own numbers are unchanged and still pinned: four distinct
    /// ids, six `SubagentStart`s and twelve `SubagentStop`s. The six extra stops
    /// are the TUI suggestion helper's phantoms, which name agents that never
    /// started and must stay no-ops — six of them here, which is the volume a
    /// model that spawned a character in order to walk it off would have to
    /// survive. [I1]
    @Test func aBackgroundSubagentGoesDormantAndIsRevivedInPlace() async throws {
        let (_, deltas, entries) = try await Fixtures.replay("four-subagents")
        let starts = entries.filter { $0.event?.kind.name == "SubagentStart" }
        let stops = entries.filter { $0.event?.kind.name == "SubagentStop" }
        #expect(starts.count == 6)
        #expect(stops.count == 12)

        var appearances: [AgentRef: Int] = [:]
        var departures: [AgentRef: Int] = [:]
        var reports: [AgentRef: Int] = [:]
        for delta in deltas {
            switch delta {
            case let .agentAppeared(agent, _, _) where agent.agent != .mainThread:
                appearances[agent, default: 0] += 1
            case let .agentDeparted(agent) where agent.agent != .mainThread:
                departures[agent, default: 0] += 1
            case let .reportDelivered(agent):
                reports[agent, default: 0] += 1
            default: break
            }
        }
        // Six starts, four characters. Two of them were revived, and revival
        // emits nothing at all — the character is already in its seat.
        #expect(appearances.count == 4)
        #expect(Set(appearances.values) == [1])
        // The report beat is untouched and still fires per turn, so the two
        // agents that ran twice delivered twice: six reports for the six real
        // stops, and none for the six phantoms.
        #expect(reports.values.reduce(0, +) == 6)
        #expect(reports.values.filter { $0 == 2 }.count == 2)
        // Every departure belongs to an agent we had, and there is exactly one
        // each — `SessionEnd`, the path that means gone. [I4]
        #expect(Set(departures.keys) == Set(appearances.keys))
        #expect(Set(departures.values) == [1])
    }

    /// The revival, event by event, because "one character not two" is the
    /// claim and a count over the whole stream cannot say *where*.
    ///
    /// `ab69ae01f1e4353c6` stops at t=31.850 and is resumed at t=41.165. Across
    /// that second `SubagentStart`: no delta at all, the same `AgentRef`, the
    /// same population, and a lifecycle that goes `dormant` → `active`.
    @Test func aSecondSubagentStartRevivesRatherThanDuplicating() async throws {
        let entries = try Fixtures.entries("four-subagents")
        let resumed = AgentID.subagent("ab69ae01f1e4353c6")
        let model = WorldModel()

        // Up to and including this agent's first `SubagentStop`.
        let stopIndex = try #require(entries.firstIndex {
            $0.event?.kind.name == "SubagentStop" && $0.event?.agentID == resumed
        })
        for entry in entries.prefix(through: stopIndex) {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }

        let ref = try #require(await model.snapshot().agents.first { $0.ref.agent == resumed }).ref
        #expect(await model.snapshot().agent(ref)?.lifecycle == .dormant)
        // Dormant is not a hidden departure: it is still in the room, and it is
        // idle, which is exactly what "finished a turn" looks like. [I2]
        #expect(await model.snapshot().agent(ref)?.isWorking == false)
        let populationBeforeRevival = await model.snapshot().agents.count

        // Everything up to its second `SubagentStart`, then that event alone.
        let startIndex = try #require(entries.indices.dropFirst(stopIndex + 1).first {
            entries[$0].event?.kind.name == "SubagentStart"
                && entries[$0].event?.agentID == resumed
        })
        for entry in entries[(stopIndex + 1)..<startIndex] {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }
        #expect(await model.snapshot().agent(ref)?.lifecycle == .dormant,
                "something before the resume already revived it")

        let revival = entries[startIndex]
        let deltas = await model.ingest(try #require(revival.event), at: revival.receivedAt)
        // **Exactly one delta, and it is the badge coming down.** This used to
        // assert `deltas.isEmpty`, on the grounds that dormant and idle drew
        // identically so there was nothing to say. `badges.states.sleep` made
        // that false: a revived character has to lose the `Z` it was wearing.
        // Everything the old assertion was really guarding — no second
        // character, no second seat, no re-spawn walk — is the three
        // expectations below, and they are unchanged.
        #expect(deltas == [.dormancyChanged(agent: ref, isDormant: false)],
                "reviving a character already on screen emitted \(deltas)")
        #expect(await model.snapshot().agent(ref)?.lifecycle == .active)
        #expect(await model.snapshot().agents.count == populationBeforeRevival)
        // Not `.spawning`: that means "walk in from the room edge", and this
        // character never left it.
        #expect(await model.snapshot().agent(ref)?.lifecycle != .spawning)
    }

    /// **[I4] — dormancy is reapable, path one: `SessionEnd`.**
    ///
    /// All four are dormant when the session ends at t=172.402, 85 s after the
    /// last of them stopped. A dormant character that outlived its session would
    /// be the same class of bug as a call that never closes.
    @Test func sessionEndDepartsEveryDormantSubagent() async throws {
        let entries = try Fixtures.entries("four-subagents")
        let end = try #require(entries.last { $0.event?.kind.name == "SessionEnd" })
        let model = WorldModel()
        for entry in entries where entry.event?.kind.name != "SessionEnd" {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }

        let before = await model.snapshot().agents
        #expect(before.count == 5, "main plus four dormant subagents")
        #expect(before.filter { $0.lifecycle == .dormant }.count == 4)

        let deltas = await model.ingest(try #require(end.event), at: end.receivedAt)
        #expect(deltas.map(\.tag) == [
            "agentDeparted", "agentDeparted", "agentDeparted", "agentDeparted", "agentDeparted",
            "populationChanged",
        ])
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// **[I4] — dormancy is reapable, path two: the session-idle sweep.**
    ///
    /// Injected instant, never `sleep`. The stream is fed without its
    /// `SessionEnd` — the shape of an app that was watching when the session
    /// died — and the four dormant characters are gone at the timeout and not a
    /// second before it.
    @Test func theIdleSweepDepartsEveryDormantSubagent() async throws {
        let entries = try Fixtures.entries("four-subagents")
        let reaper = Reaper()
        let model = WorldModel(reaper: reaper)
        var last = try #require(entries.first?.receivedAt)
        for entry in entries where entry.event?.kind.name != "SessionEnd" {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            last = entry.receivedAt
        }
        #expect(await model.snapshot().agents.filter { $0.lifecycle == .dormant }.count == 4)

        // Just short of it, still there — and that is true, because dormancy
        // carries no deadline of its own and nothing has happened.
        #expect(await model.sweep(at: last.addingTimeInterval(reaper.sessionIdleTimeout - 1))
            .isEmpty)
        #expect(await model.snapshot().agents.count == 5)

        let swept = await model.sweep(at: last.addingTimeInterval(reaper.sessionIdleTimeout))
        #expect(swept.map(\.tag) == [
            "agentDeparted", "agentDeparted", "agentDeparted", "agentDeparted", "agentDeparted",
            "populationChanged",
        ])
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// **The maintainer's bug, expressed as an assertion.**
    ///
    /// "Only one subagent registered even though there should be 4." Nothing was
    /// lost — identity, seats, the queue and the transport were each refuted with
    /// data at `a6b33ff` — and the room still showed one. The reason is the whole
    /// of it: `SubagentStop` is a **turn boundary** for a background subagent,
    /// not its death, and departing on it made the room assert *this agent is
    /// gone* from data that only says *this agent finished a turn*. This capture
    /// proves it can come back: two of the four are resumed with `SendMessage`,
    /// each resume emitting a second `SubagentStart`.
    ///
    /// So the count is the assertion. From the instant the fourth subagent
    /// exists — t=7.398 — to `SessionEnd` at t=172.402, the parent holds four
    /// agents and the room must hold four characters. Under the departing
    /// lifecycle this fails hard: the capture drops to two for 7.3 s and to one
    /// for 6.7 s inside that window. [I1, and the product's one sentence]
    @Test func thePopulationNeverFallsBelowFourOnceTheFourthSubagentExists() async throws {
        let entries = try Fixtures.entries("four-subagents")
        let origin = try #require(entries.first?.receivedAt)
        let model = WorldModel()

        var live: Set<AgentRef> = []
        var reachedFour = false
        var sawSessionEnd = false
        // Every instant the room was short-handed while the parent was not,
        // reported together: one line per dip is what makes a red run readable.
        var dips: [String] = []

        for entry in entries {
            guard let event = entry.event else { continue }
            if case .sessionEnd = event.kind { sawSessionEnd = true; break }
            for delta in await model.ingest(event, at: entry.receivedAt) {
                switch delta {
                case let .agentAppeared(agent, _, _) where agent.agent != .mainThread:
                    live.insert(agent)
                case let .agentDeparted(agent) where agent.agent != .mainThread:
                    live.remove(agent)
                default:
                    break
                }
            }
            if live.count == 4 { reachedFour = true }
            if reachedFour, live.count < 4 {
                let at = entry.receivedAt.timeIntervalSince(origin)
                dips.append(String(format: "t=%.3f %@ → %d", at, event.kind.name, live.count))
            }
        }

        #expect(reachedFour, "the fixture never put four subagents in the room at once")
        #expect(sawSessionEnd, "the fixture no longer ends on a SessionEnd")
        #expect(dips.isEmpty, """
            the room lost a subagent the parent still had assigned:
            \(dips.joined(separator: "\n"))
            """)
    }

    /// Nothing in this capture needs the reaper: every call closes through the
    /// event stream, and the four concurrent subagents leave no orphan.
    @Test func fourSubagentsReplaysCleanWithoutTheReaper() async throws {
        let (model, _, _) = try await Fixtures.replay("four-subagents")
        #expect(await model.snapshot().agents.isEmpty)
        #expect(await model.abandonedTotal == 0)
        #expect(await model.unhandledTotal == 0)
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

    /// **And still without it when the clock advances through the stream.**
    ///
    /// This is the regression risk in making the replay harness sweep
    /// mid-stream: a sweep that ran too eagerly would close these calls at their
    /// deadlines instead of letting the close paths do it, and the one property
    /// this fixture exists to prove would be gone — silently, because the
    /// fixture would still finish at zero open calls either way.
    ///
    /// It cannot happen, and here is why rather than just that: no call in this
    /// capture is open past its own deadline. `advance(to:)` only ever sweeps at
    /// an instant that is some open call's deadline and never past the event it
    /// is walking to, so with nothing expired there is no sweep at all.
    @Test func toolFailureNeedsNoReaperEvenWithTheClockAdvancing() async throws {
        let (model, timeline, _) = try await Fixtures.replayAdvancingTheClock("tool-failure")
        #expect(!timeline.contains { $0.delta.tag == "callAbandoned" })
        #expect(await model.snapshot().totalOpenCalls == 0)
        #expect(await model.abandonedTotal == 0, "a mid-stream sweep closed a call early")
    }

    /// **The six required fixtures, plus `permission-prompt`, replay identically
    /// with the clock advancing.** Same deltas, same order.
    ///
    /// The guarantee the mid-stream sweep had to keep. None of them holds a
    /// deadline that falls inside its own stream — `killed-session`'s orphan
    /// expires at t=909 in a 9.2 s capture, `permission-prompt`'s shortened one
    /// at t=117.5 in a stream that ends at t=103.5 — so stepping the clock
    /// across them must be a no-op, and if one ever gains such a deadline this
    /// is the test that says so instead of a diff nobody reads.
    ///
    /// **`denial-then-work` is excluded, and the exclusion is the point.** It
    /// joined the required set precisely because its shortened deadline *does*
    /// fall inside its stream: stepping the clock reaps the denied call at
    /// t=94.98 where the unstepped replay leaves it until `SessionEnd` at
    /// t=252.06. Asserting "stepping changes nothing" over it would assert the
    /// opposite of what it exists to prove. Its positive assertion lives in
    /// `PermissionGateTests.theShortenedDeadlineFiresInsideTheStreamWithTheSessionStillWorking`.
    ///
    /// This list is therefore *not* `Fixtures.required` minus nothing — if a
    /// future fixture legitimately gains an in-stream deadline, add it here
    /// with its own positive test, and do not silence this one.
    @Test(arguments: Fixtures.required.filter { $0 != "denial-then-work" })
    func advancingTheClockChangesNothingInTheRequiredFixtures(name: String) async throws {
        let (_, plain, _) = try await Fixtures.replay(name)
        let (_, stepped, _) = try await Fixtures.replayAdvancingTheClock(name)
        #expect(stepped.map(\.delta) == plain, "\(name): the mid-stream sweep moved a delta")
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

    /// Present across every fixture, not just the one that named it — and
    /// "every fixture" means all seventeen, which is what `Fixtures.all` is for.
    @Test func noToolUseIDIsEverClosedTwice() async throws {
        for name in Fixtures.all {
            let (_, deltas, _) = try await Fixtures.replay(name)
            var seen: Set<ToolUseID> = []
            for delta in deltas where delta.tag == "callClosed" || delta.tag == "callAbandoned" {
                let id = try #require(delta.toolUseID)
                #expect(seen.insert(id).inserted, "\(name): \(id) closed twice")
            }
        }
    }

    /// Nothing closes that was never opened, either. Also over all seventeen.
    @Test func everyCloseMatchesAnOpen() async throws {
        for name in Fixtures.all {
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
        // `UserPromptSubmit` is consumed now, so it must no longer be counted
        // as something we do not understand.
        #expect(counts["UserPromptSubmit"] == nil)
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
        // The main character now appears on `UserPromptSubmit`, before any
        // tool call — so `populationChanged` precedes the first `callOpened`
        // rather than trailing it. A turn that calls no tool still draws
        // somebody, and that somebody is idle. [I2]
        "single-agent-simple": [
            "agentAppeared", "populationChanged",
            "callOpened", "callClosed",
            "callOpened", "callClosed",
            "callOpened", "callClosed",
            "agentDeparted", "populationChanged",
        ],
        // Five opens before the first close. That shape is I3.
        "parallel-tools": [
            "agentAppeared", "populationChanged",
            "callOpened", "callOpened", "callOpened", "callOpened", "callOpened",
            "callClosed", "callClosed", "callClosed", "callClosed", "callClosed",
            "agentDeparted", "populationChanged",
        ],
        // Three `Agent` dispatches, each opening and closing in milliseconds
        // around a `SubagentStart` — the subagents outlive them by seconds.
        //
        // Each `agentLinked` lands immediately after the `callClosed` of the
        // `Agent` call that carried it, and *after* the child's
        // `agentAppeared`. That order is the whole reason the link has to be
        // applied retroactively.
        //
        // **This sequence changed when `SubagentStop` stopped departing.** It is
        // the only required fixture that contains a `SubagentStop` for an agent
        // we actually have, so it is the only one that could move. Three things
        // moved, and each is the change stated rather than absorbed:
        //
        // 1. The `agentDeparted`/`populationChanged` pair that used to follow
        //    each of the three `reportDelivered`s is **gone**. The report beat
        //    itself is untouched — three `reportDelivered`, on the same three
        //    events, in the same three places. What is gone is the claim that
        //    followed it, that the agent had left. It had not; it had finished a
        //    turn. `four-subagents` is the capture that proves those are
        //    different facts, and here the three subagents stay in their seats,
        //    dormant, for the 12.7 s between the last stop and `SessionEnd`.
        // 2. The four departures now land **together at `SessionEnd`**, in
        //    `AgentRef` order — main thread first, then the three subagents.
        //    That is `endSession` closing everything under the session, which is
        //    the path that genuinely means gone. [I4]
        // 3. There is **one** trailing `populationChanged`, not four. It is
        //    emitted once per ingested event whose count moved, and one event —
        //    the `SessionEnd` — now empties the room. The three stops no longer
        //    move the population at all, which is the whole point: the parent
        //    had three agents assigned across that window and the room now says
        //    so.
        "three-subagents": [
            "agentAppeared", "populationChanged",
            "callOpened",
            "agentAppeared", "populationChanged", "callClosed", "agentLinked",
            "callOpened", "agentAppeared", "populationChanged", "callClosed", "agentLinked",
            "callOpened", "agentAppeared", "populationChanged", "callClosed", "agentLinked",
            "callOpened", "callClosed", "callOpened",
            "callOpened", "callClosed", "callOpened", "callClosed",
            "callClosed", "callOpened", "callOpened", "callClosed",
            "callOpened", "callClosed", "callOpened",
            // `SubagentStop` is two facts, in the order they happened: the
            // report went to the parent, and the agent is now finished-but-
            // still-assigned. The first licenses the walk, the second raises
            // the `sleep` badge. Nothing here reports without also going
            // dormant, and nothing goes dormant without reporting.
            "reportDelivered", "dormancyChanged",   // first subagent goes dormant
            "callClosed", "reportDelivered", "dormancyChanged",  // second
            "callClosed", "callOpened", "callClosed",
            "reportDelivered", "dormancyChanged",   // third
            "agentDeparted", "agentDeparted", "agentDeparted", "agentDeparted",
            "populationChanged",                    // SessionEnd, all four at once
        ],
        // Ends on an open `Bash` the stream will never close. No SessionEnd.
        "killed-session": [
            "agentAppeared", "populationChanged",
            "callOpened", "callClosed",
            "callOpened", "callClosed",
            "callOpened",
        ],
        // One close by `PostToolUseFailure`, one by `PostToolBatch` alone.
        "tool-failure": [
            "agentAppeared", "populationChanged",
            "callOpened", "callClosed",
            "callOpened", "callClosed",
            "agentDeparted", "populationChanged",
        ],
        // Two gates: one denied, one approved. The denied `Bash` opens and is
        // never closed by anything in the stream — its `callAbandoned` at the
        // end is `SessionEnd` doing it, 101 s later. That is the shape ADR-001
        // is about.
        //
        // Note what is *not* here. `PermissionRequest` is consumed as of
        // ADR-001 and appears twice, and it contributes no delta at all: it
        // marks the agent, which is interior state and not a fact about the
        // room. Nothing in this sequence moved when the ADR was implemented,
        // and that is the point of writing it down.
        "permission-prompt": [
            "agentAppeared", "populationChanged",   // UserPromptSubmit
            "callOpened",                           // Bash, about to be denied
            "attentionChanged",                     // Notification, 6 s after the gate
            "attentionChanged",                     // cleared by the user's next prompt
            "callOpened",                           // Bash, about to be approved
            "attentionChanged", "attentionChanged", // raised, then cleared by its own close
            "callClosed",
            "callAbandoned",                        // the denied call, at SessionEnd
            "agentDeparted", "populationChanged",
        ],
        // The synthetic unknowns after `SessionEnd` add nothing.
        // A real interactive denial in a session that then keeps working.
        //
        // Read the position of `callAbandoned`: it is second from last, after
        // every other call has opened and closed. That is the *unstepped*
        // replay, where the denied `Bash` survives to `SessionEnd` at t=252.06.
        // Step the clock and it moves to t=94.98, ahead of three later calls —
        // which is the whole reason this fixture is in the required set, and
        // why it is the one exclusion from
        // `advancingTheClockChangesNothingInTheRequiredFixtures`.
        //
        // The six `attentionChanged` are three raise/clear pairs: two
        // permission gates and one idle stretch. `idle_prompt` fires per
        // stretch, not per session — this fixture is the capture that refuted
        // the "exactly once" claim.
        "denial-then-work": [
            "agentAppeared", "populationChanged",
            "callOpened", "attentionChanged", "attentionChanged",
            "callOpened", "callClosed",
            "attentionChanged", "attentionChanged",
            "callOpened", "callClosed",
            "attentionChanged", "attentionChanged",
            "callOpened", "callClosed",
            "callOpened", "callClosed",
            "callAbandoned",
            "agentDeparted", "populationChanged",
        ],

        "unknown-events": [
            "agentAppeared", "populationChanged",
            "callOpened", "callClosed",
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

    /// `killed-session`'s sweep must do exactly one thing.
    ///
    /// It is **not** the only sweep in `fixtures/` that does work — this comment
    /// used to say it was, and there are three: `concurrent-permission-gates`
    /// and `denied-batch-cancel` end at a dialog nobody answered and hold an
    /// orphan of their own. Their sweeps are asserted, derived rather than
    /// named, in `everyFixtureReachesZeroOpenCallsAfterTheSweep`. What is
    /// particular to this fixture is the count: it is the one capture whose
    /// whole purpose is a single `PreToolUse` with no close of any kind. [I4]
    @Test func killedSessionSweepAbandonsExactlyOneCall() async throws {
        let reaper = Reaper(sessionIdleTimeout: 24 * 60 * 60)
        let (model, _, entries) = try await Fixtures.replay("killed-session", reaper: reaper)
        let last = try #require(entries.last?.receivedAt)
        let swept = await model.sweep(
            at: last.addingTimeInterval(Reaper.longestDeadlineInterval + 1))
        #expect(swept.map(\.tag) == ["callAbandoned"])
    }

    // MARK: every fixture — M6's three-orphan rule

    /// **Exactly three fixtures hold an orphan at end of stream, and they are
    /// exactly the three with no `SessionEnd`.**
    ///
    /// M6's first exit criterion, and until this test it was asserted nowhere.
    /// What stood here was `onlyKilledSessionLeavesAnOrphanAtEndOfStream`
    /// iterating `Fixtures.required` — eight of the seventeen captures, holding
    /// exactly one of the three. Its name and its comment were true within that
    /// eight and false across `fixtures/`, so it was arranged such that it could
    /// not produce the failure it named. `spriteroom-replay --all` prints these
    /// counts and exits 0 whatever they are, so nothing else caught it either.
    ///
    /// **Both sides are derived and neither is a list of names**: the orphan set
    /// by replaying, the `SessionEnd` set from the payloads. A capture added
    /// tomorrow is scored by this rule on its next run rather than escaping it
    /// until somebody remembers to add a name.
    ///
    /// The equality is the rule; the count is pinned too, because "exactly
    /// three" is what M6 says. A new capture with no `SessionEnd` is a
    /// legitimate thing to have and turns this red on purpose: M6's own
    /// instruction is not to close a criterion by editing it, so the number
    /// moves here and in `docs/05-MILESTONES.md` together, or not at all.
    ///
    /// The stepped and unstepped replays are required to agree, which says the
    /// rule is a property of the captures and not of the harness's sweep
    /// policy. They reach it by different routes: `parallel-denial` and
    /// `denial-then-work` have their denied call reaped mid-stream when the
    /// clock is walked and force-closed by `SessionEnd` when it is not.
    @Test func exactlyTheFixturesWithNoSessionEndOrphanAtEndOfStream() async throws {
        #expect(Fixtures.all.count == 17, """
            fixtures/ holds \(Fixtures.all.count) captures, not the 17 M6 gates \
            `spriteroom-replay --all` over: \(Fixtures.all)
            """)

        var orphaning: [String: Int] = [:]
        var withoutSessionEnd: [String] = []

        for name in Fixtures.all {
            if try !Fixtures.reachesSessionEnd(name) { withoutSessionEnd.append(name) }

            let (stepped, _, _) = try await Fixtures.replayAdvancingTheClock(name)
            let open = await stepped.snapshot().totalOpenCalls
            let (plain, _, _) = try await Fixtures.replay(name)
            #expect(await plain.snapshot().totalOpenCalls == open, """
                \(name): stepping the clock changed how many calls are open at \
                end of stream, so the orphan set is an artefact of the sweep
                """)
            if open > 0 { orphaning[name] = open }
        }

        #expect(orphaning.keys.sorted() == withoutSessionEnd, """
            the orphans at end of stream are not the fixtures with no SessionEnd
            orphaned:        \(orphaning.sorted { $0.key < $1.key })
            no SessionEnd:   \(withoutSessionEnd)
            A fixture that reaches SessionEnd and still orphans has a broken \
            close path. One with no SessionEnd and no orphan means a capture \
            stopped proving what it was taken for.
            """)
        #expect(orphaning.count == 3, """
            M6 says exactly three fixtures legitimately orphan at end of stream; \
            this run found \(orphaning.count): \(orphaning.keys.sorted()). \
            Score the change against M6 rather than editing the criterion.
            """)
    }

    /// **A fixture that reaches `SessionEnd` reaches zero without the sweep.**
    ///
    /// The other half of the same criterion, and the half that is about close
    /// paths rather than about captures. `SessionEnd` force-closes everything in
    /// its session [I4], so a fixture carrying one has no business leaving work
    /// for the harness's closing sweep — if it does, an event-stream close path
    /// is missing and the sweep is hiding it.
    ///
    /// Asserted twice over: nothing open when the stream runs out, *and* a
    /// closing sweep that abandons nothing. The second is what "without the
    /// sweep" actually means; the first alone would pass on a fixture whose
    /// calls the mid-stream reaper had quietly taken.
    ///
    /// The stricter form of this — zero **without the reaper at all**, not one
    /// `callAbandoned` anywhere — belongs to `tool-failure` alone and lives in
    /// `toolFailureClosesEverythingWithoutTheReaper` and
    /// `toolFailureNeedsNoReaperEvenWithTheClockAdvancing`. It cannot be
    /// generalised: `parallel-denial` and `denial-then-work` hold an
    /// interactively denied call that nothing in the stream ever names, and no
    /// rule can invent a close for it.
    @Test func everyFixtureThatReachesSessionEndReachesZeroWithoutTheSweep() async throws {
        var checked: [String] = []

        for name in Fixtures.all {
            guard try Fixtures.reachesSessionEnd(name) else { continue }
            checked.append(name)

            let (model, _, entries) = try await Fixtures.replayAdvancingTheClock(name)
            let open = await model.snapshot().totalOpenCalls
            #expect(open == 0, "\(name) reaches SessionEnd and still left \(open) call(s) open")

            let last = try #require(entries.last?.receivedAt)
            let swept = await model.sweep(
                at: last.addingTimeInterval(Reaper.longestDeadlineInterval + 1))
            #expect(!swept.contains { $0.tag == "callAbandoned" }, """
                \(name): the closing sweep had work to do — \(swept.map(\.tag)) — \
                so a close path in the event stream is missing
                """)
        }

        #expect(checked.count == 14, """
            14 of the 17 captures reach a SessionEnd; this run found \
            \(checked.count): \(checked)
            """)
    }

    /// Every event routes to the sandbox `cwd` it was captured in.
    @Test func everyEventRoutesByCWD() async throws {
        for name in Fixtures.all {
            let entries = try Fixtures.entries(name)
            let projects = Set(entries.compactMap { $0.event?.cwd })
            #expect(projects.count == 1, "\(name) spans \(projects.count) projects")
        }
    }
}
