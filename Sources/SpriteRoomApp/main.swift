// The app. Three hosts for one scene, and two verification harnesses.
//
//   spriteroom fixtures/three-subagents.jsonl              the notch panel
//   spriteroom fixtures/three-subagents.jsonl --window     M2's plain window
//   spriteroom fixtures/... --render out/ --at 6,12,20     offscreen PNGs
//   spriteroom --probe hover                               criteria 1 and 4
//   spriteroom --probe focus --cycles 20                   criterion 2
//
// The panel is the product; the window survives because a resizable window with
// a title bar is a far better place to develop the scene than a rectangle that
// disappears when you move the mouse. `--window`, or `SPRITEROOM_HOST=window`.
//
// `--render` exists because "the nameplate is legible at this zoom" is a claim
// about pixels, and pixels have to be looked at.

import AppKit
import Foundation
import SpriteKit
import SpriteRoomCore
import SpriteRoomScene

// MARK: - Arguments

enum Host {
    case panel
    case window
    case offscreen
}

enum ProbeKind: String {
    case focus
    case hover
    case fullscreen
}

struct Options {
    var host: Host = .panel
    var fixture: URL?
    var speed: Double = 1
    var renderDirectory: URL?
    var renderTimes: [Double] = []
    var width = 960
    var height = 540
    /// Window mode: capture the live `SKView` at the `--at` marks, then quit.
    var windowRenderDirectory: URL?
    /// Panel mode: reveal the panel and capture its live `SKView` at `--at`.
    var panelRenderDirectory: URL?
    var probe: ProbeKind?
    var cycles = 20
    var countdown: Double = 0
}

func usage() -> String {
    """
    usage: spriteroom [fixture.jsonl] [options]

      (default)          drop the room out of the notch
      --window           M2's plain resizable window instead
      --speed N          replay pace, multiples of real time (default 1)
      --render DIR       render offscreen PNGs into DIR instead of opening anything
      --at T[,T...]      fixture seconds to render at (with --render)
      --size WxH         viewport size in pixels (default 960x540)
      --window-render DIR  open the window, capture the live SKView at --at, quit
      --panel-render DIR   reveal the panel, capture its live SKView at --at, quit
      --probe focus      reveal/retract N times and watch where focus is
      --probe hover      walk the real cursor through the notch and count transitions
      --probe fullscreen enter a full-screen space and check the panel is over it
      --cycles N         cycles for --probe focus (default 20)
      --countdown S      wait S seconds before --probe focus starts
      -h, --help

    SPRITEROOM_HOST=window is the same as --window.
    """
}

