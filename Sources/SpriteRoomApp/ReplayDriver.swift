import Foundation
import SpriteRoomCore
import SpriteRoomScene

/// Drives a captured fixture through `WorldModel` and hands the resulting
/// deltas to the scene.
///
/// This is M2's stand-in for the live listener. The arrow is the same one the
/// architecture describes and it points one way: fixture → model → director →
/// scene. Nothing here ever asks the model a question.
///
/// **Deltas cross to the main actor in batches, once per frame.** A burst of
/// forty events in one millisecond produces one frame's work, which is also
/// what makes the same-frame coalescing in `SceneDirector` do its job.
@MainActor
final class ReplayDriver {

    private let model = WorldModel()
    private var director: SceneDirector
    private let scene: RoomScene
    /// Deltas seen but not yet handed to the scene.
    private var pending: [WorldDelta] = []

    /// Longest gap that still counts as "the same frame".
    static let frameInterval: TimeInterval = 1.0 / 60.0

    init(scene: RoomScene) {
        self.scene = scene
        self.director = SceneDirector(manifest: scene.store.manifest, layout: scene.layout)
    }

    var unmappedTools: [String: Int] { director.unmappedTools }

    /// Feeds every entry whose `_receivedAt` falls in `(previous, now]`.
    /// Fixture time, not wall time — the same discipline the replay harness
    /// uses, so a headless render and a live window see identical input.
    func ingest(_ entries: ArraySlice<HookLogEntry>) async {
        for entry in entries {
            guard let event = entry.event else { continue }
            pending += await model.ingest(event, at: entry.receivedAt)
        }
    }

    /// Sweeps expired calls at a fixture instant. [I4]
    func sweep(at instant: Date) async {
        pending += await model.sweep(at: instant)
    }

    /// Hands one frame's accumulated deltas to the scene.
    @discardableResult
    func flush() -> [SpriteIntent] {
        guard !pending.isEmpty else { return [] }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        let intents = director.apply(batch)
        scene.apply(intents)
        return intents
    }

    var hasPending: Bool { !pending.isEmpty }
}
