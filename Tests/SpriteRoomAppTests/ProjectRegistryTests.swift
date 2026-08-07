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

    /// The registry owns no clock; every one of these tests hands it an
    /// instant. Nothing here sleeps, and nothing here would pass if it did
    /// anything but arithmetic on the number it was given.
    static let t0 = Date(timeIntervalSince1970: 1_000_000)

    static func t(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

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
        case let .attentionChanged(agent, attention):
            return .attentionChanged(agent: moved(agent), attention: attention)
        case .populationChanged:
            return .populationChanged(project: project, count: 0)
        }
    }

    /// Same events, same `cwd`, a different `session_id`.
    ///
    /// This is the `/clear` shape from `docs/FINDINGS-M0.md`: the session ends,
    /// and the next prompt in the same process carries a different
    /// `session_id`. Built by re-addressing a real stream rather than by
    /// writing payloads, for the same reason `readdress` is.
    static func resession(_ delta: WorldDelta, to session: String) -> WorldDelta {
        func moved(_ ref: AgentRef) -> AgentRef {
            AgentRef(project: ref.project, session: session, agent: ref.agent)
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
        case let .attentionChanged(agent, attention):
            return .attentionChanged(agent: moved(agent), attention: attention)
        case .populationChanged:
            return delta
        }
    }

    /// A project driven to population 0 the way a real one gets there: the full
    /// `three-subagents` stream, which ends on `SessionEnd` and departs
    /// everybody.
    static func endedProject(_ project: String) async throws -> [WorldDelta] {
        try await deltas("three-subagents", project: project)
    }

    /// The same real stream cut off before anybody leaves, so the project is
    /// left with characters still in the room. Every fixture ends on
    /// `SessionEnd`, which is exactly why a "still running" project has to be
    /// made by truncation rather than by choosing a different file.
    static func runningProject(
        _ fixture: String, project: String, session: String? = nil
    ) async throws -> [WorldDelta] {
        let all = try await deltas(fixture, project: project)
        let live = Array(all.prefix(while: { delta in
            if case .agentDeparted = delta { return false }
            return true
        }))
        guard let session else { return live }
        return live.map { resession($0, to: session) }
    }

    // MARK: Folding

    @Test func aProjectAppearsTheFirstTimeADeltaMentionsIt() async throws {
        var registry = ProjectRegistry()
        #expect(registry.isEmpty)
        registry.absorb(try await Self.deltas("three-subagents"), at: Self.t0)
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
        registry.absorb(mixed, at: Self.t0)
        #expect(Set(registry.projects) == ["/work/alpha", "/work/beta"])
    }

    @Test func aDepartedAgentLeavesTheRoster() async throws {
        var registry = ProjectRegistry()
        // `three-subagents` ends with `SessionEnd`, which departs everyone.
        registry.absorb(
            try await Self.deltas("three-subagents", project: "/work/alpha"), at: Self.t0)
        #expect(registry.population(of: "/work/alpha") == 0)
        // The project itself survives — it is a bucket, not a character.
        #expect(registry.projects == ["/work/alpha"])
    }

    @Test func theRosterOrderIsFirstSeenAndStable() async throws {
        var registry = ProjectRegistry()
        registry.absorb(
            try await Self.deltas("single-agent-simple", project: "/work/beta"), at: Self.t0)
        registry.absorb(
            try await Self.deltas("parallel-tools", project: "/work/alpha"), at: Self.t0)
        registry.absorb(
            try await Self.deltas("tool-failure", project: "/work/beta"), at: Self.t0)
        #expect(registry.projects == ["/work/beta", "/work/alpha"])
    }

    // MARK: Ageing — when a project stops being live
    //
    // The clock is advanced by handing `sweep` a later `Date`. There is no
    // `sleep` anywhere in this section, and the whole elapsed range covered
    // below — up to a full day — costs nothing to run.

    @Test func aPopulatedProjectStaysLiveHoweverLongTheClockRuns() async throws {
        var registry = ProjectRegistry()
        let all = try await Self.deltas("three-subagents", project: "/work/alpha")
        let live = Array(all.prefix(while: { delta in
            if case .agentDeparted = delta { return false }
            return true
        }))
        registry.absorb(live, at: Self.t0)
        #expect(registry.population(of: "/work/alpha") > 0)

        // A day of silence with characters still in the room is not this
        // type's problem to solve — the reaper upstream owns that, and if it
        // ever fires the departures arrive here as deltas.
        let aged = registry.sweep(at: Self.t(86_400), pinning: nil)
        #expect(aged == false)
        #expect(registry.liveness(of: "/work/alpha") == .live)
        #expect(registry.projects == ["/work/alpha"])
    }

    @Test func anEmptyProjectIsStillLiveInsideTheGracePeriod() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)
        #expect(registry.population(of: "/work/alpha") == 0)

        let justShort = ProjectRegistry.endedAfter - 1
        let aged = registry.sweep(at: Self.t(justShort), pinning: nil)
        #expect(aged == false)
        #expect(registry.liveness(of: "/work/alpha") == .live)
    }

    @Test func anEmptyProjectIsEndedOnceTheGracePeriodElapses() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)

        let aged = registry.sweep(at: Self.t(ProjectRegistry.endedAfter), pinning: nil)
        #expect(aged)
        #expect(registry.liveness(of: "/work/alpha") == .ended)
        // Marked, not deleted. This is a status surface; a project that
        // vanished the instant it finished would be indistinguishable from one
        // whose hooks broke.
        #expect(registry.projects == ["/work/alpha"])
        #expect(registry.entries.first?.liveness == .ended)
    }

    /// The `/clear` case: `SessionEnd`, a silence long enough that we called
    /// it, then the same `cwd` under a brand new `session_id`.
    @Test func aProjectThatComesBackIsLiveAgainAndKeepsItsSlot() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.deltas("single-agent-simple", project: "/work/first"),
                        at: Self.t0)
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)
        let aged = registry.sweep(at: Self.t(ProjectRegistry.endedAfter), pinning: nil)
        #expect(aged)
        #expect(registry.liveness(of: "/work/alpha") == .ended)

        // The same `cwd`, still running, under a `session_id` that has never
        // been seen before. That is all `/clear` looks like from here.
        let revived = try await Self.runningProject(
            "parallel-tools", project: "/work/alpha", session: "a-brand-new-session")
        let cameBack = registry.absorb(revived, at: Self.t(200))
        #expect(cameBack)
        #expect(registry.liveness(of: "/work/alpha") == .live)
        #expect(registry.population(of: "/work/alpha") > 0)
        // Its place in the menu never moved. Nothing reshuffles under the
        // pointer just because a session restarted.
        #expect(registry.projects == ["/work/first", "/work/alpha"])
    }

    @Test func anEndedProjectIsForgottenOnceItIsOldEnough() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)
        _ = registry.sweep(at: Self.t(ProjectRegistry.endedAfter), pinning: nil)

        let forgotten = registry.sweep(at: Self.t(ProjectRegistry.forgottenAfter), pinning: nil)
        #expect(forgotten)
        #expect(registry.projects.isEmpty)
        #expect(registry.isEmpty)
    }

    /// Removing what the user is looking at would change what they are looking
    /// at without their asking, on a surface with no way to explain it.
    @Test func theSelectedProjectIsNeverDroppedOutFromUnderTheUser() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)
        registry.absorb(try await Self.endedProject("/work/beta"), at: Self.t0)

        _ = registry.sweep(at: Self.t(86_400), pinning: "/work/alpha")
        #expect(registry.projects == ["/work/alpha"])
        // Pinned, but not lied about: it still reads as ended.
        #expect(registry.liveness(of: "/work/alpha") == .ended)
    }

    @Test func theSelectedProjectLeavesOnceTheUserLooksSomewhereElse() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)
        registry.absorb(
            try await Self.runningProject("parallel-tools", project: "/work/beta"), at: Self.t0)
        _ = registry.sweep(at: Self.t(86_400), pinning: "/work/alpha")
        #expect(registry.projects == ["/work/alpha", "/work/beta"])

        // The user picks beta. On the next frame alpha is no longer pinned.
        let unpinned = registry.sweep(at: Self.t(86_401), pinning: "/work/beta")
        #expect(unpinned)
        #expect(registry.projects == ["/work/beta"])
    }

    /// `sweep` runs once a frame. A sweep that claimed a change every time
    /// would rebuild the menu bar sixty times a second forever.
    @Test func sweepingReportsAChangeOnlyWhenSomethingActuallyChanged() async throws {
        var registry = ProjectRegistry()
        registry.absorb(try await Self.endedProject("/work/alpha"), at: Self.t0)

        let first = registry.sweep(at: Self.t(ProjectRegistry.endedAfter), pinning: "/work/alpha")
        #expect(first)
        for step in 1...5 {
            let again = registry.sweep(
                at: Self.t(ProjectRegistry.endedAfter + Double(step)), pinning: "/work/alpha")
            #expect(again == false, "sweep claimed a change at +\(step)s with nothing to report")
        }
    }

    /// The judgment call, written down where a change to it breaks a test.
    ///
    /// The reaper guards an animation, where firing early invents work that was
    /// not happening. This guards a line of text, where firing late is the lie
    /// and firing early corrects itself on the next delta. The menu is allowed
    /// to give up sooner, and is meant to.
    @Test func theMenuGivesUpOnAProjectSoonerThanTheReaperGivesUpOnASession() {
        #expect(ProjectRegistry.endedAfter < Reaper().sessionIdleTimeout)
        #expect(ProjectRegistry.endedAfter < ProjectRegistry.forgottenAfter)
        // Forgetting uses the reaper's number rather than inventing a second
        // opinion about how long "definitely over" takes.
        #expect(ProjectRegistry.forgottenAfter == Reaper().sessionIdleTimeout)
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
        registry.absorb(live, at: Self.t0)
        let population = registry.population(of: "/work/alpha")
        #expect(population > 0)

        let rebuilt = registry.reconstruct("/work/alpha")
        let appeared = rebuilt.filter { if case .agentAppeared = $0 { return true }; return false }
        #expect(appeared.count == population)
        // Every open call the registry is holding is re-opened, and nothing
        // else is invented. [I1]
        for delta in rebuilt {
            switch delta {
            case .agentAppeared, .agentLinked, .attentionChanged, .callOpened, .populationChanged:
                continue
            default: Issue.record("reconstruction emitted \(delta)")
            }
        }
    }

    @Test func reconstructionIsDeterministic() async throws {
        var registry = ProjectRegistry()
        registry.absorb(
            try await Self.deltas("parallel-tools", project: "/work/alpha"), at: Self.t0)
        #expect(registry.reconstruct("/work/alpha") == registry.reconstruct("/work/alpha"))
    }

    @Test func agentsAppearBeforeTheirCallsDo() async throws {
        var registry = ProjectRegistry()
        let all = try await Self.deltas("parallel-tools", project: "/work/alpha")
        registry.absorb(Array(all.prefix(all.count / 2)), at: Self.t0)
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
