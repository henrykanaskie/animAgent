import Darwin
import Foundation
import Testing

@testable import SpriteRoomCore

/// I5: the handler never does work. Read the body, decode, enqueue, respond
/// `202` with an empty body. There is no `async` field on the HTTP hook schema:
/// the session blocks on our answer, so every millisecond here is a millisecond
/// on the user's every tool call.
@Suite(.serialized) struct ListenerTests {

    /// Starts a listener on an ephemeral port and tears it down afterwards.
    static func withListener<R>(
        capacity: Int = 4096,
        _ body: (UInt16, EventQueue, IngestStats) async throws -> R
    ) async throws -> R {
        let queue = EventQueue(capacity: capacity)
        let stats = IngestStats()
        let listener = try HookListener(port: 0, queue: queue, stats: stats)
        let port = try await listener.start()
        defer {
            listener.stop()
            queue.finish()
        }
        return try await body(port, queue, stats)
    }

    static func samplePayload() throws -> Data {
        let entries = try Fixtures.entries("single-agent-simple")
        return try #require(entries.first { $0.event?.kind.name == "PreToolUse" }).payload
    }

    @Test func respondsWith202AndAnEmptyBody() async throws {
        try await Self.withListener { port, queue, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            let response = try client.responseText(
                body: try Self.samplePayload(), expecting: HookListener.responseByteCount)
            #expect(response.hasPrefix("HTTP/1.1 202 Accepted"))
            #expect(response.contains("Content-Length: 0"))
            #expect(response.hasSuffix("\r\n\r\n"))

            var iterator = queue.events.makeAsyncIterator()
            let event = await iterator.next()
            #expect(event?.kind.name == "PreToolUse")
            #expect(stats.counters.requests == 1)
            #expect(stats.counters.decoded == 1)
            #expect(stats.counters.malformed == 0)
        }
    }

    /// A malformed body still gets a `202` and a counter increment, never an
    /// error back into the session.
    @Test func malformedBodyStillGets202AndIsCounted() async throws {
        try await Self.withListener { port, _, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            for body in ["not json at all {", "", "[]", #"{"hook_event_name":"Stop"}"#] {
                let response = try client.responseText(
                    body: Data(body.utf8), expecting: HookListener.responseByteCount)
                #expect(response.hasPrefix("HTTP/1.1 202 Accepted"), "body: \(body)")
            }
            #expect(stats.counters.requests == 4)
            #expect(stats.counters.decoded == 0)
            #expect(stats.counters.malformed == 4)
        }
    }

    /// Loopback only. Never `0.0.0.0`. If the listener were bound to every
    /// interface, a connection to a non-loopback local address would succeed.
    @Test func boundToLoopbackOnly() async throws {
        try await Self.withListener { port, _, _ in
            // 127.0.0.1 works.
            let loopback = try LoopbackClient(port: port)
            loopback.closeConnection()

            // A routable local address for this host must not.
            var reachable = false
            for address in Self.nonLoopbackIPv4Addresses() {
                if Self.canConnect(to: address, port: port) { reachable = true }
            }
            #expect(!reachable, "the listener answered on a non-loopback address")
        }
    }

    @Test func manyRequestsOnOneKeepAliveConnectionAllArriveInOrder() async throws {
        let entries = try Fixtures.entries("single-agent-simple")
            .filter { $0.event != nil }

        try await Self.withListener { port, queue, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            for entry in entries {
                try client.roundTrip(
                    body: entry.payload, expecting: HookListener.responseByteCount)
            }

            var received: [String] = []
            var iterator = queue.events.makeAsyncIterator()
            for _ in entries {
                guard let event = await iterator.next() else { break }
                received.append(event.kind.name)
            }
            #expect(received == entries.map { $0.event!.kind.name })
            #expect(stats.counters.dropped == 0)
        }
    }

    /// `Connection: close` must still get its `202` before the socket goes
    /// away. A lost response is a session waiting on a timeout it should never
    /// have seen.
    @Test func connectionCloseStillGetsItsResponse() async throws {
        try await Self.withListener { port, _, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            let response = try client.responseText(
                body: try Self.samplePayload(),
                expecting: HookListener.responseByteCount,
                closeAfter: true)
            #expect(response.hasPrefix("HTTP/1.1 202 Accepted"))
            #expect(stats.counters.decoded == 1)
        }
    }

    /// A full queue drops and counts. It never blocks the handler, and it never
    /// fails a request.
    @Test func aFullQueueDropsRatherThanBlocks() async throws {
        try await Self.withListener(capacity: 2) { port, _, stats in
            let client = try LoopbackClient(port: port)
            defer { client.closeConnection() }

            let payload = try Self.samplePayload()
            for _ in 0..<8 {
                let response = try client.responseText(
                    body: payload, expecting: HookListener.responseByteCount)
                #expect(response.hasPrefix("HTTP/1.1 202 Accepted"))
            }
            #expect(stats.counters.requests == 8)
            #expect(stats.counters.dropped > 0)
        }
    }

    // MARK: helpers

    static func nonLoopbackIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let sockaddrPointer = entry.pointee.ifa_addr,
                  sockaddrPointer.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                sockaddrPointer, socklen_t(sockaddrPointer.pointee.sa_len),
                &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let address = String(decoding: bytes, as: UTF8.self)
            if address != "127.0.0.1" { addresses.append(address) }
        }
        return addresses
    }

    static func canConnect(to address: String, port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(
            descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout,
            socklen_t(MemoryLayout<timeval>.size))

        var target = sockaddr_in()
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        guard address.withCString({ inet_pton(AF_INET, $0, &target.sin_addr) }) == 1 else {
            return false
        }
        return withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
