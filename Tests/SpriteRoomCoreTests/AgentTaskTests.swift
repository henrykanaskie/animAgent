import Foundation
import Testing

@testable import SpriteRoomCore

/// **What a subagent was dispatched to do.**
///
/// The `Agent` tool's `PreToolUse` carries `tool_input.description`: a real
/// 3–5 word task summary written at dispatch. `fixtures/` holds thirteen of
/// them: ten written as capture prompts, and three off a real session
/// (`authoring-subagents`, #72), which is where "3–5 words written for a
/// colleague" stops being an assumption. The model
/// repeats that string and does nothing else to it: no summarising, no
/// shortening, no inference. [I1]
///
/// The whole join is `tool_use_id`. The description belongs to the *dispatching*
/// call, and the child's `agent_id` is not known until that call's
/// `PostToolUse`, so the two halves meet at the same instant the parent link
/// does, which makes this retroactive by construction, exactly as
/// `agentLinked` is. [I3]
struct AgentTaskTests {

    /// Every `Agent` dispatch in a capture: the dispatching `tool_use_id`, the
    /// `description` its payload carried, and the `agent_id` its `PostToolUse`
    /// named. Read out of the raw payloads rather than out of our own decode,
    /// so the assertions below compare the model against the capture and not
    /// against itself.
    struct Dispatch {
        var toolUseID: ToolUseID
        var description: String?
        var spawned: String?
    }

    static func dispatches(_ fixture: String) throws -> [Dispatch] {
        var byID: [ToolUseID: Dispatch] = [:]
        var order: [ToolUseID] = []
        for entry in try Fixtures.entries(fixture) {
            guard let object = try? JSONSerialization.jsonObject(with: entry.payload)
                    as? [String: Any],
                  let id = object["tool_use_id"] as? ToolUseID
            else { continue }
            switch object["hook_event_name"] as? String {
            case "PreToolUse" where object["tool_name"] as? String == "Agent":
                let input = object["tool_input"] as? [String: Any]
                byID[id] = Dispatch(
                    toolUseID: id, description: input?["description"] as? String)
                order.append(id)
            case "PostToolUse":
                guard byID[id] != nil else { continue }
                let response = object["tool_response"] as? [String: Any]
                byID[id]?.spawned = response?["agentId"] as? String
            default:
                continue
            }
        }
        return order.compactMap { byID[$0] }
    }

    /// Every `tool_input.description` anywhere in the corpus, keyed by the tool
/// that carried it. `Agent` is not the only tool with the field: that is
    /// the whole reason the decode is restricted to it.
    static func descriptionsByTool() throws -> [String: [String]] {
        var found: [String: [String]] = [:]
        for fixture in Fixtures.all {
            for entry in try Fixtures.entries(fixture) {
                guard let object = try? JSONSerialization.jsonObject(with: entry.payload)
                        as? [String: Any],
                      object["hook_event_name"] as? String == "PreToolUse",
                      let tool = object["tool_name"] as? String,
                      let input = object["tool_input"] as? [String: Any],
                      let description = input["description"] as? String
                else { continue }
                found[tool, default: []].append(description)
            }
        }
        return found
    }

    static func tasks(in deltas: [WorldDelta]) -> [(agent: AgentRef, task: String)] {
        deltas.compactMap { delta in
            if case let .agentTasked(agent, task) = delta { return (agent, task) }
            return nil
        }
    }

    // MARK: The fact itself

    /// The evidence, named end to end: fixture, `tool_use_id`, `agent_id`,
    /// string.
    ///
    /// `three-subagents` dispatches three `Explore`/`general-purpose` agents in
    /// one block. Each dispatch's `tool_use_id` carries a description, each
    /// `PostToolUse` names the child it launched, and the character that ends up
    /// wearing the task is that child and no other.
    @Test func aSubagentCarriesTheDescriptionItsDispatchGave() async throws {
        let dispatches = try Self.dispatches("three-subagents")
        #expect(dispatches.count == 3)

        let (model, deltas, _) = try await Fixtures.replay("three-subagents")
        let tasked = Self.tasks(in: deltas)

        var reported: [String] = []
        for dispatch in dispatches {
            let spawned = try #require(dispatch.spawned)
            let description = try #require(dispatch.description)
            let match = try #require(
                tasked.first { $0.agent.agent == .subagent(spawned) },
                "no agentTasked for the child of \(dispatch.toolUseID)")
            #expect(match.task == description)
            reported.append(
                "  \(dispatch.toolUseID)  ->  \(spawned)  \(description)")
        }

