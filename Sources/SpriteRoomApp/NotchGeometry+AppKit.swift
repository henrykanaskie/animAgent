import AppKit

// The only file that knows what an `NSScreen` is. Everything above it is
// arithmetic on plain numbers.

extension PanelRect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

extension PanelPoint {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

extension PanelSize {
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

extension NotchGeometry {

    /// Read a display's geometry.
    ///
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the two stretches
    /// of menu bar either side of the camera housing, and they are `nil` on
    /// every display without one. The gap between them *is* the notch: asking
    /// for it that way means we never hard-code a housing width, and a Mac
    /// model with a different one is handled without a change here.
    ///
    /// `safeAreaInsets.top` alone is not enough: it is non-zero on a notched
    /// built-in display but tells you nothing about where the notch is
    /// horizontally, and it is zero on the external display attached to the
    /// same Mac.
    @MainActor
    static func forScreen(
        _ screen: NSScreen,
        syntheticWidth: Double = NotchGeometry.defaultSyntheticWidth
    ) -> NotchGeometry {
        let frame = PanelRect(screen.frame)
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)

        var notch: PanelRect?
        // `SPRITEROOM_NO_NOTCH=1` makes a notched Mac behave like an external
        // display, so the synthesised region can be exercised on hardware that
        // has a housing. There is no other way to test that path without
        // plugging in a second monitor.
        let pretendNoNotch = ProcessInfo.processInfo.environment["SPRITEROOM_NO_NOTCH"] == "1"
        if !pretendNoNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            notch = PanelRect(
                x: left.maxX,
                y: min(left.minY, right.minY),
                width: right.minX - left.maxX,
                height: max(screen.safeAreaInsets.top, max(left.height, right.height)))
        }

        return NotchGeometry(
            display: frame,
            physicalNotch: notch,
            menuBarHeight: menuBarHeight,
            syntheticWidth: syntheticWidth)
    }

    /// The display the pointer is on, falling back to the one with the menu bar
    /// and then to whatever exists.
    ///
    /// "Active display" is the pointer's display on purpose: the panel is
    /// something you point at, so the only display it can sensibly drop from is
    /// the one the pointer is already on.
    @MainActor
    static func activeScreen(pointer: PanelPoint?) -> NSScreen? {
        if let pointer {
            let point = pointer.cgPoint
            if let hit = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
                return hit
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
