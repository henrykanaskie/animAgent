import Darwin
import Foundation
import os

/// What the app is allowed to say about **itself**, as opposed to about the
/// session it is watching.
///
/// # Why this type exists
///
/// M7c stopped the idle body animating, so that movement in the room means an
/// open tool call and nothing else. That was right (an idle character had been
/// measured moving *more* than a working one), and it left one thing behind:
/// **a room where nobody is working is now a room where nothing moves at all**,
/// and that picture is identical to the picture a dead listener draws. "My
/// agents are idle" and "this app has stopped receiving" became the same frame.
///
/// The fix cannot be a clock. A blinking light on a timer keeps blinking after
/// the listener dies, which is fiction of the plainest kind [I1] and is exactly
/// the invented activity I2 forbids. So the signal has to be **earned**: this
/// type carries the count of round trips that actually completed *through the
/// bound listener*, and the instant of the most recent one. Nothing here is
/// derived from elapsed time; `beats` only ever moves because a request was
/// accepted.
///
/// # What a reader of this value may assert, and nothing more
///
/// > A request POSTed to this app's hook port completed at `lastBeatAt`.
///
/// Not "the app is healthy", not "hooks are installed", not "an agent is
/// alive". Just that the socket the user's Claude Code sessions post to
/// answered, moments ago. Every visible consequence downstream is bounded by
/// that sentence.
public struct Liveness: Sendable, Hashable {

    /// Round trips that completed with a `202`. Monotonic for the life of a
    /// heartbeat.
    public var beats: Int

    /// When the most recent one completed. `nil` before the first, which is
    /// the honest state of a listener that has just bound and has never yet
    /// been proved to answer.
    public var lastBeatAt: Date?

    /// When the most recent attempt *failed*. Carried for diagnostics only:
    /// nothing visible is driven by it, because "the last attempt failed" and
    /// "no attempt has succeeded recently" are different statements and only
    /// the second one is safe to draw. A single dropped beat is a hiccup.
    public var lastFailureAt: Date?

    public init(beats: Int = 0, lastBeatAt: Date? = nil, lastFailureAt: Date? = nil) {
        self.beats = beats
        self.lastBeatAt = lastBeatAt
        self.lastFailureAt = lastFailureAt
    }
}

/// Proves the listener is up by **using it**.
///
/// Once per `interval` it opens a loopback connection to the port the listener
/// actually bound, POSTs a request to `ListenerHeartbeat.path`, and waits for
/// the `202`. A completed round trip is one beat. A refused connection, a
/// timeout, or anything that is not a `202` is not.
///
/// # Why a self-POST rather than reading the listener's state
///
/// `NWListener` will tell you it is `.ready`, and that is cheaper. It is also
/// weaker: a listener can be `.ready` while its accept path is wedged, while
/// the process is out of file descriptors, or while something else has taken
/// the loopback route out from under it. The question the user needs answered
/// is not "does an object say it is ready" but **"if Claude Code posted a hook
/// right now, would it land"**, and the only honest way to answer that is to
/// post one.
///
/// It is deliberately built on a raw socket rather than on `Network.framework`,
/// which is what `HookListener` uses. A probe that shares its transport with
/// the thing it is probing can be brought down by the same fault and still
/// report success from a cached state; two independent stacks cannot.
///
/// # I5: what this costs the user's tool calls
///
/// The probe is a real request and it goes through the listener's real accept
/// path, so it does contend, once a second, for the same serial queue a hook
/// POST uses. What it costs there is a connection accept, a ~90-byte header
/// parse, one string comparison and one counter increment: the probe is
/// recognised by its request target and is **never decoded and never
/// enqueued**, so it does not touch the queue, the model, or the room. At 1 Hz
/// against a session that posts on every tool call, that is noise below the
/// measurement floor; `ListenerLatencyTests` measures the p99 with a heartbeat
/// running beside it rather than taking the claim on trust.
///
/// # Reapability [I4]
///
/// It holds no state that can outlive it: one flag and one `Liveness` behind a
/// lock, and a queue it owns. `stop()` is idempotent and the next scheduled
/// tick returns without doing anything. There is nothing to leak because there
/// is nothing open.
public final class ListenerHeartbeat: Sendable {

