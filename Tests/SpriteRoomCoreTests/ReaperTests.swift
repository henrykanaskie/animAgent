import Foundation
import Testing

@testable import SpriteRoomCore

/// I4 — every open state is reapable. A character that types forever is the
/// signature bug of this project, so all three close paths are tested here:
/// the per-call deadline, `SessionEnd`, and the idle session.
///
/// Time is injected everywhere. There is no `sleep` in this file; a test that
/// passed without advancing the clock would not be testing anything.
@Suite struct ReaperTests {

    @Test func deadlineTableMatchesTheEventModel() {
        #expect(Reaper.deadlineInterval(forTool: "Read") == 30)
        #expect(Reaper.deadlineInterval(forTool: "Glob") == 30)
        #expect(Reaper.deadlineInterval(forTool: "Grep") == 30)
        #expect(Reaper.deadlineInterval(forTool: "TodoWrite") == 30)
        #expect(Reaper.deadlineInterval(forTool: "Edit") == 60)
        #expect(Reaper.deadlineInterval(forTool: "Write") == 60)
        #expect(Reaper.deadlineInterval(forTool: "NotebookEdit") == 60)
        #expect(Reaper.deadlineInterval(forTool: "Bash") == 15 * 60)
        #expect(Reaper.deadlineInterval(forTool: "WebFetch") == 15 * 60)
        #expect(Reaper.deadlineInterval(forTool: "mcp__anything__at_all") == 15 * 60)
        // The subagent-dispatch tool is `Agent`, and it closes in milliseconds.
        #expect(Reaper.deadlineInterval(forTool: "Agent") == 30)
        #expect(Reaper.deadlineInterval(forTool: "SomeToolShippedTomorrow") == 5 * 60)
    }

    // MARK: killed-session — the deadline path

    /// The fixture ends on a `Bash` `PreToolUse` with no close of any kind: no
    /// `PostToolUse`, no `PostToolBatch`, no `Stop`, no `SessionEnd`. Nothing
    /// in the stream will ever close it.
    @Test func killedSessionReachesZeroOpenCallsAfterTheDeadlineElapses() async throws {
        // Idle timeout pushed far out so this isolates the per-call deadline.
        let reaper = Reaper(sessionIdleTimeout: 24 * 60 * 60)
        let (model, _, entries) = try await Fixtures.replay("killed-session", reaper: reaper)
        let lastEventAt = try #require(entries.last?.receivedAt)

        let orphans = await model.snapshot().openCalls
        #expect(orphans.count == 1)
        #expect(orphans.first?.call.toolName == "Bash")
        #expect(orphans.first?.call.toolUseID == "toolu_01LdA9QPuMcXEf2t35ikfzvP")

        // One second before the deadline: still open. The clock is what makes
        // the difference, so prove it does.
        let justBefore = await model.sweep(at: lastEventAt.addingTimeInterval(15 * 60 - 1))
        #expect(justBefore.isEmpty)
        #expect(await model.snapshot().totalOpenCalls == 1)

        // One second after: closed, and abandoned rather than errored.
        let after = await model.sweep(at: lastEventAt.addingTimeInterval(15 * 60 + 1))
        #expect(after.count == 1)
        guard case let .callAbandoned(_, id, tool, reason) = try #require(after.first) else {
            Issue.record("expected a callAbandoned, got \(after)")
            return
        }
        #expect(id == "toolu_01LdA9QPuMcXEf2t35ikfzvP")
        #expect(tool == "Bash")
        #expect(reason == .deadlineExpired)

