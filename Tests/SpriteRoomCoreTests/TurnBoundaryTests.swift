import Foundation
import Testing

@testable import SpriteRoomCore

/// **ADR-005 §3, correction 1: the main agent's turn boundary.**
///
/// The ADR shipped with a named blind spot. Four of the five closers §3 lists
/// reach the scene as deltas; the fifth, `Stop`, reached it as nothing at all,
/// so the main character sat down at its session's first event and stood up only
/// when it left. There are 26 `Stop`s in `fixtures/` and every one of them drew
/// nothing, while a subagent's turn end got the whole report walk.
///
/// `WorldDelta.turnChanged` closes it. These tests are the model half; the
/// picture half is `PostureTests`, and the replay half is
/// `ProjectRegistryTests`.
@Suite struct TurnBoundaryTests {

    static func main(_ event: HookEvent) -> AgentRef {
        AgentRef(project: event.cwd, session: event.sessionID, agent: .mainThread)
    }

    // MARK: What `Stop` now says

    /// Every `Stop` in the corpus ends exactly one main character's turn, and
    /// the count is the ADR's own: 26.
    ///
    /// It is asserted on the **stream** rather than on the model, for the reason
    /// task #65 recorded about `gateChanged`: the scene holds whatever the last
    /// delta said, so a model-side change that emits nothing leaves the picture
    /// wrong forever.
    @Test func everyStopInTheCorpusEndsExactlyOneMainCharactersTurn() async throws {
        var stops = 0
        var ends = 0
        for name in Fixtures.all {
            let entries = try Fixtures.entries(name)
            stops += entries.filter { $0.event?.kind == .stop }.count
            let (_, deltas, _) = try await Fixtures.replay(name)
            for delta in deltas {
                guard case let .turnChanged(agent, hasTurn) = delta, !hasTurn else { continue }
                #expect(agent.agent == .mainThread, "a turn ended for \(agent), which is a subagent")
                ends += 1
            }
        }
        #expect(stops == 26, "the corpus changed: \(stops) Stops")
        // Every `Stop` lands on an agent that exists and is in a turn, so every
        // one of them is a change rather than a repeat. Two `Stop`s in a row
        // would emit once; the corpus has none.
        #expect(ends == stops, "\(stops) Stops produced \(ends) turn ends")
    }

    /// **A subagent never receives one.** Its turn boundary is `SubagentStop`,
    /// which already leaves the model as `dormancyChanged`: `03-EVENT-MODEL.md`
    /// names it *the* turn boundary the delta stream carries, and two deltas for
    /// one fact would give the scene two writers of one field.
    @Test func noSubagentIsEverToldAboutATurnBoundary() async throws {
        for name in Fixtures.all {
            let (_, deltas, _) = try await Fixtures.replay(name)
            let subagents = deltas.compactMap { delta -> AgentRef? in
                guard case let .turnChanged(agent, _) = delta,
                      agent.agent != .mainThread else { return nil }
                return agent
            }
            #expect(subagents.isEmpty, Comment(rawValue: "\(name) told \(subagents) about a turn"))
        }
    }

