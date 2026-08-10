import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **ADR-005 — posture carries the turn.**
///
/// The defect these tests were written against is the maintainer's own report of
/// the shipped app: *"the sprites would be doing something for like 1 second then
/// stopping, then resuming, then stopping"*. `SceneDirector` keyed the body on
/// the open-call set — `openCalls.isEmpty ? .idle : .working` — and `idle` is a
/// **standing** pose, so a character stood up and sat down on every tool-call
/// boundary. The median call in `fixtures/` is 23 ms and the median gap between
/// calls is seconds, so the room asserted that an agent left its workstation
/// 1.3 s after a `Read` and came back 1.4 s later. Nothing said that happened.
///
/// The rule these tests pin instead:
///
/// > A character is seated from any event this app consumes for that agent until
/// > that agent's turn ends. It stands only when it has no turn in progress.
/// > Motion over the seated pose is unchanged to the frame: a character animates
/// > if and only if it holds an open tool call.
struct PostureTests {

    static let project = "/tmp/posture"
    static let session = "s"

    static func ref(_ agent: AgentID) -> AgentRef {
        AgentRef(project: project, session: session, agent: agent)
    }

    static func call(_ id: String, _ tool: String) -> OpenCall {
        OpenCall(toolUseID: id, toolName: tool,
                 startedAt: Date(timeIntervalSinceReferenceDate: 0),
                 deadline: Date(timeIntervalSinceReferenceDate: 900))
    }

    static let origin = Date(timeIntervalSinceReferenceDate: 20_000)

    static func director() -> SceneDirector {
        SceneDirector(variantIDs: ["00", "01", "02", "03", "04", "05"])
    }

    static func bodies(_ intents: [SpriteIntent]) -> [BodyState] {
        intents.compactMap { if case let .setBody(_, state, _) = $0 { return state } else { return nil } }
    }

    // MARK: The defect

    /// **The central test.** Two calls inside one turn, at the corpus's own
    /// median call length (23 ms) and median gap (2.35 s). The character must not
    /// change posture at any point between them: it sat down for the first call
    /// and its turn has not ended.
    ///
    /// Against the rule this replaces, the close emits `setBody(.idle)` 23 ms
    /// after the spawn and the next open emits `setBody(.working)` 2.35 s later —
    /// two changes of the loudest channel in the room, carrying nothing the badge
    /// does not already carry.
    @Test func theBodyDoesNotStandUpBetweenTwoCallsOfOneTurn() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        #expect(director.bodyState(agent) == .working, "the call is open; the character is seated")

