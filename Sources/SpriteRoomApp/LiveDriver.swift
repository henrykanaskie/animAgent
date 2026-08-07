import Foundation
import SpriteRoomCore

/// The real thing `ReplayDriver` was standing in for: a bound listener, the
/// world model, and a wall clock.
///
/// The arrow points one way and this is where it starts. Nothing here reaches
/// into the scene, and nothing in the scene reaches back through here into the
/// model.
///
/// **Two clocks, deliberately.** Events are stamped with the instant they are
/// *drained*, not the instant they were received, because the listener must not
/// spend a syscall on `Date()` inside the response path — I5 caps what happens
/// there at decode-and-enqueue. The drain runs microseconds later; a deadline
/// measured in tens of seconds does not care, and the user's every tool call
/// does.
@MainActor
final class LiveDriver {

    private let queue: EventQueue
    private let listener: HookListener
    private let model = WorldModel()

    /// Deltas seen but not yet drained by the frame pump.
    private var pending: [WorldDelta] = []
    private var drainTask: Task<Void, Never>?
    private var sweepTask: Task<Void, Never>?

    private(set) var boundPort: UInt16?

    /// How often the reaper runs. Far finer than the shortest deadline in the
    /// table (30 s), so "no character is still working within the deadline"
    /// means within the deadline, not within the deadline plus a sweep
    /// interval. [I4]
    static let sweepInterval: Duration = .seconds(1)

    init(port: UInt16, capacity: Int = 1024) throws {
        let queue = EventQueue(capacity: capacity)
        self.queue = queue
        self.listener = try HookListener(port: port, queue: queue)
    }

    var counters: IngestCounters { listener.stats.counters }

    func start() async throws -> UInt16 {
        let bound = try await listener.start()
        boundPort = bound

        drainTask = Task { [queue, model] in
            for await event in queue.events {
                let deltas = await model.ingest(event, at: Date())
                if !deltas.isEmpty {
                    await MainActor.run { self.pending += deltas }
                }
            }
        }
        sweepTask = Task { [model] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sweepInterval)
                let deltas = await model.sweep(at: Date())
                if !deltas.isEmpty {
                    await MainActor.run { self.pending += deltas }
                }
            }
        }
        return bound
    }

    func stop() {
        drainTask?.cancel()
        sweepTask?.cancel()
        queue.finish()
        listener.stop()
    }

    /// One frame's accumulated deltas. Batched, once per frame, so forty events
    /// in one millisecond are one frame's work. [architecture]
    func drain() -> [WorldDelta] {
        guard !pending.isEmpty else { return [] }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        return batch
    }

    func snapshot() async -> WorldSnapshot { await model.snapshot() }
    func unhandled() async -> [String: Int] { await model.unhandledCounts }
    func abandoned() async -> Int { await model.abandonedTotal }
}
