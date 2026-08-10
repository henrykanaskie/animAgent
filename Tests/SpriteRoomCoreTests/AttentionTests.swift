import Foundation
import Testing

@testable import SpriteRoomCore

/// `Notification` → the attention badge, and the rule that takes it away
/// again.
///
/// Driven by the two M0c captures — `permission-prompt` and `idle-notification`
/// — which are real interactive sessions recorded under a pty. They are not in
/// the required six (that list is a signed-off exit criterion), but they are
/// ground truth and they are the only captures containing a `Notification` at
/// all.
@Suite struct AttentionTests {

    // MARK: Decoding

    /// Both values the design assumed are real, and neither carries an
    /// identity beyond the session.
    @Test func bothNotificationTypesDecodeFromTheirRealPayloads() throws {
        let permission = try Fixtures.entries("permission-prompt")
            .compactMap(\.event)
            .filter { if case .notification = $0.kind { return true } else { return false } }
        #expect(permission.count == 2)
        for event in permission {
            #expect(event.kind == .notification(attention: .permissionPrompt))
            // No `agent_id` key at all, which by rule 3 *is* the main thread.
            #expect(event.agentID == .mainThread)
        }

        let idle = try Fixtures.entries("idle-notification")
            .compactMap(\.event)
            .filter { if case .notification = $0.kind { return true } else { return false } }
        #expect(idle.count == 1)
        #expect(idle.first?.kind == .notification(attention: .idlePrompt))
        #expect(idle.first?.agentID == .mainThread)
    }

    /// It carries no `tool_use_id`, so it can never be joined to a call. The
    /// badge is a property of the *character*, not of any open call.
    @Test func aNotificationNamesNoToolCall() throws {
        for name in ["permission-prompt", "idle-notification"] {
            for entry in try Fixtures.entries(name) {
                guard case .notification = entry.event?.kind else { continue }
                let object = try JSONSerialization.jsonObject(with: entry.payload)
                let keys = Set(((object as? [String: Any]) ?? [:]).keys)
                #expect(!keys.contains("tool_use_id"), "\(name): Notification gained a tool_use_id")
                #expect(!keys.contains("agent_id"), "\(name): Notification gained an agent_id")
                #expect(keys.contains("notification_type"))
            }
        }
    }

