import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **ADR-005 §7: a blocked character stops moving.**
///
/// The defect this was written against, stated as the room stating the opposite
/// of the truth: an agent stopped at a permission prompt is *genuinely blocked*,
/// waiting on a human, and it played the busiest animation in the room. A gated
/// `Bash` is still an open call, so `AmbientMotion` handed it `terminal` (`S R`,
/// a 250 ms period, the fastest schedule the 8 fps grid allows) and the stuck
/// agent read as the hardest-working one.
///
/// Measured on `fixtures/concurrent-permission-gates.jsonl`, which is the whole
/// evidence base and is also this file's fixture. Two subagents block on a human:
/// `ac26da513c96ad388` from t=6.446 to t=38.263 (**31.8 s**) and
/// `a7298874eca5a457d` from t=7.919 to the end of the stream, which never
/// releases it. At t=20 both are gated, both hold one open `Bash`, and both were
/// changing **3 760 px every 125 ms**.
///
/// The rule:
///
/// > While an agent has an open permission-gate mark, its body holds the
/// > `settled` position and plays no phrase.
///
/// The badge layer already got this right: ADR-003 §1 says in as many words
/// that a gated `Bash` "is not running", so drawing `terminal` over it "asserts
/// work that is not happening". This is that sentence applied to the body, in
/// the one channel M7c measured as the only one that survives `1x`.
@MainActor
struct PermissionGateStillnessTests {

    /// Gated at t=6.446 by a `PermissionRequest` naming it; released at t=38.263
    /// when the human approves and the gated `Bash` closes normally.
    static let releasedGate = "ac26da513c96ad388"
    /// Gated at t=7.919 and **never released in the stream**. Two of the eight
    /// gates in the corpus are this shape, which is why "a gate is an interval,
    /// and a long one" is the design's premise rather than a hope.
    static let unreleasedGate = "a7298874eca5a457d"

    /// One second of fixture time in the middle of both blocks: 8 animation
    /// steps at the manifest's 8 fps, which is four complete `terminal` bars.
    /// Any residual phrase shows up as a second frame index inside it.
    static let window = 20.0...21.0

    /// **The central test.** Both blocked characters, sampled every rendered
    /// frame for a second, must put **one** texture on screen.
    ///
    /// The assertions that keep it from passing vacuously are as important as
    /// the one it is named for, because a character with no art, no body state or
    /// no open call also holds one frame:
    ///
    /// - each of them is `working`: seated, in a turn, at its desk;
    /// - each of them holds exactly one open call, and it is a `terminal` one, so
    ///   the badge layer is offering the body precisely the phrase it used to
    ///   play;
    /// - a `Character` given the same state and the same badge and no gate does
    ///   move, in the same test, so the difference is the gate and nothing else.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aCharacterStoppedAtAPermissionGateHoldsOneFrame() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))

        let entries = try HookLog.load(
            contentsOf: SceneFixtures.url("concurrent-permission-gates"))
        let first = try #require(entries.first?.event)
        func ref(_ id: String) -> AgentRef {
            AgentRef(project: first.cwd, session: first.sessionID, agent: .subagent(id))
        }
        let blocked = [ref(Self.releasedGate), ref(Self.unreleasedGate)]

        var drawn: [AgentRef: Set<Int>] = [:]
        var badges: [AgentRef: BadgeSelection] = [:]
        var bodies: [AgentRef: BodyState] = [:]
        var samples = 0

        _ = try await SceneFixtures.replayInFixtureTime(
            "concurrent-permission-gates", into: scene,
            director: SceneDirector(manifest: manifest)
        ) { time in
            guard Self.window.contains(time) else { return }
            samples += 1
            for agent in blocked {
                guard let character = scene.character(for: agent) else { continue }
                if let index = character.frameIndexForTesting {
                    drawn[agent, default: []].insert(index)
                }
                badges[agent] = character.badgeSelection
                bodies[agent] = character.state
            }
        }

        #expect(samples >= 55, "the window was not stepped: \(samples) frames")

        for agent in blocked {
            let indices = try #require(drawn[agent], "\(agent) was not on screen at t=20")
            #expect(bodies[agent] == .working, "\(agent) is not seated, so this checked nothing")
            #expect(badges[agent]?.count == 1,
                    "\(agent) holds \(badges[agent]?.count ?? -1) calls, not the gated one")
            #expect(badges[agent]?.badge == .terminal,
                    "\(agent)'s call is not the `terminal` one this defect was measured on")
            #expect(indices.count == 1, Comment(rawValue:
                "\(agent) drew \(indices.sorted()) over a second while stopped at a permission"
                + " gate: the body is asserting work that is not happening [ADR-005 §7]"))
        }

        // The control, so the assertion above is about the gate rather than
        // about a character that could not animate at all: the same seated
        // state, the same one-`Bash` badge, no gate.
        let store = TextureStore(manifest: manifest)
        let ungated = Character(
            variant: "06", nameplate: NameplateText(lead: "MAIN"), store: store)
        ungated.advance(to: 0)
        ungated.apply(state: .working, facing: .right, startingAt: 0)
        ungated.apply(badge: BadgeSelection.select(openToolNames: ["Bash"]))
        var control: Set<Int> = []
        for step in 0..<8 {
            ungated.advance(to: Double(step) / 8 + 1.0 / 16)
            if let index = ungated.frameIndexForTesting { control.insert(index) }
        }
        #expect(control.count > 1,
                "the ungated control never moved either, so this test proves nothing")
    }
}
