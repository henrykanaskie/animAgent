// M2's host: a plain, resizable `NSWindow` with the room in it.
//
// Deliberately not the notch. The panel is M3's problem and putting the scene
// in an ordinary window first is what keeps scene work from being blocked on
// panel work. `NotchPanel` replaces this host later; the scene does not change.
//
//   spriteroom fixtures/three-subagents.jsonl                 window, real time
//   spriteroom fixtures/three-subagents.jsonl --speed 4       window, 4× faster
//   spriteroom fixtures/three-subagents.jsonl \
//        --render out/ --at 6,12,20 --size 960x540            offscreen PNGs
//
// `--render` exists because "the nameplate is legible at this zoom" is a claim
// about pixels, and pixels have to be looked at.

import AppKit
import Foundation
import SpriteKit
import SpriteRoomCore
import SpriteRoomScene

// MARK: - Arguments

struct Options {
    var fixture: URL?
    var speed: Double = 1
    var renderDirectory: URL?
    var renderTimes: [Double] = []
    var width = 960
    var height = 540
    /// Window mode: capture the live `SKView` at the `--at` marks, then quit.
    var windowRenderDirectory: URL?
}

func usage() -> String {
    """
    usage: spriteroom [fixture.jsonl] [options]

      --speed N          replay pace, multiples of real time (default 1)
      --render DIR       render offscreen PNGs into DIR instead of opening a window
      --at T[,T...]      fixture seconds to render at (with --render)
      --size WxH         viewport size in pixels (default 960x540)
      --window-render DIR  open the window, capture the live SKView at --at, quit
      -h, --help
    """
}

func parse(_ arguments: [String]) -> Options? {
    var options = Options()
    var index = arguments.startIndex
    while index < arguments.endIndex {
        let argument = arguments[index]
        func next() -> String? {
            index += 1
            return index < arguments.endIndex ? arguments[index] : nil
        }
        switch argument {
        case "-h", "--help":
            print(usage())
            return nil
        case "--speed":
            guard let value = next(), let speed = Double(value), speed > 0 else {
                print("--speed needs a positive number"); return nil
            }
            options.speed = speed
        case "--render":
            guard let value = next() else { print("--render needs a directory"); return nil }
            options.renderDirectory = URL(fileURLWithPath: value)
        case "--window-render":
            guard let value = next() else { print("--window-render needs a directory"); return nil }
            options.windowRenderDirectory = URL(fileURLWithPath: value)
        case "--at":
            guard let value = next() else { print("--at needs times"); return nil }
            options.renderTimes = value.split(separator: ",").compactMap { Double($0) }
        case "--size":
            guard let value = next() else { print("--size needs WxH"); return nil }
            let parts = value.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { print("--size needs WxH"); return nil }
            options.width = parts[0]
            options.height = parts[1]
        default:
            guard !argument.hasPrefix("-") else {
                print("unknown option \(argument)\n\n" + usage()); return nil
            }
            options.fixture = URL(fileURLWithPath: argument)
        }
        index += 1
    }
    return options
}

func defaultFixture(root: URL) -> URL {
    root.appending(path: "fixtures").appending(path: "three-subagents.jsonl")
}

// MARK: - Shared setup

@MainActor
func makeScene(root: URL, viewport: CGSize) throws -> RoomScene {
    let manifest = try Manifest.load(root: root)
    let scene = RoomScene(manifest: manifest)
    scene.setViewport(viewport)
    return scene
}

// MARK: - Offscreen

@MainActor
func renderOffscreen(options: Options, root: URL, entries: [HookLogEntry]) async throws -> Int {
    guard let directory = options.renderDirectory else { return 2 }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let viewport = CGSize(width: options.width, height: options.height)
    let scene = try makeScene(root: root, viewport: viewport)
    let driver = ReplayDriver(scene: scene)
    let renderer = try OffscreenRenderer(
        scene: scene, width: options.width, height: options.height)

    guard let origin = entries.first?.receivedAt else {
        print("empty fixture"); return 2
    }
    // `SPRITEROOM_DEBUG=1` prints every intent and the final roster. Off by
    // default: this is a harness, not a log viewer.
    let traceIntents = ProcessInfo.processInfo.environment["SPRITEROOM_DEBUG"] != nil
    let marks = options.renderTimes.isEmpty ? [1.0] : options.renderTimes.sorted()
    // Simulate only as far as the last requested mark.
    let last = marks.last ?? 0
    let step = 1.0 / 60.0

    var entryIndex = entries.startIndex
    var markIndex = marks.startIndex
    var written: [String] = []
    var time = 0.0
    let name = (options.fixture ?? defaultFixture(root: root))
        .deletingPathExtension().lastPathComponent

    // A fixed-step simulation. Fixture time and the renderer's clock are the
    // same clock, so a two-second walk takes two seconds of both.
    while time <= last + step {
        let cutoff = origin.addingTimeInterval(time)
        var batchEnd = entryIndex
        while batchEnd < entries.endIndex, entries[batchEnd].receivedAt <= cutoff {
            batchEnd += 1
        }
        if batchEnd > entryIndex {
            await driver.ingest(entries[entryIndex..<batchEnd])
            entryIndex = batchEnd
        }
        let produced = driver.flush()
        if traceIntents, !produced.isEmpty {
            let line = produced.map { "\($0)" }.joined(separator: " | ")
            print(String(format: "  t=%7.3f ", time) + line)
        }
        scene.advance(to: time)
        renderer.update(atTime: time)

        while markIndex < marks.endIndex, marks[markIndex] <= time + 1e-9 {
            let label = String(
                format: "%@-%dx%d-t%06.2f.png",
                name, options.width, options.height, marks[markIndex])
                .replacingOccurrences(of: " ", with: "0")
            let url = directory.appending(path: label)
            if renderer.write(to: url) {
                written.append(label)
            } else {
                print("!! failed to write \(label)")
            }
            markIndex += 1
        }
        time += step
    }
    if traceIntents {
        for line in scene.debugRoster { print("  roster: " + line) }
    }

    let unmapped = driver.unmappedTools.sorted { $0.key < $1.key }
        .map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
    print("rendered \(written.count) frame(s) into \(directory.path)")
    for label in written { print("  \(label)") }
    print("unmapped tools: \(unmapped.isEmpty ? "none" : unmapped)")
    return written.isEmpty ? 1 : 0
}

