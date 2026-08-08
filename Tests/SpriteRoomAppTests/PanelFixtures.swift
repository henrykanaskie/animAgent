import AppKit
import Foundation
import Testing
@testable import SpriteRoomApp

/// **Is there a window server?** Asked once, here, and nowhere else.
///
/// An `NSPanel` cannot be constructed without a logged-in GUI session, so the
/// 26 tests that assert on a real panel are gated on `isAvailable` and skip on
/// any headless runner — a CI container, an `ssh` session, a `launchd` job, any
/// process outside the Aqua session.
///
/// This mirrors `SceneArt` in `Tests/SpriteRoomSceneTests/SceneFixtures.swift`
/// deliberately, idiom for idiom, because the two gates answer the same shape of
/// question and a second idiom would be one more thing to keep true. Read that
/// one first; everything here means what it means there.
///
/// **The gate alone was the dishonesty.** Until this type existed the window
/// server gate had the art gate's shape and none of its honesty: 26 tests,
/// no notice, no pinned count. On a headless runner all 26 skipped — *including
/// every I8 assertion* — `swift test` exited 0, and the summary was
/// indistinguishable from a run that had verified them. That matters more here
/// than for the art, because I8 ("the panel never steals focus") is the
/// invariant that was verified by hand with a stopwatch before these tests
/// existed. A green run that quietly skipped them re-opens exactly the hole
/// they were written to close.
///
/// `PanelAvailabilityTests` below always runs, in both modes, and reports which
/// of the two runs actually happened.
///
/// **Override.** Set `SPRITE_ROOM_REQUIRE_WINDOW_SERVER=1` on a machine that is
/// supposed to have a GUI session — a developer's laptop, a self-hosted runner
/// with a real login session, the machine cutting a release — and an absent
/// window server becomes a hard failure in `PanelAvailabilityTests` instead of a
/// skip. Named to match `SPRITE_ROOM_REQUIRE_ART` and parsed identically.
enum PanelWindowServer {

    /// What the process could learn about its own session.
    struct Survey: Sendable {
        /// `CGSessionCopyCurrentDictionary()` returned a dictionary.
        var hasSession: Bool = false

        var isAvailable: Bool { hasSession }
    }

    /// Computed once per test run. One nonisolated C call.
    static let survey = Survey(hasSession: CGSessionCopyCurrentDictionary() != nil)

    /// The gate. Safe to evaluate as a test trait: `nonisolated`, no throwing,
    /// no actor hops.
    static var isAvailable: Bool { survey.isAvailable }

    /// `SPRITE_ROOM_REQUIRE_WINDOW_SERVER=1` turns an absent window server from
    /// a skip into a failure.
    static var isRequired: Bool {
        let raw = ProcessInfo.processInfo.environment["SPRITE_ROOM_REQUIRE_WINDOW_SERVER"]?
            .trimmingCharacters(in: .whitespaces).lowercased()
        return ["1", "true", "yes"].contains(raw ?? "")
    }

    /// The three assertions that carry I8. Named in the absent notice, so they
    /// are checked here against the source rather than left to rot into a lie
    /// after a rename.
    static let invariant8TestNames = [
        "thePanelCanNeverBecomeKeyOrMain",
        "thePanelRefusesToInstallAFirstResponder",
        "thePanelIsConfiguredTheWayTheInvariantRequires",
    ]

    /// `Tests/SpriteRoomAppTests`, from this file's own location.
    static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    /// What a scan of the test sources found carrying the gate.
    struct Scan: Sendable {
        /// Gate annotations on a line that also declares a `@Test`.
        var gatedTests: Int = 0
        /// `file:line` for a gate on a `@Suite`. The scanner counts *tests*, so
        /// a suite-level gate would silently hide however many tests that suite
        /// holds. Reported as a failure rather than absorbed.
        var gatedSuites: [String] = []
        /// `file:line` for a gate on a line that declares neither. Either the
        /// annotation was split across lines — which would undercount — or
        /// something copied a whole gate string into prose. This is the trap
        /// that bit `SceneArt`'s author: a scanner written the obvious way
        /// counts *itself*. Nothing here can, because the needles below are
        /// assembled at runtime and no literal gate string exists in this file
        /// — but if one ever lands here it fails loudly instead of inflating
        /// the count by one and looking correct.
        var unattributed: [String] = []
        /// Sources actually read. Zero means the scan found nothing to scan,
        /// which is a broken scanner, not a codebase with no gated tests.
        var filesRead: Int = 0
    }

