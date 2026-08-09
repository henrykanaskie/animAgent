import Foundation
import Testing

@testable import SpriteRoomCore

/// Decoding is the contract's first line of defence. An unrecognised — or
/// unusable — `hook_event_name` becomes `.unhandled` and is counted. It never
/// throws, because the hook surface grows and a new event must not crash the
/// app.
@Suite struct HookEventDecodingTests {

    /// "Every fixture" is all seventeen captures, not the eight the ingest layer
    /// is signed off against — a payload that fails to decode is a fact about
    /// the hook surface whichever file it was captured in.
    @Test func everyRealPayloadInEveryFixtureDecodes() throws {
        for name in Fixtures.all {
            let entries = try Fixtures.entries(name)
            #expect(!entries.isEmpty, "\(name) parsed to nothing")
            for entry in entries where !entry.synthetic {
                #expect(entry.event != nil, "\(name): a real captured payload failed to decode")
            }
        }
    }

    /// Rule 3, the load-bearing one: `agent_id` present → subagent, *absent* →
    /// main thread. `agent_type` is never consulted.
    @Test func agentIdentityFollowsAgentIDOnly() throws {
        let entries = try Fixtures.entries("three-subagents")
        var mainThreadEvents = 0
        var subagentEvents = 0
        for entry in entries {
            guard let event = entry.event else { continue }
            let raw = try #require(
                try JSONSerialization.jsonObject(with: entry.payload) as? [String: Any])
            if let id = raw["agent_id"] as? String {
                #expect(event.agentID == .subagent(id))
                subagentEvents += 1
            } else {
                #expect(event.agentID == .mainThread)
                mainThreadEvents += 1
            }
        }
        #expect(subagentEvents > 0)
        #expect(mainThreadEvents > 0)
    }

    /// Two subagents of the same `agent_type` are two characters.
    @Test func sameAgentTypeIsTwoIdentities() throws {
        let entries = try Fixtures.entries("three-subagents")
        let explorers = Set(entries.compactMap { entry -> AgentID? in
            guard let event = entry.event, event.agentType == "Explore",
                  event.agentID != .mainThread else { return nil }
            return event.agentID
        })
        #expect(explorers.count == 2)
    }

    @Test func subagentDispatchToolIsNamedAgentNotTask() throws {
        var toolNames: Set<String> = []
        for name in Fixtures.required {
            for entry in try Fixtures.entries(name) {
                switch entry.event?.kind {
                case let .preToolUse(_, tool): toolNames.insert(tool)
                default: break
                }
            }
        }
        #expect(toolNames.contains("Agent"))
        #expect(!toolNames.contains("Task"))
    }

    /// The seven synthetic lines: a future name, an unknown name with a
    /// `tool_use_id`, an unknown name with an `agent_id`, a real 2.1.224 name
    /// we do not consume, no `hook_event_name` at all, a numeric one, and a
    /// body that is not JSON.
    @Test func syntheticUnknownsAllDecodeToUnhandledOrNothing() throws {
        let entries = try Fixtures.entries("unknown-events")
        let synthetic = entries.filter(\.synthetic)
        #expect(synthetic.count == 7)

        var unhandled = 0
        var unroutable = 0
        for entry in synthetic {
            if let event = entry.event {
                #expect(event.kind.isUnhandled, "\(event.kind.name) should not be consumed")
                unhandled += 1
            } else {
                unroutable += 1
            }
        }
        // Six decode to `.unhandled`; the seventh is the `{"_raw": ...}` line,
        // which carries no `session_id` and so cannot be routed anywhere.
        #expect(unhandled == 6)
        #expect(unroutable == 1)
    }

    @Test func missingAndNonStringEventNamesDecodeRatherThanThrow() throws {
        let names = try Fixtures.entries("unknown-events")
            .compactMap { $0.event?.kind.name }
        #expect(names.contains(HookEvent.missingEventName))
        #expect(names.contains("12345"))
    }

    @Test func nonJSONBodyIsNotAnEvent() {
        #expect(HookEventDecoder.decode(Data("not json at all {".utf8)) == nil)
    }

    @Test func payloadWithoutRoutingKeysIsNotAnEvent() {
        let noCWD = Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8)
        let noSession = Data(#"{"cwd":"/tmp","hook_event_name":"Stop"}"#.utf8)
        #expect(HookEventDecoder.decode(noCWD) == nil)
        #expect(HookEventDecoder.decode(noSession) == nil)
    }

    /// `PostToolUseFailure` fires *instead of* `PostToolUse` and puts its
    /// message in `error`, not `tool_response`.
    @Test func postToolUseFailureCarriesErrorAndReplacesPostToolUse() throws {
        let entries = try Fixtures.entries("tool-failure")
        var failedID: ToolUseID?
        for entry in entries {
            if case let .postToolUseFailure(id, tool, error) = entry.event?.kind {
                failedID = id
                #expect(tool == "Read")
                #expect(error?.isEmpty == false)
            }
        }
        let id = try #require(failedID)
        let successes = entries.compactMap { entry -> ToolUseID? in
            if case let .postToolUse(postID, _, _) = entry.event?.kind { return postID }
            return nil
        }
        #expect(!successes.contains(id), "a PostToolUse accompanied the failure")
    }

    @Test func postToolBatchCarriesItsToolCalls() throws {
        let entries = try Fixtures.entries("parallel-tools")
        let batches = entries.compactMap { entry -> [BatchedCall]? in
            if case let .postToolBatch(calls) = entry.event?.kind { return calls }
            return nil
        }
        #expect(batches.count == 1)
        #expect(batches.first?.count == 5)
        #expect(batches.first?.allSatisfy { $0.toolName == "Bash" } == true)
    }
}
