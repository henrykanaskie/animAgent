import AppKit
import Foundation

// Verification harnesses for the two M3 criteria that are otherwise claims
// about something a human watched: "focus never leaves the frontmost app" and
// "diagonal pointer paths do not cause oscillation".
//
// Both drive the *real* panel (the real window ordering, the real 30 Hz
// sampler, the real cursor), and both fail loudly. They are the same kind of
// thing `--render` was in M2: a harness, not a feature.

@MainActor
enum Probe {

    /// One observation of where keyboard focus is.
    struct FocusSample: Sendable {
        let cycle: Int
        let appActive: Bool
        let keyWindow: String?
        let panelIsKey: Bool
        let panelIsMain: Bool
        let frontmost: String?
    }

    // MARK: Focus

    /// Reveals and retracts the panel `cycles` times, watching where focus is
    /// the whole way through. [I8, exit criterion 2]
    ///
    /// What this proves on its own: the app never activates, no window of ours
    /// ever becomes key, and the frontmost application never changes. What it
    /// cannot prove without Accessibility permission is the *keystroke* half:
    /// synthesising key events into another app needs a permission this
    /// environment does not have. Run it with an editor frontmost and type
    /// while it runs; the two halves together are the criterion.
    static func focus(
        controller: NotchPanelController,
        cycles: Int,
        countdown: TimeInterval
    ) async -> Int {
        let panel = controller.panel
        var failures: [String] = []

        print("focus probe: \(cycles) reveal/retract cycles")
        print("")
        print("structure:")
        report("panel.canBecomeKey is false", panel.canBecomeKey == false, &failures)
        report("panel.canBecomeMain is false", panel.canBecomeMain == false, &failures)
        report(
            "panel is a non-activating panel",
            panel.styleMask.contains(.nonactivatingPanel), &failures)
        report("panel is borderless", panel.styleMask.contains(.borderless), &failures)
        report(
            "panel level is above the menu bar",
            panel.level.rawValue > NSWindow.Level.mainMenu.rawValue, &failures)
        report(
            "panel joins all spaces",
            panel.collectionBehavior.contains(.canJoinAllSpaces), &failures)
        report(
            "panel is full-screen auxiliary",
            panel.collectionBehavior.contains(.fullScreenAuxiliary), &failures)
        report("panel does not hide on deactivate", panel.hidesOnDeactivate == false, &failures)
        report("panel ignores mouse events", panel.ignoresMouseEvents, &failures)
        report("panel has no first responder view", panel.firstResponder === panel, &failures)
        let responders = keyboardCapableViews(in: panel.contentView)
        report(
            "no view in the panel accepts first responder"
                + (responders.isEmpty ? "" : " (found \(responders.joined(separator: ", ")))"),
            responders.isEmpty, &failures)
        report(
            "app is an accessory (no Dock icon, never frontmost by activation)",
            NSApp.activationPolicy() == .accessory, &failures)

        if countdown > 0 {
            print("")
            print("starting in \(Int(countdown))s, put a text editor in front and type into it")
            var remaining = countdown
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(500))
                remaining -= 0.5
            }
        }

        let baseline = NSWorkspace.shared.frontmostApplication
        let baselineID = describe(baseline)
        print("")
        print("frontmost application at start: \(baselineID ?? "none")")
        if baseline?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            failures.append("we are the frontmost application; the probe proves nothing")
        }

        var samples: [FocusSample] = []
        var offenders: Set<String> = []

        for cycle in 1...max(1, cycles) {
            controller.forceReveal()
            await observe(controller: controller, cycle: cycle, for: 0.30, into: &samples)
            controller.forceRetract()
            await observe(controller: controller, cycle: cycle, for: 0.25, into: &samples)
            print("  cycle \(cycle)/\(cycles): panel down and up, frontmost "
                + "\(describe(NSWorkspace.shared.frontmostApplication) ?? "none")")
        }

        for sample in samples {
            if sample.appActive { offenders.insert("NSApp.isActive became true") }
            if let key = sample.keyWindow { offenders.insert("a window became key: \(key)") }
            if sample.panelIsKey { offenders.insert("the panel became key") }
            if sample.panelIsMain { offenders.insert("the panel became main") }
            if sample.frontmost != baselineID {
                offenders.insert(
                    "frontmost application changed to \(sample.frontmost ?? "none")")
            }
        }

        print("")
        print("empirical: \(samples.count) samples over \(cycles) cycles")
        report("NSApp never became active", !samples.contains { $0.appActive }, &failures)
        report("no window of ours ever became key", !samples.contains { $0.keyWindow != nil },
            &failures)
        report("the panel never became key or main",
            !samples.contains { $0.panelIsKey || $0.panelIsMain }, &failures)
        report("the frontmost application never changed",
            !samples.contains { $0.frontmost != baselineID }, &failures)
        for offender in offenders.sorted() { print("     ! \(offender)") }

        print("")
        print("NOT covered here: real keystrokes. Synthesising key events into another")
        print("application requires Accessibility permission, which this process does not")
        print("have (CGPreflightPostEventAccess = \(CGPreflightPostEventAccess())). Type into an")
        print("editor while this runs and compare what arrived.")

        return finish(failures)
    }

    private static func observe(
        controller: NotchPanelController,
        cycle: Int,
        for duration: TimeInterval,
        into samples: inout [FocusSample]
    ) async {
        let step: TimeInterval = 0.02
        var elapsed: TimeInterval = 0
        while elapsed < duration {
            try? await Task.sleep(for: .milliseconds(Int(step * 1000)))
            elapsed += step
            let key = NSApp.keyWindow
            samples.append(
                FocusSample(
                    cycle: cycle,
                    appActive: NSApp.isActive,
                    keyWindow: key.map { "\(type(of: $0))" },
                    panelIsKey: controller.panel.isKeyWindow,
                    panelIsMain: controller.panel.isMainWindow,
                    frontmost: describe(NSWorkspace.shared.frontmostApplication)))
        }
    }

    /// Anything in the panel that could take a keystroke. Should be empty. [I8]
    private static func keyboardCapableViews(in view: NSView?) -> [String] {
        guard let view else { return [] }
        var found: [String] = []
        if view.acceptsFirstResponder { found.append("\(type(of: view))") }
        for subview in view.subviews { found += keyboardCapableViews(in: subview) }
        return found
    }

    // MARK: Hover

    /// Walks the real cursor through the notch region and counts how many times
    /// the panel changes state. [exit criteria 1 and 4]
    ///
    /// `CGWarpMouseCursorPosition` moves the pointer without posting an event,
    /// so it needs no permission and the panel sees exactly what it would see
    /// from a hand: a sequence of positions read off `NSEvent.mouseLocation` by
    /// its own 30 Hz sampler. Nothing about the panel is stubbed.
    static func hover(controller: NotchPanelController) async -> Int {
        var failures: [String] = []
        let geometry = controller.geometry
        let region = geometry.region

        print("hover probe")
        print("  display        \(geometry.display)")
        print("  physical notch \(geometry.physicalNotch.map { "\($0)" } ?? "none, synthesised")")
        print("  hot zone       \(region)")
        print("  panel down     \(geometry.revealedPanelFrame(size: .room))")
        print("  panel up       \(geometry.hiddenPanelFrame(size: .room))")
        print("")

        var transitions: [PanelTransition] = []
        // Focus is also sampled *at the instant the panel moves*, which is the
        // one moment a non-activating panel could plausibly get it wrong. The
        // focus probe covers 20 forced cycles; this covers the pointer-driven
        // path that a hand actually takes. [I8]
        let baseline = describe(NSWorkspace.shared.frontmostApplication)
        var focusAtTransition: [(Bool, String?)] = []
        controller.onTransition = { transition, _ in
            transitions.append(transition)
            focusAtTransition.append(
                (NSApp.isActive, describe(NSWorkspace.shared.frontmostApplication)))
        }
        defer { controller.onTransition = nil }

        let restore = NSEvent.mouseLocation
        let panelDown = geometry.revealedPanelFrame(size: .room)
        let centre = PanelPoint(x: region.midX, y: region.midY)
        // Well clear of the *panel*, not just of the notch. A point 320 points
        // under the notch is still inside the room, and moving the pointer into
        // the room must not dismiss it, which is why the first draft of this
        // probe measured nothing.
        let below = PanelPoint(x: region.midX, y: panelDown.minY - 180)
        // A diagonal has to actually cross a strip 39 points tall glued to the
        // top edge, so it runs from low-left to high-right and is clipped by
        // the top of the display on the way out, which is what a hand does.
        let diagonalStart = PanelPoint(
            x: max(geometry.display.minX + 4, region.midX - 700),
            y: region.minY - 300)
        let diagonalEnd = PanelPoint(
            x: min(geometry.display.maxX - 4, region.midX + 700),
            y: region.maxY + 300)

        func run(_ name: String, _ body: () async -> Void, expect: (reveals: Int, retracts: Int)) async {
            transitions.removeAll()
            await body()
            let reveals = transitions.filter { $0 == .reveal }.count
            let retracts = transitions.filter { $0 == .retract }.count
            let ok = reveals == expect.reveals && retracts == expect.retracts
            report(
                "\(name): \(reveals) reveal / \(retracts) retract "
                    + "(expected \(expect.reveals)/\(expect.retracts))",
                ok, &failures)
        }

        // Park well away from the notch and let any pending state settle.
        await warp(to: below)
        try? await Task.sleep(for: .milliseconds(1200))

        // 1 - a deliberate approach. The panel must come down, once.
        await run("deliberate entry reveals", {
            await sweep(from: below, to: centre, duration: 0.45)
            try? await Task.sleep(for: .milliseconds(700))
        }, expect: (1, 0))

        // 2 - walking away. The panel must go up, once.
        await run("leaving retracts", {
            await sweep(from: centre, to: below, duration: 0.25)
            try? await Task.sleep(for: .milliseconds(1100))
        }, expect: (0, 1))

        // 3 - the criterion-4 case: a fast diagonal straight across the notch,
        // the pointer on its way to a menu on the other side. Nothing at all
        // should happen.
        await run("fast diagonal across the hot zone does not flash the panel", {
            await sweep(from: diagonalStart, to: diagonalEnd, duration: 0.30)
            await warp(to: below)
            try? await Task.sleep(for: .milliseconds(1400))
        }, expect: (0, 0))

        // 4 - the same diagonal, slowly. It dwells long enough to be
        // deliberate, so one reveal and one retract is correct. What must not
        // happen is more than one of either.
        await run("slow diagonal reveals once and retracts once, never more", {
            await sweep(from: diagonalStart, to: diagonalEnd, duration: 2.6)
            await warp(to: below)
            try? await Task.sleep(for: .milliseconds(1500))
        }, expect: (1, 1))

        // 5 - a hand trembling on the edge of the hot zone with the panel away.
        // In and out every 55 ms: no crossing lasts a dwell, so nothing arms.
        await run("trembling on the hot-zone edge never opens it", {
            for _ in 0..<18 {
                await warp(to: PanelPoint(x: region.midX, y: region.minY - 9))
                try? await Task.sleep(for: .milliseconds(55))
                await warp(to: PanelPoint(x: region.midX, y: region.minY + 9))
                try? await Task.sleep(for: .milliseconds(55))
            }
            await warp(to: below)
            try? await Task.sleep(for: .milliseconds(1200))
        }, expect: (0, 0))

        // 6 - the panel is down and the pointer keeps dipping out of the
        // keep-open zone. Each dip is shorter than the grace period, so the
        // panel must not go anywhere.
        await run("repeated dips out of the keep-open zone do not retract it", {
            await sweep(from: below, to: centre, duration: 0.45)
            try? await Task.sleep(for: .milliseconds(600))
            for _ in 0..<10 {
                await warp(to: PanelPoint(x: region.midX, y: panelDown.minY - 60))
                try? await Task.sleep(for: .milliseconds(150))
                await warp(to: PanelPoint(x: region.midX, y: panelDown.minY + 60))
                try? await Task.sleep(for: .milliseconds(150))
            }
        }, expect: (1, 0))

        report(
            "the app never activated while the pointer drove the panel "
                + "(\(focusAtTransition.count) transitions)",
            !focusAtTransition.contains { $0.0 }, &failures)
        report(
            "the frontmost application never changed while the pointer drove the panel",
            !focusAtTransition.contains { $0.1 != baseline }, &failures)

        await warp(to: PanelPoint(restore))
        return finish(failures)
    }

    /// Moves the cursor along a straight line, one step every 8 ms, finer than
    /// the panel's own 30 Hz sampling, so the sampler sees a genuinely
    /// continuous path rather than teleports.
    private static func sweep(
        from start: PanelPoint, to end: PanelPoint, duration: TimeInterval
    ) async {
        let steps = max(2, Int(duration / 0.008))
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            await warp(
                to: PanelPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t))
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Global y-up screen coordinates to the flipped space `CGWarp…` wants.
    private static func warp(to point: PanelPoint) async {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryHeight - point.y))
    }

    // MARK: Full-screen spaces

    /// Puts a real window into a real full-screen space and checks that the
    /// panel is still on screen over it. [exit criterion 3]
    ///
    /// The window server's own on-screen window list is the evidence: if the
    /// panel were confined to the desktop that owns it, entering a full-screen
    /// space would take it off that list and drop `.visible` from its occlusion
    /// state. Reading the list is metadata, not pixels, so it works without the
    /// Screen Recording permission this environment does not have.
    static func fullScreen(controller: NotchPanelController) async -> Int {
        var failures: [String] = []
        let panel = controller.panel

        report(
            "panel joins all spaces", panel.collectionBehavior.contains(.canJoinAllSpaces),
            &failures)
        report(
            "panel is full-screen auxiliary",
            panel.collectionBehavior.contains(.fullScreenAuxiliary), &failures)

        controller.forceReveal()
        try? await Task.sleep(for: .milliseconds(600))
        report("panel is on screen to begin with", onScreen(panel), &failures)

        // A window of our own, because we cannot ask another application to go
        // full screen without Accessibility permission.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let stage = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        stage.collectionBehavior = [.fullScreenPrimary]
        stage.title = "full-screen stage"
        stage.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(800))

        stage.toggleFullScreen(nil)
        var waited = 0.0
        while waited < 8.0, !stage.styleMask.contains(.fullScreen) {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 0.2
        }
        report("a full-screen space was entered", stage.styleMask.contains(.fullScreen), &failures)
        try? await Task.sleep(for: .milliseconds(1500))

        let visible = panel.isVisible
        let occlusion = panel.occlusionState.contains(.visible)
        let listed = onScreen(panel)
        print("  panel over the full-screen space: isVisible=\(visible) "
            + "occlusionState.visible=\(occlusion) inWindowServerOnScreenList=\(listed)")
        report("the panel is still ordered in over the full-screen space", visible, &failures)
        report("the window server still lists the panel as on screen", listed, &failures)
        report("the panel is not occluded by the full-screen window", occlusion, &failures)

        stage.toggleFullScreen(nil)
        try? await Task.sleep(for: .milliseconds(2000))
        stage.close()
        NSApp.setActivationPolicy(.accessory)
        controller.forceRetract()
        return finish(failures)
    }

    /// Does the window server consider this window on screen right now?
    private static func onScreen(_ window: NSWindow) -> Bool {
        let number = CGWindowID(window.windowNumber)
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { entry in
            guard let listed = entry[kCGWindowNumber as String] as? NSNumber else { return false }
            return CGWindowID(listed.uint32Value) == number
        }
    }

    // MARK: Reporting

    private static func report(_ what: String, _ ok: Bool, _ failures: inout [String]) {
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { failures.append(what) }
    }

    private static func describe(_ app: NSRunningApplication?) -> String? {
        guard let app else { return nil }
        return app.bundleIdentifier ?? app.localizedName ?? "pid \(app.processIdentifier)"
    }

    private static func finish(_ failures: [String]) -> Int {
        print("")
        if failures.isEmpty {
            print("PASS: every check held")
            return 0
        }
        print("FAIL: \(failures.count) check(s) did not hold:")
        for failure in failures { print("  - \(failure)") }
        return 1
    }
}