    /// The number of tests carrying the gate, counted from the test sources at
    /// runtime rather than maintained by hand, so the notice cannot drift into
    /// naming a number that stopped being true.
    ///
    /// Diverges from `SceneArt.gatedTestCount` in one way, on purpose: it counts
    /// per *line* and requires the line to declare a `@Test`, where `SceneArt`
    /// counts occurrences anywhere in the file. That is what lets the two holes
    /// above — a suite-level gate, a gate the scanner cannot attribute — be
    /// reported instead of silently mis-counted.
    ///
    /// Both spellings are counted. The 26 gates are written
    /// `NotchPanelTests.hasWindowServer`, which is where the gate lived before
    /// this type existed; that spelling is kept, and kept working, so that
    /// closing this hole did not require touching 26 annotations in three files
    /// that other work is live in. A new test may use either name.
    static let scan: Scan = {
        // Assembled from pieces so that these lines do not match themselves.
        let needles = [
            ".enabled(if: NotchPanelTests" + ".hasWindowServer)",
            ".enabled(if: PanelWindowServer" + ".isAvailable)",
        ]
        var scan = Scan()
        let names = (try? FileManager.default
            .contentsOfDirectory(atPath: testsDirectory.path))?.sorted() ?? []

        for name in names where name.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: testsDirectory.appending(path: name),
                                         encoding: .utf8) else { continue }
            scan.filesRead += 1
            for (offset, line) in text.components(separatedBy: "\n").enumerated() {
                let hits = needles.reduce(0) { $0 + line.components(separatedBy: $1).count - 1 }
                guard hits > 0 else { continue }
                let where_ = "\(name):\(offset + 1)"
                if line.contains("@Suite") {
                    scan.gatedSuites.append(where_)
                } else if line.contains("@Test") {
                    scan.gatedTests += hits
                } else {
                    scan.unattributed.append(where_)
                }
            }
        }
        return scan
    }()

    static var gatedTestCount: Int { scan.gatedTests }

    /// What is expected to be gated, so a test that quietly gains *or loses* the
    /// trait is reported rather than absorbed. Update deliberately, in the same
    /// change that moves a test across the line.
    ///
    /// 26 as of the gate being made honest: 6 in `NotchPanelTests` (the three
    /// I8 assertions, plus menu-bar constraint, controller phase, and the
    /// keyboard-capable-view walk), 10 in `ProjectSelectorTests`, 10 in
    /// `ThemeMenuTests`. All three build real AppKit objects.
    static let expectedGatedTestCount = 26

    /// The notice, as a pure function of what was surveyed, so the branch this
    /// machine cannot reach can still be rendered and asserted on. Rendering it
    /// is not the same as proving the 26 skip — see
    /// `theAbsentNoticeSaysTheRunVerifiedNothing`, which is a text test and says
    /// so.
    static func notice(survey: Survey, gated: Int, required: Bool) -> String {
        let rule = String(repeating: "=", count: 78)
        var lines = [rule]

        if survey.isAvailable {
            lines.append(
                "SPRITE ROOM WINDOW SERVER: PRESENT — this process is in a logged-in"
                + " GUI session.")
            lines.append(
                "  \(gated) window-server-dependent tests RAN, including all three I8"
                + " assertions.")
            lines.append("  I8 was checked against a real NSPanel, not argued for in a comment.")
        } else {
            lines.append(
                "SPRITE ROOM WINDOW SERVER: ABSENT —"
                + " CGSessionCopyCurrentDictionary() returned nil.")
            lines.append("  \(gated) window-server-dependent tests were SKIPPED.")
            lines.append("  THIS RUN VERIFIED NOTHING ABOUT THE PANEL.")
            lines.append(
                "  I8 — \"the panel never steals focus\" — was NOT checked by this run.")
            for name in invariant8TestNames { lines.append("    did not execute: \(name)") }
            lines.append("  Expected on a headless runner: a CI container, an ssh session, any")
            lines.append("  process outside the Aqua session. An NSPanel cannot be built without")
            lines.append("  a window server, so these skip rather than fail.")
            if required {
                lines.append(
                    "  SPRITE_ROOM_REQUIRE_WINDOW_SERVER is SET, so this is a FAILURE below.")
            } else {
                lines.append(
                    "  Set SPRITE_ROOM_REQUIRE_WINDOW_SERVER=1 to make this a failure"
                    + " instead of a skip.")
            }
        }
        lines.append(rule)
        return lines.joined(separator: "\n")
    }
}

