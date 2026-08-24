import Foundation
import Testing

@testable import SpriteRoomCore

/// The framing layer sits in front of everything. A hook POST blocks the
/// session that sent it until this replies, so a listener that traps takes down
/// every Claude Code session pointed at it: the failure is not a missing room,
/// it is the user's own work stopping. These are the malformed-input cases,
/// none of which had any coverage.
@Suite struct HTTPFramingTests {

    private static func raw(_ headers: String, body: String = "") -> Data {
        Data("POST / HTTP/1.1\r\n\(headers)\r\n\r\n\(body)".utf8)
    }

    // MARK: the well-formed case, so the malformed ones mean something

    @Test func aWellFormedRequestFramesItsBodyAndLeavesTheRemainder() throws {
        let buffer = Self.raw("Content-Length: 4", body: "abcdEXTRA")
        let parsed = try #require(HTTPRequest.parse(buffer))
        #expect(String(data: parsed.request.body, encoding: .utf8) == "abcd")
        #expect(String(data: parsed.remainder, encoding: .utf8) == "EXTRA")
        #expect(parsed.request.keepAlive)
    }

    @Test func aPartialBodyIsNotARequestYet() {
        #expect(HTTPRequest.parse(Self.raw("Content-Length: 10", body: "abcd")) == nil)
    }

    // MARK: the crash

    /// **This traps against the old code rather than failing.** `Content-Length`
    /// was read as `Int(value) ?? 0`, which accepts a negative, which puts
    /// `bodyEnd` before `bodyStart`, and slicing `Data` with a reversed range
    /// is a fatal error, not a thrown one. One malformed header from anything
    /// that can reach the port would end the process.
    @Test func aNegativeContentLengthDoesNotTakeTheProcessDown() throws {
        for value in ["-1", "-9999999"] {
            let parsed = try #require(HTTPRequest.parse(Self.raw("Content-Length: \(value)")))
            #expect(parsed.request.body.isEmpty)
        }
    }

    @Test func anUnparseableContentLengthFramesAnEmptyBody() throws {
        for value in ["", "abc", "1.5", "0x10", "99999999999999999999999999"] {
            let parsed = try #require(
                HTTPRequest.parse(Self.raw("Content-Length: \(value)", body: "xyz")))
            #expect(parsed.request.body.isEmpty, "Content-Length: \(value) framed a body")
        }
    }

    // MARK: the unbounded paths

    /// A declared length past the cap is answered and closed instead of
    /// buffered. The alternative is the listener holding whatever a client cares
    /// to claim it is about to send.
    @Test func anAbsurdlyLargeContentLengthIsRefusedRatherThanBuffered() throws {
        let over = HTTPRequest.maximumBodyBytes + 1
        let parsed = try #require(HTTPRequest.parse(Self.raw("Content-Length: \(over)")))
        #expect(parsed.request.body.isEmpty)
        #expect(!parsed.request.keepAlive, "the connection must not be kept for a refused body")
        #expect(parsed.remainder.isEmpty)
    }

    /// The quieter unbounded path: no `\r\n\r\n` ever arrives, so there is no
    /// declared length to check and `parse` returns `nil` forever while the
    /// caller keeps appending. Capping the body alone would not have caught it.
    @Test func aHeadThatNeverTerminatesIsAbandonedOnceItPassesTheCap() throws {
        let short = Data(repeating: UInt8(ascii: "x"), count: 1024)
        #expect(HTTPRequest.parse(short) == nil, "a short unterminated head is just incomplete")

        let huge = Data(
            repeating: UInt8(ascii: "x"), count: HTTPRequest.maximumHeaderBytes + 1)
        let parsed = try #require(HTTPRequest.parse(huge))
        #expect(parsed.request.body.isEmpty)
        #expect(!parsed.request.keepAlive)
        #expect(parsed.remainder.isEmpty)
    }

    // MARK: the real ceiling

    /// The largest POST measured in a live session is 5.7 MB, from a 5.5 MB
    /// `Edit` (a hook payload carries the whole `tool_input`). It has to frame
    /// intact, and nothing covered it.
    @Test func aMultiMegabyteEditStillFramesExactly() throws {
        let body = String(repeating: "a", count: 5_700_000)
        let parsed = try #require(
            HTTPRequest.parse(Self.raw("Content-Length: \(body.utf8.count)", body: body)))
        #expect(parsed.request.body.count == 5_700_000)
        #expect(parsed.remainder.isEmpty)
        #expect(parsed.request.keepAlive)
    }

    // MARK: framing details that already held, now pinned

    @Test func connectionCloseIsHonouredAndIsCaseInsensitive() throws {
        for header in ["Connection: close", "connection: CLOSE", "CONNECTION: Close"] {
            let parsed = try #require(
                HTTPRequest.parse(Self.raw("Content-Length: 0\r\n\(header)")))
            #expect(!parsed.request.keepAlive, "\(header) was not honoured")
        }
    }

    @Test func aHeadThatIsNotUTF8IsConsumedSoTheConnectionCannotWedge() throws {
        var buffer = Data([0xFF, 0xFE, 0xFF])
        buffer.append(Data("\r\n\r\nleftover".utf8))
        let parsed = try #require(HTTPRequest.parse(buffer))
        #expect(parsed.request.body.isEmpty)
        #expect(!parsed.request.keepAlive)
        #expect(String(data: parsed.remainder, encoding: .utf8) == "leftover")
    }

    /// Two requests in one read, which is what pipelining gives us.
    @Test func twoPipelinedRequestsFrameOneAfterTheOther() throws {
        var buffer = Self.raw("Content-Length: 2", body: "ab")
        buffer.append(Self.raw("Content-Length: 3", body: "cde"))

        let first = try #require(HTTPRequest.parse(buffer))
        #expect(String(data: first.request.body, encoding: .utf8) == "ab")
        let second = try #require(HTTPRequest.parse(first.remainder))
        #expect(String(data: second.request.body, encoding: .utf8) == "cde")
        #expect(second.remainder.isEmpty)
    }
}
