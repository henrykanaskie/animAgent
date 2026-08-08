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
    /// Live only: wait for two projects, then drive the real menu items.
    case selector
}

/// What to do instead of opening anything.
enum HookAction: String {
    case install
    case remove
    case status
}

struct Options {
    var host: Host = .panel
    var fixture: URL?
    /// Live mode: bind the listener and let real sessions drive the room.
    var live = false
    var port: UInt16 = 8787
    var hookAction: HookAction?
    /// Consent, given on the command line. Without it `--install-hooks`
    /// refuses to write.
    var consented = false
    /// Point the installer at a copy instead of the user's real settings.
    var settingsPath: URL?
    /// Live mode: stop after this many seconds. 0 means never.
    var duration: Double = 0
    /// Live mode: show the first-run consent dialog when hooks are absent.
    var hookPrompt = true
    /// Answer the first-run question without a dialog. For a harness that has
    /// nobody to click it — never a default, because silence is not consent.
    var consentAnswer: HookConsent?
    /// Live mode: never show the removal-on-quit dialog.
    var quitPrompt = true
    /// Answer the removal-on-quit question without a dialog. Never a default,
    /// for the same reason `consentAnswer` is not: a settings write with nobody
    /// present is a settings write nobody agreed to.
    var quitAnswer: HookQuit?
    var speed: Double = 1
    /// Name the room `--render` (and `--window`) draws. `nil` means the theme
    /// the app would derive for the fixture's `cwd`.
    var themeID: String?
    /// `--panel-render` reveals the real panel over whatever you are doing.
    /// It refuses without this. [see `PanelDelegate.applicationWillTerminate`]
    var forcePanelRender = false
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