        print("""

            three-subagents.jsonl: dispatching tool_use_id -> agent_id, task
            \(reported.joined(separator: "\n"))

            """)

        // Pinned, so a capture that changes meaning fails rather than drifts.
        #expect(Set(tasked.map(\.task)) == [
            "Read alpha.txt and sleep",
            "Read beta/gamma and sleep",
            "Read delta/epsilon, sleep, reread alpha",
        ])
        // Nothing left over: the session ends and takes every character with
        // it, tasks included. [I4]
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// The task also stands in the snapshot, not only in the delta stream: a
    /// scene attaching after the fact reads the same value.
    @Test func theTaskStandsInTheSnapshotUntilTheCharacterLeaves() async throws {
        let entries = try Fixtures.entries("three-subagents")
        let dispatches = try Self.dispatches("three-subagents")
        let model = WorldModel()

        // Up to the last `Agent` dispatch's close, which is where the last
        // child learns its task.
        let lastLink = try #require(entries.lastIndex {
            guard let event = $0.event, case let .postToolUse(id, _, spawned) = event.kind
            else { return false }
            return spawned != nil && dispatches.contains { $0.toolUseID == id }
        })
        for entry in entries.prefix(through: lastLink) {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }

        let snapshot = await model.snapshot()
        let subagents = snapshot.agents.filter { $0.ref.agent != .mainThread }
        #expect(subagents.count == 3)
        #expect(subagents.allSatisfy { $0.task != nil })
        #expect(Set(subagents.compactMap(\.task)) == Set(dispatches.compactMap(\.description)))
        // And every one of them is linked, because both facts came off the same
        // payload.
        #expect(subagents.allSatisfy { $0.parent == .mainThread })
    }

    // MARK: [I1] - only a string the payload carried, and only from `Agent`

    /// **Every task the model ever emits is a `description` some `Agent`
    /// dispatch actually carried**, checked over all eighteen captures against
    /// the raw payloads.
    @Test func everyEmittedTaskIsVerbatimFromAnAgentDispatch() async throws {
        let legal = Set(try Self.descriptionsByTool()["Agent"] ?? [])
        #expect(legal.count >= 9)

        var emitted = 0
        for fixture in Fixtures.all {
            let (_, deltas, _) = try await Fixtures.replay(fixture)
            for (_, task) in Self.tasks(in: deltas) {
                #expect(legal.contains(task), "\(fixture) invented \(task)")
                emitted += 1
            }
        }
        #expect(emitted == 13, "thirteen Agent dispatches in the corpus, thirteen tasks")
    }

    /// **`description` is not the `Agent` tool's field alone, and that is why
    /// the decode is keyed on the tool name.**
    ///
    /// 88 of the corpus's `Bash` calls carry one, and so does its single
    /// `Monitor` call, but on a `Bash` it describes a shell command, not an
    /// agent's assignment. Capturing those would put "Create the sandbox
    /// files" on a nameplate as though somebody had been sent to do it. [I1]
    ///
    /// **The eighteenth capture is what makes that risk concrete rather than
    /// theoretical.** It was 37 of 45 while the corpus was scripted; a real
    /// session describes nearly every `Bash` call it makes, so the field this
    /// gate refuses to read is now present on the large majority of them.
    ///
    /// It is the same gate that keeps the decode off the hot path, so this test
    /// pins both: no `OpenCall` outside an `Agent` dispatch carries a
    /// `dispatchedTask`, which means no `PreToolUse` outside one opened
    /// `tool_input` at all. [I5]
    @Test func onlyTheAgentToolsDescriptionIsRead() async throws {
        let byTool = try Self.descriptionsByTool()
        #expect(byTool["Bash"]?.count == 88)
        #expect(byTool["Monitor"]?.count == 1)
        #expect(byTool["Agent"]?.count == 13)
        let notAgent = Set((byTool["Bash"] ?? []) + (byTool["Monitor"] ?? []))
        #expect(!notAgent.isEmpty)

        for fixture in Fixtures.all {
            for entry in try Fixtures.entries(fixture) {
                guard let event = entry.event,
                      case let .preToolUse(_, tool, task) = event.kind
                else { continue }
                if tool == HookEvent.agentDispatchTool { continue }
                #expect(task == nil, "\(fixture): \(tool) had its description read")
            }
            let (_, deltas, _) = try await Fixtures.replay(fixture)
            for delta in deltas {
                guard case let .callOpened(_, call) = delta, let carried = call.dispatchedTask
                else { continue }
                #expect(call.toolName == HookEvent.agentDispatchTool)
                #expect(!notAgent.contains(carried))
            }
        }
    }

    /// **The main agent has no task and must never be given one.** It has no
    /// dispatching `Agent` call; its absence is what makes it the main thread.
    @Test func theMainAgentIsNeverTasked() async throws {
        var mainAgentsSeen = 0
        for fixture in Fixtures.all {
            let (model, deltas, _) = try await Fixtures.replay(fixture)
            for (agent, task) in Self.tasks(in: deltas) {
                #expect(agent.agent != .mainThread, "\(fixture) tasked the main agent: \(task)")
            }
            for agent in await model.snapshot().agents where agent.ref.agent == .mainThread {
                mainAgentsSeen += 1
                #expect(agent.task == nil, "\(fixture) left a task on the main agent")
            }
        }
        #expect(mainAgentsSeen > 0, "no fixture left a main agent standing to check")
    }

    /// A `SendMessage` resume returns a `tool_response.agentId` and carries no
    /// `description`: its `tool_input` has `summary`, `content`, `recipient`
    /// and no such field. So a resume links without tasking, and saying nothing
    /// is the whole of the fallback. [I1]
    @Test func aResumeLinksWithoutInventingATask() async throws {
        let entries = try Fixtures.entries("four-subagents")
        let resumes = entries.filter {
            guard let object = try? JSONSerialization.jsonObject(with: $0.payload)
                    as? [String: Any] else { return false }
            return object["hook_event_name"] as? String == "PreToolUse"
                && object["tool_name"] as? String == "SendMessage"
        }
        #expect(resumes.count == 2)
        for resume in resumes {
            let object = try #require(
                try JSONSerialization.jsonObject(with: resume.payload) as? [String: Any])
            let input = object["tool_input"] as? [String: Any]
            #expect(input?["description"] == nil)
            guard let event = resume.event, case let .preToolUse(_, tool, task) = event.kind
            else { Issue.record("not a PreToolUse"); continue }
            #expect(tool == "SendMessage")
            #expect(task == nil)
        }

        let (_, deltas, _) = try await Fixtures.replay("four-subagents")
        #expect(Self.tasks(in: deltas).count == 4, "four dispatches, four tasks, no fifth")
    }

    // MARK: Retroactive, exactly as the parent link is

    /// `SubagentStart` fires *before* the `PostToolUse` that names the child, so
    /// a character appears and learns its task a moment later. The delta order
    /// has to say so.
    @Test func theCharacterAppearsBeforeItLearnsItsTask() async throws {
        for fixture in Fixtures.all {
            let (_, deltas, _) = try await Fixtures.replay(fixture)
            for (index, delta) in deltas.enumerated() {
                guard case let .agentTasked(agent, _) = delta else { continue }
                let appearance = deltas.prefix(index).lastIndex {
                    if case let .agentAppeared(other, _, _) = $0 { return other == agent }
                    return false
                }
                #expect(appearance != nil, "\(fixture): tasked a character that had not appeared")
                // Behind the link, on the same payload's news.
                let link = deltas.prefix(index).lastIndex {
                    if case let .agentLinked(other, _) = $0 { return other == agent }
                    return false
                }
                #expect(link != nil, "\(fixture): tasked before linked")
            }
        }
    }

    /// A *change*, never a repeat: at most one `agentTasked` per agent, over
    /// every capture. A stream that restated it would make the plate rewrite
    /// itself for nothing.
    @Test func aTaskIsEmittedAtMostOncePerAgent() async throws {
        for fixture in Fixtures.all {
            var counts: [AgentRef: Int] = [:]
            let (_, deltas, _) = try await Fixtures.replay(fixture)
            for (agent, _) in Self.tasks(in: deltas) { counts[agent, default: 0] += 1 }
            #expect(counts.values.allSatisfy { $0 == 1 }, "\(fixture) restated a task")
        }
    }

    /// **The app attached mid-session.** With every `SubagentStart` dropped, the
    /// dispatching `PostToolUse` arrives before the child exists, so the link
    /// *and* the task wait together in `pendingParents` and are played out by
    /// the child's own first `PreToolUse`, in that order.
    ///
    /// Real events, in their real order, with some of them never delivered.
    /// Nothing is written by hand.
    @Test func aTaskLearnedBeforeItsCharacterWaitsForIt() async throws {
        let entries = try Fixtures.entries("three-subagents")
            .filter { $0.event?.kind.name != "SubagentStart" }
        let model = WorldModel()
        var deltas: [WorldDelta] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            deltas += await model.ingest(event, at: entry.receivedAt)
        }

        let tasked = Self.tasks(in: deltas)
        #expect(tasked.count == 3)
        for (agent, _) in tasked {
            let appeared = deltas.firstIndex {
                if case let .agentAppeared(other, _, _) = $0 { return other == agent }
                return false
            }
            let learned = deltas.firstIndex {
                if case let .agentTasked(other, _) = $0 { return other == agent }
                return false
            }
            // Same batch, in the order the character came into existence and
            // then was told about itself.
            let appearedAt = try #require(appeared)
            let learnedAt = try #require(learned)
            #expect(appearedAt < learnedAt)
        }
        #expect(await model.snapshot().agents.isEmpty)
    }

    // MARK: [I4] - nothing held here outlives the call that held it

    /// **The description is held on the `OpenCall` and nowhere else, so a
    /// dispatch the reaper abandons takes it with it.**
    ///
    /// Built from real events: `three-subagents` is replayed up to its first
    /// `Agent` dispatch, the clock is then advanced past that call's 15-minute
    /// deadline so the reaper closes it, and the capture's own `PostToolUse`
    /// for that same `tool_use_id` is delivered afterwards. The child is still
    /// linked (`tool_response.agentId` is on the event, not on the call) and
    /// carries **no** task, because the string went out with the call it lived
    /// on. Saying nothing is the fallback. [I1]
    ///
    /// This is the leak the invariant is about, in map form: had the
    /// description been kept in a side table keyed by `tool_use_id`, the entry
    /// would still be sitting there.
    @Test func anAbandonedDispatchLeavesNoTaskBehind() async throws {
        let entries = try Fixtures.entries("three-subagents")
        let dispatch = try #require(try Self.dispatches("three-subagents").first)
        let openIndex = try #require(entries.firstIndex {
            guard let event = $0.event, case let .preToolUse(id, _, _) = event.kind
            else { return false }
            return id == dispatch.toolUseID
        })
        let closeEntry = try #require(entries.first {
            guard let event = $0.event, case let .postToolUse(id, _, spawned) = event.kind
            else { return false }
            return id == dispatch.toolUseID && spawned != nil
        })

        let model = WorldModel()
        for entry in entries.prefix(through: openIndex) {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }
        // The call is open and holding the description.
        let open = try #require(await model.snapshot().openCalls
            .first { $0.call.toolUseID == dispatch.toolUseID })
        #expect(open.call.dispatchedTask == dispatch.description)

        // Past the `Agent` deadline. The reaper closes it and the string goes.
        let reapedAt = entries[openIndex].receivedAt.addingTimeInterval(16 * 60)
        let steps = await model.advance(to: reapedAt)
        let abandoned = steps.flatMap(\.deltas).contains {
            if case let .callAbandoned(_, id, _, _) = $0 { return id == dispatch.toolUseID }
            return false
        }
        #expect(abandoned)
        #expect(await model.snapshot().openCalls.isEmpty)

        // The real close, delivered late. The link still lands (it rides on
        // `tool_response.agentId`, which is on the event and not on the call)
        // and there is nothing left to say about the task.
        let spawned = try #require(dispatch.spawned)
        var after = await model.ingest(try #require(closeEntry.event), at: reapedAt)
        // The child has not started yet at this point in the capture, so both
        // halves of the news go pending; the task half is empty.
        #expect(Self.tasks(in: after).isEmpty, "a reaped dispatch still produced a task")

        // Its real `SubagentStart`, which is what plays the pending news out.
        let startEntry = try #require(entries.first {
            $0.event?.kind.name == "SubagentStart"
                && $0.event?.agentID == .subagent(spawned)
        })
        after = await model.ingest(try #require(startEntry.event), at: reapedAt)
        #expect(after.contains { if case .agentLinked = $0 { return true } else { return false } })
        #expect(Self.tasks(in: after).isEmpty, "a reaped dispatch still produced a task")
        let child = try #require(await model.snapshot().agents
            .first { $0.ref.agent == .subagent(spawned) })
        #expect(child.parent == .mainThread)
        #expect(child.task == nil)
    }

    /// The other force-close path, and the reason no bookkeeping is needed for
    /// it: `SessionEnd` removes the whole `SessionState`, which is where every
    /// `OpenCall`, every `AgentState.task` and every pending link live. Replay
    /// every capture that reaches one and assert the world is empty: a
    /// surviving task would need a store outside that structure, and there is
    /// none. [I4]
    @Test func sessionEndTakesEveryTaskWithIt() async throws {
        var checked = 0
        for fixture in Fixtures.all where try Fixtures.reachesSessionEnd(fixture) {
            let (model, deltas, _) = try await Fixtures.replay(fixture)
            guard !Self.tasks(in: deltas).isEmpty else { continue }
            checked += 1
            #expect(await model.snapshot().agents.isEmpty, "\(fixture) kept characters")
            #expect(await model.snapshot().totalOpenCalls == 0)
        }
        #expect(checked >= 3, "no fixture exercised a task through SessionEnd")
    }

    // MARK: [I5] - the decode never walks a large `tool_input`

    /// A `PreToolUse` whose `tool_input` is megabytes (a 5.5 MB `Edit`
    /// produces a 5.7 MB POST) must not cost the session anything for this
    /// feature. It does not, because the branch that opens `tool_input` is
    /// reached only for `tool_name == "Agent"`, and an `Agent` dispatch's input
    /// is a prompt.
    ///
    /// The payload is a **real captured `PreToolUse`** with one string value
    /// inflated, which is the same sanctioned synthetic as `Fixtures.rewriting`
    /// and for the same reason: no capture contains a 5 MB tool call, and the
    /// shape has to be real.
    @Test func aHugeToolInputIsNeverWalked() throws {
        let entry = try #require(try Fixtures.entries("single-agent-simple").first {
            guard let object = try? JSONSerialization.jsonObject(with: $0.payload)
                    as? [String: Any] else { return false }
            return object["hook_event_name"] as? String == "PreToolUse"
                && object["tool_name"] as? String == "Bash"
        })
        var object = try #require(
            try JSONSerialization.jsonObject(with: entry.payload) as? [String: Any])
        var input = try #require(object["tool_input"] as? [String: Any])
        input["command"] = String(repeating: "x", count: 5_500_000)
        object["tool_input"] = input
        let payload = try JSONSerialization.data(withJSONObject: object)
        #expect(payload.count > 5_000_000)

        let started = Date()
        let event = try #require(HookEventDecoder.decode(payload))
        let elapsed = Date().timeIntervalSince(started)

        guard case let .preToolUse(_, tool, task) = event.kind else {
            Issue.record("not a PreToolUse")
            return
        }
        #expect(tool == "Bash")
        #expect(task == nil)
        print("  decoded a \(payload.count / 1_000_000) MB PreToolUse in "
              + String(format: "%.1f ms", elapsed * 1000))
        // Generous by an order of magnitude against the listener's 5 ms p99
        // budget; it is here to fail loudly if this decode ever starts copying
        // the tool's arguments rather than to pin a number.
        #expect(elapsed < 0.5, "decoding a 5.7 MB payload took \(elapsed) s")
    }
}
