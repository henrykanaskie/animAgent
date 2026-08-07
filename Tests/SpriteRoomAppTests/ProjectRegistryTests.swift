import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomApp

/// The menu bar's model. Driven by real captured payloads — M0's fixtures,
/// through the real `WorldModel` — so the delta shapes it folds are the shapes
/// that actually occur.
///
/// M0 captured one project, so a second `cwd` is produced by *re-addressing*
/// a real stream rather than by writing payloads by hand. Every delta is still
/// one the model really emitted.
struct ProjectRegistryTests {

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func deltas(_ fixture: String, project: String? = nil) async throws -> [WorldDelta] {
        let url = Self.repositoryRoot.appending(path: "fixtures/\(fixture).jsonl")
        let entries = try HookLog.load(contentsOf: url)
        let model = WorldModel()
        var deltas: [WorldDelta] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            deltas += await model.ingest(event, at: entry.receivedAt)
        }
        guard let project else { return deltas }
        return deltas.map { readdress($0, to: project) }
    }

    /// Same events, different `cwd` bucket.
    static func readdress(_ delta: WorldDelta, to project: String) -> WorldDelta {
        func moved(_ ref: AgentRef) -> AgentRef {
            AgentRef(project: project, session: ref.session, agent: ref.agent)
        }
        switch delta {
        case let .agentAppeared(agent, type, lifecycle):
            return .agentAppeared(agent: moved(agent), agentType: type, lifecycle: lifecycle)
        case let .agentLinked(agent, parent):
            return .agentLinked(agent: moved(agent), parent: parent)
        case let .agentDeparted(agent):
            return .agentDeparted(agent: moved(agent))
        case let .callOpened(agent, call):
            return .callOpened(agent: moved(agent), call: call)
        case let .callClosed(agent, id, name, outcome):
            return .callClosed(agent: moved(agent), toolUseID: id, toolName: name, outcome: outcome)
        case let .callAbandoned(agent, id, name, reason):
            return .callAbandoned(agent: moved(agent), toolUseID: id, toolName: name, reason: reason)
        case let .reportDelivered(agent):
            return .reportDelivered(agent: moved(agent))
        case .populationChanged:
            return .populationChanged(project: project, count: 0)
        }
    }

    // MARK: Folding

    @Test func aProjectAppearsTheFirstTimeADeltaMentionsIt() async throws {
        var registry = ProjectRegistry()
        #expect(registry.isEmpty)
        registry.absorb(try await Self.deltas("three-subagents"))
        #expect(registry.projects.count == 1)
    }

    @Test func twoProjectsAreKeptApart() async throws {
        var registry = ProjectRegistry()
        let a = try await Self.deltas("three-subagents", project: "/work/alpha")
        let b = try await Self.deltas("parallel-tools", project: "/work/beta")
        // Interleaved, the way two live sessions arrive.
        var mixed: [WorldDelta] = []
        for index in 0..<max(a.count, b.count) {
            if index < a.count { mixed.append(a[index]) }
            if index < b.count { mixed.append(b[index]) }
        }
        registry.absorb(mixed)
        #expect(Set(registry.projects) == ["/work/alpha", "/work/beta"])
    }

    @Test func aDepartedAgentLeavesTheRoster() async throws {
        var registry = ProjectRegistry()
        // `three-subagents` ends with `SessionEnd`, which departs everyone.
        registry.absorb(try await Self.deltas("three-subagents", project: "/work/alpha"))
        #expect(registry.population(of: "/work/alpha") == 0)
        // The project itself survives — it is a bucket, not a character.
        #expect(registry.projects == ["/work/alpha"])
    }

    @Test func theRosterOrderIsFirstSeenAndStable() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.deltas("single-agent-simple", project: "/work/beta"))
        registry.absorb(try await Self.deltas("parallel-tools", project: "/work/alpha"))
        registry.absorb(try await Self.deltas("tool-failure", project: "/work/beta"))
        #expect(registry.projects == ["/work/beta", "/work/alpha"])
    }

    // MARK: Reconstruction — what switching projects feeds a fresh scene

    @Test func reconstructionRebuildsExactlyTheLiveRoster() async throws {
        var registry = ProjectRegistry()
        let all = try await Self.deltas("three-subagents", project: "/work/alpha")
        // Stop before `SessionEnd` so there is something to reconstruct.
        let live = Array(all.prefix(while: { delta in
            if case .agentDeparted = delta { return false }
            return true
        }))
        registry.absorb(live)
        let population = registry.population(of: "/work/alpha")
        #expect(population > 0)

        let rebuilt = registry.reconstruct("/work/alpha")
        let appeared = rebuilt.filter { if case .agentAppeared = $0 { return true }; return false }
        #expect(appeared.count == population)
        // Every open call the registry is holding is re-opened, and nothing
        // else is invented. [I1]
        for delta in rebuilt {
            switch delta {
            case .agentAppeared, .agentLinked, .callOpened, .populationChanged: continue
            default: Issue.record("reconstruction emitted \(delta)")
            }
        }
    }

    @Test func reconstructionIsDeterministic() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.deltas("parallel-tools", project: "/work/alpha"))
        #expect(registry.reconstruct("/work/alpha") == registry.reconstruct("/work/alpha"))
    }

    @Test func agentsAppearBeforeTheirCallsDo() async throws {
        var registry = ProjectRegistry()
        let all = try await Self.deltas("parallel-tools", project: "/work/alpha")
        registry.absorb(Array(all.prefix(all.count / 2)))
        var seenAgents: Set<AgentRef> = []
        for delta in registry.reconstruct("/work/alpha") {
            switch delta {
            case let .agentAppeared(agent, _, _):
                seenAgents.insert(agent)
            case let .callOpened(agent, _):
                #expect(seenAgents.contains(agent), "call opened for an agent not yet appeared")
            default: break
            }
        }
    }

    @Test func reconstructingAnUnknownProjectIsEmptyRatherThanWrong() {
        let registry = ProjectRegistry()
        #expect(registry.reconstruct("/nowhere").isEmpty)
    }

    // MARK: Naming

    @Test func projectsAreNamedByTheirLastPathComponent() {
        let names = ProjectRegistry.displayNames(for: ["/Users/me/code/teamwork"])
        #expect(names["/Users/me/code/teamwork"] == "teamwork")
    }

    @Test func collidingNamesAreLengthenedUntilTheyAreDistinct() {
        let paths = ["/Users/me/a/teamwork", "/Users/me/b/teamwork", "/Users/me/other"]
        let names = ProjectRegistry.displayNames(for: paths)
        #expect(names["/Users/me/a/teamwork"] == "a/teamwork")
        #expect(names["/Users/me/b/teamwork"] == "b/teamwork")
        #expect(names["/Users/me/other"] == "other")
        #expect(Set(names.values).count == 3)
    }

    @Test func everyProjectGetsSomeName() {
        let paths = ["/a", "/b/c", "", "/"]
        let names = ProjectRegistry.displayNames(for: paths)
        for path in paths { #expect(names[path] != nil) }
    }
}