// MARK: - Window

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    let root: URL
    let entries: [HookLogEntry]
    var window: NSWindow?
    var view: SKView?
    var scene: RoomScene?

    init(options: Options, root: URL, entries: [HookLogEntry]) {
        self.options = options
        self.root = root
        self.entries = entries
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: options.width, height: options.height)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        let view = SKView(frame: frame)
        view.autoresizingMask = [.width, .height]
        // Nothing here should ever smooth a pixel. [standing rule]
        view.ignoresSiblingOrder = true
        window.contentView = view
        window.center()

        do {
            let scene = try makeScene(
                root: root,
                viewport: CGSize(width: options.width, height: options.height))
            // The credit line is required by the Modern Interiors licence and
            // has to be visible somewhere. The About panel is M3's; the title
            // bar is where it lives until then.
            window.title = "Sprite Room — \(scene.store.manifest.credit.text)"
            view.presentScene(scene)
            self.scene = scene
            self.window = window
            self.view = view
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("window number \(window.windowNumber) visible=\(window.isVisible) "
                + "occlusion=\(window.occlusionState.contains(.visible) ? "visible" : "occluded") "
                + "backingScale=\(window.backingScaleFactor)")
            Task { await self.drive(scene: scene) }
        } catch {
            print("could not build the scene: \(error)")
            NSApp.terminate(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let view, let scene else { return }
        scene.setViewport(view.bounds.size)
    }

    /// Drives the replay against wall time, batching deltas into frames.
    ///
    /// `SKView` runs its own render loop and calls `RoomScene.update(_:)`, so
    /// the scene's clock here is the display's, not a simulated one. Same
    /// animation engine as the offscreen path — only the driver differs.
    private func drive(scene: RoomScene) async {
        let driver = ReplayDriver(scene: scene)
        guard let origin = entries.first?.receivedAt else { return }
        let started = Date()
        var marks = options.renderTimes.sorted()
        var index = entries.startIndex
        var written: [String] = []

        while index < entries.endIndex || !marks.isEmpty {
            let elapsed = Date().timeIntervalSince(started) * options.speed
            let cutoff = origin.addingTimeInterval(elapsed)
            var batchEnd = index
            while batchEnd < entries.endIndex, entries[batchEnd].receivedAt <= cutoff {
                batchEnd += 1
            }
            if batchEnd > index {
                await driver.ingest(entries[index..<batchEnd])
                driver.flush()
                index = batchEnd
            }
            while let next = marks.first, next <= elapsed {
                marks.removeFirst()
                if let name = capture(scene: scene, at: next) { written.append(name) }
            }
            try? await Task.sleep(for: .milliseconds(8))
        }

        if options.windowRenderDirectory != nil {
            print("captured \(written.count) frame(s) from the live window")
            for name in written { print("  \(name)") }
            NSApp.terminate(nil)
        }
        print("replay finished")
    }

    /// Grabs what the on-screen `SKView` is currently drawing.
    private func capture(scene: RoomScene, at mark: Double) -> String? {
        guard let directory = options.windowRenderDirectory, let view else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let texture = view.texture(from: scene),
              let image = texture.cgImage() as CGImage?,
              let bitmap = try? PixelImage.bitmap(from: image) else {
            print("!! window capture failed at t=\(mark)")
            return nil
        }
        let name = String(format: "window-%dx%d-t%06.2f.png", options.width, options.height, mark)
        return PixelImage.writePNG(bitmap, to: directory.appending(path: name)) ? name : nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Entry point

// Unbuffered, so a harness watching stdout sees the window number before the
// process is done.
setvbuf(stdout, nil, _IONBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
guard let options = parse(arguments) else { exit(2) }

let root = Manifest.developmentRoot()
let fixtureURL = options.fixture ?? defaultFixture(root: root)
let entries: [HookLogEntry]
do {
    entries = try HookLog.load(contentsOf: fixtureURL)
} catch {
    print("could not read \(fixtureURL.path): \(error)")
    exit(2)
}

if options.renderDirectory != nil {
    do {
        exit(Int32(try await renderOffscreen(options: options, root: root, entries: entries)))
    } catch {
        print("offscreen render failed: \(error)")
        exit(1)
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate(options: options, root: root, entries: entries)
    application.delegate = delegate
    application.run()
}
