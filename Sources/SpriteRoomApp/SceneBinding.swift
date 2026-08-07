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

    init(scene: RoomScene) {
        self.scene = scene
        self.director = SceneDirector(manifest: scene.store.manifest, layout: scene.layout)
    }

    convenience init(manifest: Manifest, viewport: CGSize) {
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(viewport)
        self.init(scene: scene)
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
