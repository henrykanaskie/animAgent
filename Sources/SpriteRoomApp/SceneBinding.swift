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

    init(scene: RoomScene, themeID: String? = nil) {
        self.scene = scene
        // The scene and the director must be given the *same* id. The scene
        // draws the theme's props; the director resolves each agent's station
        // within it. Hand them different ids and a character sits at a station
        // the room is not dressed for — silently, because both halves are
        // individually valid. [ADR-002 §8 item 5]
        self.director = SceneDirector(
            manifest: scene.store.manifest, themeID: themeID, layout: scene.layout)
    }

    convenience init(manifest: Manifest, themeID: String? = nil, viewport: CGSize) {
        let scene = RoomScene(manifest: manifest, themeID: themeID)
        scene.setViewport(viewport)
        self.init(scene: scene, themeID: themeID)
    }

    var unmappedTools: [String: Int] { director.unmappedTools }

    @discardableResult
    func apply(_ deltas: [WorldDelta]) -> [SpriteIntent] {
        guard !deltas.isEmpty else { return [] }
        let intents = director.apply(deltas)
        scene.apply(intents)
        return intents
    }
}
