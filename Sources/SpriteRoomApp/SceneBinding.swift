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

    @discardableResult
    func apply(_ deltas: [WorldDelta]) -> [SpriteIntent] {
        guard !deltas.isEmpty else { return [] }
        let intents = director.apply(deltas)
        scene.apply(intents)
        return intents
    }
}