func parse(_ arguments: [String]) -> Options? {
    var options = Options()
    if ProcessInfo.processInfo.environment["SPRITEROOM_HOST"] == "window" {
        options.host = .window
    }
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
        case "--window":
            options.host = .window
        case "--panel":
            options.host = .panel
        case "--speed":
            guard let value = next(), let speed = Double(value), speed > 0 else {
                print("--speed needs a positive number"); return nil
            }
            options.speed = speed
        case "--render":
            guard let value = next() else { print("--render needs a directory"); return nil }
            options.renderDirectory = URL(fileURLWithPath: value)
            options.host = .offscreen
        case "--window-render":
            guard let value = next() else { print("--window-render needs a directory"); return nil }
            options.windowRenderDirectory = URL(fileURLWithPath: value)
            options.host = .window
        case "--panel-render":
            guard let value = next() else { print("--panel-render needs a directory"); return nil }
            options.panelRenderDirectory = URL(fileURLWithPath: value)
            options.host = .panel
        case "--at":
            guard let value = next() else { print("--at needs times"); return nil }
            options.renderTimes = value.split(separator: ",").compactMap { Double($0) }
        case "--size":
            guard let value = next() else { print("--size needs WxH"); return nil }
            let parts = value.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { print("--size needs WxH"); return nil }
            options.width = parts[0]
            options.height = parts[1]
        case "--probe":
            guard let value = next(), let kind = ProbeKind(rawValue: value) else {
                print("--probe needs 'focus', 'hover' or 'fullscreen'"); return nil
            }
            options.probe = kind
            options.host = .panel
        case "--cycles":
            guard let value = next(), let count = Int(value), count > 0 else {
                print("--cycles needs a positive integer"); return nil
            }
            options.cycles = count
        case "--countdown":
            guard let value = next(), let seconds = Double(value), seconds >= 0 else {
                print("--countdown needs a non-negative number"); return nil
            }
            options.countdown = seconds
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

/// Feeds a fixture to a sink against wall time, batching deltas into frames.
///
/// Shared by the panel and the window: both are consumers of one delta stream
/// and neither of them is allowed to reach back into the model. [architecture]
@MainActor
func replay(
    entries: [HookLogEntry],
    speed: Double,
    marks: [Double] = [],
    onMark: ((Double) -> Void)? = nil,
    into sink: @escaping ([WorldDelta]) -> Void
) async {
    let driver = ReplayDriver()
    guard let origin = entries.first?.receivedAt else { return }
    let started = Date()
    var remainingMarks = marks.sorted()
    var index = entries.startIndex

    while index < entries.endIndex || !remainingMarks.isEmpty {
        let elapsed = Date().timeIntervalSince(started) * speed
        let cutoff = origin.addingTimeInterval(elapsed)
        var batchEnd = index
        while batchEnd < entries.endIndex, entries[batchEnd].receivedAt <= cutoff {
            batchEnd += 1
        }
        if batchEnd > index {
            await driver.ingest(entries[index..<batchEnd])
            index = batchEnd
        }
        sink(driver.drain())
        while let next = remainingMarks.first, next <= elapsed {
            remainingMarks.removeFirst()
            onMark?(next)
        }
        try? await Task.sleep(for: .milliseconds(8))
    }
}

// MARK: - Offscreen

@MainActor
func renderOffscreen(options: Options, root: URL, entries: [HookLogEntry]) async throws -> Int {
    guard let directory = options.renderDirectory else { return 2 }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let viewport = CGSize(width: options.width, height: options.height)
    let scene = try makeScene(root: root, viewport: viewport)
    let binding = SceneBinding(scene: scene)
    let driver = ReplayDriver()
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
        let produced = binding.apply(driver.drain())
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

    let unmapped = binding.unmappedTools.sorted { $0.key < $1.key }
        .map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
    print("rendered \(written.count) frame(s) into \(directory.path)")
    for label in written { print("  \(label)") }
    print("unmapped tools: \(unmapped.isEmpty ? "none" : unmapped)")
    return written.isEmpty ? 1 : 0
}

// MARK: - Window (M2's host, kept for scene work)

@MainActor
final class WindowDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    let root: URL
    let entries: [HookLogEntry]
    var window: NSWindow?
    var view: SKView?
    var binding: SceneBinding?

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
            window.title = "Sprite Room — \(scene.store.manifest.credit.text)"
            view.presentScene(scene)
            let binding = SceneBinding(scene: scene)
            self.binding = binding
            self.window = window
            self.view = view
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("window number \(window.windowNumber) visible=\(window.isVisible) "
                + "occlusion=\(window.occlusionState.contains(.visible) ? "visible" : "occluded") "
                + "backingScale=\(window.backingScaleFactor)")
            Task { await self.drive(scene: scene, binding: binding) }
        } catch {
            print("could not build the scene: \(error)")
            NSApp.terminate(nil)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let view, let binding else { return }
        binding.scene.setViewport(view.bounds.size)
    }

    private func drive(scene: RoomScene, binding: SceneBinding) async {
        var written: [String] = []
        await replay(
            entries: entries,
            speed: options.speed,
            marks: options.renderTimes,
            onMark: { mark in
                if let name = self.capture(scene: scene, at: mark) { written.append(name) }
            },
            into: { binding.apply($0) })

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

// MARK: - Panel (the product)

@MainActor
final class PanelDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    let root: URL
    let entries: [HookLogEntry]
    var host: RoomHost?
    var controller: NotchPanelController?
    var selector: ProjectSelector?

    init(options: Options, root: URL, entries: [HookLogEntry]) {
        self.options = options
        self.root = root
        self.entries = entries
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.accessory`: no Dock icon, no app menu, and the app is never
        // activated by being launched. The first line of defence for I8 — an
        // accessory app that also refuses key windows has no route to focus at
        // all.
        NSApp.setActivationPolicy(.accessory)

        do {
            let manifest = try Manifest.load(root: root)
            let host = RoomHost(manifest: manifest, viewport: PanelSize.room.cgSize)
            let controller = NotchPanelController(contentView: host.view, size: .room)
            let selector = ProjectSelector(
                credit: manifest.credit.text, creditURL: manifest.credit.url)

            // Push, one way. The selector is told what exists; it never asks.
            host.onRosterChanged = { [weak selector] entries, selected in
                selector?.update(entries: entries, selected: selected)
            }
            selector.onSelect = { [weak host] project in
                host?.select(project)
            }
            if ProcessInfo.processInfo.environment["SPRITEROOM_DEBUG"] != nil {
                controller.onTransition = { transition, phase in
                    print("panel \(transition) → \(phase)")
                }
            }

            self.host = host
            self.controller = controller
            self.selector = selector
            controller.start()

            let geometry = controller.geometry
            print("notch panel ready — "
                + (geometry.hasPhysicalNotch
                    ? "physical notch \(geometry.physicalNotch!)"
                    : "no notch on this display, hot zone synthesised")
                + ", hot zone \(geometry.region)")

            if let probe = options.probe {
                Task { await self.runProbe(probe, controller: controller) }
            } else {
                print("point at the notch to reveal the room; the menu bar item picks the project")
                var written: [String] = []
                Task {
                    if self.options.panelRenderDirectory != nil {
                        // Capturing means the panel has to be down. There is no
                        // user-facing way to ask for that, so the harness does
                        // what the harness does. [I8 is about focus, not about
                        // never moving the window]
                        controller.stop()
                        controller.forceReveal()
                    }
                    await replay(
                        entries: self.entries,
                        speed: self.options.speed,
                        marks: self.options.renderTimes,
                        onMark: { mark in
                            if let name = self.capture(host: host, at: mark) {
                                written.append(name)
                            }
                        },
                        into: { host.consume($0) })
                    if self.options.panelRenderDirectory != nil {
                        print("captured \(written.count) frame(s) from the live panel")
                        for name in written { print("  \(name)") }
                        NSApp.terminate(nil)
                    }
                    print("replay finished — the panel stays up")
                }
            }
        } catch {
            print("could not build the scene: \(error)")
            NSApp.terminate(nil)
        }
    }

    /// In-process capture of what the panel's `SKView` is drawing.
    ///
    /// Not a screenshot: `screencapture -l` fails in this environment because
    /// the terminal has no Screen Recording permission, which M2 hit as well.
    /// This is the pixels the view produced, which is the strongest evidence
    /// available here that the room is inside the panel.
    private func capture(host: RoomHost, at mark: Double) -> String? {
        guard let directory = options.panelRenderDirectory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let texture = host.view.texture(from: host.scene),
              let image = texture.cgImage() as CGImage?,
              let bitmap = try? PixelImage.bitmap(from: image) else {
            print("!! panel capture failed at t=\(mark)")
            return nil
        }
        let name = String(
            format: "panel-%.0fx%.0f-t%06.2f.png",
            PanelSize.room.width, PanelSize.room.height, mark)
        return PixelImage.writePNG(bitmap, to: directory.appending(path: name)) ? name : nil
    }

    private func runProbe(_ probe: ProbeKind, controller: NotchPanelController) async {
        // The probes need the panel and nothing else moving.
        let status: Int
        switch probe {
        case .focus:
            controller.stop()
            status = await Probe.focus(
                controller: controller, cycles: options.cycles, countdown: options.countdown)
        case .hover:
            status = await Probe.hover(controller: controller)
        case .fullscreen:
            controller.stop()
            status = await Probe.fullScreen(controller: controller)
        }
        exit(Int32(status))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Entry point

// Unbuffered, so a harness watching stdout sees progress before the process is
// done.
setvbuf(stdout, nil, _IONBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
guard let options = parse(arguments) else { exit(2) }

let root = Manifest.developmentRoot()
let fixtureURL = options.fixture ?? defaultFixture(root: root)
var entries: [HookLogEntry] = []
if options.probe == nil {
    do {
        entries = try HookLog.load(contentsOf: fixtureURL)
    } catch {
        print("could not read \(fixtureURL.path): \(error)")
        exit(2)
    }
}

switch options.host {
case .offscreen:
    do {
        exit(Int32(try await renderOffscreen(options: options, root: root, entries: entries)))
    } catch {
        print("offscreen render failed: \(error)")
        exit(1)
    }
case .window:
    let application = NSApplication.shared
    let delegate = WindowDelegate(options: options, root: root, entries: entries)
    application.delegate = delegate
    application.run()
case .panel:
    let application = NSApplication.shared
    let delegate = PanelDelegate(options: options, root: root, entries: entries)
    application.delegate = delegate
    application.run()
}
