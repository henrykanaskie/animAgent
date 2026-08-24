import Foundation
import Testing

@testable import SpriteRoomCore

/// I4: every open state is reapable. A character that types forever is the
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
        // The subagent-dispatch tool is `Agent`, and it dispatches *both* ways:
        // M0 captured it closing in ~16 ms (`async_launched`), M4 saw it stay
        // open for the subagent's whole life. It gets the long deadline because
        // reaping it early abandons a call that is genuinely still running,
        // which renders a working character as idle. [I1]
        #expect(Reaper.deadlineInterval(forTool: "Agent") == 15 * 60)
        #expect(Reaper.deadlineInterval(forTool: "SomeToolShippedTomorrow") == 5 * 60)
    }

    // MARK: killed-session: the deadline path

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

        // An event we do not consume, arriving for *this* session 59 s on. It
        // emits nothing, but the session is demonstrably not silent, so the
        // idle sweep must not fire at 61 s.
        //
        // `UserPromptSubmit` used to serve here; it is consumed now, and
        // `killed-session` contains no other unconsumed event. The payload is
        // this session's own, with `hook_event_name` rewritten to
        // `UserPromptExpansion` (a name 2.1.224 really emits and we really do
        // not handle). Synthetic in the same, necessary sense as the tail of
        // `unknown-events.jsonl`: the fixture cannot be made to contain an
        // event the capture did not produce.
        let last = try #require(entries.last)
        let unconsumed = try #require(
            Fixtures.rewritingEventName(last.payload, to: "UserPromptExpansion"))
        #expect(unconsumed.kind.isUnhandled)
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
    ///
    /// **"Every fixture" is all eighteen.** It iterated `Fixtures.required`
    /// (eight) while saying every, which is the same overclaim the orphan rule
    /// carried: the three captures that actually need this sweep are
    /// `killed-session`, `concurrent-permission-gates` and
    /// `denied-batch-cancel`, and only the first was in the eight.
    ///
    /// The sweep is also required to abandon **exactly** the calls that were
    /// open when the stream ran out: no fewer, which would be a call surviving
    /// it, and no more, which would mean it invented one. That is where the
    /// other two fixtures' sweeps are asserted;
    /// `killedSessionSweepAbandonsExactlyOneCall` keeps the named claim for the
    /// capture whose whole purpose is a single unclosed `PreToolUse`.
    @Test func everyFixtureReachesZeroOpenCallsAfterTheSweep() async throws {
        for name in Fixtures.all {
            let (model, _, entries) = try await Fixtures.replay(name)
            let orphans = await model.snapshot().totalOpenCalls
            let last = try #require(entries.last?.receivedAt)
            let swept = await model.sweep(
                at: last.addingTimeInterval(Reaper.longestDeadlineInterval + 1))
            let abandoned = swept.filter { $0.tag == "callAbandoned" }.count
            #expect(abandoned == orphans, """
                \(name): \(orphans) call(s) open at end of stream, \(abandoned) \
                abandoned by the sweep
                """)
            #expect(await model.snapshot().totalOpenCalls == 0, "\(name) left calls open")
        }
    }
}
