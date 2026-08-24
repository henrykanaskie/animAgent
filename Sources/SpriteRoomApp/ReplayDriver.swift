import Foundation
import SpriteRoomCore

/// Drives a captured fixture through `WorldModel` and hands out the deltas it
/// produces.
///
/// The stand-in for the live listener until M4. The arrow is the same one the
/// architecture describes and it points one way: fixture → model → deltas →
/// director → scene. Nothing here ever asks the model a question, and the
/// driver deliberately knows nothing about scenes: the panel and the plain
/// window are two different consumers of the same stream.
///
/// **Deltas cross to the main actor in batches, once per frame.** A burst of
/// forty events in one millisecond produces one frame's work, which is also
/// what makes the same-frame coalescing in `SceneDirector` do its job.
@MainActor
final class ReplayDriver {

    private let model = WorldModel()
    /// Deltas seen but not yet drained.
    private var pending: [WorldDelta] = []

    /// Longest gap that still counts as "the same frame".
    static let frameInterval: TimeInterval = 1.0 / 60.0

    init() {}

    /// Feeds every entry whose `_receivedAt` falls in `(previous, now]`.
    /// Fixture time, not wall time: the same discipline the replay harness
    /// uses, so a headless render and a live panel see identical input.
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

    /// Takes one frame's accumulated deltas.
    func drain() -> [WorldDelta] {
        guard !pending.isEmpty else { return [] }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        return batch
    }

    var hasPending: Bool { !pending.isEmpty }
}
