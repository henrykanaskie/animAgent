import AppKit
import Testing
@testable import SpriteRoomApp

/// I8, asserted on the real window object rather than argued for in a comment.
///
/// These need a window server (an `NSPanel` cannot be built without one) so
/// they skip rather than fail when there is no GUI session. The hysteresis and
/// the geometry, which are the parts with logic in them, need no such thing and
/// always run.
@MainActor
struct NotchPanelTests {

    /// True in a logged-in GUI session.
    ///
    /// The question itself now lives in `PanelWindowServer` (`PanelFixtures.swift`),
    /// alongside the always-on notice and the pinned count that make the skip
    /// legible: the same arrangement `SceneArt` has for the art. This forwards
    /// rather than being renamed away so that 26 gate annotations across three
    /// files did not have to change to close that hole.
    nonisolated static var hasWindowServer: Bool { PanelWindowServer.isAvailable }

    static func panel() -> NotchPanel {
        // Touching `NSApplication.shared` first initialises the connection the
        // window needs.
        _ = NSApplication.shared
        return NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 200))
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func thePanelCanNeverBecomeKeyOrMain() {
        let panel = Self.panel()
        #expect(panel.canBecomeKey == false)
        #expect(panel.canBecomeMain == false)
        #expect(panel.acceptsFirstResponder == false)
        // The call that would break the invariant, made deliberately. It has to
        // be a no-op, not a bug report.
        panel.makeKeyAndOrderFront(nil)
        #expect(panel.isKeyWindow == false)
        #expect(panel.isMainWindow == false)
        panel.orderOut(nil)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func thePanelRefusesToInstallAFirstResponder() {
        let panel = Self.panel()
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(panel.makeFirstResponder(field) == false)
        #expect(panel.firstResponder === panel)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func thePanelIsConfiguredTheWayTheInvariantRequires() {
        let panel = Self.panel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        // Criterion 3: over a full-screen space. `canJoinAllSpaces` alone puts
        // it on every *desktop*; `fullScreenAuxiliary` is what lets it sit over
        // a full-screen window.
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
        #expect(panel.level.rawValue > NSWindow.Level.statusBar.rawValue)
        // Not above the screen saver: covering a locked screen with the room
        // would be a privacy bug.
        #expect(panel.level.rawValue < NSWindow.Level.screenSaver.rawValue)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func thePanelIsNotConstrainedAwayFromTheMenuBar() {
        let panel = Self.panel()
        // AppKit would otherwise push it down below the menu bar, which is
        // exactly where the reveal animation needs it to be.
        let proposed = NSRect(x: 10, y: 5000, width: 400, height: 200)
        #expect(panel.constrainFrameRect(proposed, to: nil) == proposed)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func theControllerStartsHiddenAndTracksThePolicy() {
        _ = NSApplication.shared
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let controller = NotchPanelController(contentView: content)
        #expect(controller.phase == .hidden)
        #expect(controller.isRevealed == false)

        controller.forceReveal(at: 0)
        #expect(controller.isRevealed)
        #expect(controller.revealCount == 1)
        controller.forceRetract(at: 1)
        #expect(controller.isRevealed == false)
        #expect(controller.retractCount == 1)
        controller.panel.orderOut(nil)
    }

    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func nothingInThePanelCanTakeAKeystroke() {
        _ = NSApplication.shared
        // The real content view. A stock `SKView` accepts first responder
        // status (the focus probe found that) so the panel uses a subclass
        // that does not, and this is the test that keeps it that way.
        let content = RoomView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(content.acceptsFirstResponder == false)
        #expect(content.becomeFirstResponder() == false)
        let controller = NotchPanelController(contentView: content)
        var responders: [String] = []
        func walk(_ view: NSView?) {
            guard let view else { return }
            if view.acceptsFirstResponder { responders.append("\(type(of: view))") }
            view.subviews.forEach(walk)
        }
        walk(controller.panel.contentView)
        #expect(responders.isEmpty, "keyboard-capable views in the panel: \(responders)")
        controller.panel.orderOut(nil)
    }

    // MARK: Getting off the screen

    /// **The ghost panel.** `--panel-render` used to reveal the real panel and
    /// hard-exit without ordering it out, and the window server can leave that
    /// surface drawn with no process behind it. It is the one window a user
    /// cannot clear by hand: `ignoresMouseEvents` so clicks pass through, a
    /// level above the menu bar so nothing can be raised in front of it, and
    /// `canJoinAllSpaces` so it follows every desktop. The maintainer hit it,
    /// and killing the process did not help; the process was already gone.
    ///
    /// `hide()` is the teardown call every exit path now goes through. It has
    /// to work from the revealed state, which is the only state that leaves a
    /// ghost.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func hidingTakesThePanelOffTheScreenFromTheRevealedState() {
        _ = NSApplication.shared
        let content = RoomView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let controller = NotchPanelController(contentView: content)

        controller.forceReveal(at: 0)
        #expect(controller.isRevealed)
        controller.panel.orderFrontRegardless()
        #expect(controller.panel.isVisible)

        controller.hide(at: 1)

        // Ordered out is what removes the surface from the window server.
        // Nothing else in this type does that synchronously: `slide` only
        // orders out in an animation completion handler, which is precisely
        // the callback a process that is exiting never runs.
        #expect(controller.panel.isVisible == false, "the panel is still on the screen")
        // And the policy agrees, so a stray sample cannot bring it back.
        #expect(controller.isRevealed == false)
        #expect(controller.phase == .hidden)
    }

    /// Hiding twice, and hiding something already hidden, are both no-ops.
    /// Teardown runs from `applicationWillTerminate` *and* from the `exit()`
    /// paths, and on some routes from both.
    @Test(.enabled(if: NotchPanelTests.hasWindowServer))
    func hidingIsSafeToDoTwiceAndFromTheHiddenState() {
        _ = NSApplication.shared
        let content = RoomView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let controller = NotchPanelController(contentView: content)

        controller.hide(at: 0)
        #expect(controller.panel.isVisible == false)
        controller.forceReveal(at: 1)
        controller.panel.orderFrontRegardless()
        controller.hide(at: 2)
        controller.hide(at: 3)
        #expect(controller.panel.isVisible == false)
        #expect(controller.phase == .hidden)
    }

    /// The gate on the harness that caused the ghost. `--render` draws the same
    /// scene offscreen and touches no display, so the panel path is only wanted
    /// when the panel is the thing under test, and then it is asked for
    /// explicitly.
    @Test func panelRenderIsOptOutOfNothingAndOptInToSomething() {
        #expect(parse(["--panel-render", "out"])?.forcePanelRender == false)
        #expect(parse(["--panel-render", "out", "--force-panel-render"])?.forcePanelRender == true)
        #expect(parse([])?.forcePanelRender == false)
        let text = usage()
        #expect(text.contains("--force-panel-render"))
    }
}
