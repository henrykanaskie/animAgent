import Foundation

// The notch region, computed as arithmetic on plain numbers.
//
// Deliberately free of AppKit types, for the same reason `RoomCamera` is free
// of SpriteKit types: the interesting part is a claim about rectangles, and a
// claim about rectangles should be a unit test rather than something you check
// by looking at a screen. `NotchGeometry+AppKit.swift` is the only file that
// knows what an `NSScreen` is.
//
// Coordinates throughout are AppKit *global screen* coordinates: y increases
// upward, the origin is the bottom-left of the main display. Not the flipped
// CoreGraphics space.

/// A point in global screen coordinates, y-up.
public struct PanelPoint: Sendable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var description: String { String(format: "(%.1f, %.1f)", x, y) }
}

/// A rectangle in global screen coordinates, y-up. Non-negative extents.
public struct PanelRect: Sendable, Hashable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public static let zero = PanelRect(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public var description: String {
        String(format: "(%.0f, %.0f, %.0f×%.0f)", x, y, width, height)
    }

    /// Half-open on the far edges, so two rectangles that share an edge do not
    /// both claim a point on it.
    public func contains(_ point: PanelPoint) -> Bool {
        guard !isEmpty else { return false }
        return point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    /// Negative insets grow the rectangle. Growing never fails; shrinking
    /// clamps at empty.
    public func inset(dx: Double, dy: Double) -> PanelRect {
        PanelRect(
            x: x + dx, y: y + dy,
            width: width - 2 * dx, height: height - 2 * dy)
    }

    /// The smallest rectangle containing both. An empty operand is ignored —
    /// unioning with `.zero` must not drag a region down to the origin.
    public func union(_ other: PanelRect) -> PanelRect {
        if other.isEmpty { return self }
        if isEmpty { return other }
        let lowX = Swift.min(minX, other.minX)
        let lowY = Swift.min(minY, other.minY)
        return PanelRect(
            x: lowX, y: lowY,
            width: Swift.max(maxX, other.maxX) - lowX,
            height: Swift.max(maxY, other.maxY) - lowY)
    }
}

/// Where the notch is on one display, and where the panel hangs from it.
///
/// **On a display without a notch** — an external monitor, or any Mac before
/// the 2021 MacBook Pro — there is no physical region to point at, so the hot
/// zone is *synthesised*: a rectangle of `syntheticWidth` points centred on the
/// top edge, as tall as that display's menu bar. It sits where a notch would be
/// if the display had one. That keeps one mental model ("point at the middle of
/// the top edge") across every display, and the middle of the menu bar is the
/// one stretch of it that neither the app menus nor the status items use.
public struct NotchGeometry: Sendable, Hashable {

    /// The full display, global coordinates.
    public let display: PanelRect
    /// The camera housing, if this display has one. `nil` on every other
    /// display, including external monitors attached to a notched Mac.
    public let physicalNotch: PanelRect?
    /// Height of the menu bar on this display.
    public let menuBarHeight: Double
    /// Width of the synthesised region used when `physicalNotch` is `nil`.
    public let syntheticWidth: Double

    /// Points of slack added to each side of the physical notch. The housing is
    /// the *visual* landmark; the hot zone is a little wider than it so that
    /// aiming at the notch does not require hitting it exactly.
    public static let notchPadding: Double = 12
    /// Default width of the synthetic region. Roughly a physical notch (220 pt
    /// on a 14-inch MacBook Pro) plus the same padding.
    public static let defaultSyntheticWidth: Double = 240
    /// Fallback when a display reports no menu bar at all — a secondary display
    /// with the menu bar disabled still needs a hot zone with some height.
    public static let minimumRegionHeight: Double = 24

    public init(
        display: PanelRect,
        physicalNotch: PanelRect?,
        menuBarHeight: Double,
        syntheticWidth: Double = NotchGeometry.defaultSyntheticWidth
    ) {
        self.display = display
        self.physicalNotch = physicalNotch
        self.menuBarHeight = max(0, menuBarHeight)
        self.syntheticWidth = max(1, syntheticWidth)
    }

    public var hasPhysicalNotch: Bool { physicalNotch != nil }

    /// Height of the hot zone: the menu bar, or the notch if it is taller.
    public var regionHeight: Double {
        max(Self.minimumRegionHeight, max(menuBarHeight, physicalNotch?.height ?? 0))
    }

    /// The hot zone. Pointing here reveals the panel.
    ///
    /// Anchored to the top edge of the display in both cases, so the region is
    /// always reachable by throwing the pointer at the ceiling.
    public var region: PanelRect {
        let height = regionHeight
        let centre: Double
        let width: Double
        if let notch = physicalNotch {
            centre = notch.midX
            width = notch.width + 2 * Self.notchPadding
        } else {
            centre = display.midX
            width = syntheticWidth
        }
        let clampedWidth = min(width, display.width)
        let x = clamp(centre - clampedWidth / 2, low: display.minX, high: display.maxX - clampedWidth)
        return PanelRect(
            x: x, y: display.maxY - height,
            width: clampedWidth, height: height)
    }

    /// Where the panel sits when it is fully down: hanging from the top edge,
    /// centred on the notch, kept inside the display.
    public func revealedPanelFrame(size: PanelSize) -> PanelRect {
        let width = min(size.width, display.width)
        let height = min(size.height, display.height)
        let x = clamp(
            region.midX - width / 2,
            low: display.minX, high: display.maxX - width)
        return PanelRect(x: x, y: display.maxY - height, width: width, height: height)
    }

    /// Where the panel sits when it is away: the same rectangle, slid straight
    /// up until its bottom edge is the top edge of the display.
    ///
    /// The panel is never resized to hide it. Resizing would re-lay-out the
    /// scene sixty times a second during the animation; sliding does not touch
    /// the scene at all.
    public func hiddenPanelFrame(size: PanelSize) -> PanelRect {
        var frame = revealedPanelFrame(size: size)
        frame.y = display.maxY
        return frame
    }

    private func clamp(_ value: Double, low: Double, high: Double) -> Double {
        guard high > low else { return low }
        return min(max(value, low), high)
    }
}

/// The panel's content size. A plain pair so `NotchGeometry` stays free of
/// `CGSize` and therefore of CoreGraphics.
public struct PanelSize: Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    /// The room, as it hangs under the notch.
    ///
    /// Judgment call: 720×400 at 1× backing. Wide enough that six characters at
    /// `2x` still have air around them, short enough that the panel does not
    /// cover a whole editor window on a 13-inch display.
    public static let room = PanelSize(width: 720, height: 400)
}
