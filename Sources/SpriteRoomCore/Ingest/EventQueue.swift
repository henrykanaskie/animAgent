import Foundation
import os

/// Bounded handoff from the listener to the model actor.
///
/// `enqueue` is synchronous, non-blocking and order-preserving — the three
/// things I5 needs. The listener never awaits anything to answer a request.
public final class EventQueue: Sendable {

    public enum EnqueueResult: Sendable, Hashable {
        case enqueued
        /// The buffer was full, or the stream had already finished. Counted,
        /// never fatal.
        case dropped
    }

    /// Drain this exactly once, from whatever drives the `WorldModel`.
    public let events: AsyncStream<HookEvent>
    public let capacity: Int

    private let continuation: AsyncStream<HookEvent>.Continuation

    public init(capacity: Int = 1024) {
        self.capacity = capacity
        let (stream, continuation) = AsyncStream.makeStream(
            of: HookEvent.self, bufferingPolicy: .bufferingNewest(capacity))
        self.events = stream
        self.continuation = continuation
    }

    @discardableResult
    public func enqueue(_ event: HookEvent) -> EnqueueResult {
        switch continuation.yield(event) {
        case .enqueued: return .enqueued
        default: return .dropped
        }
    }

    public func finish() {
        continuation.finish()
    }
}

/// What the ingest path saw. Counters only — a malformed body is an increment
/// and a `202`, never an error back into the user's session. [I5]
public struct IngestCounters: Sendable, Hashable {
    public var requests = 0
    public var decoded = 0
    /// Body was not JSON, or carried no `session_id` / `cwd`.
    public var malformed = 0
    /// Queue was full. Should be zero; if it is not, the drain is too slow.
    public var dropped = 0
    /// Self-probes answered. `ListenerHeartbeat` posts one a second and the
    /// room's pilot lamp is lit by them.
    ///
    /// **On its own axis, and deliberately outside `requests`.** Every other
    /// counter here describes the hook stream, and a probe is not part of it —
    /// folded into `requests` it would add one a second forever and make the
    /// number useless for the thing it exists for, and folded into `malformed`
    /// (which is where an undeclared probe would land, since it carries no
    /// decodable body) it would bury the counter that notices a real decoding
    /// problem under a steady drip of our own traffic.
    public var probes = 0

    public init() {}
}

/// Thread-safe counters for the listener.
///
/// An unfair lock rather than an actor because the handler must not `await`
/// anything to answer a request. The lock is held for one integer increment and
/// is never held across a response. [I5]
public final class IngestStats: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: IngestCounters())

    public init() {}

    public var counters: IngestCounters { state.withLock { $0 } }

    /// A self-probe was answered. One increment, no decode, no enqueue.
    public func recordProbe() {
        state.withLock { $0.probes += 1 }
    }

    public func record(decoded: Bool, dropped: Bool) {
        state.withLock { counters in
            counters.requests += 1
            if decoded { counters.decoded += 1 } else { counters.malformed += 1 }
            if dropped { counters.dropped += 1 }
        }
    }
}
