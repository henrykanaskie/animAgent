import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// ADR-003's closing beat: when an agent's open-call set empties by a real
/// close, the badge already on screen stays for `D` and then clears.
///
/// **The first test in this file is the one the ADR stands or falls on.** §6
/// condition 1 says the document is *void*, not degraded, if an implementer
/// holds the body in `working` for the beat — an idle body under a `magnifier`
/// bubble reads "not working; the last thing was a read", which is true, while a
/// `working` body under it asserts the agent is still reading, which is false.
/// So the body is checked on **every frame** of the beat rather than at its
/// ends, and it is checked through both channels the scene has: the state the
/// director would draw, and every `setBody` intent it emitted.
struct ClosingBeatTests {

    static func director(workingPoses: [String: String] = [:]) -> SceneDirector {
        SceneDirector(variantIDs: ["00", "01"], workingPoses: workingPoses)
    }

    static let project = "/tmp/beat"
    static let session = "s"

    static func ref(_ agent: AgentID) -> AgentRef {
        AgentRef(project: project, session: session, agent: agent)
    }

    static func call(_ id: String, _ tool: String) -> OpenCall {
        OpenCall(toolUseID: id, toolName: tool,
                 startedAt: Date(timeIntervalSinceReferenceDate: 0),
                 deadline: Date(timeIntervalSinceReferenceDate: 900))
    }

    static let origin = Date(timeIntervalSinceReferenceDate: 10_000)

    // MARK: The condition the whole thing rests on

    /// **The body is `idle` for every frame of the beat.** [ADR-003 §6 item 1]
    ///
    /// Stepped at 1/60 across the whole 500 ms — thirty frames — rather than
    /// sampled at the ends, because "the body went idle and came back" and "the
    /// body stayed idle" have the same endpoints and only one of them is the
    /// ADR.
    ///
    /// The director is given a `workingPoses` table naming a seated pose for
    /// `magnifier`. That table is empty in the shipped manifest, so a beat that
    /// wrongly reached the pose lookup would be invisible today and would become
    /// visible on the day somebody fills it in. Naming a pose here is what makes
    /// "the lookup is not reached" a thing this test can see: if the body ever
    /// resolved through the badge during the beat it would come back `sitB`, and
    /// it never does.
    @Test func theBodyIsIdleForEveryFrameOfTheBeat() {
        var director = Self.director(workingPoses: ["magnifier": "sit_b",
                                                    "default": "sit_b"])
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        #expect(director.bodyState(agent) == .working, "the call is open; the body works")

        let closedAt = Self.origin.addingTimeInterval(0.006)
        var bodies: [BodyState] = []
        for intent in director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: closedAt
        ) {
            if case let .setBody(_, state, _) = intent { bodies.append(state) }
        }
        #expect(bodies == [.idle], "the body did not go idle at the instant of the close")

