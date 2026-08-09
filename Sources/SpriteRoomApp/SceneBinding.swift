import Foundation
import SpriteRoomCore
import SpriteRoomScene

/// One scene and the director that feeds it.
///
/// The last link in the one-way chain: deltas in, sprite intents out, nothing
/// ever going back the other way. It exists as its own object because the panel
/// throws one away and builds another every time the displayed project changes,
/// and doing that has to be one line.
@MainActor
final class SceneBinding {

    let scene: RoomScene
    private var director: SceneDirector

    /// The pilot lamp, built on the first frame that has anything true to say
    /// about this process's liveness and never before.
    ///
    /// **A run with no listener never builds one, and that is the I1 answer
    /// rather than an optimisation.** `--render` replays a fixture off disk;
    /// there is no bound port, nothing is receiving, and a lamp in that picture
    /// could only be reporting on a listener that does not exist. When you
    /// cannot represent something truthfully, show nothing.
    ///
    /// It is also what keeps `scripts/preview-theme.py --verify` an honest
    /// check: that harness compares its own composition against `spriteroom
    /// --render` pixel for pixel with an empty register, so a lamp drawn in a
    /// listener-less render would fail the I7 gate — correctly, because it
    /// would be a pixel the room cannot account for.
    private var lamp: LivenessLamp?

    /// The scene and the director must be given the **same** id. The scene
    /// draws the theme's props; the director resolves each agent's station
    /// within it. Hand them different ids and a character sits at a station the
    /// room is not dressed for — silently, because both halves are
    /// individually valid. [ADR-002 §8 item 5]
    ///
    /// **So there is no id parameter here.** This used to take one alongside
    /// the scene, which meant every caller had to remember to pass the same
    /// value twice, and `--render` did not: it built an unthemed scene, passed
    /// no id, and drew the plain office no matter what. The id is now read back
    /// off the scene that was actually built, so "both halves agree" is not a
    /// rule a caller can break — there is nothing left to get wrong.
    init(scene: RoomScene) {
        self.scene = scene
        self.director = SceneDirector(
            manifest: scene.store.manifest,
            themeID: scene.store.themeID,
            layout: scene.layout)
    }

    convenience init(manifest: Manifest, themeID: String? = nil, viewport: CGSize) {
        let scene = RoomScene(manifest: manifest, themeID: themeID)
        scene.setViewport(viewport)
        self.init(scene: scene)
    }

    /// The room both halves were built for. One value, one source.
    var themeID: String? { scene.store.themeID }

    var unmappedTools: [String: Int] { director.unmappedTools }

    /// One frame's deltas, and the instant that frame happened.
    ///
    /// **The empty-batch guard is gone and its absence is load-bearing.**
    /// `SceneDirector` is a function of deltas *and time* as of ADR-003: the
    /// closing beat ends by the clock passing its expiry, and the frame that
    /// ends it is almost always a frame with nothing in it — an agent whose
    /// open-call set has just emptied is by definition not producing deltas.
    /// Guarding on `!deltas.isEmpty` would leave the beat up until that agent's
    /// next event, which the M7a capture measures at a mean of 18.5 s.
    @discardableResult
    func apply(_ deltas: [WorldDelta], at now: Date) -> [SpriteIntent] {
        let intents = director.apply(deltas, at: now)
        guard !intents.isEmpty else { return [] }
        scene.apply(intents)
        return intents
    }

    /// One frame of the pilot lamp.
    ///
    /// `nil` means this run has no listener to report on — a replay, a render,
    /// a capture — and the lamp is taken down if one was ever up. It does not
    /// mean "the listener is down": that case arrives as a `Liveness` whose
    /// `lastBeatAt` has gone stale, which is a lamp drawn `dark`, and the
    /// difference between *no answer* and *nothing to answer for* is exactly
    /// the difference between a dark lamp and no lamp.
    func showLiveness(_ liveness: Liveness?, at now: Date) {
        guard let liveness else {
            lamp?.remove()
            lamp = nil
            return
        }
        if lamp == nil { lamp = LivenessLamp(scene: scene) }
        lamp?.update(liveness, at: now)
    }

    /// What the lamp is currently drawing, or `nil` when there is no lamp.
    /// Read by tests and by the capture harness; nothing depends on it.
    var lampPhase: LivenessLamp.Phase? { lamp?.phase }
}
