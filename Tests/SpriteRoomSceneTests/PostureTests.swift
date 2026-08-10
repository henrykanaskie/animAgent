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

    // MARK: The corpus

    /// One character's posture over one fixture, under both rules.
    struct PostureTrace: Sendable {
        /// Posture changes the scene performs, counting the first one — the
        /// character has to be drawn in *some* posture when it appears.
        var changes = 0
        var lastState: BodyState?
        var lastChangeAt: Date?
        /// Shortest interval between two consecutive posture changes.
        var minimumDwell: TimeInterval = .infinity

        mutating func observe(_ state: BodyState, at instant: Date) {
            guard state != lastState else { return }
            if lastState != nil, let last = lastChangeAt {
                minimumDwell = min(minimumDwell, instant.timeIntervalSince(last))
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
    /// | | before | after |
    /// |---|---:|---:|
    /// | posture changes, all 17 fixtures | 95 | **40** |
    /// | shortest posture dwell | **0.017 s** | **8.196 s** |
    ///
    /// **0.017 s is one frame and it is a floor imposed by the measurement**,
    /// not by the room: deltas are batched at 1/60 here because that is how the
    /// scene receives them, so two events 3 ms apart land in one batch and the
    /// posture between them is never drawn. On the raw event stream the shortest
    /// seated stint was 0.003 s. The measured floor is the honest number for
    /// "what the renderer could show", and it is still three orders of magnitude
    /// under the new one.
    ///
    /// **Eleven fixtures end at exactly one posture change** — the character
    /// sits down when it appears and never moves again. That is the main agent
    /// having no visible turn boundary: `Stop` emits no delta, so the room
    /// declines to draw a boundary it was not told about. See `SceneDirector`.
    @Test func thePostureChannelIsOnTheTimescaleOfAGlance() async throws {
        var total = FixtureMeasurement()
        var rows: [String] = []
        for name in Self.corpus {
            let measured = try await Self.measure(name)
            total.before += measured.before
            total.after += measured.after
            total.minimumDwellBefore = min(total.minimumDwellBefore, measured.minimumDwellBefore)
            total.minimumDwellAfter = min(total.minimumDwellAfter, measured.minimumDwellAfter)
            rows.append(String(
                format: "  %-28s before %3d (min dwell %8.3f s)  after %3d (min dwell %8.3f s)",
                (name as NSString).utf8String!, measured.before, measured.minimumDwellBefore,
                measured.after, measured.minimumDwellAfter))
        }
        print("POSTURE CHANGES OVER fixtures/")
        print(rows.joined(separator: "\n"))
        print(String(format: "  TOTAL before %d (min dwell %.3f s) after %d (min dwell %.3f s)",
                     total.before, total.minimumDwellBefore,
                     total.after, total.minimumDwellAfter))

        #expect(total.minimumDwellBefore < 0.5,
                "the defect is not reproduced by this measurement, so it cannot show the fix")
        #expect(total.minimumDwellAfter > 4.0,
                "a character changed posture twice inside \(total.minimumDwellAfter) s")
        #expect(total.after < total.before)
        // Pinned, so that a change to the rule has to restate the table above
        // rather than quietly move it.
        #expect(total.before == 95, "the corpus changed: \(total.before) before-changes")
        #expect(total.after == 40, "the rule changed: \(total.after) after-changes")
        #expect(abs(total.minimumDwellAfter - 8.196) < 0.01,
                "the shortest posture dwell moved to \(total.minimumDwellAfter) s")
    }
}
