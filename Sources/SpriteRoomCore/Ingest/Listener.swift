import Foundation
import Network
import os

/// The in-process HTTP listener Claude Code POSTs hook payloads to.
///
/// **I5 — the handler never does work.** Read the body, decode, enqueue,
/// respond `202` with an empty body. Nothing else happens on that path: no
/// rendering, no disk, no lock held across a response. There is no `async`
/// field on the HTTP hook schema, so the session *blocks* on our answer — a
/// listener that holds for 3 s adds 3 s to every tool call. Measured.
///
/// **Loopback only.** Bound to `127.0.0.1`. Never `0.0.0.0`.
public final class HookListener: Sendable {

    public enum ListenerError: Error, Sendable {
        case invalidPort(UInt16)
        case notReady
    }

    /// Exactly what every request gets, whatever it contained.
    static let acceptedResponse = Data("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\n\r\n".utf8)

    /// Byte length of `acceptedResponse`, so a benchmark client knows when one
    /// response has fully arrived.
    public static let responseByteCount = acceptedResponse.count

    public let stats: IngestStats

    private let listener: NWListener
    private let queue: EventQueue
    private let dispatchQueue = DispatchQueue(
        label: "com.spriteroom.listener", qos: .userInitiated)

    /// - Parameter port: `0` asks the system for an ephemeral port; read the
    ///   assigned one back from `start()`.
    public init(port: UInt16, queue: EventQueue, stats: IngestStats = IngestStats()) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerError.invalidPort(port)
        }
        self.queue = queue
        self.stats = stats

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        // Loopback only. This is the bind address, not a filter. [I5]
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        self.listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the port actually bound.
    public func start() async throws -> UInt16 {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        @Sendable func claim() -> Bool {
            resumed.withLock { alreadyResumed in
                if alreadyResumed { return false }
                alreadyResumed = true
                return true
            }
        }

        listener.newConnectionHandler = { [self] connection in
            accept(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    guard claim() else { return }
                    if let port = listener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: ListenerError.notReady)
                    }
                case .failed(let error), .waiting(let error):
                    // For a loopback bind, `waiting` means the port is taken
                    // and retrying forever helps nobody. Surface it.
                    guard claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard claim() else { return }
                    continuation.resume(throwing: ListenerError.notReady)
                default:
                    break
                }
            }
            listener.start(queue: dispatchQueue)
        }
    }

    public func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: dispatchQueue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [self] data, _, isComplete, error in

            var pending = buffer
            if let data, !data.isEmpty { pending.append(data) }

            var responses = Data()
            var keepAlive = true
            while let parsed = HTTPRequest.parse(pending) {
                pending = parsed.remainder
                handle(body: parsed.request.body)
                responses.append(HookListener.acceptedResponse)
                if !parsed.request.keepAlive {
                    keepAlive = false
                    break
                }
            }

            let finished = error != nil || isComplete || !keepAlive
            if !responses.isEmpty {
                if finished {
                    // Flush before tearing down, or the last `202` is lost and
                    // the session waits for a timeout it should never see.
                    connection.send(content: responses, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }
                connection.send(content: responses, completion: .idempotent)
            }

            if finished {
                connection.cancel()
                return
            }
            receive(connection, buffer: pending)
        }
    }

    /// The entire hot path. Decode, enqueue, count. Anything more expensive
    /// than this belongs downstream of the queue.
    private func handle(body: Data) {
        guard let event = HookEventDecoder.decode(body) else {
            stats.record(decoded: false, dropped: false)
            return
        }
        let result = queue.enqueue(event)
        stats.record(decoded: true, dropped: result == .dropped)
    }
}

// MARK: - Minimal HTTP/1.1 request framing

/// Just enough HTTP to find where one request ends and the next begins.
///
/// `Content-Length` framing only: Claude Code POSTs a JSON body from an
/// ordinary HTTP client, which always sets it. A body framed any other way
/// reads as empty, which decodes to nothing, which is counted as malformed and
/// still answered `202` — the failure mode stays harmless.
struct HTTPRequest {
    let body: Data
    let keepAlive: Bool

    struct Parsed {
        let request: HTTPRequest
        let remainder: Data
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    /// The largest body this listener will frame, at 64 MB.
    ///
    /// Chosen against the measured ceiling rather than a round number that felt
    /// safe: the largest POST observed is 5.7 MB, produced by a 5.5 MB `Edit`,
    /// because a hook payload carries the whole `tool_input`. 64 MB leaves an
    /// order of magnitude over that and still bounds what one connection can
    /// make this process hold.
    static let maximumBodyBytes = 64 * 1024 * 1024

    /// The largest head this listener will wait through, at 256 KB. Claude
    /// Code's hook request carries a handful of ordinary headers; anything past
    /// this is not going to terminate.
    static let maximumHeaderBytes = 256 * 1024

    /// Returns `nil` while the buffer holds less than one complete request.
    static func parse(_ buffer: Data) -> Parsed? {
        guard let headerEnd = buffer.firstRange(of: headerTerminator) else {
            // The other unbounded path, and the quieter one: a client that never
            // sends `\r\n\r\n` leaves this returning `nil` forever while the
            // caller appends to the same buffer. Capping the body alone would
            // not have caught it, because a request with no head has no
            // declared length to check.
            guard buffer.count > maximumHeaderBytes else { return nil }
            return Parsed(
                request: HTTPRequest(body: Data(), keepAlive: false),
                remainder: Data())
        }

        let headerBytes = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerBytes, encoding: .utf8) else {
            // Unparseable head: consume it so the connection cannot wedge.
            return Parsed(
                request: HTTPRequest(body: Data(), keepAlive: false),
                remainder: Data(buffer[headerEnd.upperBound...]))
        }

        var contentLength = 0
        var keepAlive = true
        for line in headerText.split(separator: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch name {
            // **Clamped at zero, and that is a crash fix rather than tidiness.**
            // `Int(value) ?? 0` accepted a negative, which made `bodyEnd` land
            // *before* `bodyStart`, and `buffer[bodyStart..<bodyEnd]` on a
            // reversed range is a trap, not an error — one malformed header
            // would take the listener down and with it every session posting to
            // it. A negative length frames no body, so it reads as empty, which
            // decodes to nothing, which is counted malformed and answered `202`
            // like any other unparseable request. [I5]
            case "content-length": contentLength = max(0, Int(value) ?? 0)
            case "connection": keepAlive = value.lowercased() != "close"
            default: break
            }
        }

        // A body larger than anything Claude Code can legitimately send is a
        // broken or hostile client, and buffering it is how a listener becomes
        // the reason a machine runs out of memory. Consume the head and frame an
        // empty body: the connection cannot wedge, and the sender is answered
        // rather than left waiting on a socket that will never reply. The
        // largest real POST measured is 5.7 MB, from a 5.5 MB `Edit`.
        guard contentLength <= maximumBodyBytes else {
            return Parsed(
                request: HTTPRequest(body: Data(), keepAlive: false),
                remainder: Data())
        }

        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else {
            return nil
        }
        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        return Parsed(
            request: HTTPRequest(body: Data(buffer[bodyStart..<bodyEnd]), keepAlive: keepAlive),
            remainder: Data(buffer[bodyEnd...]))
    }
}
