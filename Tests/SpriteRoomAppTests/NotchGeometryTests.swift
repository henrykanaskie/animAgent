import Testing
@testable import SpriteRoomApp

/// The notch region, as arithmetic. Nothing here needs a screen, which is the
/// point of keeping `NotchGeometry` free of `NSScreen`.
struct NotchGeometryTests {

    /// A 14-inch MacBook Pro, measured off this machine: 1800×1169 points,
    /// 38-point safe area, camera housing spanning x ∈ [790, 1010].
    static func notched() -> NotchGeometry {
        NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 1800, height: 1169),
            physicalNotch: PanelRect(x: 790, y: 1131, width: 220, height: 38),
            menuBarHeight: 39)
    }

    /// An external monitor: no housing, ordinary menu bar.
    static func plain(width: Double = 2560, height: Double = 1440, originX: Double = 0)
        -> NotchGeometry {
        NotchGeometry(
            display: PanelRect(x: originX, y: 0, width: width, height: height),
            physicalNotch: nil,
            menuBarHeight: 24)
    }

    // MARK: With a notch

    @Test func theHotZoneStraddlesTheHousingWithSlack() {
        let geometry = Self.notched()
        let region = geometry.region
        #expect(geometry.hasPhysicalNotch)
        #expect(region.minX == 790 - NotchGeometry.notchPadding)
        #expect(region.maxX == 1010 + NotchGeometry.notchPadding)
        // The housing is inside the hot zone, never the other way round.
        #expect(region.contains(PanelPoint(x: 900, y: 1150)))
    }

    @Test func theHotZoneIsGluedToTheTopEdge() {
        for geometry in [Self.notched(), Self.plain(), Self.plain(originX: -1800)] {
            #expect(geometry.region.maxY == geometry.display.maxY)
        }
    }

    @Test func theHotZoneCoversTheWholeMenuBar() {
        let geometry = Self.notched()
        // 39-point menu bar, 38-point housing: the taller one wins, so there is
        // no dead strip under the notch where the pointer is over the menu bar
        // but not over the hot zone.
        #expect(geometry.region.height == 39)
        #expect(geometry.region.minY <= geometry.display.maxY - 39)
    }

    // MARK: Without a notch - the case the milestone asks about

    @Test func aDisplayWithoutAHousingGetsACentredSyntheticRegion() {
        let geometry = Self.plain()
        #expect(!geometry.hasPhysicalNotch)
        let region = geometry.region
        #expect(region.width == NotchGeometry.defaultSyntheticWidth)
        #expect(region.midX == geometry.display.midX)
        #expect(region.maxY == geometry.display.maxY)
    }

    @Test func theSyntheticRegionIsAtLeastAsTallAsAMenuBar() {
        // A secondary display can report a zero-height menu bar. The region
        // still has to be tall enough to aim at.
        let geometry = NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 1920, height: 1080),
            physicalNotch: nil,
            menuBarHeight: 0)
        #expect(geometry.region.height == NotchGeometry.minimumRegionHeight)
    }

    @Test func aDisplayLeftOfTheMainOneKeepsItsRegionOnItself() {
        let geometry = Self.plain(width: 1440, height: 900, originX: -1440)
        let region = geometry.region
        #expect(region.minX >= geometry.display.minX)
        #expect(region.maxX <= geometry.display.maxX)
        #expect(region.midX == -720)
    }

    @Test func aRegionWiderThanTheDisplayIsClamped() {
        let geometry = NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 160, height: 400),
            physicalNotch: nil,
            menuBarHeight: 24,
            syntheticWidth: 900)
        #expect(geometry.region.width == 160)
        #expect(geometry.region.minX == 0)
    }

    // MARK: The panel's own frames

    @Test func thePanelHangsFromTheTopEdgeCentredOnTheRegion() {
        let geometry = Self.notched()
        let frame = geometry.revealedPanelFrame(size: .room)
        #expect(frame.maxY == geometry.display.maxY)
        #expect(frame.height == PanelSize.room.height)
        #expect(abs(frame.midX - geometry.region.midX) < 0.001)
    }

    @Test func hidingSlidesThePanelClearOfTheDisplay() {
        let geometry = Self.notched()
        let hidden = geometry.hiddenPanelFrame(size: .room)
        let shown = geometry.revealedPanelFrame(size: .room)
        // Same rectangle, moved. Never resized: resizing would re-lay-out the
        // scene on every frame of the animation.
        #expect(hidden.width == shown.width)
        #expect(hidden.height == shown.height)
        #expect(hidden.minX == shown.minX)
        #expect(hidden.minY == geometry.display.maxY)
    }

    @Test func thePanelStaysOnTheDisplayEvenWhenTheNotchIsNearAnEdge() {
        // Contrived, but the clamp is the only thing standing between a wide
        // panel and half of it hanging off the side of a small display.
        let geometry = NotchGeometry(
            display: PanelRect(x: 0, y: 0, width: 900, height: 600),
            physicalNotch: PanelRect(x: 20, y: 570, width: 60, height: 30),
            menuBarHeight: 30)
        let frame = geometry.revealedPanelFrame(size: .room)
        #expect(frame.minX >= geometry.display.minX)
        #expect(frame.maxX <= geometry.display.maxX)
    }

    // MARK: Rectangle arithmetic

    @Test func edgesBelongToExactlyOneRectangle() {
        let rect = PanelRect(x: 0, y: 0, width: 10, height: 10)
        #expect(rect.contains(PanelPoint(x: 0, y: 0)))
        #expect(!rect.contains(PanelPoint(x: 10, y: 5)))
        #expect(!rect.contains(PanelPoint(x: 5, y: 10)))
    }

    @Test func unioningWithAnEmptyRectangleChangesNothing() {
        let rect = PanelRect(x: 100, y: 100, width: 10, height: 10)
        #expect(rect.union(.zero) == rect)
        #expect(PanelRect.zero.union(rect) == rect)
    }

    @Test func negativeInsetsGrow() {
        let rect = PanelRect(x: 10, y: 10, width: 10, height: 10).inset(dx: -5, dy: -5)
        #expect(rect == PanelRect(x: 5, y: 5, width: 20, height: 20))
    }
}
