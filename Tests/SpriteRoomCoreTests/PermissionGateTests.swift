import Foundation
import Testing

@testable import SpriteRoomCore

/// **ADR-001 (d): mark on `PermissionRequest`, act on `UserPromptSubmit`,
/// change only the deadline.** Accepted 2026-08-07.
///
/// Click "No" on a permission prompt and nothing ever closes that tool call:
/// no `PostToolUse`, no `PostToolUseFailure`, no mention in the following
/// `PostToolBatch`, not even a `Stop` for the turn. `Bash` carries the
/// 15-minute deadline, so a two-second interaction left that character typing
/// for 900 s: the signature bug of this project on the most ordinary
/// interaction there is.
///
/// Three rules replace that, and each one is a test below:
///
/// 1. a `PermissionRequest` **marks** the agent and the set of calls it held
///    open at that instant: no join, by name or by recency;
/// 2. any close of any marked call, or a `Stop`, **disarms** the mark;
/// 3. a `UserPromptSubmit` for that agent while the mark is still set pulls
///    those calls' deadlines in to `now + G`. **Shortened, never closed**: the
///    reaper still does the closing and still emits `.callAbandoned`.
///
/// Everything here is driven by captured payloads. Where a shape no capture
/// contains is needed (a denial whose turn produced a `Stop`, an approved call
/// still running when a later prompt arrives), it is built by re-ordering real
/// payloads from one real session, or by the one sanctioned rewrite helper, and
/// the comment says which and why. Time is injected everywhere; there is no
/// `sleep` in this file.
@Suite struct PermissionGateTests {

    // MARK: Scaffolding

    /// The denied call in `fixtures/permission-prompt.jsonl`. Opens, is refused
    /// at the dialog, and is never named again by anything in the stream.
    static let deniedCall = "toolu_0199hyfQtR1Hf3i3feHZvivV"
    /// The approved call in the same capture. Closes normally 1.81 s later.
    static let approvedCall = "toolu_015N71EzzTiFqrnLirnMGCCz"

    /// Every entry of `permission-prompt`, plus the main-thread ref they all
    /// belong to.
    private func permissionPrompt() throws -> (entries: [HookLogEntry], main: AgentRef) {
        let entries = try Fixtures.entries("permission-prompt")
        let first = try #require(entries.first?.event)
        return (entries, AgentRef(
            project: first.cwd, session: first.sessionID, agent: .mainThread))
    }

    /// The first entry whose event is `kind`, by name.
    private func entry(
        _ entries: [HookLogEntry], _ name: String, skipping: Int = 0
    ) throws -> HookLogEntry {
        let matches = entries.filter { $0.event?.kind.name == name }
        return try #require(matches.dropFirst(skipping).first, "no \(name) at index \(skipping)")
    }

    /// Feeds entries up to and including the first one matching `name`.
    @discardableResult
    private func feed(
        _ model: WorldModel, _ entries: [HookLogEntry], through name: String, skipping: Int = 0
    ) async throws -> Date {
        var seen = 0
        for candidate in entries {
            guard let event = candidate.event else { continue }
            await model.ingest(event, at: candidate.receivedAt)
            if event.kind.name == name {
                seen += 1
                if seen > skipping { return candidate.receivedAt }
            }
        }
        Issue.record("stream ended before \(name) #\(skipping)")
        return Date()
    }

    // MARK: Decoding - it is consumed, and it still names no call

    /// `PermissionRequest` stops being counted as unhandled. That is a real
    /// cost (the unhandled counter's job is to notice the hook surface growing)
    /// and it is paid deliberately.
    @Test func permissionRequestIsConsumedRatherThanCounted() async throws {
        let (entries, _) = try permissionPrompt()
        let requests = entries.filter { $0.event?.kind == .permissionRequest }
        #expect(requests.count == 2, "the fixture's two gates are the point of this test")

        let (model, _, _) = try await Fixtures.replay("permission-prompt")
        #expect(await model.unhandledCounts["PermissionRequest"] == nil)
        #expect(await model.unhandledTotal == 0)
    }

    /// **The fact the whole design rests on.** It carries `tool_name`,
    /// `tool_input` and `permission_suggestions[]` and *no* `tool_use_id`, so
    /// there is nothing to join with, which is why marking is legitimate where
    /// pairing would not be. ADR-001 (c), rejected: `tool_name` + `tool_input`
    /// is not even unique within one batch, and a wrong join closes the wrong
    /// call. [I3]
    @Test func permissionRequestNamesNoToolCall() throws {
        let (entries, _) = try permissionPrompt()
        var checked = 0
        for candidate in entries where candidate.event?.kind == .permissionRequest {
            let object = try JSONSerialization.jsonObject(with: candidate.payload)
            let keys = Set(((object as? [String: Any]) ?? [:]).keys)
            #expect(!keys.contains("tool_use_id"), "PermissionRequest gained a tool_use_id")
            #expect(keys.contains("tool_name"))
            checked += 1
        }
        #expect(checked == 2)
    }

