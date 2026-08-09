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
}
