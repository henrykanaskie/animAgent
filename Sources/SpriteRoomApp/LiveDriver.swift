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

    /// The thing that proves the listener is up by using it. Built only once a
    /// port is actually bound, because there is nothing to post to before that.
    private var heartbeat: ListenerHeartbeat?

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

    /// What this process has proved about its own listener, as of now.
    ///
    /// `nil` before `start()` has bound a port: nothing has been proved, and a
    /// zeroed `Liveness` would be the weaker claim "we checked and nothing
    /// answered" rather than the true one "we have not checked". The panel
    /// draws no lamp at all for `nil`. [I1]
    var liveness: Liveness? { heartbeat?.liveness }

    func start() async throws -> UInt16 {
        let bound = try await listener.start()
        boundPort = bound

        // Only now, and against the port that was actually bound rather than
        // the one that was asked for — `--port 0` asks for an ephemeral one, so
        // those are different numbers and probing the requested one would probe
        // nothing.
        let heartbeat = ListenerHeartbeat(port: bound)
        self.heartbeat = heartbeat
        heartbeat.start()

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
        // Before the listener, so the last thing the heartbeat can observe is a
        // listener that was still answering. Stopping it afterwards would let
        // one failed round trip be recorded on the way out, which is true but
        // pointless noise on a run that is ending on purpose.
        heartbeat?.stop()
        heartbeat = nil
        drainTask?.cancel()
        sweepTask?.cancel()
        queue.finish()
        listener.stop()
    }

    /// Stops **only** the listener, leaving the heartbeat beating against a
    /// port nothing is on.
    ///
    /// It exists for one caller: `--liveness-demo`, which has to show that the
    /// lamp goes dark for a real reason. A harness that faked the dark state by
    /// stopping the heartbeat would be demonstrating that a variable can be
    /// left alone, not that the signal is tied to the listener. This kills the
    /// listener and lets the probe fail on its own.
    func stopListenerOnly() {
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