    /// **ADR-001's risk 3, settled in the rule's favour: a subagent's gate
    /// carries the subagent's `agent_id`, and is attributed to the subagent.**
    ///
    /// This test used to be `everyCapturedPermissionRequestIsMainThread`, which
    /// was true of `permission-prompt` and was the whole evidence base. It said
    /// more than it asserted, and M6c captured the file that lets it assert the
    /// useful thing instead. Both halves are checked: the main-thread gates are
    /// still main-thread, and the subagent one lands on the subagent.
    ///
    /// It is load-bearing rather than tidy. Per-agent scoping is what keeps the
    /// synchronous-`Agent` case safe: in this same fixture the parent's `Agent`
    /// call is open across the child's dialog, so a session-scoped mark would
    /// mark the parent and let a synthetic prompt shorten it.
    @Test func aSubagentsGateIsAttributedToTheSubagent() async throws {
        let (mainThreadGates, _) = try permissionPrompt()
        for candidate in mainThreadGates where candidate.event?.kind == .permissionRequest {
            #expect(candidate.event?.agentID == .mainThread)
        }

        let entries = try Fixtures.entries("subagent-permission")
        let first = try #require(entries.first?.event)
        let child = AgentRef(
            project: first.cwd, session: first.sessionID,
            agent: .subagent("ab2378e6a85dea269"))
        let main = AgentRef(project: first.cwd, session: first.sessionID, agent: .mainThread)

        let gate = try #require(entries.first { $0.event?.kind == .permissionRequest })
        #expect(gate.event?.agentID == child.agent)

        let model = WorldModel()
        for candidate in entries {
            guard let event = candidate.event else { continue }
            await model.ingest(event, at: candidate.receivedAt)
            if event.kind == .permissionRequest { break }
        }
        #expect(await model.permissionGateMark(child) == ["toolu_01FDPVqz93DqdjxorZPzz2Y9"])
        // The parent is mid-`Agent` and mid-dialog-on-its-child's-behalf, and
        // its call is *not* marked. That is the exclusion ADR-001 states as
        // structural and which is in fact this scoping.
        #expect(await model.permissionGateMark(main) == nil)
        #expect(await model.snapshot().agent(main)?.isWorking == true)
    }

    // MARK: Rule 1 - the mark arms and records the right set

    /// It records *this agent's open-call set at that instant* and nothing
    /// else. No `tool_use_id` is read from the event, because it has none.
    @Test func theMarkArmsOnPermissionRequestAndRecordsTheOpenCallSet() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()

        // Before the gate: the call is open and nothing is marked.
        try await feed(model, entries, through: "PreToolUse")
        #expect(await model.snapshot().agent(main)?.openCalls.count == 1)
        #expect(await model.permissionGateMark(main) == nil)

        let gate = try entry(entries, "PermissionRequest")
        let deltas = await model.ingest(try #require(gate.event), at: gate.receivedAt)

        // **One delta, and it carries the `Bool` and nothing else.** This read
        // `deltas.isEmpty` until ADR-005 §7, on the grounds that "a marker is not
        // a fact about the room". The *marked set* is not; being stopped at a
        // gate is, it is the only answer this app has to "is any agent stuck",
        // and the body holds still for as long as it lasts. The set itself still
        // does not leave the model. [I3]
        #expect(deltas == [.gateChanged(agent: main, isGated: true)])
        #expect(await model.permissionGateMark(main) == [Self.deniedCall])
    }

/// A second gate re-marks with the set as it stands *then*, which in this
    /// capture is both calls, because the denied one is still open. "At most
    /// one permission prompt outstanding" is untested and nothing here assumes
    /// it.
    @Test func aSecondGateMarksWhateverIsOpenAtThatMoment() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()
        try await feed(model, entries, through: "PermissionRequest", skipping: 1)
        #expect(await model.permissionGateMark(main) == [Self.deniedCall, Self.approvedCall])
    }

    /// Consuming it must not have made it a badge-clearing event. It is the
    /// *announcement* of a wait, and it arrives 6 s before the `Notification`
