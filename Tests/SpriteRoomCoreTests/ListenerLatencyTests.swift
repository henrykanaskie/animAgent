import Foundation
import Testing

@testable import SpriteRoomCore

/// M1 exit criterion: the listener responds `202` in under 5 ms at p99 over
/// 10 000 requests.
///
/// The number matters because there is no `async` field on the HTTP hook
/// schema — the session blocks on the answer, so this latency is added to every
/// tool call the user makes. A listener that held for 3 s was measured adding
/// 3 s per call. [I5]
@Suite(.serialized) struct ListenerLatencyTests {

    static let requestCount = 10_000
    static let budgetSeconds = 0.005

    @Test func respondsUnderFiveMillisecondsAtP99Over10kRequests() async throws {
        let payload = try ListenerTests.samplePayload()

        let (samples, counters) = try await ListenerTests.withListener(capacity: 1 << 16) {
            port, queue, stats -> ([Double], IngestCounters) in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            // Warm the connection and the decoder before measuring.
            for _ in 0..<200 {
                try client.roundTrip(body: payload, expecting: HookListener.responseByteCount)
            }

            // Drain concurrently, as the real app does: a full queue would
            // measure the queue, not the listener.
            let drain = Task.detached {
                var seen = 0
                for await _ in queue.events {
                    seen += 1
                    if seen >= Self.requestCount { break }
                }
            }

            var samples: [Double] = []
            samples.reserveCapacity(Self.requestCount)
            for _ in 0..<Self.requestCount {
                samples.append(
                    try client.roundTrip(body: payload, expecting: HookListener.responseByteCount))
            }
            drain.cancel()
            return (samples, stats.counters)
        }

        let p50 = percentile(samples, 0.50) * 1000
        let p95 = percentile(samples, 0.95) * 1000
        let p99 = percentile(samples, 0.99) * 1000
        let worst = (samples.max() ?? 0) * 1000
        let mean = samples.reduce(0, +) / Double(samples.count) * 1000

        print("""

            listener latency over \(samples.count) requests (round trip, keep-alive loopback)
              mean \(String(format: "%.3f", mean)) ms
              p50  \(String(format: "%.3f", p50)) ms
              p95  \(String(format: "%.3f", p95)) ms
              p99  \(String(format: "%.3f", p99)) ms
              max  \(String(format: "%.3f", worst)) ms
              requests \(counters.requests)  decoded \(counters.decoded)  \
            malformed \(counters.malformed)  dropped \(counters.dropped)

            """)

        #expect(counters.malformed == 0)
        #expect(p99 < Self.budgetSeconds * 1000, "p99 was \(p99) ms, budget 5 ms")
    }
}