        #expect(await model.snapshot().totalOpenCalls == 0)
        #expect(await model.abandonedTotal == 1)
    }

    @Test func sweepingTwiceDoesNotAbandonTwice() async throws {
        let reaper = Reaper(sessionIdleTimeout: 24 * 60 * 60)
        let (model, _, entries) = try await Fixtures.replay("killed-session", reaper: reaper)
        let expired = try #require(entries.last?.receivedAt).addingTimeInterval(15 * 60 + 1)
        #expect(await model.sweep(at: expired).count == 1)
        #expect(await model.sweep(at: expired).isEmpty)
        #expect(await model.abandonedTotal == 1)
    }

    // MARK: the idle path

    @Test func aSilentSessionIsPresumedDead() async throws {
        let reaper = Reaper(sessionIdleTimeout: 30 * 60)
        let (model, _, entries) = try await Fixtures.replay("killed-session", reaper: reaper)
        let lastEventAt = try #require(entries.last?.receivedAt)

        #expect(await model.snapshot().agents.count == 1)

        let deltas = await model.sweep(at: lastEventAt.addingTimeInterval(30 * 60 + 1))
        #expect(deltas.contains { $0.tag == "agentDeparted" })
        #expect(deltas.contains { $0.tag == "populationChanged" })
        #expect(await model.snapshot().agents.isEmpty)
        #expect(await model.snapshot().totalOpenCalls == 0)
    }

    /// An unhandled event still proves the session is alive, so it must push
    /// the idle deadline out.
    @Test func anUnhandledEventKeepsASessionAlive() async throws {
        let entries = try Fixtures.entries("killed-session")
        let model = WorldModel(reaper: Reaper(sessionIdleTimeout: 60))
        for entry in entries {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }
        let lastEventAt = try #require(entries.last?.receivedAt)
        #expect(await model.snapshot().agents.count == 1)

        // This session's own `UserPromptSubmit` — an event we do not consume —
        // replayed 59 s on. It emits nothing, but the session is demonstrably
        // not silent, so the idle sweep must not fire at 61 s.
        let unconsumed = try #require(entries.first { $0.event?.kind.isUnhandled == true }?.event)
        let deltas = await model.ingest(unconsumed, at: lastEventAt.addingTimeInterval(59))
        #expect(deltas.isEmpty)

        await model.sweep(at: lastEventAt.addingTimeInterval(61))
        #expect(await model.snapshot().agents.count == 1)

        // 61 s after *that* event, it is silent.
        let idle = await model.sweep(at: lastEventAt.addingTimeInterval(59 + 61))
        #expect(idle.contains { delta in
            if case let .callAbandoned(_, _, _, reason) = delta { return reason == .sessionIdle }
            return false
        })
        #expect(await model.snapshot().agents.isEmpty)
    }

    // MARK: SessionEnd

    @Test func sessionEndClosesEverythingUnderTheSession() async throws {
        let entries = try Fixtures.entries("parallel-tools")
        let model = WorldModel()

        // Stop just before the closes arrive: five calls open.
        let upToFirstClose = entries.prefix { $0.event?.kind.name != "PostToolUse" }
        for entry in upToFirstClose {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }
        #expect(await model.snapshot().totalOpenCalls == 5)

        let sessionEnd = try #require(entries.last { $0.event?.kind.name == "SessionEnd" })
        let deltas = await model.ingest(
            try #require(sessionEnd.event), at: sessionEnd.receivedAt)

        let abandoned = deltas.filter { $0.tag == "callAbandoned" }
        #expect(abandoned.count == 5)
        for delta in abandoned {
            guard case let .callAbandoned(_, _, _, reason) = delta else { continue }
            #expect(reason == .sessionEnded)
        }
        #expect(deltas.contains { $0.tag == "agentDeparted" })
        #expect(await model.snapshot().totalOpenCalls == 0)
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// Belt and braces: the harness's own end-of-run sweep must leave nothing
    /// open in any fixture.
    @Test func everyFixtureReachesZeroOpenCallsAfterTheSweep() async throws {
        for name in Fixtures.required {
            let (model, _, entries) = try await Fixtures.replay(name)
            let last = try #require(entries.last?.receivedAt)
            await model.sweep(at: last.addingTimeInterval(Reaper.longestDeadlineInterval + 1))
            #expect(await model.snapshot().totalOpenCalls == 0, "\(name) left calls open")
        }
    }
}