/// that raises the badge, so a second gate opening while the first badge
    /// is up would otherwise erase a badge that is still true.
    @Test func aPermissionRequestDoesNotClearTheAttentionBadge() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()
        try await feed(model, entries, through: "Notification")
        #expect(await model.snapshot().agent(main)?.attention == .permissionPrompt)

        // The capture's *second* `PermissionRequest` payload, fed while the
        // first badge is still up: the "two gates at once" shape, assembled
        // from real payloads of one real session because no capture contains
        // it.
        let second = try entry(entries, "PermissionRequest", skipping: 1)
        let deltas = await model.ingest(
            try #require(second.event), at: second.receivedAt)
        // And it is silent, because this agent's gate was already open: a change,
        // never a repeat. The re-arm behind it does re-snapshot the *marked set*,
        // and that is interior. [ADR-005 §7]
        #expect(deltas.isEmpty)
        #expect(await model.permissionGateMark(main) != nil)
        #expect(await model.snapshot().agent(main)?.attention == .permissionPrompt)
    }

    // MARK: Rule 2 - disarming

    /// **The test that stops this fix reaping approved long-running calls.**
    ///
    /// This is the failure mode option (a) had on its own: arming a short
    /// deadline at the gate cannot tell approve from deny, so an approved
    /// five-minute build gets reaped at the gate deadline while it is genuinely
    /// running. An early reap is fiction, and it lands on the *more common*
    /// path. [I1]
    ///
    /// Under (d) the approval closes the gated call, that close disarms the
    /// mark, and no later prompt can shorten anything, including a call opened
    /// afterwards that runs for a quarter of an hour.
    @Test func theApprovePathDisarmsAndALaterPromptShortensNothing() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()

        // Up to the approved call's gate: marked.
        try await feed(model, entries, through: "PermissionRequest", skipping: 1)
        #expect(await model.permissionGateMark(main)?.contains(Self.approvedCall) == true)

        // The approval's own `PostToolUse` (one of the three close paths,
        // behaving exactly as it always has) disarms it.
        let close = try entry(entries, "PostToolUse")
        await model.ingest(try #require(close.event), at: close.receivedAt)
        #expect(await model.permissionGateMark(main) == nil)

        // A long `Bash` opened after the gate was answered. Real captured
        // payload (`killed-session`'s never-closed call) routed into this
        // session by the one sanctioned rewrite helper, because no single
        // capture contains "a gate, then an approval, then a long-running
        // command". Only its address is changed.
        let longCallEntry = try #require(try Fixtures.firstEntry("killed-session") {
            if case let .preToolUse(_, tool, _) = $0.kind { return tool == "Bash" }
            return false
        })
        let longCall = try #require(Fixtures.rewriting(longCallEntry.payload, [
            "session_id": main.session,
            "cwd": main.project,
        ]))
        let openedAt = close.receivedAt.addingTimeInterval(1)
        await model.ingest(longCall, at: openedAt)

        // The user's next prompt, 30 s into that command. Nothing is marked, so
        // rule 3 does not fire and the deadline table is untouched.
        let prompt = try entry(entries, "UserPromptSubmit", skipping: 1)
        await model.ingest(
            try #require(prompt.event), at: openedAt.addingTimeInterval(30))

        let call = try #require(await model.snapshot().agent(main)?.openCalls
            .first { $0.toolName == "Bash" && $0.toolUseID != Self.deniedCall })
        #expect(call.deadline == openedAt.addingTimeInterval(15 * 60),
                "an approved long-running call had its deadline pulled in")
        #expect(await model.permissionGateMark(main) == nil)
    }

    /// `Stop` disarms: the turn completed, so whatever the gate was waiting for
    /// is no longer pending.
    ///
    /// Assembled by re-ordering real payloads from this one session, because
    /// the shape cannot be captured: a denial produces *no* `Stop` for its
    /// turn, which is the whole reason this ADR exists. The `Stop` used is the
    /// capture's own.
    @Test func stopDisarmsTheMark() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()
        let gateAt = try await feed(model, entries, through: "PermissionRequest")
        #expect(await model.permissionGateMark(main) == [Self.deniedCall])

        let stop = try entry(entries, "Stop")
        let deltas = await model.ingest(
            try #require(stop.event), at: gateAt.addingTimeInterval(1))
        // **`Stop` says two things and they are separate facts on separate
        // channels.** The gate clear releases a body that was being held still
        // [ADR-005 §7]; the turn end stands the character up [ADR-005 §3]. The
        // order is the one every other arm takes: the wait ended, then the turn
        // did.
        #expect(deltas == [
            .gateChanged(agent: main, isGated: false),
            .turnChanged(agent: main, hasTurn: false),
        ])
        #expect(await model.permissionGateMark(main) == nil)

        // A second `Stop` says nothing: there is no gate left to close and no
        // turn left to end. Both halves are a change and never a repeat.
        #expect(await model.ingest(
            try #require(stop.event), at: gateAt.addingTimeInterval(2)).isEmpty)

        // And a prompt afterwards therefore shortens nothing.
        let prompt = try entry(entries, "UserPromptSubmit", skipping: 1)
        await model.ingest(
            try #require(prompt.event), at: gateAt.addingTimeInterval(10))
        let call = try #require(await model.snapshot().agent(main)?.openCalls.first)
        #expect(call.deadline == call.startedAt.addingTimeInterval(15 * 60))
    }

    // MARK: Rule 3 - the deadline, pulled in

    /// **The fix, measured against the fixture that motivated it.**
    ///
    /// The denied `Bash` opens at t=2.06 and nothing in the stream ever closes
    /// it. Its deadline used to be t=902; the user's next prompt lands at
    /// t=57.46, so it is now t=117.46: `now + G`, 60 s.
    ///
    /// The capture's `SessionEnd` arrives at t=103.46 and would close the call
    /// first, so it is withheld here: `permission-prompt.jsonl` ends before the
    /// deadline could ever have mattered, which is exactly the fourth capture
    /// ADR-001 asks for. Everything up to that point is replayed verbatim.
    @Test func theDeniedCallIsAbandonedSixtySecondsAfterTheNextPromptNotNineHundred()
    async throws {
        let (entries, main) = try permissionPrompt()
        // Idle timeout pushed far out so this isolates the per-call deadline.
        let model = WorldModel(reaper: Reaper(sessionIdleTimeout: 24 * 60 * 60))

        var promptAt: Date?
        var openedAt: Date?
        var prompts = 0
        for candidate in entries where candidate.event?.kind.name != "SessionEnd" {
            guard let event = candidate.event else { continue }
            await model.ingest(event, at: candidate.receivedAt)
            if case let .preToolUse(id, _, _) = event.kind, id == Self.deniedCall {
                openedAt = candidate.receivedAt
            }
            if event.kind == .userPromptSubmit {
                prompts += 1
                if prompts == 2 { promptAt = candidate.receivedAt }
            }
        }
        let opened = try #require(openedAt)
        let answered = try #require(promptAt, "the user's next prompt after the denial")

        // The orphan is still open and its deadline has moved, and only its
        // deadline. It is still a `Bash`, still started when it started.
        let orphan = try #require(await model.snapshot().agent(main)?.openCalls.first)
        #expect(orphan.toolUseID == Self.deniedCall)
        #expect(orphan.startedAt == opened)
        #expect(orphan.deadline == answered.addingTimeInterval(60))

        // The number this replaces, stated so the improvement is legible. The
        // call used to live 900 s from the moment it opened; it now lives
        // 115.4 s: the 55.4 s the user spent at the dialog and afterwards,
        // plus G. The deadline moved in by 784.6 s.
        let old = opened.addingTimeInterval(Reaper.deadlineInterval(forTool: "Bash"))
        #expect(abs(old.timeIntervalSince(orphan.deadline) - 784.6) < 1,
                "pulled in by \(old.timeIntervalSince(orphan.deadline))s")
        let lifetime = orphan.deadline.timeIntervalSince(opened)
        #expect(abs(lifetime - 115.4) < 1, "the orphan now lives \(lifetime)s, was 900")

        // A second before: still open. The clock is what makes the difference,
        // so prove it does.
        #expect(await model.sweep(at: orphan.deadline.addingTimeInterval(-1)).isEmpty)
        #expect(await model.snapshot().totalOpenCalls == 1)

        // At the deadline: closed by the reaper, on the same path and with the
        // same delta as every other expired call. No new close path exists.
        let swept = await model.sweep(at: orphan.deadline)
        guard case let .callAbandoned(agent, id, tool, reason) = try #require(swept.first) else {
            Issue.record("expected a callAbandoned, got \(swept)")
            return
        }
        #expect(agent == main)
        #expect(id == Self.deniedCall)
        #expect(tool == "Bash")
        #expect(reason == .deadlineExpired)
        #expect(await model.snapshot().totalOpenCalls == 0)
        #expect(await model.abandonedTotal == 1)
    }

    /// **The same fix against the capture that can actually distinguish 60 s
    /// from 900 s, and with the clock advancing through the stream, which is
    /// how a replay sees it.**
    ///
    /// `permission-prompt.jsonl` ends 40 s after its denial, so its `SessionEnd`
    /// always closes the orphan first and no deadline value is observable from
    /// the stream alone. `fixtures/denial-then-work.jsonl` is ADR-001's fourth
    /// requested capture and does not have that problem: the denied `Bash` opens
    /// at t=3.138, the mark lands at t=3.151, the user's next prompt at t=34.984
    /// puts the deadline at **t=94.98**, and the session then does three more
    /// turns of real work before ending at t=252.06. **157 s of stream after the
    /// deadline.**
    ///
    /// Nothing here is injected but the walk itself: the deltas, the instants
    /// and the 60 s are all the fixture's.
    @Test func theShortenedDeadlineFiresInsideTheStreamWithTheSessionStillWorking()
    async throws {
        let denied = "toolu_01WXAhzmcL2iKm1mdYfuLczp"
        let (model, timeline, entries) = try await Fixtures
            .replayAdvancingTheClock("denial-then-work")
        let origin = try #require(entries.first?.receivedAt)
        let end = try #require(entries.last?.receivedAt)

        let abandoned = try #require(timeline.first {
            $0.delta.tag == "callAbandoned" && $0.delta.toolUseID == denied
        })
        guard case let .callAbandoned(_, _, tool, reason) = abandoned.delta else {
            Issue.record("expected a callAbandoned, got \(abandoned.delta)")
            return
        }
        #expect(tool == "Bash")
        // The reaper closed it, on its own deadline, not `SessionEnd` at
        // t=252.06, which is what a replay that only swept at the end reported.
        #expect(reason == .deadlineExpired)

        let at = abandoned.instant.timeIntervalSince(origin)
        #expect(abs(at - 94.98) < 0.1, "abandoned at \(at)s, expected the shortened deadline")

        // Derived from the fixture rather than restated: prompt + G.
        let prompt = try #require(entries.first {
            $0.event?.kind == .userPromptSubmit && $0.receivedAt > origin
        })
        #expect(abandoned.instant == prompt.receivedAt
            .addingTimeInterval(Reaper.permissionGateGraceInterval))

        // And the session kept working for a long time afterwards, which is the
        // whole reason this capture can prove what `permission-prompt` cannot.
        let tail = end.timeIntervalSince(abandoned.instant)
        #expect(abs(tail - 157.08) < 0.5, "only \(tail)s of stream after the deadline")
        #expect(timeline.contains {
            $0.instant > abandoned.instant && $0.delta.tag == "callOpened"
        }, "no further work in the stream after the deadline")

        #expect(await model.abandonedTotal == 1)
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// The defect this replaced, pinned so it cannot come back quietly: a walk
    /// that never advances the clock between events reports the same call as
    /// `sessionEnded` at t=252.06, and that instant says nothing about the
    /// deadline at all.
    @Test func withoutAdvancingTheClockTheDeadlineIsInvisible() async throws {
        let denied = "toolu_01WXAhzmcL2iKm1mdYfuLczp"
        let (_, deltas, _) = try await Fixtures.replay("denial-then-work")
        let closes = deltas.filter { $0.toolUseID == denied && $0.tag == "callAbandoned" }
        guard case let .callAbandoned(_, _, _, reason) = try #require(closes.first) else {
            Issue.record("expected a callAbandoned")
            return
        }
        #expect(reason == .sessionEnded)
    }

    /// Pulled *in*, never out. A `Read` marked at a gate carries a 30 s
    /// deadline of its own; a prompt arriving 5 s later must not push it to
    /// 60 s, because this rule exists to shorten deadlines and never to grant a
    /// call more life than the ordinary table allows.
    @Test func aShorterDeadlineIsNeverPushedOut() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let reaper = Reaper()
        let read = start.addingTimeInterval(Reaper.deadlineInterval(forTool: "Read"))
        #expect(reaper.shortenedDeadline(read, answeredAt: start.addingTimeInterval(5)) == read)

        let bash = start.addingTimeInterval(Reaper.deadlineInterval(forTool: "Bash"))
        let answered = start.addingTimeInterval(5)
        #expect(reaper.shortenedDeadline(bash, answeredAt: answered)
            == answered.addingTimeInterval(60))
    }

    // MARK: G

    /// **G is a measurement, and this is the measurement.**
    ///
    /// The only thing G has to survive is the gap between a synthetic
    /// `UserPromptSubmit` and the close of a call that is genuinely still
    /// running. `three-subagents` contains the only two such straddles anyone
    /// has captured (8.05 s and 15.05 s) and G is four times the larger.
    ///
    /// Derived from the fixture rather than written down, so that a capture
    /// with a longer straddle turns this from a passing test into a failing
    /// one, which is the conversation ADR-001 asks for.
    @Test func gIsFourTimesTheLargestStraddleAnyoneHasCaptured() throws {
        let entries = try Fixtures.entries("three-subagents")
        var openedAt: [ToolUseID: Date] = [:]
        var prompts: [Date] = []
        var straddles: [TimeInterval] = []

        for candidate in entries {
            guard let event = candidate.event else { continue }
            switch event.kind {
            case .userPromptSubmit:
                prompts.append(candidate.receivedAt)
            case let .preToolUse(id, _, _):
                openedAt[id] = candidate.receivedAt
            case let .postToolUse(id, _, _), let .postToolUseFailure(id, _, _):
                guard let start = openedAt.removeValue(forKey: id) else { break }
                if prompts.contains(where: { $0 > start && $0 < candidate.receivedAt }) {
                    straddles.append(candidate.receivedAt.timeIntervalSince(start))
                }
            default:
                break
            }
        }

        #expect(straddles.count == 2, "the fixture's two straddles are the evidence base")
        let largest = try #require(straddles.max())
        #expect(abs(largest - 15.049) < 0.1, "largest straddle \(largest)s")
        #expect(Reaper.permissionGateGraceInterval == 60)
        // 60 / 15.049 = 3.987. "Four times", as the ADR states it, is the
        // largest straddle rounded to the second, which is the precision the
        // claim deserves and the precision this pins it to. A capture with a
        // straddle past ~15.4 s makes this fail, which is the conversation the
        // ADR asks for rather than a number that quietly stops being true.
        #expect(Reaper.permissionGateGraceInterval / largest > 3.9,
                "G is \(Reaper.permissionGateGraceInterval / largest)× the largest straddle")
    }

    // MARK: Regression - the hazard that got option (b) rejected

    /// **The two straddles in `three-subagents` are untouched, and this is the
    /// test that says so.**
    ///
    /// Option (b), "the next `UserPromptSubmit` closes stragglers", was
    /// rejected because a subagent's result reaches the main thread as a
    /// *synthetic* `UserPromptSubmit`, and two calls here are genuinely still
    /// running when one arrives: `toolu_017StzPCoy…` for 8.05 s across one
    /// prompt, `toolu_01NDyNkE17…` for 15.05 s across two. Rule (b) closes both.
    /// Both were working. An early reap is fiction, and it fails in the
    /// direction this project cares about most. [I1]
    ///
    /// (d) defuses that rather than ignoring it: shortening needs the *same
    /// agent* to be sitting at a gate at that moment, and there is no gate
    /// anywhere in this capture. So neither call may have its deadline moved by
    /// so much as a millisecond, and neither may be abandoned.
    @Test func theStraddledCallsInThreeSubagentsAreNeverShortened() async throws {
        let straddlers = ["toolu_017StzPCoyQd5H8puKZQtS1M", "toolu_01NDyNkE174tDhSxomFqDA63"]
        let entries = try Fixtures.entries("three-subagents")
        #expect(!entries.contains { $0.event?.kind == .permissionRequest },
                "the fixture gained a gate; this test's premise is gone")

        let model = WorldModel()
        var seen: Set<ToolUseID> = []

        for candidate in entries {
            guard let event = candidate.event else { continue }
            await model.ingest(event, at: candidate.receivedAt)

            for agent in await model.snapshot().agents {
                // Nothing is ever marked, on any character, at any point.
                #expect(await model.permissionGateMark(agent.ref) == nil,
                        "\(agent.ref) was marked by \(event.kind.name)")
                for call in agent.openCalls where straddlers.contains(call.toolUseID) {
                    seen.insert(call.toolUseID)
                    #expect(call.deadline == call.startedAt.addingTimeInterval(
                        Reaper.deadlineInterval(forTool: call.toolName)),
                            "\(call.toolUseID) was shortened after \(event.kind.name)")
                }
            }
        }

        #expect(seen == Set(straddlers), "the fixture no longer holds both straddled calls")
        // Both closed normally, by their own `PostToolUse`. Nothing was reaped.
        #expect(await model.abandonedTotal == 0)
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// The other side of the same coin: a prompt only ever reaches the agent it
    /// is addressed to. Every `UserPromptSubmit` in every fixture carries no
    /// `agent_id`, so it is the main thread's by the identity rule: a
    /// subagent's marked calls could not be shortened by one even if a subagent
    /// gate existed.
    @Test func aPromptOnlyEverAnswersItsOwnAgentsGate() async throws {
        for name in Fixtures.all {
            for candidate in try Fixtures.entries(name)
            where candidate.event?.kind == .userPromptSubmit {
                #expect(candidate.event?.agentID == .mainThread,
                        "\(name): a UserPromptSubmit carried an agent_id")
            }
        }
    }

    // MARK: Reapability [I4] - the marker must not leak

    /// It is one more open state, so it answers to the same three paths as
    /// every other one. `SessionEnd` takes the character and the mark with it.
    @Test func sessionEndClearsAnArmedMark() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()
        try await feed(model, entries, through: "PermissionRequest")
        #expect(await model.permissionGateMark(main) == [Self.deniedCall])

        let end = try entry(entries, "SessionEnd")
        await model.ingest(try #require(end.event), at: end.receivedAt)
        #expect(await model.permissionGateMark(main) == nil)
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// And the session-idle sweep, which departs the character entirely.
    ///
    /// The timeout is shortened for this test so that the idle path is the one
    /// under test: at the real 30 minutes the gated `Bash`'s own 900 s deadline
        // fires first, and reaping a marked call disarms the mark by rule 2, true,
    /// and belt and braces, but it would mean this test never exercised the
    /// sweep it is named after. [I4]
    @Test func theIdleSweepClearsAnArmedMark() async throws {
        let (entries, main) = try permissionPrompt()
        let reaper = Reaper(sessionIdleTimeout: 60)
        let model = WorldModel(reaper: reaper)
        let gateAt = try await feed(model, entries, through: "PermissionRequest")
        #expect(await model.permissionGateMark(main) != nil)

        // Just short of the timeout it is still armed, which is true: nothing
        // has happened.
        await model.sweep(at: gateAt.addingTimeInterval(reaper.sessionIdleTimeout - 1))
        #expect(await model.permissionGateMark(main) != nil)
        #expect(await model.snapshot().totalOpenCalls == 1)

        await model.sweep(at: gateAt.addingTimeInterval(reaper.sessionIdleTimeout))
        #expect(await model.permissionGateMark(main) == nil)
        #expect(await model.snapshot().agents.isEmpty)
    }

    /// **And `SubagentStop`, which no longer departs the character.**
    ///
    /// This one is a path that did not need naming before. Departure used to
    /// clear the mark by deleting the whole `AgentState`; a subagent that stops
    /// now *keeps* its state, so if nothing disarmed the mark it would carry an
    /// armed gate into dormancy for the rest of the session and be badged by a
    /// later `permission_prompt` it has nothing to do with. [I1]
    ///
    /// The abandon path hides this in the ordinary case: `SubagentStop`
    /// abandons the agent's open calls, and abandoning a *marked* call disarms
    /// by rule 2. The case it does not cover is the legal empty mark: a snapshot
    /// of an open-call set that happened to be empty. So this test builds
    /// exactly that, from real payloads, by feeding
    /// `fixtures/concurrent-permission-gates.jsonl` **without** the `PreToolUse`
    /// at t=6.434 that opens the gated `Bash`. What is left is the real capture
    /// minus one line; no payload is invented.
    ///
    /// The disarm is independently correct rather than merely convenient: it is
    /// ADR-001 (d) rule 2 read for a subagent. `Stop` disarms the main thread's
    /// mark because the turn completed, and `SubagentStop` is that same fact.
    @Test func aSubagentGoingDormantDisarmsItsMark() async throws {
        let entries = try Fixtures.entries("concurrent-permission-gates")
        let first = try #require(entries.first?.event)
        let gated = AgentRef(
            project: first.cwd, session: first.sessionID,
            agent: .subagent("ac26da513c96ad388"))
        let stillGated = AgentRef(
            project: first.cwd, session: first.sessionID,
            agent: .subagent("a7298874eca5a457d"))
        let main = AgentRef(project: first.cwd, session: first.sessionID, agent: .mainThread)

        let model = WorldModel()
        var reachedStop = false
        var stopDeltas: [WorldDelta] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            // Drop only this agent's gated `PreToolUse`, so its mark arms over
            // an empty open-call set (legal, documented, and the one shape the
            // abandon path cannot disarm).
            if case let .preToolUse(_, tool, _) = event.kind,
               tool == "Bash", event.agentID == gated.agent { continue }
            let deltas = await model.ingest(event, at: entry.receivedAt)
            if event.kind.name == "SubagentStop", event.agentID == gated.agent {
                reachedStop = true
                stopDeltas = deltas
                break
            }
        }
        #expect(reachedStop, "the fixture no longer stops this subagent")
        // And it says so, ahead of the report beat it rides with: the turn is
        // over, so the gate is over, so the body may move again, which for this
        // character means the walk to its parent it is about to play.
        // [ADR-005 §7]
        #expect(stopDeltas.map(\.tag)
            == ["gateChanged", "reportDelivered", "dormancyChanged"])

        // Dormant, in the room, and carrying nothing.
        #expect(await model.snapshot().agent(gated)?.lifecycle == .dormant)
        #expect(await model.permissionGateMark(gated) == nil)
        // The other gate is untouched: it is genuinely still open, and the mark
        // was always per-agent rather than per-session. That scoping is what
        // makes this a one-line change instead of a rule.
        #expect(await model.permissionGateMark(stillGated) != nil)

        // So the next `permission_prompt` badges the agent still at a dialog and
        // not the dormant one.
        let notification = try entry(entries, "Notification", skipping: 1)
        await model.ingest(try #require(notification.event), at: notification.receivedAt)
        #expect(await model.snapshot().agent(stillGated)?.attention == .permissionPrompt)
        #expect(await model.snapshot().agent(gated)?.attention == nil)
        #expect(await model.snapshot().agent(main)?.attention == nil)
    }

    // MARK: The delta [ADR-005 §7]

    /// **The approve path closes the gate, and the delta says so before the
    /// close it rode in on.**
    ///
    /// This is the ordinary release: the human clicks yes, the gated call's own
    /// `PostToolUse` arrives, and `removeCall` disarms. The order (gate clear,
    /// then `callClosed`) is the one `clearsAttention` already reads in: the
    /// wait ended, then the work did.
    @Test func theApprovingCloseClearsTheGateAndSaysSo() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()
        try await feed(model, entries, through: "PermissionRequest", skipping: 1)

        let close = try entry(entries, "PostToolUse")
        let deltas = await model.ingest(try #require(close.event), at: close.receivedAt)
        #expect(deltas.map(\.tag) == ["gateChanged", "callClosed"])
        #expect(deltas.first == .gateChanged(agent: main, isGated: false))
        #expect(await model.permissionGateMark(main) == nil)
        #expect(await model.snapshot().agent(main)?.isGated == false)
    }

    /// **The deny path closes it too, at the prompt that answers the dialog.**
    ///
    /// Rule 3 shortens deadlines and closes nothing, so before this delta
    /// existed there was no moment at which anything downstream learned the human
    /// had answered "no": the character would have gone on standing still until
    /// the reaper abandoned the call 60 s later. The prompt is the answer, so the
    /// gate ends there.
    @Test func theAnsweringPromptClearsTheGate() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel()
        try await feed(model, entries, through: "PermissionRequest")

        let prompt = try entry(entries, "UserPromptSubmit", skipping: 1)
        let deltas = await model.ingest(try #require(prompt.event), at: prompt.receivedAt)
        #expect(deltas.contains(.gateChanged(agent: main, isGated: false)))
        #expect(await model.permissionGateMark(main) == nil)
        // Shortened, never closed: the call is still open and still that agent's.
        #expect(await model.snapshot().agent(main)?.openCalls.count == 1)
        // And the abandon that follows 60 s later emits no second clear: the
        // gate closed once, at the answer.
        let orphan = try #require(await model.snapshot().agent(main)?.openCalls.first)
        let swept = await model.sweep(at: orphan.deadline)
        #expect(!swept.contains { $0.tag == "gateChanged" })
    }

    /// **A reaped gated call clears it as well**, which is the path that has to
    /// hold when the human never answers at all: the deadline expires, the call
    /// is abandoned, and the same `removeCall` disarms. Otherwise a character
    /// frozen by a gate would stay frozen with nothing left to unfreeze it:
    /// I4's *types forever* with the sign flipped.
    @Test func abandoningAGatedCallClearsTheGate() async throws {
        let (entries, main) = try permissionPrompt()
        let model = WorldModel(reaper: Reaper(sessionIdleTimeout: 24 * 60 * 60))
        try await feed(model, entries, through: "PermissionRequest")
        let orphan = try #require(await model.snapshot().agent(main)?.openCalls.first)

        let swept = await model.sweep(at: orphan.deadline)
        #expect(swept.map(\.tag) == ["gateChanged", "callAbandoned"])
        #expect(swept.first == .gateChanged(agent: main, isGated: false))
        #expect(await model.snapshot().agent(main)?.isGated == false)
    }

    /// **[I4] Every gate that opens in every fixture is closed, or its character
    /// leaves.** The balance check, over all eighteen captures and both sweeps.
    ///
    /// §7 claims the mark reaps for free because it lives inside `AgentState`.
    /// That is true of the *mark* and it is `nothingIsMarkedOnceEveryFixtureHas
    /// Finished` below that checks it. It is **not** automatically true of the
    /// delta stream, which is what the scene actually holds: a scene told
    /// `gateChanged(true)` and never told anything else draws a character frozen
    /// forever, and it would be frozen by a fact the model had already forgotten.
    /// So this walks the stream instead of the model, and the only two
    /// acceptable endings for an open gate are a `gateChanged(false)` and an
    /// `agentDeparted`.
    ///
    /// It also pins the corpus: **nine gates open across the eighteen files**,
    /// and two of them are still open when their stream ends: the pair in
    /// `concurrent-permission-gates`, one of which never sees a human at all.
    ///
    /// Both of those two are nonetheless closed by a `gateChanged(false)` rather
    /// than by their character walking out, and that is worth recording because
    /// it was not the expected answer: the idle sweep ends the session, ending
    /// the session abandons the agent's open calls, and abandoning a *marked*
    /// call disarms the mark through the same `removeCall` every other close
    /// path uses. The departure ending is therefore reachable only for a gate
    /// whose marked set is empty or already closed, which no capture contains:
    /// so `closedByDeparture` is 0 and the branch is kept for the shape rather
    /// than for the corpus.
    @Test func everyGateThatOpensIsClosedOrItsCharacterLeaves() async throws {
        var opened = 0
        var closedByDeparture = 0

        for name in Fixtures.all {
            let (model, deltas, entries) = try await Fixtures.replay(name)
            var gated: Set<AgentRef> = []

            for delta in deltas {
                switch delta {
                case let .gateChanged(agent, isGated):
                    if isGated {
                        #expect(!gated.contains(agent),
                                "\(name): \(agent) was told it was gated twice running")
                        gated.insert(agent)
                        opened += 1
                    } else {
                        #expect(gated.contains(agent),
                                "\(name): \(agent) was ungated without ever being gated")
                        gated.remove(agent)
                    }
                case let .agentDeparted(agent):
                    if gated.remove(agent) != nil { closedByDeparture += 1 }
                default:
                    break
                }
            }

            // The end of the stream is not the end of the world: two gates in
            // the corpus are genuinely still open there, and the sweep that
            // presumes a silent session dead is what takes them.
            let last = try #require(entries.last?.receivedAt)
            for delta in await model.sweep(
                at: last.addingTimeInterval(Reaper().sessionIdleTimeout + 1)) {
                switch delta {
                case let .gateChanged(agent, isGated) where !isGated:
                    gated.remove(agent)
                case let .agentDeparted(agent):
                    if gated.remove(agent) != nil { closedByDeparture += 1 }
                default:
                    break
                }
            }

            #expect(gated.isEmpty, Comment(rawValue:
                "\(name): \(gated.count) character(s) left stopped at a permission gate after"
                + " every close path and both sweeps: a character frozen forever [I4]"))
        }

        #expect(opened == 9, "the corpus's gate count moved: \(opened)")
        #expect(closedByDeparture == 0, Comment(rawValue:
            "\(closedByDeparture) gate(s) ended by their character leaving rather than by a"
            + " clear, true and legal, but no capture produced that shape before, so the"
            + " marked-set-is-empty path has become reachable and wants a look"))
    }

    /// A departing character takes it too. The mark lives inside the agent's
    /// own state, which is what makes all three of these true by construction
    /// rather than by three separate pieces of housekeeping somebody has to
    /// remember.
    ///
    /// **Over all eighteen captures.** It named `Fixtures.required` plus two
    /// interactive files, one of which, `permission-prompt`, had already joined
    /// the required set at ADR-001, so the list was a duplicate and a gap at
    /// once: `concurrent-permission-gates`, the one capture that ends with two
    /// gates outstanding, was in neither.
    @Test func nothingIsMarkedOnceEveryFixtureHasFinished() async throws {
        for name in Fixtures.all {
            let (model, _, entries) = try await Fixtures.replay(name)
            let last = try #require(entries.last?.receivedAt)
            await model.sweep(at: last.addingTimeInterval(Reaper.longestDeadlineInterval + 1))
            for agent in await model.snapshot().agents {
                #expect(await model.permissionGateMark(agent.ref) == nil,
                        "\(name): \(agent.ref) still carries a permission-gate mark")
            }
        }
    }
}