        let closed = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin.addingTimeInterval(0.023))
        #expect(director.bodyState(agent) == .working,
                "the character stood up 23 ms after sitting down; no event said it left its desk")
        #expect(Self.bodies(closed).isEmpty,
                "a close emitted \(Self.bodies(closed)) — the turn did not end, so the posture must not move")

        let opened = director.apply(
            [.callOpened(agent: agent, call: Self.call("b", "Bash"))],
            at: Self.origin.addingTimeInterval(2.373))
        #expect(director.bodyState(agent) == .working)
        #expect(Self.bodies(opened).isEmpty,
                "the next call re-seated a character that never stood up")
    }

    /// The same for the other three ways an open-call set can empty without the
    /// turn ending: an abandon, a batch reconcile, and a call closing into a
    /// still-occupied set. None of them is a turn boundary and none of them may
    /// move the body.
    @Test func nothingThatEmptiesTheOpenCallSetStandsACharacterUp() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
            .callOpened(agent: agent, call: Self.call("b", "Bash")),
        ], at: Self.origin)

        let partial = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)
        #expect(Self.bodies(partial).isEmpty, "a close into a non-empty set moved the body")

        let abandoned = director.apply(
            [.callAbandoned(agent: agent, toolUseID: "b", toolName: "Bash", reason: .deadlineExpired)],
            at: Self.origin.addingTimeInterval(900))
        #expect(director.openCallCount(agent) == 0, "the set did not empty; this test proves nothing")
        // The reaper closing our blind spot is not the agent saying it left.
        #expect(director.bodyState(agent) == .working, "a reaped call stood the character up")
        #expect(Self.bodies(abandoned).isEmpty)
    }

    /// An attention badge is a fact about the human, not evidence the agent's
    /// turn ended or resumed. It has never had a body state and it still has
    /// none.
    @Test func attentionDoesNotMoveTheBody() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Bash")),
        ], at: Self.origin)
        let raised = director.apply(
            [.attentionChanged(agent: agent, attention: .permissionPrompt)],
            at: Self.origin.addingTimeInterval(0.016))
        #expect(Self.bodies(raised).isEmpty)
        #expect(director.bodyState(agent) == .working)
    }

    // MARK: The turn boundary that the delta stream carries

    /// `SubagentStop` is the one turn boundary the model emits a delta for —
    /// `dormancyChanged(true)` — and it is what stands a subagent up. The `Z` tab
    /// then sits over a body that agrees with it: standing, still, finished.
    ///
    /// A revival seats it again, which is `SubagentStart` or the subagent's next
    /// `PreToolUse` reaching `WorldModel.ensureAgent`.
    @Test func aSubagentStandsWhenItsTurnEndsAndSitsWhenItIsResumed() {
        var director = Self.director()
        let agent = Self.ref(.subagent("a1234567890abcdef"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning),
        ], at: Self.origin)
        #expect(director.bodyState(agent) == .working,
                "a subagent that has started is in a turn and is at its desk")

        _ = director.apply([
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin.addingTimeInterval(1))
        _ = director.apply([
            .callAbandoned(agent: agent, toolUseID: "a", toolName: "Read", reason: .agentStopped),
            .dormancyChanged(agent: agent, isDormant: true),
        ], at: Self.origin.addingTimeInterval(2))
        #expect(director.bodyState(agent) == .idle, "the turn ended and the character stayed seated")
        #expect(director.badge(agent).isSleeping)

        _ = director.apply([
            .dormancyChanged(agent: agent, isDormant: false),
        ], at: Self.origin.addingTimeInterval(20))
        #expect(director.bodyState(agent) == .working, "a revived subagent is back in a turn")
    }

    /// `turnChanged` is the main agent's boundary and it is the mirror image of
    /// the subagent test above: the character stands when the turn ends and sits
    /// at the next prompt or tool call.
    ///
    /// **The two arms are separate on purpose and no agent can receive both.**
    /// `Stop` never carries an `agent_id` and `SubagentStop` always does.
    @Test func theMainCharacterStandsOnTurnChangedAndSitsOnEitherOpener() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
        ], at: Self.origin)
        #expect(director.bodyState(agent) == .working, "a prompt is the start of a turn")

        let ended = director.apply(
            [.turnChanged(agent: agent, hasTurn: false)],
            at: Self.origin.addingTimeInterval(1.7))
        #expect(director.bodyState(agent) == .idle, "the turn ended and the character stayed seated")
        #expect(Self.bodies(ended) == [.idle])

        // The next prompt. `turnChanged(true)` is the only delta a second
        // `UserPromptSubmit` produces, which is why the delta had to be a `Bool`.
        let prompted = director.apply(
            [.turnChanged(agent: agent, hasTurn: true)],
            at: Self.origin.addingTimeInterval(10))
        #expect(Self.bodies(prompted) == [.working])

        // And the other opener: a `PreToolUse` seats it through `callOpened`,
        // which is the path that was already there.
        _ = director.apply([.turnChanged(agent: agent, hasTurn: false)],
                           at: Self.origin.addingTimeInterval(20))
        let working = director.apply(
            [.turnChanged(agent: agent, hasTurn: true),
             .callOpened(agent: agent, call: Self.call("a", "Bash"))],
            at: Self.origin.addingTimeInterval(30))
        #expect(Self.bodies(working) == [.working], "one setBody, not two: the batch coalesces")
        #expect(director.bodyState(agent) == .working)
    }

    /// A turn ending takes no badge and no motion. It is the posture channel and
    /// nothing else — the same division `gateChanged` keeps in the other
    /// direction, where the motion moves and the posture does not.
    @Test func aTurnEndingTakesNoBadgeAndCancelsNoBeat() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin.addingTimeInterval(0.023))
        #expect(director.badge(agent).badge == .magnifier, "the beat is not armed; nothing to check")

        let ended = director.apply(
            [.turnChanged(agent: agent, hasTurn: false)],
            at: Self.origin.addingTimeInterval(0.1))
        // The glyph stays. A beat says *the last thing this agent did was a
        // read*, which is still true across the turn boundary, and a standing
        // body asserts less ongoing work than a seated one rather than more.
        // [ADR-003 §6 as ADR-005 §5 restated it]
        #expect(director.badge(agent).badge == .magnifier)
        #expect(ended.allSatisfy { if case .setBadge = $0 { return false }; return true },
                "a turn ending moved the badge")
    }

    // MARK: The main agent's turn boundary — ADR-005 §3, correction 1

    /// **The central test of `turnChanged`.** `Stop` is the main thread's turn
    /// boundary and until now it left the model in no form at all, so the main
    /// character sat down at its session's first event and stood up only when it
    /// left. `fixtures/denial-then-work.jsonl` is the case that measures it: four
    /// prompts, three `Stop`s and almost no tool calls, so its character stood
    /// motionless through 157 s of three complete turns.
    ///
    /// Six posture changes, one per real event: sit at each of the three
    /// `UserPromptSubmit`s that open a turn, stand at each of the three `Stop`s
    /// that close one. (The fourth prompt is the one that answers the denial
    /// dialog *inside* a turn already in progress, so it opens nothing.)
    @Test func theMainCharacterStandsWhenItsTurnEndsAndSitsWhenTheUserPrompts() async throws {
        let measured = try await Self.measure("denial-then-work")
        #expect(measured.after == 6, Comment(rawValue:
            "the main character changed posture \(measured.after) times over four prompts and"
            + " three Stops — ADR-005 §3 measures six"))
    }

    /// A turn that uses no tool at all. `fixtures/idle-notification.jsonl` is one
    /// prompt, one `Stop`, one `idle_prompt` 60 s later and a `SessionEnd`: no
    /// `PreToolUse` anywhere in it. Under the open-call rule the body never moved
    /// (0 changes); under the turn rule it sits at the prompt and stands at the
    /// `Stop`.
    ///
    /// This is M4's defect — *an agent that was thinking was invisible* — read on
    /// the body channel rather than on the roster, and it is the half of it that
    /// was left unfinished.
    @Test func aTurnThatCallsNoToolIsStillVisibleOnTheBody() async throws {
        let measured = try await Self.measure("idle-notification")
        #expect(measured.before == 1, Comment(rawValue:
            "under the open-call rule this body is drawn once, standing, and never moves again;"
            + " it moved \(measured.before) times, so the fixture no longer shows what it was"
            + " chosen for"))
        #expect(measured.after == 2, Comment(rawValue:
            "a turn with no tool call drew \(measured.after) posture changes; it should draw two"))
    }

    // MARK: The corpus

    /// One character's posture over one fixture, under both rules.
    struct PostureTrace: Sendable {
        /// Posture changes the scene performs, counting the first one — the
        /// character has to be drawn in *some* posture when it appears.
        var changes = 0
        var lastState: BodyState?
        var lastChangeAt: Date?
        /// Shortest interval between two consecutive posture changes, whatever
        /// posture was held across it.
        var minimumDwell: TimeInterval = .infinity
        /// **The same, split by which posture was being held.** [ADR-005 §3]
        ///
        /// The composite above is the honest headline and it is the wrong number
        /// to *diagnose* with, because the two halves mean opposite things. A
        /// short **standing** interval is the defect: the character stood up and
        /// sat back down, so a turn boundary was drawn where no turn ended —
        /// which is precisely what ADR-005 §9 risk 3 warns `Stop` could produce.
        /// A short **seated** interval is a short *turn*: the user prompted and
        /// the assistant finished, and the room saying so quickly is the room
        /// being right quickly.
        ///
        /// Keeping only the composite is what made this change look like a
        /// regression when it is not: it moves 8.196 → 1.706 s, and every
        /// interval under 4.2 s in the whole corpus is a seated one.
        var minimumDwellHolding: [BodyState: TimeInterval] = [:]

        mutating func observe(_ state: BodyState, at instant: Date) {
            guard state != lastState else { return }
            if let held = lastState, let last = lastChangeAt {
                let dwell = instant.timeIntervalSince(last)
                minimumDwell = min(minimumDwell, dwell)
                minimumDwellHolding[held] = min(minimumDwellHolding[held] ?? .infinity, dwell)
            }
            changes += 1
            lastState = state
            lastChangeAt = instant
        }
    }

    struct FixtureMeasurement: Sendable {
        var before = 0
        var after = 0
        var minimumDwellBefore: TimeInterval = .infinity
        var minimumDwellAfter: TimeInterval = .infinity
        /// After the change only, split by posture. `.idle` is standing,
        /// `.working` is seated at the desk.
        var minimumDwellAfterHolding: [BodyState: TimeInterval] = [:]

        mutating func absorb(_ other: FixtureMeasurement) {
            before += other.before
            after += other.after
            minimumDwellBefore = min(minimumDwellBefore, other.minimumDwellBefore)
            minimumDwellAfter = min(minimumDwellAfter, other.minimumDwellAfter)
            for (state, dwell) in other.minimumDwellAfterHolding {
                minimumDwellAfterHolding[state] =
                    min(minimumDwellAfterHolding[state] ?? .infinity, dwell)
            }
        }

        /// Shortest time any character in this fixture spent **standing** before
        /// sitting back down. `.infinity` when nobody stood and then sat.
        var minimumStandingDwell: TimeInterval { minimumDwellAfterHolding[.idle] ?? .infinity }
        /// Shortest time any character spent **seated** before standing up.
        var minimumSeatedDwell: TimeInterval { minimumDwellAfterHolding[.working] ?? .infinity }
    }

    /// Replays one fixture and measures the posture channel under both rules off
    /// the **same** replay, so they cannot differ in anything but the rule.
    ///
    /// `before` is the rule this change replaces, stated by its definition rather
    /// than by a flag: `openCalls.isEmpty ? .idle : .working`. `after` is what the
    /// director now says. Deltas are batched a frame at a time, which is how the
    /// scene actually receives them, so two events inside one frame produce one
    /// posture rather than two.
    static func measure(_ name: String) async throws -> FixtureMeasurement {
        var director = Self.director()
        var openCalls: [AgentRef: Set<ToolUseID>] = [:]
        var present: Set<AgentRef> = []
        var before: [AgentRef: PostureTrace] = [:]
        var after: [AgentRef: PostureTrace] = [:]

        for batch in try await SceneFixtures.timedBatchedDeltas(name) {
            for delta in batch.deltas {
                switch delta {
                case let .agentAppeared(agent, _, _):
                    present.insert(agent)
                case let .callOpened(agent, call):
                    openCalls[agent, default: []].insert(call.toolUseID)
                case let .callClosed(agent, id, _, _), let .callAbandoned(agent, id, _, _):
                    openCalls[agent]?.remove(id)
                case let .agentDeparted(agent):
                    present.remove(agent)
                    openCalls.removeValue(forKey: agent)
                default:
                    break
                }
            }
            _ = director.apply(batch.deltas, at: batch.at)
            for agent in present.sorted(by: { $0.agent < $1.agent }) {
                let old: BodyState = (openCalls[agent] ?? []).isEmpty ? .idle : .working
                before[agent, default: PostureTrace()].observe(old, at: batch.at)
                guard let new = director.bodyState(agent) else { continue }
                after[agent, default: PostureTrace()].observe(new, at: batch.at)
            }
        }

        var measurement = FixtureMeasurement()
        for trace in before.values {
            measurement.before += trace.changes
            measurement.minimumDwellBefore = min(measurement.minimumDwellBefore, trace.minimumDwell)
        }
        for trace in after.values {
            measurement.after += trace.changes
            measurement.minimumDwellAfter = min(measurement.minimumDwellAfter, trace.minimumDwell)
            for (state, dwell) in trace.minimumDwellHolding {
                measurement.minimumDwellAfterHolding[state] =
                    min(measurement.minimumDwellAfterHolding[state] ?? .infinity, dwell)
            }
        }
        return measurement
    }

    static let corpus = [
        "concurrent-permission-gates", "denial-then-work", "denied-batch-cancel",
        "four-subagents", "idle-notification", "interactive-batch-serial",
        "interactive-session", "killed-session", "parallel-denial", "parallel-tools",
        "permission-prompt", "queued-prompt", "single-agent-simple", "subagent-permission",
        "three-subagents", "tool-failure", "unknown-events",
    ]

    /// **The number the maintainer's complaint is about, over the whole corpus.**
    ///
    /// The complaint is not how *many* posture changes there are; it is how fast
    /// they come. So the binding assertion is on the shortest interval between
    /// two posture changes of one character anywhere in `fixtures/`:
    ///
    /// | | keyed to the call | keyed to the turn | + the main agent's `Stop` |
    /// |---|---:|---:|---:|
    /// | posture changes, all 17 fixtures | 95 | 40 | **73** |
    /// | shortest **standing** dwell | — | 8.196 | **4.226** |
    /// | shortest **seated** dwell | 0.017 | ∞ | **1.706** |
    ///
    /// **0.017 s is one frame and it is a floor imposed by the measurement**,
    /// not by the room: deltas are batched at 1/60 here because that is how the
    /// scene receives them, so two events 3 ms apart land in one batch and the
    /// posture between them is never drawn. On the raw event stream the shortest
    /// seated stint was 0.003 s.
    ///
    /// **The composite minimum moves 8.196 → 1.706 s and that is not the defect
    /// coming back, which is why this test measures the two postures apart.**
    /// Every interval under 4.2 s in the corpus is a **seated** one, and a short
    /// seated interval is a short *turn*: `idle-notification` is one prompt whose
    /// answer took 1.706 s, `three-subagents` has three turns of 1.80–5.23 s.
    /// The room drawing a 1.7 s turn as a 1.7 s seated interval is the room being
    /// right, and it is drawing **one** transition — the character spawns seated,
    /// stands once, and then stands for 119 s.
    ///
    /// The interval that would be the defect is a short **standing** one: a
    /// character that stood up and sat back down means a turn boundary was drawn
    /// where no turn ended, which is ADR-005 §9 risk 3 —  `Stop` fires once per
    /// assistant message stream and can fire several times in one user turn. That
    /// number is **4.226 s**, reproducing ADR-005 §3's own prediction exactly,
    /// and nothing in the corpus is under it. The measurement behind why is in
    /// `WorldModel.endTurn`: no `Stop` in `fixtures/` is followed by more work in
    /// the same turn, because the thing that wakes a stopped main thread is
    /// itself a `UserPromptSubmit`.
    @Test func thePostureChannelIsOnTheTimescaleOfAGlance() async throws {
        var total = FixtureMeasurement()
        var rows: [String] = []
        for name in Self.corpus {
            let measured = try await Self.measure(name)
            total.absorb(measured)
            rows.append(String(
                format: "  %-28s before %3d (min %7.3f s)  after %3d (min %7.3f s"
                    + " — standing %7.3f, seated %7.3f)",
                (name as NSString).utf8String!, measured.before, measured.minimumDwellBefore,
                measured.after, measured.minimumDwellAfter,
                measured.minimumStandingDwell, measured.minimumSeatedDwell))
        }
        print("POSTURE CHANGES OVER fixtures/")
        print(rows.joined(separator: "\n"))
        print(String(
            format: "  TOTAL before %d (min %.3f s) after %d (min %.3f s"
                + " — standing %.3f, seated %.3f)",
            total.before, total.minimumDwellBefore, total.after, total.minimumDwellAfter,
            total.minimumStandingDwell, total.minimumSeatedDwell))

        #expect(total.minimumDwellBefore < 0.5,
                "the defect is not reproduced by this measurement, so it cannot show the fix")
        #expect(total.after < total.before)

        // **The binding assertion.** A character that stands up and sits back
        // down inside four seconds is a turn boundary drawn where no turn ended,
        // which is the strobe returning on the key ADR-005 §9 risk 3 names.
        #expect(total.minimumStandingDwell > 4.0, Comment(rawValue:
            "a character stood up and sat back down inside"
            + " \(total.minimumStandingDwell) s — Stop is being drawn as a turn end where the"
            + " turn did not end [ADR-005 §9 risk 3]"))

        // Pinned, so that a change to the rule has to restate the table above
        // rather than quietly move it.
        #expect(total.before == 95, "the corpus changed: \(total.before) before-changes")
        #expect(total.after == 73, "the rule changed: \(total.after) after-changes")
        #expect(abs(total.minimumStandingDwell - 4.226) < 0.01,
                "the shortest standing dwell moved to \(total.minimumStandingDwell) s")
        #expect(abs(total.minimumSeatedDwell - 1.706) < 0.01,
                "the shortest seated dwell moved to \(total.minimumSeatedDwell) s")
    }

    /// **Every posture interval in the corpus shorter than ADR-005 §3's 4.226 s
    /// floor is a seated one, and this is the assertion that says so.**
    ///
    /// The test above pins two numbers; this one pins the *shape* behind them,
    /// because the numbers alone would let a future change trade a short seated
    /// interval for a short standing one and keep the same minimum. A short
    /// standing interval is the defect. A short seated interval is a short turn.
    @Test func nothingUnderTheFloorIsACharacterStandingUpAndSittingBackDown() async throws {
        var standing: [TimeInterval] = []
        var seated: [TimeInterval] = []
        for name in Self.corpus {
            let measured = try await Self.measure(name)
            if measured.minimumStandingDwell.isFinite { standing.append(measured.minimumStandingDwell) }
            if measured.minimumSeatedDwell.isFinite { seated.append(measured.minimumSeatedDwell) }
        }
        #expect(!standing.isEmpty, "nobody stood and sat again, so this checked nothing")
        #expect(!seated.isEmpty)
        #expect(standing.allSatisfy { $0 >= 4.2 }, Comment(rawValue:
            "standing dwells under the floor: \(standing.filter { $0 < 4.2 })"))
        #expect(seated.contains { $0 < 4.2 }, Comment(rawValue:
            "no short turn is left in the corpus, so the distinction this test draws is untested"))
    }
}