    /// The request target that marks a request as a probe.
    ///
    /// A path rather than a header or a body sentinel, for two reasons. It is
    /// the first token of the first line, so the listener can recognise it
    /// before it has looked at anything else; and it cannot collide with a hook
    /// POST, which goes to `/hook`.
    public static let path = "/_liveness"

    /// How often a beat is attempted.
    ///
    /// **One second, and the number is taken from the reaper rather than
    /// chosen.** `LiveDriver.sweepInterval` is already 1 s and is already the
    /// rate at which this app decides it is time to look at the world; a second
    /// cadence at some other rate would be a second answer to a question that
    /// has one. It is also the coarsest rate that still lets the scene's `hold`
    /// (two intervals) notice a dead listener inside two seconds, which is
    /// about as long as a person will look at a still room before concluding it
    /// is broken.
    public static let interval: TimeInterval = 1.0

    /// How long one round trip may take before it counts as a failure.
    ///
    /// Loopback connect-and-answer is measured in tens of microseconds
    /// (`ListenerLatencyTests`: p99 under 5 ms over 10 000 requests, and that
    /// is the *listener's* budget, not this one's). 250 ms is three orders of
    /// magnitude of head-room, and it is well under `interval`, so a stalled
    /// probe can never overlap the next one.
    static let timeout: TimeInterval = 0.25

    private struct State {
        var liveness = Liveness()
        var running = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// The probe's own queue, at `.utility`: it must never be the reason a hook
    /// response is late, so it asks for less of the machine than the listener's
    /// `.userInitiated` does.
    private let queue = DispatchQueue(label: "com.spriteroom.heartbeat", qos: .utility)
    private let port: UInt16
    private let interval: TimeInterval

    public init(port: UInt16, interval: TimeInterval = ListenerHeartbeat.interval) {
        self.port = port
        self.interval = max(0.05, interval)
    }

    /// What has actually been proved. Safe to read from any thread, and read
    /// once per frame by the panel.
    public var liveness: Liveness { state.withLock { $0.liveness } }

    /// Begins beating. Idempotent: a second call while running does nothing.
    public func start() {
        let begin = state.withLock { state -> Bool in
            guard !state.running else { return false }
            state.running = true
            return true
        }
        guard begin else { return }
        // The first beat is attempted immediately rather than after `interval`,
        // so a panel that opens onto a live listener says so on its first frame
        // instead of drawing a dark lamp for a second. There is nothing to wait
        // for: the listener is bound by the time anything constructs this.
        schedule(after: 0)
    }

    /// Stops beating. Idempotent. After this the `Liveness` stops changing,
    /// which is the truthful thing for it to do: this object is no longer
    /// checking anything.
    public func stop() {
        state.withLock { $0.running = false }
    }

    private func schedule(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            guard state.withLock({ $0.running }) else { return }
            let succeeded = roundTrip()
            let now = Date()
            state.withLock { state in
                guard state.running else { return }
                if succeeded {
                    state.liveness.beats += 1
                    state.liveness.lastBeatAt = now
                } else {
                    state.liveness.lastFailureAt = now
                }
            }
            schedule(after: interval)
        }
    }

    /// One connect / POST / `202` cycle. `true` only when all three happened.
    ///
    /// Blocking, on this object's own queue, which is why it may be: nothing
    /// else runs there and no cooperative pool thread is held.
    private func roundTrip() -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var limit = timeval(
            tv_sec: Int(Self.timeout),
            tv_usec: Int32((Self.timeout - Double(Int(Self.timeout))) * 1_000_000))
        let limitSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, limitSize)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, limitSize)
        var enable: Int32 = 1
        setsockopt(
            descriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &enable,
            socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return false }

        let request = Array("""
            POST \(Self.path) HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: 0\r
            Connection: close\r
            \r

            """.utf8)
        var sent = 0
        while sent < request.count {
            let wrote = request.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return -1 }
                return write(descriptor, base + sent, request.count - sent)
            }
            guard wrote > 0 else { return false }
            sent += wrote
        }

        // Only the status line is needed, and reading exactly it means a
        // listener that answered something other than `202` (or answered
        // nothing) is a failure rather than a beat.
        let expected = Array("HTTP/1.1 202".utf8)
        var received = [UInt8](repeating: 0, count: expected.count)
        var got = 0
        while got < expected.count {
            let read = received.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return -1 }
                return recv(descriptor, base + got, expected.count - got, 0)
            }
            guard read > 0 else { return false }
            got += read
        }
        return received == expected
    }
}
