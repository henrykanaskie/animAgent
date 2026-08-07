// Replay harness. Drives a captured fixture through the `WorldModel` and
// prints the resulting deltas. No window, no pixels — this is M1's whole
// user interface.
//
//   spriteroom-replay --all
//   spriteroom-replay fixtures/three-subagents.jsonl --speed 1000
//
// Fixture time, not wall time, is what the model sees: every event is ingested
// at its own `_receivedAt`. `--speed` only changes how long the *harness* waits
// between events, never what the model believes the time is. [I4]
//
// The clock advances *between* events as well as at them. Before each event the
// model is walked forward to that event's instant, sweeping at each open call's
// own deadline on the way, so an abandonment is reported when it happens rather
// than at the end of the run — `WorldModel.advance(to:)`. Without that, ADR-001
// was undemonstrable here: `denial-then-work`'s shortened deadline falls at
// t=94.98 with 157 s of session left, and a harness that only swept at the end
// printed `sessionEnded` at 252.06 and could not tell 60 s from 900 s.
//
// The closing sweep is unchanged and still runs at a fixture instant past the
// longest deadline, because after the last event there is no more information
// about when anything happened. Orphans that outlive their stream —
// `killed-session`, `permission-prompt` — are still reported exactly there.

import Foundation
import SpriteRoomCore

// MARK: - Arguments

struct Options {
    var paths: [String] = []
    var all = false
    var fixturesDirectory: URL
    var speed: Double?
    var quiet = false
}

func defaultFixturesDirectory() -> URL {
    // Sources/SpriteRoomReplay/main.swift → repository root.
    let fromSource = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "fixtures")
    if FileManager.default.fileExists(atPath: fromSource.path) { return fromSource }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appending(path: "fixtures")
}

func usage() -> String {
    """
    usage: spriteroom-replay [options] [fixture.jsonl ...]

      --all              replay every .jsonl in the fixtures directory
      --fixtures DIR     fixtures directory (default: <repo>/fixtures)
      --speed N          pace replay off _receivedAt at N× real time (e.g. 1000)
      --quiet            summary lines only, no per-delta output
      -h, --help
    """
}

enum ParseOutcome {
    case parsed(Options)
    case stop(message: String, exitCode: Int32)
}

func parseArguments(_ arguments: [String]) -> ParseOutcome {
    var options = Options(fixturesDirectory: defaultFixturesDirectory())
    var index = arguments.startIndex
    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--all":
            options.all = true
        case "--quiet":
            options.quiet = true
        case "-h", "--help":
            return .stop(message: usage(), exitCode: 0)
        case "--fixtures":
            index += 1
            guard index < arguments.endIndex else {
                return .stop(message: "--fixtures needs a path", exitCode: 2)
            }
            options.fixturesDirectory = URL(fileURLWithPath: arguments[index])
        case "--speed":
            index += 1
            guard index < arguments.endIndex, let value = Double(arguments[index]), value > 0 else {
                return .stop(message: "--speed needs a positive number", exitCode: 2)
            }
            options.speed = value
        default:
            guard !argument.hasPrefix("-") else {
                return .stop(message: "unknown option \(argument)\n\n" + usage(), exitCode: 2)
            }
            options.paths.append(argument)
        }
        index += 1
    }
    if options.paths.isEmpty { options.all = true }
    return .parsed(options)
}

// MARK: - Report

struct FixtureReport {
    var name = ""
    var events = 0
    var malformed = 0
    var deltas = 0
    var unhandled: [String: Int] = [:]
    var orphansAtEndOfStream: [(agent: AgentRef, call: OpenCall)] = []
    /// Calls the reaper closed *while the stream was still running*, each at its
    /// own deadline. Non-zero is the interesting case and the only one that
    /// prints a line — ADR-001's whole point is a deadline that falls inside a
    /// session that then keeps working.
    var abandonedMidStream = 0
    var abandonedBySweep = 0
    var openAfterSweep = 0

    var passed: Bool { openAfterSweep == 0 }
}

func relative(_ instant: Date, from origin: Date) -> String {
    String(format: "%8.3f", instant.timeIntervalSince(origin))
}

// MARK: - Replay

