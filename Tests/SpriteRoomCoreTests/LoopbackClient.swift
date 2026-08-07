import Darwin
import Foundation

/// A deliberately dumb blocking HTTP client over a raw loopback socket.
///
/// It exists so the latency numbers measure the *listener*, not a client
/// framework's scheduling. One connection, keep-alive, one request in flight —
/// which is the shape of a Claude Code session blocking on a hook response.
struct LoopbackClient {

    enum ClientError: Error {
        case couldNotConnect(Int32)
        case writeFailed(Int32)
        case readFailed(Int32)
        case closed
    }

    private let descriptor: Int32

    init(port: UInt16) throws {
        descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ClientError.couldNotConnect(errno) }

        var enable: Int32 = 1
        setsockopt(
            descriptor, Int32(IPPROTO_TCP), TCP_NODELAY, &enable,
            socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(descriptor)
            throw ClientError.couldNotConnect(code)
        }
    }

    func closeConnection() {
        close(descriptor)
    }

    func requestBytes(body: Data, path: String = "/hook", closeAfter: Bool = false) -> Data {
        var request = Data("""
            POST \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n\
            \(closeAfter ? "Connection: close\r\n" : "")Content-Length: \(body.count)\r\n\r\n
            """.utf8)
        request.append(body)
        return request
    }

    private func sendAll(_ payload: Data) throws {
        try payload.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let written = write(descriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                guard written > 0 else { throw ClientError.writeFailed(errno) }
                sent += written
            }
        }
    }

    private func readExactly(_ count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let got = buffer.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress!.advanced(by: received), count - received)
            }
            if got == 0 { throw ClientError.closed }
            guard got > 0 else { throw ClientError.readFailed(errno) }
            received += got
        }
        return buffer
    }

    /// Sends one request and blocks until the whole response has come back.
    /// Returns the elapsed time in seconds — the wait a Claude Code session
    /// actually pays on every hooked tool call.
    @discardableResult
    func roundTrip(body: Data, expecting responseBytes: Int) throws -> Double {
        let payload = requestBytes(body: body)
        let start = DispatchTime.now().uptimeNanoseconds
        try sendAll(payload)
        _ = try readExactly(responseBytes)
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    /// Every response we send is bodiless, so this is the whole thing.
    func responseText(
        body: Data, expecting responseBytes: Int, closeAfter: Bool = false
    ) throws -> String {
        try sendAll(requestBytes(body: body, closeAfter: closeAfter))
        return String(decoding: try readExactly(responseBytes), as: UTF8.self)
    }
}

/// Percentile over an unsorted sample, nearest-rank.
func percentile(_ samples: [Double], _ fraction: Double) -> Double {
    guard !samples.isEmpty else { return 0 }
    let sorted = samples.sorted()
    let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
    return sorted[min(max(rank, 0), sorted.count - 1)]
}