    /// **`Stop` ends the turn even when the open-call set is not empty**, and
    /// five `Stop`s in the corpus are that shape.
    ///
    /// Every one of them is an interactively denied `Bash` that nothing in its
    /// stream will ever close (the shape ADR-001 exists for), so the set is
    /// stale and standing the character up is the truer picture. Consulting it
    /// would also re-couple the two channels ADR-005 §3 separated, on the side
    /// where the set is known to be wrong.
    @Test func aStopEndsTheTurnEvenWithACallStillOpen() async throws {
        var withOpenCalls: [(String, [String])] = []
        for name in Fixtures.all {
            let entries = try Fixtures.entries(name)
            let model = WorldModel()
            for entry in entries {
                guard let event = entry.event else { continue }
                guard event.kind == .stop else {
                    await model.ingest(event, at: entry.receivedAt)
                    continue
                }
                let ref = Self.main(event)
                let open = await model.snapshot().agent(ref)?.openCalls ?? []
                let deltas = await model.ingest(event, at: entry.receivedAt)
                #expect(deltas.contains(.turnChanged(agent: ref, hasTurn: false)),
                        Comment(rawValue: "\(name): a Stop holding \(open.count) calls said nothing"))
                #expect(await model.snapshot().agent(ref)?.hasTurn == false)
                // The set is untouched. `Stop` is not a close path. [I4]
                #expect(await model.snapshot().agent(ref)?.openCalls == open)
                if !open.isEmpty { withOpenCalls.append((name, open.map(\.toolName))) }
            }
        }
        #expect(withOpenCalls.count == 5, Comment(rawValue:
            "\(withOpenCalls.count) Stops arrived with an open call: \(withOpenCalls)"))
        #expect(withOpenCalls.allSatisfy { $0.1 == ["Bash"] }, Comment(rawValue:
            "a Stop arrived over something other than the denied Bash: \(withOpenCalls)"))
    }

    // MARK: Reaping the stream [I4]

    /// **The obligation, and it runs the opposite way from `gateChanged`'s.**
    ///
    /// A scene told `gateChanged(true)` and nothing else holds a character still
    /// forever. The dangerous standing value *here* is the other one: a character
    /// left **seated** is the room asserting a turn that is still running, and
    /// that is I4's character-that-types-forever on the posture channel.
    ///
    /// So the check is that nothing is left seated once every close path has run.
    /// Four paths bound it (`Stop`, `SessionEnd`, the 30-minute idle sweep and
    /// eviction), and the last three take the character with them, exactly as
    /// `dormancyChanged` and `gateChanged` do.
    @Test func noCharacterIsLeftSeatedOnceTheReaperHasHadItsSay() async throws {
        for name in Fixtures.all {
            let entries = try Fixtures.entries(name)
            let model = WorldModel()
            for entry in entries {
                guard let event = entry.event else { continue }
                await model.ingest(event, at: entry.receivedAt)
            }
            guard let last = entries.last?.receivedAt else { continue }
            // Past the 30-minute idle timeout, which departs every session.
            await model.sweep(at: last.addingTimeInterval(Reaper().sessionIdleTimeout + 1))
            let seated = await model.snapshot().agents.filter(\.hasTurn)
            #expect(seated.isEmpty, Comment(rawValue:
                "\(name) left \(seated.map(\.ref)) seated after the sweep"))
            #expect(await model.snapshot().agents.isEmpty)
        }
    }

    /// **A standing character is never working**, which is the invariant that
    /// makes the `false` direction need no reaping of its own: standing is the
    /// room declining to claim anything, and any work that resumes re-opens the
    /// turn *before* the call opens.
    ///
    /// Walked over the stream rather than over the model, because the ordering
    /// inside one ingest is the whole claim: `beginTurn` runs ahead of `open`, so
    /// a `callOpened` can never reach a scene that still thinks the turn is over.
    @Test func noCharacterEverWorksWhileItsTurnIsOver() async throws {
        var checked = 0
        for name in Fixtures.all {
            let (_, deltas, _) = try await Fixtures.replay(name)
            var seated: Set<AgentRef> = []
            for delta in deltas {
                switch delta {
                case let .agentAppeared(agent, _, _):
                    seated.insert(agent)
                case let .turnChanged(agent, hasTurn):
                    if hasTurn { seated.insert(agent) } else { seated.remove(agent) }
                case let .dormancyChanged(agent, isDormant):
                    if isDormant { seated.remove(agent) } else { seated.insert(agent) }
                case let .agentDeparted(agent):
                    seated.remove(agent)
                case let .callOpened(agent, _):
                    #expect(seated.contains(agent), Comment(rawValue:
                        "\(name): \(agent) opened a call while standing: the room would draw the"
                        + " busiest agent as the one with no turn in progress"))
                    checked += 1
                default:
                    break
                }
            }
        }
        // `idle-notification` opens no call at all, which is why this is counted
        // over the corpus rather than per fixture.
        // 75 until the eighteenth capture doubled it: one real session opens as
        // many calls as all seventeen sandbox scenarios put together.
        #expect(checked == 151, "the corpus opens \(checked) calls; 151 was the count")
    }

    // MARK: The edges

    /// A `Stop` for a session nothing has been seen from creates the session and
    /// its main agent, and that character is drawn **standing**.
    ///
    /// The creation is not new (`createsSession` has always included `Stop`, and
    /// nothing may wait for a lifecycle event to make identity), but what it
    /// draws is. It used to be a seated character, which asserted a turn in
    /// progress out of an event that says a turn just ended.
    @Test func aStopIsTheOnlyEventThatCreatesACharacterAlreadyStanding() async throws {
        let stop = try #require(try Fixtures.firstEntry("three-subagents") { $0.kind == .stop })
        let event = try #require(stop.event)
        let model = WorldModel()
        let deltas = await model.ingest(event, at: stop.receivedAt)
        let ref = Self.main(event)
        #expect(deltas.map(\.tag) == ["agentAppeared", "turnChanged", "populationChanged"],
                Comment(rawValue: "a cold Stop emitted \(deltas.map(\.tag))"))
        #expect(await model.snapshot().agent(ref)?.hasTurn == false)
        #expect(await model.snapshot().agent(ref)?.isWorking == false)
    }

    /// Both directions are a change and never a repeat, the same discipline
    /// `dormancyChanged`, `attentionChanged` and `gateChanged` all keep. A delta
    /// stream that restates itself makes the scene's suppression memory the only
    /// thing standing between a stable posture and a flicker.
    @Test func aRepeatedBoundarySaysNothingInEitherDirection() async throws {
        let entries = try Fixtures.entries("three-subagents")
        let prompt = try #require(entries.first { $0.event?.kind == .userPromptSubmit })
        let stop = try #require(entries.first { $0.event?.kind == .stop })
        let model = WorldModel()

        await model.ingest(try #require(prompt.event), at: prompt.receivedAt)
        // A second prompt inside a turn already open.
        #expect(await model.ingest(try #require(prompt.event), at: prompt.receivedAt).isEmpty)

        let ended = await model.ingest(try #require(stop.event), at: stop.receivedAt)
        #expect(ended.map(\.tag) == ["turnChanged"])
        // A second `Stop` with no turn left to end.
        #expect(await model.ingest(try #require(stop.event), at: stop.receivedAt).isEmpty)

        let reopened = await model.ingest(try #require(prompt.event), at: prompt.receivedAt)
        #expect(reopened == [.turnChanged(agent: Self.main(try #require(prompt.event)),
                                          hasTurn: true)])
    }

    /// The three openers ADR-005 §3 names, each re-seating a stopped character:
    /// `UserPromptSubmit`, `PreToolUse`, and, for a subagent, `SubagentStart`.
    ///
    /// Only the first two are reachable for the main thread, because a
    /// `SubagentStart` carries an `agent_id` and therefore names somebody else.
    /// That is why the third is silent in every capture and is written down
    /// anyway: the openers belong in one place.
    @Test func aPreToolUseReSeatsAStoppedCharacterAheadOfTheCallItOpens() async throws {
        let entries = try Fixtures.entries("single-agent-simple")
        let stop = try #require(entries.first { $0.event?.kind == .stop })
        let call = try #require(entries.first { entry in
            guard case .preToolUse = entry.event?.kind else { return false }
            return true
        })
        let model = WorldModel()
        await model.ingest(try #require(stop.event), at: stop.receivedAt)

        let deltas = await model.ingest(try #require(call.event), at: call.receivedAt)
        // **The order is the claim.** The character sits down and *then* starts
        // working; a `callOpened` arriving at a standing character would draw the
        // busiest agent in the room as the one with nothing to do.
        #expect(deltas.map(\.tag) == ["turnChanged", "callOpened"],
                Comment(rawValue: "a PreToolUse after a Stop emitted \(deltas.map(\.tag))"))
    }
}
