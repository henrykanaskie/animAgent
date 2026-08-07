import AppKit
import Testing
@testable import SpriteRoomApp

/// I8, asserted on the real window object rather than argued for in a comment.
///
/// These need a window server — an `NSPanel` cannot be built without one — so
/// they skip rather than fail when there is no GUI session. The hysteresis and
/// the geometry, which are the parts with logic in them, need no such thing and
/// always run.
@MainActor
struct NotchPanelTests {

    /// True in a logged-in GUI session. A nonisolated C call, so it is safe to
    /// evaluate as a test trait.
    nonisolated static var hasWindowServer: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

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
        // Not above the screen saver — covering a locked screen with the room
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
        // status — the focus probe found that — so the panel uses a subclass
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
}