func replay(_ url: URL, options: Options) async -> FixtureReport {
    var report = FixtureReport()
    report.name = url.lastPathComponent

    let entries: [HookLogEntry]
    do {
        entries = try HookLog.load(contentsOf: url)
    } catch {
        print("  ! could not read \(url.path): \(error)")
        report.openAfterSweep = -1
        return report
    }
    guard let origin = entries.first?.receivedAt else {
        print("  ! empty fixture")
        return report
    }

    let model = WorldModel()
    var previous = origin

    for entry in entries {
        report.events += 1

        if let speed = options.speed {
            let gap = entry.receivedAt.timeIntervalSince(previous) / speed
            if gap > 0 { try? await Task.sleep(for: .seconds(gap)) }
        }
        previous = entry.receivedAt

        // Walk the model forward to this event, reaping at each deadline that
        // falls on the way. Before the decode, so that a malformed payload does
        // not skip it — a deadline expiring is a fact about the world, not
        // about the line we are looking at. [I4]
        for step in await model.advance(to: entry.receivedAt) {
            report.deltas += step.deltas.count
            for delta in step.deltas {
                if case .callAbandoned = delta { report.abandonedMidStream += 1 }
                if !options.quiet {
                    print("  [\(relative(step.instant, from: origin))] \(delta)")
                }
            }
        }

        guard let event = entry.event else {
            // Not JSON, or no session_id/cwd. Counted, never thrown. [I5]
            report.malformed += 1
            if !options.quiet {
                print("  [\(relative(entry.receivedAt, from: origin))] -- malformed payload, counted")
            }
            continue
        }

        let deltas = await model.ingest(event, at: entry.receivedAt)
        report.deltas += deltas.count
        if !options.quiet {
            for delta in deltas {
                print("  [\(relative(entry.receivedAt, from: origin))] \(delta)")
            }
        }
    }

    // Orphans: what is still open when the stream runs out — the calls the
    // event stream never closed and whose deadlines have not yet fallen. For
    // every fixture but `killed-session` and the denial captures this must be
    // empty; if `tool-failure` needs the reaper at all, a close path is wrong.
    //
    // A mid-stream reap removes a call from this list, which is right: a call
    // the reaper already closed *inside* the stream is not an orphan left over
    // at the end of one. `abandonedMidStream` is where those are reported.
    let atEndOfStream = await model.snapshot()
    report.orphansAtEndOfStream = atEndOfStream.openCalls
    report.unhandled = await model.unhandledCounts

    let sweepAt = previous.addingTimeInterval(Reaper.longestDeadlineInterval + 1)
    let sweepDeltas = await model.sweep(at: sweepAt)
    report.deltas += sweepDeltas.count
    if !options.quiet {
        for delta in sweepDeltas {
            print("  [\(relative(sweepAt, from: origin))] \(delta)")
        }
    }
    report.abandonedBySweep = sweepDeltas.filter {
        if case .callAbandoned = $0 { return true }
        return false
    }.count
    report.openAfterSweep = await model.snapshot().totalOpenCalls
    return report
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
let options: Options
switch parseArguments(arguments) {
case .parsed(let parsed):
    options = parsed
case let .stop(message, exitCode):
    print(message)
    exit(exitCode)
}

var urls: [URL] = options.paths.map { URL(fileURLWithPath: $0) }
if options.all {
    let contents = (try? FileManager.default.contentsOfDirectory(
        at: options.fixturesDirectory, includingPropertiesForKeys: nil)) ?? []
    urls += contents.filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
}

guard !urls.isEmpty else {
    print("no fixtures found in \(options.fixturesDirectory.path)")
    exit(2)
}

var reports: [FixtureReport] = []
for url in urls {
    print("── \(url.lastPathComponent) " + String(repeating: "─", count: max(0, 56 - url.lastPathComponent.count)))
    let report = await replay(url, options: options)
    reports.append(report)

    let unhandled = report.unhandled.sorted { $0.key < $1.key }
        .map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
    print("   events \(report.events)  deltas \(report.deltas)  malformed \(report.malformed)")
    print("   unhandled: \(unhandled.isEmpty ? "none" : unhandled)")

    // Printed only when it happened. A zero here is already legible from the
    // delta log, and keeping the line out of the fixtures that have nothing to
    // say leaves the six required ones reading exactly as they did.
    if report.abandonedMidStream > 0 {
        print("   reaped mid-stream, each at its own deadline: \(report.abandonedMidStream)")
    }
    if report.orphansAtEndOfStream.isEmpty {
        print("   orphaned open calls at end of stream: 0")
    } else {
        print("   orphaned open calls at end of stream: \(report.orphansAtEndOfStream.count)")
        for orphan in report.orphansAtEndOfStream.sorted(by: { $0.call < $1.call }) {
            print("     \(orphan.agent) \(orphan.call) deadline \(orphan.call.deadline)")
        }
    }
    print("   after deadline sweep: \(report.abandonedBySweep) abandoned, \(report.openAfterSweep) still open")
    print("")
}

let failures = reports.filter { !$0.passed }
if failures.isEmpty {
    print("all \(reports.count) fixture(s) replayed with zero open calls after the sweep")
    exit(0)
} else {
    for failure in failures {
        print("FAIL \(failure.name): \(failure.openAfterSweep) open call(s) survived the sweep")
    }
    exit(1)
}