        // Indexed rather than accumulated: repeated `+= 1/60` in a double
        // drifts, and at a real `Date`'s magnitude the drift is larger than the
        // gap it is compared against.
        let frames = Int(SceneDirector.closingBeatDuration * 60)
        for frame in 0...frames {
            let elapsed = Double(frame) / 60.0
            for intent in director.apply([], at: closedAt.addingTimeInterval(elapsed)) {
                if case let .setBody(_, state, _) = intent { bodies.append(state) }
            }
            // Every frame of the beat, and the frame it clears on.
            #expect(director.bodyState(agent) == .idle,
                    "the body was \(String(describing: director.bodyState(agent))) at +\(elapsed) s")
            // …and the beat really is still up for every frame before the last,
            // so the assertion above is not being made about an empty slot.
            if frame < frames {
                #expect(director.badge(agent).badge == .magnifier,
                        "the beat cleared early at +\(elapsed) s")
            }
        }

        #expect(frames == 30, "a 500 ms beat is thirty frames at 60 Hz; stepped \(frames)")
        #expect(bodies.allSatisfy { $0 == .idle },
                "a body state other than idle was emitted during the beat: \(bodies)")
        // And the beat really was up for the frames just asserted on, so the
        // loop above was not asserting about an empty slot.
        #expect(director.badge(agent).badge == nil, "the beat outlived D")
    }

    /// The same guarantee stated as the structural fact underneath it: the beat
    /// lives in a field `Presentation.body` does not read, so there is no input
    /// by which it could reach the body.
    @Test func aBeatDoesNotSelectAWorkingPose() {
        var director = Self.director(workingPoses: ["magnifier": "sit_b",
                                                    "default": "sit_b"])
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)

        #expect(director.badge(agent).badge == .magnifier, "the beat is up")
        #expect(director.bodyState(agent) == .idle,
                "the badge selected a seated working pose during a beat")
    }

    // MARK: The beat itself

    /// A 6 ms call on an idle agent — the median `magnifier` call in the M7a
    /// capture is 6 ms — produces a badge for `D` and then none.
    @Test func aSixMillisecondCallProducesABadgeForExactlyD() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Grep")),
        ], at: Self.origin)

        let closedAt = Self.origin.addingTimeInterval(0.006)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Grep", outcome: .succeeded)],
            at: closedAt)

        // Every frame strictly inside the beat, indexed rather than accumulated:
        // repeated `+= 1/60` in a double drifts, and at a real `Date`'s
        // magnitude the drift is larger than the gap it is being compared
        // against — `filmstrip.py` records the same trap on the renderer's own
        // loop.
        let frames = Int(SceneDirector.closingBeatDuration * 60)
        for frame in 0..<frames {
            let elapsed = Double(frame) / 60.0
            _ = director.apply([], at: closedAt.addingTimeInterval(elapsed))
            #expect(director.badge(agent).badge == .magnifier, "cleared early at +\(elapsed) s")
            #expect(director.badge(agent).count == 0, "the ×N was not suppressed at +\(elapsed) s")
        }
        #expect(frames == 30, "500 ms is thirty frames at 60 Hz")

        _ = director.apply([], at: closedAt.addingTimeInterval(SceneDirector.closingBeatDuration))
        #expect(director.badge(agent).badge == nil)
    }

    /// **The beat is bounded by the clock, not by frames.** A retracted panel
    /// renders nothing, so a beat counted in ticks would freeze while hidden and
    /// be presented stale on reveal. One `apply` a long way after the close is
    /// the reveal, and the beat is already gone. [ADR-003 §8 item 4]
    @Test func aBeatThatExpiredWhileNothingWasRenderedIsAlreadyGone() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)

        _ = director.apply([], at: Self.origin.addingTimeInterval(120))
        #expect(director.badge(agent).badge == nil, "a beat survived two minutes of no frames")
    }

    /// A close into a still-occupied set produces **no** beat and no badge
    /// change: the slot is occupied and the character is visibly working anyway.
    /// [ADR-003 §3]
    @Test func aCloseIntoAStillOccupiedSetArmsNoBeatAndChangesNoBadge() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
            .callOpened(agent: agent, call: Self.call("b", "Bash")),
        ], at: Self.origin)
        #expect(director.badge(agent).badge == .magnifier)
        #expect(director.badge(agent).count == 2)

        let intents = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)
        #expect(director.closingBeat(agent) == nil, "a beat was armed into a non-empty set")
        // The lowest-ordinal rule decides the glyph from the surviving call, as
        // it always did, and the badge genuinely changes because the set did.
        #expect(director.badge(agent).badge == .terminal)
        #expect(director.badge(agent).count == 1)
        #expect(director.bodyState(agent) == .working, "one call is still open")
        #expect(intents.contains { if case .setBadge = $0 { return true } else { return false } })
    }

    /// `.callAbandoned` arms no beat, **including when it empties the set**. An
    /// abandoned call is the reaper closing our blind spot rather than a
    /// completed action, and it fires up to fifteen minutes after the fact.
    /// [I1, ADR-003 §3]
    @Test func anAbandonedCallArmsNoBeatEvenWhenItEmptiesTheSet() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)

        _ = director.apply(
            [.callAbandoned(agent: agent, toolUseID: "a", toolName: "Read", reason: .deadlineExpired)],
            at: Self.origin)
        #expect(director.closingBeat(agent) == nil)
        #expect(director.badge(agent).badge == nil, "an abandon left a badge on screen")
        #expect(director.bodyState(agent) == .idle)
    }

    /// A duplicate close — `PostToolBatch` re-reports ids a `PostToolUse`
    /// already closed, and both appear for one id in `fixtures/tool-failure` —
    /// must not re-arm. A beat can be cancelled but never extended.
    /// [ADR-003 §6]
    @Test func aDuplicateCloseCannotExtendABeat() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)
        let armed = director.closingBeat(agent)
        #expect(armed != nil, "the beat did not arm")

        // A second close of the same id, a quarter of a beat later.
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin.addingTimeInterval(0.125))
        #expect(director.closingBeat(agent)?.until == armed?.until, "the beat was extended")

        _ = director.apply([], at: Self.origin.addingTimeInterval(SceneDirector.closingBeatDuration))
        #expect(director.badge(agent).badge == nil)
    }

    // MARK: What cancels it

    /// A `.callOpened` cancels immediately — the normal rule resumes and the
    /// open set decides the glyph. [ADR-003 §3]
    @Test func aCallOpeningMidBeatCancelsItAndTheOpenSetDecides() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)
        #expect(director.badge(agent).badge == .magnifier)

        _ = director.apply(
            [.callOpened(agent: agent, call: Self.call("b", "Bash"))],
            at: Self.origin.addingTimeInterval(0.1))
        #expect(director.closingBeat(agent) == nil, "the beat outlived the call that cancelled it")
        #expect(director.badge(agent).badge == .terminal)
        #expect(director.badge(agent).count == 1)
        #expect(director.bodyState(agent) == .working)

        // And it does not come back when the new call's own beat would have
        // ended: the glyph is the new one, not the old one.
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "b", toolName: "Bash", outcome: .succeeded)],
            at: Self.origin.addingTimeInterval(0.2))
        #expect(director.badge(agent).badge == .terminal)
    }

    /// Attention outranks a live tool badge for three reasons and beats a
    /// finished one more strongly still, so a rising notification **cancels**
    /// rather than merely covering. [ADR-003 §3]
    @Test func attentionCancelsABeat() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)

        _ = director.apply(
            [.attentionChanged(agent: agent, attention: .idlePrompt)],
            at: Self.origin.addingTimeInterval(0.1))
        #expect(director.closingBeat(agent) == nil)
        #expect(director.badge(agent).isAttention)
        // Cancelled, not covered: clearing the attention inside what would have
        // been the beat's life does not bring the tool glyph back.
        _ = director.apply(
            [.attentionChanged(agent: agent, attention: nil)],
            at: Self.origin.addingTimeInterval(0.2))
        #expect(director.badge(agent).badge == nil, "a cancelled beat came back")
    }

    /// `dormancyChanged(true)` cancels: the `Z` is a fact about now and the beat
    /// is not. [ADR-003 §3]
    @Test func dormancyCancelsABeat() {
        var director = Self.director()
        let agent = Self.ref(.subagent("a1234567890abcdef"))
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)

        _ = director.apply(
            [.dormancyChanged(agent: agent, isDormant: true)],
            at: Self.origin.addingTimeInterval(0.1))
        #expect(director.closingBeat(agent) == nil)
        #expect(director.badge(agent).isSleeping)
        _ = director.apply(
            [.dormancyChanged(agent: agent, isDormant: false)],
            at: Self.origin.addingTimeInterval(0.2))
        #expect(director.badge(agent).badge == nil, "a cancelled beat came back")
    }

    /// A beat armed before a rebuild does not survive it. A rebuild is a new
    /// `SceneDirector`, so this is structural — recorded because "unreachable
    /// today" is a property of today's wiring and the beat is per-character
    /// state that has to answer to every reaping path. [I4]
    @Test func aBeatDoesNotSurviveARebuild() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply(
            [.callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded)],
            at: Self.origin)
        #expect(director.closingBeat(agent) != nil)

        var rebuilt = Self.director()
        _ = rebuilt.apply(
            [.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)], at: Self.origin)
        #expect(rebuilt.closingBeat(agent) == nil)
        #expect(rebuilt.badge(agent).badge == nil)
    }

    /// Departure takes the beat with the character, because the beat is a field
    /// of the presentation the departure removes. [I4]
    @Test func aDepartingCharacterTakesItsBeatWithIt() {
        var director = Self.director()
        let agent = Self.ref(.mainThread)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: nil, lifecycle: .active),
            .callOpened(agent: agent, call: Self.call("a", "Read")),
        ], at: Self.origin)
        _ = director.apply([
            .callClosed(agent: agent, toolUseID: "a", toolName: "Read", outcome: .succeeded),
            .agentDeparted(agent: agent),
        ], at: Self.origin)
        #expect(director.closingBeat(agent) == nil)
        #expect(director.population == 0)
        // And no intent tries to badge a character that has left.
        let later = director.apply([], at: Self.origin.addingTimeInterval(1))
        #expect(later.isEmpty)
    }

    // MARK: What the beat buys, on a real fixture

    /// **The point of the whole thing, on a capture in the repository.**
    ///
    /// The M7a measurement's finding was that `magnifier` and `checklist` calls
    /// are so short they land on no sampled frame at all. `three-subagents`
    /// carries the same shape: `Agent` dispatches that open and close about
    /// 16 ms apart, which is `checklist`.
    ///
    /// Sampled once a second — the rig's interval — count the (frame, character)
    /// pairs showing each glyph, with and without the beat. The assertion is not
    /// a threshold: it is that the classes which had **zero** frames now have
    /// some, and that the classes which already had frames did not lose any.
    @Test func shortCallsLandOnSampledFramesThatTheyPreviouslyMissed() async throws {
        let (before, after) = try await Self.badgeFramesPerSecond()

        let dark = before.filter { $0.value == 0 }.keys.sorted()
        #expect(!dark.isEmpty, "no class was invisible in this fixture; the test proves nothing")
        for badge in dark {
            #expect((after[badge] ?? 0) > 0,
                    "\(badge) had 0 sampled frames and still has \(after[badge] ?? 0)")
        }
        // §6 condition 5: the room is never *quieter* than the truth as a
        // consequence. The beat only ever adds a glyph after work.
        for (badge, count) in before {
            #expect((after[badge] ?? 0) >= count,
                    "\(badge) lost frames: \(count) → \(after[badge] ?? 0)")
        }
    }

    /// Replays `three-subagents` at 1/60 in fixture time and counts, once a
    /// second, the (character, glyph) pairs on screen — the rig's
    /// `badge_agent_frames`, computed here without a renderer.
    ///
    /// Both readings come off **one** replay, so they cannot differ in anything
    /// but the rule. `before` is the pre-ADR-003 room by its definition rather
    /// than by a flag: the lowest-ordinal badge over the agent's open-call set,
    /// which is what `SceneDirector` drew before the beat existed and what
    /// `03-EVENT-MODEL.md` still states as the rule for a non-empty set.
    /// `after` is what the director now says.
    static func badgeFramesPerSecond() async throws
    -> (before: [ToolBadge: Int], after: [ToolBadge: Int]) {
        var director = Self.director()
        var openCalls: [AgentRef: [ToolUseID: String]] = [:]
        var before: [ToolBadge: Int] = [:]
        var after: [ToolBadge: Int] = [:]

        let entries = try HookLog.load(contentsOf: SceneFixtures.url("three-subagents"))
        guard let origin = entries.first?.receivedAt,
              let end = entries.last?.receivedAt else { return ([:], [:]) }
        let model = WorldModel()
        var index = entries.startIndex
        var time = 0.0
        var nextSample = 0.0
        let step = 1.0 / 60.0

        // Every badge class the fixture's calls map to is seeded at zero as the
        // calls arrive, so a class that draws no frame at all is a zero rather
        // than an absence — which is the whole finding being reproduced.
        while time <= end.timeIntervalSince(origin) {
            var pending: [WorldDelta] = []
            let cutoff = origin.addingTimeInterval(time)
            while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                if let event = entries[index].event {
                    pending += await model.ingest(event, at: entries[index].receivedAt)
                }
                index += 1
            }
            for delta in pending {
                switch delta {
                case let .callOpened(agent, call):
                    openCalls[agent, default: [:]][call.toolUseID] = call.toolName
                    before[ToolBadge.badge(forTool: call.toolName), default: 0] += 0
                case let .callClosed(agent, id, _, _), let .callAbandoned(agent, id, _, _):
                    openCalls[agent]?.removeValue(forKey: id)
                case let .agentDeparted(agent):
                    openCalls.removeValue(forKey: agent)
                default:
                    break
                }
            }
            _ = director.apply(pending, at: cutoff)

            if time + 1e-9 >= nextSample {
                for (agent, calls) in openCalls {
                    if let badge = BadgeSelection.select(openToolNames: calls.values).badge {
                        before[badge, default: 0] += 1
                    }
                    let now = director.badge(agent)
                    if !now.isAttention, !now.isSleeping, let badge = now.badge {
                        after[badge, default: 0] += 1
                    }
                }
                nextSample += 1.0
            }
            time += step
        }
        return (before, after)
    }
}