/// Always runs, in both modes, and never fails for the absence of a window
/// server.
///
/// A gate alone would only relocate the dishonesty: a suite that goes green on a
/// headless runner has reported success having verified nothing about the panel.
/// This prints which of the two runs actually happened. The counterpart to
/// `ArtAvailabilityTests`.
struct PanelAvailabilityTests {

    @Test func theSuiteSaysOutLoudWhetherItCheckedThePanel() {
        let survey = PanelWindowServer.survey
        let gated = PanelWindowServer.gatedTestCount
        print(PanelWindowServer.notice(
            survey: survey, gated: gated, required: PanelWindowServer.isRequired))

        // Never a failure for an absent window server — that is the whole point.
        // Everything below is about the gate's own integrity.
        let drift = "\(gated) tests carry the window-server gate but"
            + " \(PanelWindowServer.expectedGatedTestCount) were expected; update"
            + " PanelWindowServer.expectedGatedTestCount in the same change"
        #expect(gated == PanelWindowServer.expectedGatedTestCount, Comment(rawValue: drift))

        let scan = PanelWindowServer.scan
        #expect(scan.filesRead > 0, "the gate scanner read no test sources at all")
        #expect(
            scan.gatedSuites.isEmpty,
            Comment(rawValue: "the gate is on a @Suite at \(scan.gatedSuites.joined(separator: ", "))"
                + "; the scanner counts tests, so teach it to count that suite's tests"))
        #expect(
            scan.unattributed.isEmpty,
            Comment(rawValue: "a gate at \(scan.unattributed.joined(separator: ", "))"
                + " is on no @Test or @Suite line, so it is not being counted"))

        if PanelWindowServer.isRequired && !survey.isAvailable {
            Issue.record(Comment(rawValue:
                "SPRITE_ROOM_REQUIRE_WINDOW_SERVER is set but there is no window server:"
                + " CGSessionCopyCurrentDictionary() returned nil, so \(gated) panel tests"
                + " skipped and I8 was not checked"))
        }
    }

    /// The absent branch, rendered and asserted on this machine — which has a
    /// window server and so can never reach it for real.
    ///
    /// This proves the *text*. It does not prove that the 26 skip; only a
    /// genuinely headless run proves that.
    @Test func theAbsentNoticeSaysTheRunVerifiedNothing() {
        let text = PanelWindowServer.notice(
            survey: PanelWindowServer.Survey(hasSession: false), gated: 26, required: false)
        #expect(text.contains("ABSENT"))
        #expect(text.contains("26 window-server-dependent tests were SKIPPED."))
        #expect(text.contains("THIS RUN VERIFIED NOTHING ABOUT THE PANEL."))
        #expect(text.contains("SPRITE_ROOM_REQUIRE_WINDOW_SERVER=1"))
        for name in PanelWindowServer.invariant8TestNames {
            #expect(text.contains(name), Comment(rawValue: "the notice does not name \(name)"))
        }

        let required = PanelWindowServer.notice(
            survey: PanelWindowServer.Survey(hasSession: false), gated: 26, required: true)
        #expect(required.contains("is SET, so this is a FAILURE below."))

        let present = PanelWindowServer.notice(
            survey: PanelWindowServer.Survey(hasSession: true), gated: 26, required: false)
        #expect(present.contains("PRESENT"))
        #expect(present.contains("26 window-server-dependent tests RAN"))
        #expect(present.contains("VERIFIED NOTHING") == false)
    }

    /// The notice names three tests by name. If one is renamed and the notice is
    /// not, the notice becomes a lie in exactly the mode nobody is watching.
    @Test func theNoticeNamesI8TestsThatActuallyExistAndAreGated() throws {
        let source = try String(
            contentsOf: PanelWindowServer.testsDirectory.appending(path: "NotchPanelTests.swift"),
            encoding: .utf8)
        let gate = ".enabled(if: NotchPanelTests" + ".hasWindowServer)"
        let lines = source.components(separatedBy: "\n")
        for name in PanelWindowServer.invariant8TestNames {
            guard let index = lines.firstIndex(where: { $0.contains("func \(name)(") }) else {
                Issue.record(Comment(rawValue:
                    "the absent notice names \(name), which no longer exists in"
                    + " NotchPanelTests.swift"))
                continue
            }
            #expect(
                index > 0 && lines[index - 1].contains(gate),
                Comment(rawValue: "\(name) is named in the notice as gated but is not gated"))
        }
    }
}

