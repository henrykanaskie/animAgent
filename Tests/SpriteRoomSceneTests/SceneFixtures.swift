import Foundation
import SpriteRoomCore
import SpriteRoomScene

/// Fixtures over mocks, same as the core tests: every scene test that needs
/// event data drives a real captured payload through the real `WorldModel`.
enum SceneFixtures {

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpriteRoomSceneTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static func url(_ name: String) -> URL {
        repositoryRoot.appending(path: "fixtures").appending(path: "\(name).jsonl")
    }

    static func manifest() throws -> Manifest {
        try Manifest.load(root: repositoryRoot)
    }

    /// The delta stream, batched the way the scene actually receives it: one
    /// batch per frame of fixture time, not one per event. Same-frame
    /// coalescing is a real behaviour and the tests have to exercise it.
    static func batchedDeltas(
        _ name: String, frameInterval: TimeInterval = 1.0 / 60.0
    ) async throws -> [[WorldDelta]] {
        let entries = try HookLog.load(contentsOf: url(name))
        let model = WorldModel()
        var batches: [[WorldDelta]] = []
        var current: [WorldDelta] = []
        var frameEnd: Date?

        for entry in entries {
            guard let event = entry.event else { continue }
            if let end = frameEnd, entry.receivedAt > end {
                if !current.isEmpty { batches.append(current) }
                current = []
                frameEnd = entry.receivedAt.addingTimeInterval(frameInterval)
            } else if frameEnd == nil {
                frameEnd = entry.receivedAt.addingTimeInterval(frameInterval)
            }
            current += await model.ingest(event, at: entry.receivedAt)
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    /// Replays a fixture **at its own pace** against a scene, stepping the
    /// scene clock a frame at a time and delivering each event as its
    /// `_receivedAt` passes.
    ///
    /// This is the same loop the offscreen render harness runs, and it is the
    /// only honest way to test anything phrased as "at real time": compressing
    /// the event stream against a slower animation clock manufactures
    /// coincidences — two characters in one spot — that could not happen in a
    /// real replay, and then fails on them.
    ///
    /// `tail` keeps stepping after the last event so exit walks finish.
    @MainActor
    static func replayInFixtureTime(
        _ name: String,
        into scene: RoomScene,
        director: SceneDirector,
        step: TimeInterval = 1.0 / 60.0,
        tail: TimeInterval = 10,
        onFrame: (TimeInterval) -> Void
    ) async throws -> SceneDirector {
        var director = director
        let entries = try HookLog.load(contentsOf: url(name))
        guard let origin = entries.first?.receivedAt,
              let end = entries.last?.receivedAt else { return director }
        let duration = end.timeIntervalSince(origin) + tail

        var index = entries.startIndex
        var pending: [WorldDelta] = []
        var time = 0.0

        while time <= duration {
            let cutoff = origin.addingTimeInterval(time)
            while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                if let event = entries[index].event {
                    pending += await scene.modelForReplay.ingest(event, at: entries[index].receivedAt)
                }
                index += 1
            }
            if !pending.isEmpty {
                scene.apply(director.apply(pending))
                pending.removeAll(keepingCapacity: true)
            }
            scene.advance(to: time)
            onFrame(time)
            time += step
        }
        return director
    }
}

/// One `WorldModel` per scene, for the replay helper above. The scene never
/// reaches into it — the model is driven by the test and only deltas cross.
@MainActor
private var replayModels: [ObjectIdentifier: WorldModel] = [:]

@MainActor
extension RoomScene {
    var modelForReplay: WorldModel {
        let key = ObjectIdentifier(self)
        if let existing = replayModels[key] { return existing }
        let model = WorldModel()
        replayModels[key] = model
        return model
    }
}
