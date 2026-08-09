import Foundation
import Testing

@testable import SpriteRoomCore

/// **The liveness signal, and the half of it that matters most: the negative.**
///
/// A test that only shows the lamp beating is half a test. Anything at all
/// beats when everything is fine — a timer does, and a timer is the fiction
/// this whole design exists to avoid. What has to be shown is that the beat
/// **stops when the listener stops**, and that is what
/// `theHeartbeatStopsWhenTheListenerStops` is. [I1]
@Suite(.serialized) struct LivenessTests {

    /// A listener bound to an ephemeral port, handed to `body` along with the
    /// object itself so a test can kill it half way through.
    ///
    /// Port 0, always. The user's live app is on 8787 and nothing in this suite
    /// may bind, disturb or be mistaken for it.
    static func withListener<R>(
        _ body: (UInt16, HookListener, EventQueue, IngestStats) async throws -> R
    ) async throws -> R {
        let queue = EventQueue(capacity: 4096)
        let stats = IngestStats()
        let listener = try HookListener(port: 0, queue: queue, stats: stats)
        let port = try await listener.start()
        defer {
            listener.stop()
            queue.finish()
        }
        return try await body(port, listener, queue, stats)
    }

    /// Polls `condition` until it holds or `seconds` elapse. Returns whether it
    /// held. Polling rather than sleeping a fixed span so a fast machine does
    /// not pay for a slow one's worst case.
    static func waitUntil(
        _ seconds: Double, _ condition: @Sendable () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: The positive

    @Test func theHeartbeatBeatsThroughARealListener() async throws {
        try await Self.withListener { port, _, _, stats in
            let heartbeat = ListenerHeartbeat(port: port, interval: 0.05)
            defer { heartbeat.stop() }
            #expect(heartbeat.liveness.beats == 0, "nothing is proved before it starts")
            #expect(heartbeat.liveness.lastBeatAt == nil)

            heartbeat.start()
            let beat = await Self.waitUntil(5) { heartbeat.liveness.beats >= 3 }
            #expect(beat, "three round trips in five seconds against a live listener")

            let liveness = heartbeat.liveness
            #expect(liveness.lastBeatAt != nil)
            // Every beat is a request the listener actually answered, so the
            // two counts are the same number seen from the two ends of the
            // socket. If they ever diverge, something is beating without
            // posting — which is the fiction this design forbids. [I1]
            #expect(stats.counters.probes >= liveness.beats)
        }
    }

    // MARK: The negative — the half that makes it a signal rather than a clock

    @Test func theHeartbeatStopsWhenTheListenerStops() async throws {
        try await Self.withListener { port, listener, _, _ in
            let heartbeat = ListenerHeartbeat(port: port, interval: 0.05)
            defer { heartbeat.stop() }
            heartbeat.start()
            #expect(await Self.waitUntil(5) { heartbeat.liveness.beats >= 2 })

            listener.stop()
            // One interval of grace: a beat already in flight when the socket
            // closed is allowed to land.
            try? await Task.sleep(for: .milliseconds(200))
            let atDeath = heartbeat.liveness

            // Twenty intervals of a heartbeat that is still running, still
            // scheduled, and still trying.
            try? await Task.sleep(for: .seconds(1))
            let after = heartbeat.liveness

            #expect(after.beats == atDeath.beats, """
                the heartbeat kept beating with the listener dead: \
                \(atDeath.beats) → \(after.beats). It is a clock, not a signal.
                """)
            #expect(after.lastBeatAt == atDeath.lastBeatAt)
            // …and it is *trying*, which is what separates "stopped counting"
            // from "stopped looking". A failure recorded after the listener
            // died is the probe reporting the failure rather than going quiet.
            let failure = try #require(after.lastFailureAt)
            #expect(failure > atDeath.lastBeatAt!)
        }
    }

    @Test func aStoppedHeartbeatStopsMovingAndStaysStopped() async throws {
        try await Self.withListener { port, _, _, _ in
            let heartbeat = ListenerHeartbeat(port: port, interval: 0.05)
            heartbeat.start()
            #expect(await Self.waitUntil(5) { heartbeat.liveness.beats >= 2 })
            heartbeat.stop()
            try? await Task.sleep(for: .milliseconds(300))
            let stopped = heartbeat.liveness
            try? await Task.sleep(for: .milliseconds(500))
            #expect(heartbeat.liveness == stopped)
            // Idempotent, and a second stop cannot resurrect it.
            heartbeat.stop()
            #expect(heartbeat.liveness == stopped)
        }
    }

    // MARK: The probe never reaches the world [I1, I5]

    @Test func aProbeIsCountedOnItsOwnAxisAndNeverDecoded() async throws {
        try await Self.withListener { port, _, _, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            let response = try client.responseText(
                body: Data(), expecting: HookListener.responseByteCount,
                path: ListenerHeartbeat.path)
            #expect(response.hasPrefix("HTTP/1.1 202 Accepted"))

            let counters = stats.counters
            #expect(counters.probes == 1)
            // Not a hook request, not a malformed one. Both of those counters
            // exist to notice something, and a probe folded into either would
            // be a steady drip of our own traffic burying the signal.
            #expect(counters.requests == 0)
            #expect(counters.malformed == 0)
            #expect(counters.decoded == 0)
        }
    }

    @Test func aProbeNeverEntersTheQueueAndCannotCreateAWorld() async throws {
        try await Self.withListener { port, _, queue, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            // A probe, then a real event. If the probe ever became a
            // `HookEvent` the drain would see it first.
            _ = try client.responseText(
                body: Data(), expecting: HookListener.responseByteCount,
                path: ListenerHeartbeat.path)
            let payload = try ListenerTests.samplePayload()
            _ = try client.responseText(
                body: payload, expecting: HookListener.responseByteCount)

            var iterator = queue.events.makeAsyncIterator()
            let first = await iterator.next()
            #expect(first?.kind.name == "PreToolUse", "the probe reached the queue")

            let counters = stats.counters
            #expect(counters.probes == 1)
            #expect(counters.requests == 1)
            #expect(counters.decoded == 1)
        }
    }

    @Test func aHookRequestIsNeverMistakenForAProbe() async throws {
        try await Self.withListener { port, _, _, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }
            _ = try client.responseText(
                body: try ListenerTests.samplePayload(),
                expecting: HookListener.responseByteCount)
            #expect(stats.counters.probes == 0)
            #expect(stats.counters.requests == 1)
        }
    }

    /// The probe path is not a prefix match and not a substring match.
    @Test func onlyTheExactProbeTargetCounts() async throws {
        try await Self.withListener { port, _, _, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }
            for path in ["/hook", "/_livenessx", "/x/_liveness", "/"] {
                _ = try client.responseText(
                    body: Data(), expecting: HookListener.responseByteCount, path: path)
            }
            #expect(stats.counters.probes == 0)
            #expect(stats.counters.malformed == 4, "four empty bodies, none of them a probe")
        }
    }

    // MARK: I5 — the probe must not be why a hook response is late

    /// The listener's p99 budget is 5 ms and the session blocks on it. A
    /// heartbeat running beside it at its **real** rate must not move that.
    ///
    /// 2000 requests rather than `ListenerLatencyTests`' 10 000: this is not a
    /// second measurement of the listener, it is a check that adding one
    /// self-POST a second changes nothing about it.
    @Test func aRunningHeartbeatDoesNotCostTheSessionLatency() async throws {
        try await Self.withListener { port, _, queue, _ in
            let payload = try ListenerTests.samplePayload()
            let heartbeat = ListenerHeartbeat(port: port)
            defer { heartbeat.stop() }
            heartbeat.start()

            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }
            for _ in 0..<200 {
                try client.roundTrip(body: payload, expecting: HookListener.responseByteCount)
            }
            let drain = Task.detached {
                var seen = 0
                for await _ in queue.events {
                    seen += 1
                    if seen >= 2200 { break }
                }
            }
            var samples: [Double] = []
            for _ in 0..<2000 {
                samples.append(
                    try client.roundTrip(
                        body: payload, expecting: HookListener.responseByteCount))
            }
            drain.cancel()

            let p99 = percentile(samples, 0.99) * 1000
            print("""

                listener p99 with a 1 Hz heartbeat beside it: \
                \(String(format: "%.3f", p99)) ms over \(samples.count) requests \
                (\(heartbeat.liveness.beats) beats landed during the run)
                """)
            #expect(p99 < ListenerLatencyTests.budgetSeconds * 1000)
        }
    }
}