      (default)          drop the room out of the notch, replaying a fixture
      --live             bind the listener; real Claude Code sessions drive it
      --port N           listener port (default 8787; 0 asks for an ephemeral one)
      --for S            live mode: quit after S seconds
      --install-hooks    write our block into ~/.claude/settings.json
      --remove-hooks     take it back out
      --hooks-status     report whether it is there
      --yes              consent for --install-hooks (it refuses without this)
      --no-hook-prompt   live mode: never show the first-run consent dialog
      --consent A        answer the first-run question: 'install' or 'decline'
      --no-quit-prompt   live mode: never ask about removing the hooks on quit
      --quit-answer A    answer the removal-on-quit question: 'remove' or 'keep'
      --settings-path P  operate on P instead of the real ~/.claude/settings.json
      --window           M2's plain resizable window instead
      --speed N          replay pace, multiples of real time (default 1)
      --render DIR       render offscreen PNGs into DIR instead of opening anything
      --theme ID         room to draw with --render/--window; 'list' names them.
                         Default: the theme the app derives from the fixture's cwd
      --at T[,T...]      fixture seconds to render at (with --render)
      --size WxH         viewport size in pixels (default 960x540)
      --window-render DIR  open the window, capture the live SKView at --at, quit
      --panel-render DIR   reveal the REAL panel over your screen and capture it;
                           needs --force-panel-render. Prefer --render.
      --force-panel-render  mean it
      --probe focus      reveal/retract N times and watch where focus is
      --probe hover      walk the real cursor through the notch and count transitions
      --probe fullscreen enter a full-screen space and check the panel is over it
      --probe selector   (with --live) wait for 2 projects, then click the menu
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
        case "--live":
            options.live = true
            options.host = .panel
        case "--port":
            guard let value = next(), let port = UInt16(value) else {
                print("--port needs a number in 0...65535"); return nil
            }
            options.port = port
        case "--for":
            guard let value = next(), let seconds = Double(value), seconds > 0 else {
                print("--for needs a positive number of seconds"); return nil
            }
            options.duration = seconds
        case "--install-hooks":
            options.hookAction = .install
        case "--remove-hooks":
            options.hookAction = .remove
        case "--hooks-status":
            options.hookAction = .status
        case "--yes":
            options.consented = true
        case "--no-hook-prompt":
            options.hookPrompt = false
        case "--consent":
            guard let value = next(), let answer = HookConsent(rawValue: value) else {
                print("--consent needs 'install' or 'decline'"); return nil
            }
            options.consentAnswer = answer
        case "--no-quit-prompt":
            options.quitPrompt = false
        case "--quit-answer":
            guard let value = next(), let answer = HookQuit(rawValue: value) else {
                print("--quit-answer needs 'remove' or 'keep'"); return nil
            }
            options.quitAnswer = answer
        case "--settings-path":
            guard let value = next() else { print("--settings-path needs a file"); return nil }
            options.settingsPath = URL(fileURLWithPath: value)
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
        case "--theme":
            guard let value = next() else { print("--theme needs a theme id, or 'list'"); return nil }
            options.themeID = value
        case "--force-panel-render":
            options.forcePanelRender = true
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

// MARK: - Hook installation

/// The `--install-hooks` / `--remove-hooks` / `--hooks-status` path. Opens no
/// window; this is the one thing the app does that outlives the process.
///
/// **Consent is required and is not implied by running the command.** The flag
/// says what you want; `--yes` says you mean it. Writing to
/// `~/.claude/settings.json` changes the behaviour of every Claude Code session
/// on the machine, including ones already running, so a typo must not be enough
/// to do it.
func runHookAction(_ action: HookAction, options: Options) -> Int32 {
    let installer = HookInstaller(settingsURL: options.settingsPath, port: options.port)
    let path = installer.settingsURL.path

    func describeState() {
        do {
            switch try installer.state() {
            case .absent:
                print("hooks: not installed in \(path)")
            case .installed(let port):
                print("hooks: installed in \(path), posting to 127.0.0.1:\(port)")
            case .installedAtOtherPort(let ports):
                let list = ports.map(String.init).joined(separator: ", ")
                print("hooks: installed in \(path) but pointing at port(s) \(list), not \(options.port)")
            }
        } catch {
            print("could not read \(path): \(error)")
        }
    }

    switch action {
    case .status:
        describeState()
        return 0

    case .install:
        guard options.consented else {
            print("""
                SpriteRoom would add \(HookInstaller.events.count) hook entries to
                  \(path)
                Each one POSTs the hook payload to \(installer.url) with a \
                \(HookInstaller.timeout)s timeout.
                Every other key in that file is left exactly as it is, and a copy of the \
                current file is kept at
                  \(installer.backupURL.path)
                so --remove-hooks can put it back byte for byte.

                Re-run with --yes to consent.
                """)
            return 3
        }
        do {
            let written = try installer.install()
            print("installed \(written.count) hook entries into \(path)")
            print("  url \(installer.url), timeout \(HookInstaller.timeout)s")
            print("  backup \(installer.backupURL.path)")
            print("  events \(written.joined(separator: ", "))")
            return 0
        } catch {
            print("install failed: \(error)")
            return 1
        }

    case .remove:
        do {
            if try installer.remove() {
                print("removed our hook entries from \(path)")
            } else {
                print("nothing of ours in \(path); left untouched")
            }
            return 0
        } catch {
            print("remove failed: \(error)")
            return 1
        }
    }
}

// MARK: - Shared setup

/// Which room the offscreen renderer and the plain window dress themselves in.
///
/// **Why the harnesses need this at all.** `--render` is the safe way to look at
/// what the app draws: it produces the scene offscreen and never touches the
/// display, unlike `--panel-render`. It used to build a `RoomScene` with no
/// theme, so it drew the plain office and nothing else — theme selection lived
/// only in `RoomHost`, which only the `--live` path constructs. A renderer that
/// cannot show what the app will actually draw is not a renderer of this app.
///
/// **Why the default is derived rather than the manifest default.** `--render`
/// with no `--theme` now answers the question "what will this fixture's project
/// look like", and the answer the app itself gives is
/// `ThemeSelector.theme(for:stored:manifest:)` over the fixture's `cwd` — the
/// same function, in the same module, guarded by the same pinned FNV-1a vector.
/// Silently drawing the default room instead was the bug.
///
/// **`stored:` is deliberately empty.** The derived half is a pure function of
/// `cwd` and the manifest, so the same fixture renders the same room on any
/// machine and in any checkout. Reading the maintainer's `themes.json` would
/// make a render harness produce different pixels for different people, which
/// is the opposite of what a harness is for. `--theme` is how you ask for a
/// specific room; the flag says it, so nothing is silent either way.
enum ResolvedTheme {
    /// The id to hand to *both* halves. `nil` means `manifest.room` — the room
    /// this app drew before themes existed, and the honest answer for a
    /// manifest that declares none.
    case theme(String?)
    /// `--theme list`.
    case list([String])
    /// `--theme` named something the manifest does not have.
    case unknown(requested: String, declared: [String])
}

func resolveTheme(options: Options, manifest: Manifest, entries: [HookLogEntry]) -> ResolvedTheme {
    let declared = manifest.themes.orderedIDs
    if let requested = options.themeID {
        if requested == "list" { return .list(declared) }
        guard manifest.themes.contains(requested) else {
            return .unknown(requested: requested, declared: declared)
        }
        return .theme(requested)
    }
    // No `--theme`: the theme the app would derive for this fixture's project.
    guard let cwd = entries.compactMap({ $0.event?.cwd }).first else {
        return .theme(manifest.themes.defaultID)
    }
    return .theme(ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest))
}