/// A pointer path, played into a `RevealPolicy` at a fixed sample rate.
///
/// Samples at 120 Hz by default — four times what the real controller uses —
/// so a path that survives this has seen more chances to chatter than it ever
/// will in the app.
struct Simulation {

    var policy: RevealPolicy
    private(set) var now: TimeInterval = 0
    /// Every state change, with the time it happened.
    private(set) var transitions: [(time: TimeInterval, transition: PanelTransition)] = []

    let rate: Double

    init(policy: RevealPolicy, rate: Double = 120) {
        self.policy = policy
        self.rate = rate
    }

    var step: TimeInterval { 1.0 / rate }
    var reveals: Int { transitions.filter { $0.transition == .reveal }.count }
    var retracts: Int { transitions.filter { $0.transition == .retract }.count }

    mutating func sample(_ pointer: PanelPoint?) {
        if let transition = policy.update(pointer: pointer, at: now) {
            transitions.append((now, transition))
        }
        now += step
    }

    /// Hold the pointer still.
    mutating func hold(_ pointer: PanelPoint?, for duration: TimeInterval) {
        var elapsed = 0.0
        while elapsed < duration {
            sample(pointer)
            elapsed += step
        }
    }

    /// Move the pointer in a straight line at constant speed.
    mutating func sweep(from start: PanelPoint, to end: PanelPoint, duration: TimeInterval) {
        let steps = max(1, Int(duration * rate))
        for index in 0...steps {
            let t = Double(index) / Double(steps)
            sample(
                PanelPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t))
        }
    }

    /// The shortest gap between any two state changes. `nil` when there are
    /// fewer than two.
    var closestTransitions: TimeInterval? {
        guard transitions.count >= 2 else { return nil }
        return zip(transitions.dropFirst(), transitions)
            .map { $0.time - $1.time }
            .min()
    }
}

enum PanelFixtures {

    /// The display this was developed on: 14-inch MacBook Pro, 1800×1169
    /// points, camera housing x ∈ [790, 1010], 39-point menu bar.
    static var notched: NotchGeometry {
        NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 1800, height: 1169),
            physicalNotch: PanelRect(x: 790, y: 1131, width: 220, height: 38),
            menuBarHeight: 39)
    }

    static var external: NotchGeometry {
        NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 2560, height: 1440),
            physicalNotch: nil,
            menuBarHeight: 24)
    }

    static func policy(
        _ geometry: NotchGeometry = PanelFixtures.notched,
        tuning: RevealPolicy.Tuning = .default
    ) -> RevealPolicy {
        RevealPolicy(geometry: geometry, size: .room, tuning: tuning)
    }

    /// Dead centre of the hot zone.
    static func inside(_ geometry: NotchGeometry = PanelFixtures.notched) -> PanelPoint {
        PanelPoint(x: geometry.region.midX, y: geometry.region.midY)
    }

    /// A long way from anything the panel cares about.
    static func away(_ geometry: NotchGeometry = PanelFixtures.notched) -> PanelPoint {
        PanelPoint(x: geometry.display.midX, y: geometry.display.minY + 40)
    }
}