    /// An unrecognised `notification_type` still means "this session wants
    /// you" — the same fact the one glyph asserts — so it still badges. The
    /// raw value is kept rather than discarded. [I1]
    @Test func anUnrecognisedNotificationTypeIsCarriedVerbatim() {
        #expect(AttentionKind(notificationType: "some_future_type")
            == .other("some_future_type"))
        #expect(AttentionKind(notificationType: nil) == .other(nil))
        #expect("\(AttentionKind(notificationType: "some_future_type"))" == "some_future_type")
    }

    // MARK: Raising

    /// The badge goes up on the main agent, once per notification.
    @Test func aPermissionPromptRaisesTheBadgeOnTheMainAgent() async throws {
        let (_, deltas, _) = try await Fixtures.replay("permission-prompt")
        let raises = deltas.compactMap { delta -> AgentRef? in
            guard case let .attentionChanged(agent, attention) = delta,
                  attention == .permissionPrompt else { return nil }
            return agent
        }
        #expect(raises.count == 2)
        #expect(raises.allSatisfy { $0.agent == .mainThread })
    }

    /// A character can be holding an open call *and* be waiting on a human.
    /// That is not an edge case — it is what every permission prompt looks
    /// like, since `PermissionRequest` lands ~16 ms after `PreToolUse` and the
    /// call then sits at the gate.
    @Test func attentionAndAnOpenCallCoexist() async throws {
        let entries = try Fixtures.entries("permission-prompt")
        let model = WorldModel()
        var sawBoth = false
        for entry in entries {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            for agent in await model.snapshot().agents where agent.attention != nil {
                if agent.isWorking { sawBoth = true }
            }
        }
        #expect(sawBoth, "no moment in the capture had a badge up and a call open")
    }

    // MARK: Clearing — the rule

    /// **The clear rule, measured against the capture that produced it.**
    ///
    /// There is no "notification answered" event, so the badge is cleared by
    /// the next consumed event from the same agent. In this fixture that is
    /// each of the two shapes a user actually produces:
    ///
    /// - the **approved** call's notification is cleared by its own
    ///   `PostToolUse`, 1.81 s later;
    /// - the **denied** call's notification is cleared by the user's next
    ///   `UserPromptSubmit`, 49.37 s later — because a denial emits nothing at
    ///   all, not even a `Stop` for its turn.
    ///
    /// The second number is the cost of the rule, stated rather than hidden:
    /// between clicking "No" and typing again, the badge asserts a wait that
    /// has ended. Nothing in 2.1.224 observes that click —
    /// `PermissionDenied` has never fired on either denial path — so no rule
    /// can do better without an event that does not exist.
    @Test func theBadgeClearsOnTheNextEventAndTheseAreTheDurations() async throws {
        let entries = try Fixtures.entries("permission-prompt")
        let model = WorldModel()

        var raisedAt: Date?
        var durations: [TimeInterval] = []
        var clearedBy: [String] = []

        for entry in entries {
            guard let event = entry.event else { continue }
            for delta in await model.ingest(event, at: entry.receivedAt) {
                guard case let .attentionChanged(_, attention) = delta else { continue }
                if attention != nil {
                    raisedAt = entry.receivedAt
                } else if let raised = raisedAt {
                    durations.append(entry.receivedAt.timeIntervalSince(raised))
                    clearedBy.append(event.kind.name)
                    raisedAt = nil
                }
            }
        }

        #expect(clearedBy == ["UserPromptSubmit", "PostToolUse"])
        #expect(durations.count == 2)
        // Denied: cleared by the user's next prompt. Approved: by the call's
        // own close. Pinned to a tenth of a second so a change in the rule
        // cannot be absorbed silently.
        #expect(abs(durations[0] - 49.370) < 0.1, "denied-path duration \(durations[0])")
        #expect(abs(durations[1] - 1.814) < 0.1, "approved-path duration \(durations[1])")
    }

    /// Nothing is left raised at the end of either capture.
    @Test(arguments: ["permission-prompt", "idle-notification", "interactive-session"])
    func noBadgeSurvivesTheEndOfAStream(name: String) async throws {
        let (model, deltas, _) = try await Fixtures.replay(name)
        #expect(await model.snapshot().agents.allSatisfy { $0.attention == nil })

        // And every raise in the stream had a matching clear or a departure.
        var raised = false
        for delta in deltas {
            switch delta {
            case let .attentionChanged(_, attention): raised = attention != nil
            case .agentDeparted: raised = false
            default: break
            }
        }
        #expect(!raised, "\(name) ended with an attention badge still up")
    }

    /// `idle_prompt` lands a full minute after `Stop`, and once within an idle
    /// stretch however long that stretch lasts. It means "waiting a while", not
    /// "waiting" — nothing may drive a live idle state off it.
    ///
    /// **Once per stretch, not once per session** — see
    /// `idlePromptFiresOncePerIdleStretchNotOncePerSession` below. This capture
    /// holds a single stretch, which is why one is the right number *here*.
    @Test func idlePromptArrivesAMinuteAfterStopAndOnceWithinTheStretch() async throws {
        let entries = try Fixtures.entries("idle-notification")
        let stop = try #require(entries.first { $0.event?.kind == .stop })
        let notifications = entries.filter {
            if case .notification = $0.event?.kind { return true } else { return false }
        }
        #expect(notifications.count == 1)
        let gap = try #require(notifications.first).receivedAt.timeIntervalSince(stop.receivedAt)
        #expect(abs(gap - 60.021) < 0.1, "idle_prompt arrived \(gap)s after Stop")

        // `Stop` raises no badge. It ends the turn and stands the character up
        // [ADR-005 §3] — that is the whole of its news, and it is on a different
        // channel: the posture says *no turn in progress*, and the badge would
        // say *the room needs you*, which nothing yet does. The `idle_prompt`
        // that does say it is still 60 s away.
        let model = WorldModel()
        for entry in entries.prefix(while: { $0.event?.kind != .stop }) {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
        }
        let onStop = await model.ingest(try #require(stop.event), at: stop.receivedAt)
        #expect(onStop.map(\.tag) == ["turnChanged"], Comment(rawValue:
            "a Stop emitted \(onStop.map(\.tag)) — only the turn end belongs to it"))
        #expect(await model.snapshot().agents.allSatisfy { $0.attention == nil })
    }

    /// **`idle_prompt` fires once per idle *stretch*, not once per session.**
    ///
    /// `03-EVENT-MODEL.md` said "exactly once", sourced from an M0c session that
    /// contained one idle stretch and was left idle a further 145 s without a
    /// repeat. The non-repeat *within* a stretch is right; "once" read as once
    /// per session is not. `fixtures/denial-then-work.jsonl` settles it: two,
    /// 60.03 s and 60.02 s after each of two `Stop`s, with real work in between.
    ///
    /// Nothing in the model assumed at-most-once, and this pins that. Each
    /// stretch raises its own badge because the user's prompt cleared the
    /// previous one first; `setAttention`'s idempotence only suppresses a repeat
    /// of a badge that is *still up*, which is a different fact.
    @Test func idlePromptFiresOncePerIdleStretchNotOncePerSession() async throws {
        let entries = try Fixtures.entries("denial-then-work")
        let idles = entries.filter { $0.event?.kind == .notification(attention: .idlePrompt) }
        #expect(idles.count == 2, "the two idle stretches are the point of this test")

        let stops = entries.filter { $0.event?.kind == .stop }
        #expect(stops.count >= 2)
        for (stop, idle) in zip(stops, idles) {
            let gap = idle.receivedAt.timeIntervalSince(stop.receivedAt)
            #expect(abs(gap - 60.02) < 0.1, "idle_prompt arrived \(gap)s after its Stop")
        }

        // Both raise, and each is cleared by the user coming back before the
        // next one arrives. Two raises, two clears, in order.
        let (_, deltas, _) = try await Fixtures.replay("denial-then-work")
        let idleBadges = deltas.compactMap { delta -> Bool? in
            guard case let .attentionChanged(_, attention) = delta else { return nil }
            return attention != nil
        }
        #expect(idleBadges.filter { $0 }.count == 3, "one permission prompt and two idle ones")
        #expect(idleBadges == [true, false, true, false, true, false])
    }

    /// `SessionEnd` takes the character and the badge with it. No separate
    /// clear delta: a badge on a character that no longer exists is not a
    /// state.
    @Test func sessionEndRemovesTheBadgeWithTheCharacter() async throws {
        let (model, deltas, _) = try await Fixtures.replay("idle-notification")
        let tags = deltas.map(\.tag)
        #expect(tags == [
            "agentAppeared", "populationChanged",   // UserPromptSubmit
            "turnChanged",                          // Stop, 1.7 s later [ADR-005 §3]
            "attentionChanged",                     // Notification, 60 s after Stop
            "agentDeparted", "populationChanged",   // SessionEnd
        ])
        #expect(await model.snapshot().agents.isEmpty)
    }

    // MARK: Raising — *which* character, when the notification names none

    /// The subagent id whose `Bash` sits at the dialog in
    /// `fixtures/subagent-permission.jsonl`.
    static let gatedSubagent = AgentID.subagent("ab2378e6a85dea269")

    /// The refs of one fixture's session, and its entries.
    private func session(
        _ name: String
    ) throws -> (entries: [HookLogEntry], main: AgentRef) {
        let entries = try Fixtures.entries(name)
        let first = try #require(entries.first?.event)
        return (entries, AgentRef(
            project: first.cwd, session: first.sessionID, agent: .mainThread))
    }

    private func ref(_ main: AgentRef, _ agent: AgentID) -> AgentRef {
        AgentRef(project: main.project, session: main.session, agent: agent)
    }

    /// **The mismatch that made the badge fiction, stated from the payloads.**
    ///
    /// `PermissionRequest` carries the gated agent's `agent_id`;  the
    /// `Notification` that follows it 6.016 s later carries none at all. Read
    /// through the identity rule alone the second one is a main-thread event, so
    /// the badge landed on the main character while the agent actually stuck at
    /// the dialog was a subagent. [I1]
    @Test func aSubagentsGateAndItsNotificationDisagreeAboutWhoIsBlocked() throws {
        let (entries, _) = try session("subagent-permission")
        let gate = try #require(entries.first { $0.event?.kind == .permissionRequest })
        let notification = try #require(entries.first {
            if case .notification = $0.event?.kind { return true } else { return false }
        })

        #expect(gate.event?.agentID == Self.gatedSubagent)
        #expect(notification.event?.agentID == .mainThread)
        #expect(notification.event?.kind == .notification(attention: .permissionPrompt))
        let delay = notification.receivedAt.timeIntervalSince(gate.receivedAt)
        #expect(abs(delay - 6.016) < 0.1, "notification arrived \(delay)s after the gate")
    }

    /// **One marked agent: the badge goes on the agent that is actually
    /// blocked.**
    ///
    /// And the main thread does not get one — which matters here more than
    /// usual, because in this capture the main thread is genuinely working: its
    /// `Agent` call ran synchronously and is open for the child's whole life, so
    /// under the old rule the main character wore "needs your permission" over a
    /// call that was running fine.
    @Test func oneMarkedAgentTakesTheBadgeAndTheMainThreadDoesNot() async throws {
        let (entries, main) = try session("subagent-permission")
        let child = ref(main, Self.gatedSubagent)
        let model = WorldModel()

        for entry in entries {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            if case .notification = event.kind { break }
        }

        let snapshot = await model.snapshot()
        #expect(snapshot.agent(child)?.attention == .permissionPrompt)
        #expect(snapshot.agent(main)?.attention == nil)
        // The main character is working, truthfully, and shows a tool badge.
        #expect(snapshot.agent(main)?.isWorking == true)
    }

    /// **Zero marked agents: the main thread, exactly as before.**
    ///
    /// The same capture with its `PermissionRequest` withheld, which is not a
    /// hypothetical shape — it is what every session looked like before ADR-001
    /// consumed that event, and what one still looks like if the registration is
    /// missing from `~/.claude/settings.json`. The notification did happen and
    /// nothing tells us whose it is, so the main agent is the honest default
    /// rather than a guess. [I1]
    @Test func withNothingMarkedTheBadgeFallsBackToTheMainThread() async throws {
        let (entries, main) = try session("subagent-permission")
        let child = ref(main, Self.gatedSubagent)
        let model = WorldModel()

        for entry in entries {
            guard let event = entry.event, event.kind != .permissionRequest else { continue }
            await model.ingest(event, at: entry.receivedAt)
            if case .notification = event.kind { break }
        }

        #expect(await model.permissionGateMark(child) == nil)
        #expect(await model.snapshot().agent(main)?.attention == .permissionPrompt)
        #expect(await model.snapshot().agent(child)?.attention == nil)
    }

    /// **Several marked agents: every one of them, because every one of them
    /// really is waiting on a human.**
    ///
    /// `fixtures/concurrent-permission-gates.jsonl` — two subagents launched in
    /// one assistant message, gates at t=6.446 and t=7.919, the first answered
    /// at t=38.263. **31.8 s with two gates open**, which is why "attribute it
    /// to the single marked agent" is not a rule that can be written.
    @Test func everyMarkedAgentTakesTheBadgeWhenSeveralGatesAreOpen() async throws {
        let (entries, main) = try session("concurrent-permission-gates")
        let model = WorldModel()

        var raises: [AgentRef] = []
        for entry in entries {
            guard let event = entry.event else { continue }
            for delta in await model.ingest(event, at: entry.receivedAt) {
                if case let .attentionChanged(agent, .some(.permissionPrompt)) = delta {
                    raises.append(agent)
                }
            }
            if case .notification = event.kind { break }
        }

        #expect(raises.count == 2, "two gates were open; got \(raises)")
        #expect(raises.allSatisfy { $0.agent != .mainThread })
        #expect(Set(raises).count == 2)
        #expect(await model.snapshot().agent(main)?.attention == nil)
        // Deterministic order, so the delta stream is reproducible. [I3]
        #expect(raises == raises.sorted())
    }

    /// **The clear rule when the badge is on a subagent — it did not have to
    /// change, and this is the test that says so.**
    ///
    /// "The next consumed event from the same agent" was already agent-scoped.
    /// With a badge on a gated subagent that reads: the approval closes the
    /// child's own `Bash`, and that close takes the child's badge down. 5.5 s
    /// here, against the 1.81 s the main-thread approve path measures — the
    /// difference is the `PostToolUse` landing later, not a different rule.
    ///
    /// Main-thread traffic in between must not clear it, which is the same
    /// restriction that stops subagent traffic clearing the main thread's badge,
    /// read in the other direction.
    @Test func aSubagentsBadgeClearsOnTheSubagentsOwnNextEvent() async throws {
        let (entries, main) = try session("subagent-permission")
        let child = ref(main, Self.gatedSubagent)
        let model = WorldModel()

        var raisedAt: Date?
        var clearedAt: Date?
        var clearedBy: String?
        for entry in entries {
            guard let event = entry.event else { continue }
            for delta in await model.ingest(event, at: entry.receivedAt) {
                guard case let .attentionChanged(agent, attention) = delta,
                      agent == child else { continue }
                if attention != nil {
                    raisedAt = entry.receivedAt
                } else {
                    clearedAt = entry.receivedAt
                    clearedBy = event.kind.name
                }
            }
            // The main thread never wore it at any point in the stream.
            #expect(await model.snapshot().agent(main)?.attention == nil,
                    "\(event.kind.name) put the badge on the main character")
        }

        let raised = try #require(raisedAt)
        let cleared = try #require(clearedAt)
        #expect(clearedBy == "PostToolUse")
        #expect(abs(cleared.timeIntervalSince(raised) - 5.525) < 0.1,
                "subagent approve-path duration \(cleared.timeIntervalSince(raised))")
    }

    /// The other half of the concurrent case: answering one gate takes down one
    /// badge and leaves the other up, because the other agent is still at a
    /// dialog. A session-scoped badge could not express this.
    @Test func answeringOneOfTwoGatesClearsOnlyThatAgentsBadge() async throws {
        let (entries, main) = try session("concurrent-permission-gates")
        let model = WorldModel()
        for entry in entries {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            // Stop just after the first gate is answered.
            if case .postToolUse = event.kind, event.agentID != .mainThread { break }
        }

        let badged = await model.snapshot().agents.filter { $0.attention != nil }
        #expect(badged.count == 1, "expected one badge left up, got \(badged.map(\.ref))")
        let stillWaiting = try #require(badged.first?.ref)
        #expect(stillWaiting.agent == .subagent("a7298874eca5a457d"))
        // Still badged because still marked: it is genuinely at a dialog.
        #expect(await model.permissionGateMark(stillWaiting) != nil)
        #expect(await model.snapshot().agent(main)?.attention == nil)
    }

    /// `idle_prompt` is about the session sitting at the prompt, not about a
    /// gated call, so it stays on the main thread even while a subagent's gate
    /// is marked. Unrecognised types go the same way, for the same reason: we
    /// know an alert fired, we do not know it is a gate.
    @Test func idlePromptStaysOnTheMainThreadEvenWithAGateMarked() async throws {
        let (entries, main) = try session("subagent-permission")
        let child = ref(main, Self.gatedSubagent)
        let armed = WorldModel()

        // Stop at the gate: the subagent is marked, nothing is badged yet.
        var gateAt: Date?
        for entry in entries {
            guard let event = entry.event else { continue }
            await armed.ingest(event, at: entry.receivedAt)
            if event.kind == .permissionRequest { gateAt = entry.receivedAt; break }
        }
        let lastAt = try #require(gateAt)
        #expect(await armed.permissionGateMark(child) != nil)

        // The real `idle_prompt` payload from `idle-notification`, routed into
        // this session by the one sanctioned rewrite helper. Only its address
        // changes; no capture holds an idle prompt during a subagent gate.
        let idlePayload = try #require(try Fixtures.firstEntry("idle-notification") {
            $0.kind == .notification(attention: .idlePrompt)
        }).payload
        let idle = try #require(Fixtures.rewriting(idlePayload, [
            "session_id": main.session, "cwd": main.project,
        ]))
        await armed.ingest(idle, at: lastAt.addingTimeInterval(60))

        #expect(await armed.snapshot().agent(main)?.attention == .idlePrompt)
        #expect(await armed.snapshot().agent(child)?.attention == nil)
        // The mark is untouched: a badge decision is not a gate decision.
        #expect(await armed.permissionGateMark(child) != nil)
    }

    // MARK: Clearing — what must *not* clear it

    /// **A subagent's traffic must not clear the main thread's badge.**
    ///
    /// This is the case the "same agent, not same session" restriction exists
    /// for, and it is not hypothetical: an async subagent emits a
    /// `PreToolUse`/`PostToolUse` every few hundred milliseconds into the same
    /// `session_id` while the main thread sits at a dialog. Without the
    /// restriction the badge would be wiped roughly instantly, every time.
    ///
    /// Built by routing the *real* `Notification` payload from
    /// `permission-prompt` into `three-subagents`' session — the only capture
    /// with concurrent subagent traffic — via the one sanctioned rewrite
    /// helper. Nothing about the event is invented; only its address.
    @Test func subagentEventsDoNotClearTheMainThreadsBadge() async throws {
        let subagentRun = try Fixtures.entries("three-subagents")
        let host = try #require(subagentRun.first?.event)

        let notificationPayload = try #require(
            try Fixtures.firstEntry("permission-prompt") {
                if case .notification = $0.kind { return true } else { return false }
            }).payload
        let notification = try #require(Fixtures.rewriting(notificationPayload, [
            "session_id": host.sessionID,
            "cwd": host.cwd,
        ]))
        #expect(notification.agentID == .mainThread)

        let model = WorldModel()
        let mainRef = AgentRef(project: host.cwd, session: host.sessionID, agent: .mainThread)

        // Everything up to and including the turn's `Stop`: three subagents
        // are live and working by then.
        var index = 0
        let entries = subagentRun
        while index < entries.count {
            guard let event = entries[index].event else { index += 1; continue }
            await model.ingest(event, at: entries[index].receivedAt)
            index += 1
            if event.kind == .stop { break }
        }

        let raised = await model.ingest(notification, at: entries[index - 1].receivedAt)
        #expect(raised.map(\.tag) == ["attentionChanged"])
        #expect(await model.snapshot().agent(mainRef)?.attention == .permissionPrompt)

        // Now every subagent event up to the next main-thread one. In this
        // capture that is seventeen events across three different subagents,
        // including a `SubagentStop`.
        var subagentEvents = 0
        while index < entries.count, let event = entries[index].event,
              event.agentID != .mainThread {
            await model.ingest(event, at: entries[index].receivedAt)
            subagentEvents += 1
            index += 1
            #expect(await model.snapshot().agent(mainRef)?.attention == .permissionPrompt,
                    "\(event.kind.name) from \(event.agentID) cleared the main thread's badge")
        }
        #expect(subagentEvents >= 10, "expected a run of subagent traffic, got \(subagentEvents)")

        // The next main-thread event is the one that clears it.
        let next = try #require(entries[index].event)
        #expect(next.agentID == .mainThread)
        let cleared = await model.ingest(next, at: entries[index].receivedAt)
        #expect(cleared.contains { $0.attentionChange == .some(AttentionKind?.none) })
        #expect(await model.snapshot().agent(mainRef)?.attention == nil)
    }

    /// An unhandled event changes nothing at all — including this. It matters
    /// concretely: `PermissionRequest` is unhandled and arrives 6 s *before*
    /// the `Notification` it precedes, so a rule that cleared on any event
    /// would still be fine there, but a `PermissionRequest` for a *second*
    /// gated call would erase a badge that is still true.
    @Test func anUnhandledEventDoesNotClearTheBadge() async throws {
        let entries = try Fixtures.entries("permission-prompt")
        let model = WorldModel()
        var mainRef: AgentRef?

        for entry in entries {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            if case .notification = event.kind {
                mainRef = AgentRef(
                    project: event.cwd, session: event.sessionID, agent: .mainThread)
                break
            }
        }
        let ref = try #require(mainRef)
        #expect(await model.snapshot().agent(ref)?.attention == .permissionPrompt)

        // A real captured payload from this same session, renamed to something
        // 2.1.224 emits and we do not consume.
        let firstPayload = try #require(entries.first).payload
        let stray = try #require(
            Fixtures.rewritingEventName(firstPayload, to: "UserPromptExpansion"))
        let deltas = await model.ingest(stray, at: Date())
        #expect(deltas.isEmpty)
        #expect(await model.snapshot().agent(ref)?.attention == .permissionPrompt)
    }

    /// Two identical notifications are one fact. A repeat must not produce a
    /// second badge change — otherwise the scene's suppression memory is the
    /// only thing between a stable badge and a flicker.
    @Test func aRepeatedNotificationEmitsNothing() async throws {
        let entry = try #require(try Fixtures.firstEntry("idle-notification") {
            if case .notification = $0.kind { return true } else { return false }
        })
        let event = try #require(entry.event)
        let model = WorldModel()
        await model.ingest(event, at: entry.receivedAt)
        let again = await model.ingest(event, at: entry.receivedAt.addingTimeInterval(145))
        #expect(again.isEmpty)
    }

    // MARK: Reapability [I4]

    /// **The badge cannot stick forever, and it does not need a deadline of
    /// its own to be reapable.**
    ///
    /// Three paths bound it: the agent's next consumed event, `SessionEnd`,
    /// and the 30-minute session-idle sweep, which departs the character
    /// entirely. A fourth timer was considered and rejected: it would have to
    /// be a number with nothing behind it, and it would make the badge lie by
    /// *omission* in the one case where the true statement is "still waiting"
    /// — an `idle_prompt` badge on a session nobody has come back to is
    /// correct for as long as nobody has come back to it.
    @Test func theBadgeCannotOutliveTheSession() async throws {
        let entries = try Fixtures.entries("idle-notification")
        let model = WorldModel()
        var last = Date()
        for entry in entries where entry.event?.kind.name != "SessionEnd" {
            guard let event = entry.event else { continue }
            await model.ingest(event, at: entry.receivedAt)
            last = entry.receivedAt
        }
        #expect(await model.snapshot().agents.contains { $0.attention == .idlePrompt })

        // Just short of the idle timeout the badge is still up — which is
        // true, because nothing has happened.
        let reaper = Reaper()
        #expect(await model.sweep(
            at: last.addingTimeInterval(reaper.sessionIdleTimeout - 1)).isEmpty)
        #expect(await model.snapshot().agents.contains { $0.attention == .idlePrompt })

        // Past it, the character leaves and takes the badge with it.
        let swept = await model.sweep(at: last.addingTimeInterval(reaper.sessionIdleTimeout))
        #expect(swept.map(\.tag) == ["agentDeparted", "populationChanged"])
        #expect(await model.snapshot().agents.isEmpty)
    }

    // MARK: Regression

    /// Wiring this must not have moved a single delta in the fixtures the
    /// ingest layer is signed off against.
    ///
    /// Stated as an *iff* rather than as "none of them badges", because
    /// `permission-prompt` joined the required set at ADR-001 and it does
    /// contain `Notification`s. The force of the test is unchanged: a badge
    /// delta appears exactly where a `Notification` was captured and nowhere
    /// else, so no fixture can quietly gain or lose one.
    @Test(arguments: Fixtures.required)
    func theRequiredFixturesBadgeExactlyWhereTheyWereCaptured(name: String) async throws {
        let entries = try Fixtures.entries(name)
        let hasNotification = entries.contains {
            if case .notification = $0.event?.kind { return true } else { return false }
        }
        let (_, deltas, _) = try await Fixtures.replay(name)
        #expect(deltas.contains { $0.tag == "attentionChanged" } == hasNotification,
                "\(name): attention deltas and captured Notifications disagree")
    }
}