/// Prints what went wrong and hands back an exit code, or the id to draw.
enum ThemeToDraw {
    case draw(String?)
    case stop(Int32)
}

func themeToDraw(
    options: Options, manifest: Manifest, entries: [HookLogEntry]
) -> ThemeToDraw {
    switch resolveTheme(options: options, manifest: manifest, entries: entries) {
    case .theme(let id):
        return .draw(id)
    case .list(let declared):
        if declared.isEmpty {
            print("this manifest declares no themes; the room is the one it has always drawn")
        } else {
            for id in declared {
                let mark = id == manifest.themes.defaultID ? " (default)" : ""
                print("  \(id)\(mark)")
            }
        }
        return .stop(0)
    case .unknown(let requested, let declared):
        print("no theme '\(requested)' in this manifest.")
        print(declared.isEmpty
            ? "  it declares none at all"
            : "  declared: " + declared.joined(separator: ", "))
        return .stop(2)
    }
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
    let manifest = try Manifest.load(root: root)
    let themeID: String?
    switch themeToDraw(options: options, manifest: manifest, entries: entries) {
    case .draw(let id): themeID = id
    case .stop(let code): return Int(code)
    }
    // **One construction, so both halves cannot disagree.** `SceneBinding`
    // hands the same id to the scene (which draws the props) and to the
    // `SceneDirector` (which resolves each agent's station). Building the scene
    // separately and passing it in is what let the director default to `nil`
    // while the scene was themed — a character seated at a station the room is
    // not dressed for, silently, because both halves are individually valid.
    // [ADR-002 §8 item 5]
    let binding = SceneBinding(manifest: manifest, themeID: themeID, viewport: viewport)
    let scene = binding.scene
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
    // The theme goes in the filename. Two `--theme` runs into one directory is
    // exactly how you check that a themed render differs from the default, and
    // it cannot be if the second overwrites the first.
    let name = (options.fixture ?? defaultFixture(root: root))
        .deletingPathExtension().lastPathComponent
        + (themeID.map { "-" + $0 } ?? "")

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
    let source = options.themeID == nil ? "derived from the fixture's cwd" : "--theme"
    print("room: \(themeID ?? "manifest.room (this manifest declares no themes)") (\(source))")
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
            let manifest = try Manifest.load(root: root)
            // Same construction as `--render`, for the same reason: one call
            // hands one id to both the scene and the director. `--window` had
            // the identical defect and would have grown it back the moment
            // `--render` was fixed alone.
            let themeID: String?
            switch themeToDraw(options: options, manifest: manifest, entries: entries) {
            case .draw(let id): themeID = id
            case .stop(let code): exit(code)
            }
            let binding = SceneBinding(
                manifest: manifest,
                themeID: themeID,
                viewport: CGSize(width: options.width, height: options.height))
            let scene = binding.scene
            window.title = "Sprite Room — \(scene.store.manifest.credit.text)"
            view.presentScene(scene)
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
    var live: LiveDriver?
    /// The installer this run took responsibility for.
    ///
    /// Set once live mode has bound a port, and `nil` everywhere else on
    /// purpose: a replay or capture run never became the thing the hooks point
    /// at, so it has no standing to ask about the user's settings file on the
    /// way out. Quitting `spriteroom fixtures/x.jsonl` must not pop a dialog
    /// about a configuration it never touched.
    private var hookInstaller: HookInstaller?
    /// `applicationShouldTerminate` can be called more than once. The user is
    /// asked at most once.
    private var answeredHookQuit = false

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
            // The one file this app persists, read once, here, before the first
            // project is displayed and never again. [ADR-002 §3d]
            let themeStore = ThemeStore()
            let host = RoomHost(
                manifest: manifest,
                viewport: PanelSize.room.cgSize,
                themes: ThemeCatalog.declared(in: manifest),
                themeStore: themeStore)
            // The derived half of ADR-002 §3c. Without this the hash never
            // runs, every project falls straight to `themes.default`, and the
            // picker is the only way a room is ever anything but the default —
            // which is not the design, it is half of it. `rendezvous` lives in
            // `SpriteRoomScene` beside its pinned FNV-1a vector; implementing
            // it here as well would leave that vector guarding half the
            // mapping. [§11 risk 7]
            host.derive = { cwd, pool in ThemeSelector.rendezvous(key: cwd, over: pool) }
            let controller = NotchPanelController(contentView: host.view, size: .room)
            let selector = ProjectSelector(
                credit: manifest.credit.text, creditURL: manifest.credit.url)
            selector.themes = host.themes

            // Push, one way. The selector is told what exists; it never asks.
            host.onRosterChanged = { [weak selector, weak host] entries, selected in
                selector?.currentThemeID = host?.themeID
                selector?.update(entries: entries, selected: selected)
            }
            selector.onSelect = { [weak host] project in
                host?.select(project)
            }
            selector.onPickTheme = { [weak host] themeID in
                host?.chooseTheme(themeID)
            }
            if case .discarded(let path) = themeStore.load {
                print("themes.json was unreadable and has been set aside at \(path); "
                    + "every project starts on its derived room")
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

            if options.live {
                Task { await self.runLive(host: host, selector: selector) }
            } else if let probe = options.probe {
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
                        into: { host.consume($0, at: Date()) })
                    if self.options.panelRenderDirectory != nil {
                        print("captured \(written.count) frame(s) from the live panel")
                        for name in written { print("  \(name)") }
                        await self.tearDownPanel()
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

    // MARK: Getting off the screen

    /// Order the panel out and give AppKit a turn to actually do it.
    ///
    /// **The bug this exists for.** `--panel-render` revealed the real panel
    /// over whatever the maintainer was doing and then hard-exited without
    /// `orderOut`. The window server can leave that surface drawn with **no
    /// process behind it**, and the panel is precisely the window you cannot
    /// get rid of by hand: `ignoresMouseEvents = true` so it cannot be clicked,
    /// a level above the menu bar so nothing can be raised in front of it, and
    /// `canJoinAllSpaces` so it follows you. Killing the process does not help;
    /// the process is already gone. It takes a space switch or Mission Control.
    ///
    /// Ordering out is the fix. The sleep is the other half: `orderOut` posts
    /// to the window server and the process must still be alive when that is
    /// serviced, so the exit waits one beat rather than racing it. 120 ms is
    /// generous for a single window operation and invisible on a harness run.
    ///
    /// Nothing here touches focus. `orderOut` is the opposite of activation and
    /// the panel could not have been key regardless. [I8]
    private func tearDownPanel() async {
        controller?.hide()
        try? await Task.sleep(for: .milliseconds(120))
    }

    /// The path `NSApp.terminate` takes. `exit()` does **not** call this, which
    /// is why the two `exit()` sites call `tearDownPanel()` themselves.
    func applicationWillTerminate(_ notification: Notification) {
        controller?.hide()
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

    /// The same in-process capture, under a name the caller chooses.
    @discardableResult
    private func capture(host: RoomHost, named name: String, into directory: URL) -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let texture = host.view.texture(from: host.scene),
              let image = texture.cgImage() as CGImage?,
              let bitmap = try? PixelImage.bitmap(from: image) else {
            print("!! panel capture failed for \(name)")
            return false
        }
        return PixelImage.writePNG(bitmap, to: directory.appending(path: name))
    }

    // MARK: Live

    /// Bind the listener and let real sessions drive the room.
    ///
    /// This is the whole of M4's plumbing: listener → queue → model → deltas →
    /// scene, once per frame, with the reaper running underneath. The frame
    /// pump is the only thing on the main actor, and all it does is move a
    /// batch of value types across.
    private func runLive(host: RoomHost, selector: ProjectSelector) async {
        let driver: LiveDriver
        do {
            driver = try LiveDriver(port: options.port)
        } catch {
            print("could not create the listener: \(error)")
            NSApp.terminate(nil)
            return
        }
        let bound: UInt16
        do {
            bound = try await driver.start()
        } catch {
            print("could not bind 127.0.0.1:\(options.port): \(error)")
            print("another SpriteRoom, or something else, already has that port")
            NSApp.terminate(nil)
            return
        }
        self.live = driver
        print("listening on http://127.0.0.1:\(bound)/hook")

        // Only now. Hooks must never point at a port nothing is listening on:
        // there is no `async` field on the HTTP hook schema, so an absent
        // listener costs the user the full `timeout` on every event. [I5]
        offerToInstallHooks(port: bound)

        let trace = ProcessInfo.processInfo.environment["SPRITEROOM_DEBUG"] != nil
        let started = Date()
        var lastReport = started
        // `--at` in live mode is seconds since the listener came up. Capturing
        // means the panel has to be down; there is no user-facing way to ask
        // for that, so the harness asks for it. [I8 is about focus, not about
        // never moving the window]
        var marks = options.renderTimes.sorted()
        if options.panelRenderDirectory != nil, !marks.isEmpty {
            controller?.stop()
            controller?.forceReveal()
        }

        if options.probe == .selector {
            Task { await self.driveSelector(host: host, selector: selector) }
        }

        while !Task.isCancelled {
            let deltas = driver.drain()
            if trace, !deltas.isEmpty {
                let elapsed = Date().timeIntervalSince(started)
                for delta in deltas { print(String(format: "  t=%8.3f ", elapsed) + "\(delta)") }
            }
            let now = Date()
            // Every frame, empty batch or not: the roster ages on this call and
            // a project that has gone quiet produces no deltas to ride in on.
            host.consume(deltas, at: now)

            let elapsed = now.timeIntervalSince(started)
            while let mark = marks.first, mark <= elapsed {
                marks.removeFirst()
                if let directory = options.panelRenderDirectory {
                    let name = String(format: "live-t%06.2f.png", mark)
                    if capture(host: host, named: name, into: directory) {
                        print("captured \(name)")
                    }
                }
            }
            if trace, now.timeIntervalSince(lastReport) >= 1 {
                lastReport = now
                let counters = driver.counters
                let snapshot = await driver.snapshot()
                let working = snapshot.agents.filter(\.isWorking).count
                print(String(
                    format: "  t=%8.3f roster agents=%d working=%d open=%d "
                        + "| requests=%d malformed=%d dropped=%d | projects=%@ selected=%@",
                    now.timeIntervalSince(started),
                    snapshot.agents.count, working, snapshot.totalOpenCalls,
                    counters.requests, counters.malformed, counters.dropped,
                    host.entries.map { "\($0.displayName)=\($0.population)" }
                        .joined(separator: ",") as NSString,
                    host.selected ?? "-" as NSString))
            }
            if options.duration > 0, now.timeIntervalSince(started) >= options.duration {
                break
            }
            try? await Task.sleep(for: .milliseconds(16))
        }

        let snapshot = await driver.snapshot()
        let counters = driver.counters
        print("live finished after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        print("  requests=\(counters.requests) decoded=\(counters.decoded) "
            + "malformed=\(counters.malformed) dropped=\(counters.dropped)")
        print("  agents left=\(snapshot.agents.count) open calls=\(snapshot.totalOpenCalls) "
            + "abandoned=\(await driver.abandoned())")
        let unhandled = await driver.unhandled().sorted { $0.key < $1.key }
            .map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
        print("  unhandled: \(unhandled.isEmpty ? "none" : unhandled)")
        driver.stop()
        NSApp.terminate(nil)
    }

    /// First run: if our block is not in `~/.claude/settings.json`, ask.
    ///
    /// Asking is a modal `NSAlert`, because this writes to the file that
    /// governs every Claude Code session on the machine and that is not a
    /// decision to infer from someone having launched an app. `--consent`
    /// answers it without the dialog, which is how the branch gets exercised
    /// by a harness that has no one to click it.
    private func offerToInstallHooks(port: UInt16) {
        let installer = HookInstaller(settingsURL: options.settingsPath, port: port)
        // From here on this run is the process the hooks point at, so it is
        // also the run that has to offer to take them back out. [see
        // `applicationShouldTerminate`]
        hookInstaller = installer

        // The menu item the consent dialog promises. Wire it before asking, so
        // the promise is true whichever way the answer goes.
        selector?.onToggleHooks = { [weak self] installed in
            do {
                if installed {
                    _ = try installer.remove()
                    print("hooks removed from \(installer.settingsURL.path)")
                } else {
                    try installer.install()
                    print("hooks registered in \(installer.settingsURL.path)")
                }
            } catch {
                print("could not change \(installer.settingsURL.path): \(error)")
            }
            self?.refreshHookMenuItem(installer: installer)
        }

        let answer = options.consentAnswer
        let outcome = installer.firstRun {
            if let answer { return answer }
            guard options.hookPrompt else { return nil }
            return Self.askForConsent(installer: installer)
        }
        switch outcome {
        case .alreadyInstalled:
            print("hooks already registered in \(installer.settingsURL.path)")
        case .installed:
            print("hooks registered in \(installer.settingsURL.path) — "
                + "run `spriteroom --remove-hooks` to take them out again")
        case .reinstalled(let ports):
            print("hooks re-pointed from port(s) \(ports.map(String.init).joined(separator: ", "))"
                + " to \(port) in \(installer.settingsURL.path)")
        case .declined:
            print("hooks not registered. Nothing will reach the room until they are:")
            print("  spriteroom --install-hooks --port \(port) --yes")
        case .failed(let message):
            print("could not check or write \(installer.settingsURL.path): \(message)")
        }
        refreshHookMenuItem(installer: installer)
    }

    private func refreshHookMenuItem(installer: HookInstaller) {
        guard let selector else { return }
        if case .installed = try? installer.state() {
            selector.hooksInstalled = true
        } else {
            selector.hooksInstalled = false
        }
        selector.update(entries: host?.entries ?? [], selected: host?.selected)
    }

    /// The dialog itself. Deliberately the only part of this flow that needs a
    /// screen, and deliberately the only part that holds no logic.
    private static func askForConsent(installer: HookInstaller) -> HookConsent {
        let alert = NSAlert()
        alert.messageText = "Let Sprite Room watch your Claude Code sessions?"
        alert.informativeText = """
            Sprite Room adds \(HookInstaller.events.count) hook entries to
            \(installer.settingsURL.path)

            Each one posts the hook payload to \(installer.url) and gives up \
            after \(HookInstaller.timeout) seconds. Everything else in that file \
            is left exactly as it is, and a copy of it is kept so removal puts \
            it back unchanged.

            You can take them out at any time from the menu bar item.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Register Hooks")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn ? .install : .decline
    }

    // MARK: Quitting

    /// On the way out: our hooks are about to start posting to a port nothing
    /// is listening on, so offer to take them out.
    ///
    /// **What goes wrong without this.** The hooks are registered at user
    /// scope — one registration, routed by `cwd`, which is the design and not
    /// an accident. So they fire for *every* Claude Code session on the
    /// machine, in every project, whether or not SpriteRoom is running. The
    /// moment this process is gone, every tool call in every session POSTs to a
    /// dead port and Claude Code reports `ECONNREFUSED`. A status viewer that
    /// puts an error in the session it is watching has inverted its own
    /// purpose. I5 is the same sentence one process boundary in: the app never
    /// surfaces an error into the user's session.
    ///
    /// **It asks. It does not remove silently.** `~/.claude/settings.json` is
    /// the user's file; the install path asks and the removal path has to
    /// match. Removing without asking would also quietly undo a deliberate
    /// choice every time someone quit and relaunched. `HookInstaller.remove()`
    /// does the writing, restoring the original bytes from the install-time
    /// backup — no second write path exists and none is added here.
    ///
    /// **This covers a quit, and only a quit.** A crash, a `kill -9`, a reboot
    /// or a power cut runs no code of ours, so nothing in this app can cover
    /// them; see the note in `README.md`. The menu bar's **Remove Claude Code
    /// Hooks** is the manual equivalent and predates this, and
    /// `spriteroom --remove-hooks` works with no window server at all — which
    /// is the recovery path after a crash, because there cannot be another one.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Before the dialog, not after: an alert with the room still hanging
        // over it is a worse thing to look at, and the app is leaving anyway.
        controller?.hide()
        guard let installer = hookInstaller, !answeredHookQuit else { return .terminateNow }
        answeredHookQuit = true

        switch installer.atQuit(ask: { self.hookQuitAnswer(installer: installer) }) {
        case .notInstalled:
            break
        case .kept:
            print("hooks left in \(installer.settingsURL.path). While nothing is listening on "
                + "\(installer.url) every Claude Code tool call will report a connection error; "
                + "`spriteroom --remove-hooks` takes them out.")
        case .removed:
            print("hooks removed from \(installer.settingsURL.path)")
        case .failed(let message):
            print("could not check or write \(installer.settingsURL.path): \(message)")
        }
        return .terminateNow
    }

    /// `nil` means nobody could be asked, and nothing is written.
    private func hookQuitAnswer(installer: HookInstaller) -> HookQuit? {
        if let answer = options.quitAnswer { return answer }
        guard options.quitPrompt else { return nil }
        // A harness has no one to click a modal. `--panel-render` and the
        // probes both exit on their own schedule and would hang forever on
        // one, so neither is ever asked; `--quit-answer` is how those runs
        // exercise this branch.
        guard options.probe == nil, options.panelRenderDirectory == nil else { return nil }
        return Self.askAboutRemoval(installer: installer)
    }

    /// The dialog. Like the consent dialog, this is the only part of the flow
    /// that needs a screen and the only part that holds no logic.
    ///
    /// It is an `NSAlert` from the menu-bar app. Nothing about it touches the
    /// panel, which takes no keyboard events and is not a responder. [I8]
    ///
    /// **"Leave Them" is the default button.** The destructive-looking answer
    /// is not the one a stray Return picks, and leaving them is the answer that
    /// writes nothing.
    private static func askAboutRemoval(installer: HookInstaller) -> HookQuit {
        let alert = NSAlert()
        alert.messageText = "Remove Sprite Room's Claude Code hooks?"
        alert.informativeText = """
            Sprite Room is quitting, and its hooks are still registered in
            \(installer.settingsURL.path)

            They are registered at user scope, so they fire for every Claude \
            Code session on this machine. With nothing listening on \
            \(installer.url), every tool call in every session will spend up to \
            \(HookInstaller.timeout) seconds failing to reach Sprite Room and \
            report a connection error.

            Removing them puts that file back exactly as it was. Register them \
            again from the menu bar next time, or with \
            `spriteroom --install-hooks --yes`.
            """
        alert.alertStyle = .warning
        // First button is the default. Keeping them writes nothing, so that is
        // the safe answer to land on.
        alert.addButton(withTitle: "Leave Them")
        alert.addButton(withTitle: "Remove Hooks")
        return alert.runModal() == .alertFirstButtonReturn ? .keep : .remove
    }

    /// Criterion 5, driven through the real menu items rather than around
    /// them: find each project's `NSMenuItem`, perform its action, and report
    /// what the room became.
    private func driveSelector(host: RoomHost, selector: ProjectSelector) async {
        print("selector: waiting for two projects…")
        while host.entries.count < 2 {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
        // Keep switching for as long as the run lasts. One pass would prove
        // the mechanism; repeating it is what shows the two rooms diverging
        // while both sessions are actually doing something.
        var pass = 0
        while !Task.isCancelled {
            // The menu is built lazily when it is about to be shown; ask for
            // that explicitly rather than reaching past it.
            selector.menu.delegate?.menuNeedsUpdate?(selector.menu)
            let items = selector.menu.items.filter { $0.representedObject is String }
            print("selector: pass \(pass), \(items.count) project item(s): "
                + items.map(\.title).joined(separator: " | "))

            for item in items {
                guard let action = item.action, let target = item.target else { continue }
                _ = target.perform(action, with: item)
                try? await Task.sleep(for: .seconds(3))
                let roster = host.entries
                    .map { "\($0.displayName)=\($0.population)" }.joined(separator: ",")
                print("selector: clicked '\(item.title)' → selected=\(host.selected ?? "-") "
                    + "charactersOnScreen=\(host.scene.charactersOnScreen.count) roster=[\(roster)]")
                if let directory = options.panelRenderDirectory {
                    let safe = (host.selected ?? "none")
                        .split(separator: "/").last.map(String.init) ?? "none"
                    _ = capture(
                        host: host, named: "selector-p\(pass)-\(safe).png", into: directory)
                }
            }
            pass += 1
            try? await Task.sleep(for: .seconds(6))
        }
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
        case .selector:
            // Driven from `runLive`, which is the only place two projects can
            // exist. Reaching here means `--probe selector` without `--live`.
            print("--probe selector needs --live: it drives the menu over real sessions")
            status = 2
        }
        // `exit()` runs no `applicationWillTerminate`, and every probe leaves
        // the real panel somewhere on the screen. Same ghost, same fix.
        await tearDownPanel()
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

// Installing hooks opens no window and needs no scene. It happens before
// anything else so a bad manifest cannot stop the user from *removing* our
// hooks — the one operation that must always be available.
if let action = options.hookAction {
    exit(runHookAction(action, options: options))
}

let root = Manifest.developmentRoot()

// `--panel-render` reveals the *real* panel over whatever you are doing, at a
// level above the menu bar, on every space, ignoring the mouse. It is worth
// having — the panel is sometimes the thing under test — but it is never worth
// having by accident, and it is not the way to look at the scene: `--render`
// draws the same room offscreen, takes `--theme`, and never touches the
// display. So the panel path says what it costs and asks you to mean it.
if options.panelRenderDirectory != nil, !options.forcePanelRender {
    print("""
        --panel-render reveals the real panel on your screen: above the menu bar, \
        on every space, and click-through.

        You almost certainly want --render, which draws the same scene offscreen \
        and opens nothing:
          spriteroom \(options.fixture?.path ?? "fixtures/three-subagents.jsonl") \
        --render \(options.panelRenderDirectory!.path) --at \
        \(options.renderTimes.isEmpty ? "6,12,20" : options.renderTimes.map { String($0) }.joined(separator: ","))

        If the panel itself is what you are testing, add --force-panel-render.
        """)
    exit(2)
}

// `--theme` names the room for the two hosts that build one from a flag. The
// panel derives a theme per project from its `cwd` and takes overrides from
// Room ▸ — a flag there would be a fourth answer to a question §3c already
// answers, so it is refused rather than ignored.
if let requested = options.themeID, requested != "list", options.host == .panel {
    print("--theme applies to --render and --window. The panel derives each "
        + "project's room from its cwd; Room ▸ in the menu bar overrides it.")
    exit(2)
}
if options.themeID == "list" {
    do {
        let manifest = try Manifest.load(root: root)
        switch themeToDraw(options: options, manifest: manifest, entries: []) {
        case .draw: exit(0)
        case .stop(let code): exit(code)
        }
    } catch {
        print("could not read the manifest: \(error)")
        exit(1)
    }
}

let fixtureURL = options.fixture ?? defaultFixture(root: root)
var entries: [HookLogEntry] = []
if options.probe == nil && !options.live {
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
