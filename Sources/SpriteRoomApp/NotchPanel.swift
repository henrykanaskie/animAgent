import AppKit

/// The window the room lives in. [I8]
///
/// Every line of the configuration below exists to make one sentence true:
/// **this window can never take focus from what you are doing.** The invariant
/// is not "we try not to steal focus" — it is that there is no code path by
/// which focus could arrive here.
///
/// * `.nonactivatingPanel` — ordering the panel in does not activate the app.
/// * `canBecomeKey` / `canBecomeMain` are hard `false`. AppKit asks these
///   before it makes any window key; answering `false` means the window is not
///   a candidate, so `makeKeyAndOrderFront` is a no-op rather than a bug
///   waiting to happen.
/// * `acceptsFirstResponder` is `false` and the panel installs no field editor.
///   Keyboard events are routed to the key window; a window that is never key
///   receives none, ever.
/// * `ignoresMouseEvents = true` — the panel does not consume clicks either.
///   Nothing in the room is clickable (read-only, always), so a click that
///   lands on it belongs to the window underneath and is passed straight
///   through. Hover is detected by sampling the pointer's global position, not
///   by receiving events, which is why this costs us nothing.
///
/// The panel is therefore a *display surface* in the strictest sense: pixels
/// out, no events in.
final class NotchPanel: NSPanel {

    /// Judgment call: `.mainMenu + 3`.
    ///
    /// It has to be above the menu bar (`.mainMenu`, 24) and above status items
    /// (`.statusBar`, 25) because the panel hangs over both. It deliberately is
    /// *not* `.screenSaver`: covering a screen saver or a lock screen with the
    /// room would be a privacy bug, and no notch panel needs to outrank those.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        // Order matters here, and a test caught it: `isFloatingPanel`'s setter
        // assigns `.floating` (level 3) as a side effect, which is *below* the
        // menu bar. It has to be set before the level, never after.
        isFloatingPanel = true
        level = Self.level
        // `canJoinAllSpaces` puts it on every desktop; `fullScreenAuxiliary` is
        // what lets it sit over a full-screen space instead of being confined
        // to the desktop that owns it. Both are required for the third exit
        // criterion — either alone is not enough.
        collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        isMovable = false
        ignoresMouseEvents = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        // AppKit's own window animations fight the reveal animation and add an
        // uncontrolled duration to it.
        animationBehavior = .none
        // Nothing in here is a document and nothing is restorable.
        isRestorable = false
        // A panel that never becomes key must not be offered in the Window menu
        // or to the accessibility focus ring.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    // MARK: The invariant, stated as code

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    /// AppKit calls this on the window before making it key. Refusing here as
    /// well as in `canBecomeKey` costs nothing and closes the path where a
    /// stray `makeFirstResponder` would install one.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        responder == nil ? super.makeFirstResponder(nil) : false
    }

    /// Keyboard events cannot reach a window that is never key, but if one ever
    /// did, dropping it is better than acting on it. [I8]
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}

    /// AppKit constrains ordinary windows so they cannot be pushed under the
    /// menu bar or off the top of the screen. Both are exactly what the reveal
    /// animation does, so the constraint is refused.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
