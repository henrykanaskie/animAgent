import Foundation

/// A point in unscaled scene pixels, y-up. Deliberately not `CGPoint` — the
/// layout is pure arithmetic and unit-tests without any graphics framework.
public struct ScenePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Where everything stands, in unscaled scene pixels.
///
/// **Side view, by necessity.** Both sit rows in Modern Interiors are side art
/// in all four direction blocks — there is no front- or back-facing sitting
/// sprite at any size. So the desks face sideways and the camera looks along
/// the row. That is the design, not a compromise to fix later.
/// [04-ART-DIRECTION, "Sitting is side-view only"]
public struct RoomLayout: Sendable, Hashable {

    public let tile: Int
    /// Seats the floor is drawn wide enough for. Beyond this, seats wrap and
    /// characters share columns — a room with more than this many agents is
    /// past the point where anything reads anyway.
    public let seatCapacity: Int
    /// Tiles between adjacent seats: one for the character, one for its desk,
    /// one of air.
    public let seatSpacingTiles: Int
    public let columns: Int
    public let rows: Int
    /// Floor rows are below this; wall rows at and above it.
    public let wallRows: Int

    public init(tile: Int = 32, seatCapacity: Int = 7, seatSpacingTiles: Int = 3) {
        self.tile = max(1, tile)
        self.seatCapacity = max(1, seatCapacity)
        self.seatSpacingTiles = max(2, seatSpacingTiles)
        // Enough columns for every seat plus its desk plus a margin each side.
        self.columns = self.seatCapacity * self.seatSpacingTiles + 4
        self.rows = 6
        self.wallRows = 2
    }

    /// Tiles are drawn past the room's nominal bounds so no zoom level ever
    /// shows the void behind the room. The *content* box the camera fits stays
    /// `width` × `height`; this is only what gets painted.
    public var drawnRows: ClosedRange<Int> { -6...(rows + 8) }
    public var drawnColumns: ClosedRange<Int> { -8...(columns + 8) }

    public var width: Double { Double(columns * tile) }
    public var height: Double { Double(rows * tile) }
    public var floorRows: Int { rows - wallRows }

    /// Y of the line characters stand on: the top of the second floor row, so
    /// there is a clear tile of floor beneath for the nameplate.
    public var baselineY: Double { Double(tile * 2) }

    /// The walkway one tile in front of the desk row, nearer the camera.
    ///
    /// Everything that moves — entering, reporting, leaving — moves along this
    /// line rather than through the seats. Without it a reporting subagent
    /// walks straight through whoever is sitting between it and the anchor,
    /// and the two nameplates collide at the delivery point.
    public var aisleY: Double { baselineY - Double(tile) }
    /// Y where the wall meets the floor.
    public var wallBaseY: Double { Double(floorRows * tile) }

    /// Seats fill outward from the centre: 0 centre, 1 right of it, 2 left of
    /// it, and so on. Deterministic, so a given arrival order always produces
    /// the same room.
    public func seatColumn(_ index: Int) -> Int {
        let wrapped = index % seatCapacity
        let step = (wrapped + 1) / 2
        let sign = wrapped.isMultiple(of: 2) ? -1 : 1
        let centre = columns / 2
        return centre + sign * step * seatSpacingTiles
    }

    /// Where the character's feet go when seated at `index`.
    public func seatPosition(_ index: Int) -> ScenePoint {
        ScenePoint(x: Double(seatColumn(index) * tile + tile / 2), y: baselineY)
    }

    /// Bottom-**centre** of the desk for a seat. It sits just to the character's
    /// right; every seated character faces right at it. Uniform facing keeps the
    /// row readable and keeps every seated sprite inside the two directions the
    /// pack drew.
    ///
    /// The offset is seven eighths of a tile, which puts a 32 px desk's near
    /// edge four pixels inside the body. That overlap is the point: at 32 px the
    /// only cue that a character is sitting *at* a desk rather than beside one
    /// is whether the desk's near edge crosses it.
    public func deskPosition(_ index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x + Double(tile) * 0.875, y: baselineY)
    }

    public var seatedFacing: Facing { .right }

    /// Where a reporting subagent walks to before it delivers: into the aisle,
    /// short of the main agent's seat. On the aisle rather than the seat row so
    /// it does not walk through whoever is sitting in between.
    ///
    /// The gap is a tile and a half, not a quarter-tile, and the number is
    /// load-bearing: at three quarters of a tile the reporter's 32px-wide body
    /// stood squarely on top of the anchor's nameplate. That was legible only
    /// because the plate is drawn in an overlay band; standing clear as well
    /// means the anchor's identity is not merely on top of a body but
    /// unobstructed by one, at the exact moment the room is dramatising a
    /// report. [criterion 5]
    public var deliveryPosition: ScenePoint { deliveryPosition(slot: 0) }

    /// Subagents can stop within a second of each other, so the delivery point
    /// is a row of slots rather than a single spot. Slot 0 is nearest the
    /// anchor and each further slot steps one pitch away.
    ///
    /// The pitch is wider than the widest nameplate the font will draw, so two
    /// reporters delivering at once cannot land their plates on top of one
    /// another. Slots rather than a queue because queueing would mean a
    /// character standing about waiting, and nothing in the data says it
    /// waited. [I1]
    ///
    /// `anchorSeat` is whose seat the reporter delivers to. It is 0 — the main
    /// agent — unless `tool_response.agentId` linked the reporter to a
    /// different parent that is still in the room.
    public func deliveryPosition(anchorSeat: Int = 0, slot: Int) -> ScenePoint {
        ScenePoint(
            x: seatPosition(anchorSeat).x - Double(tile) * 1.5
                - Double(max(0, slot)) * Self.deliverySlotPitch,
            y: aisleY)
    }

    /// One pitch clear of the widest plate `PixelFont` will produce at the
    /// nameplate's glyph limit.
    public static let deliverySlotPitch: Double = 80

    /// Which way the reporter faces to hand its report over. It stands left of
    /// the anchor, so it turns right — delivering with your back to the person
    /// you are delivering to would be a small lie about a real event. [I1]
    public var deliveryFacing: Facing { deliveryFacing(anchorSeat: 0) }

    public func deliveryFacing(anchorSeat: Int) -> Facing {
        deliveryPosition(anchorSeat: anchorSeat, slot: 0).x < seatPosition(anchorSeat).x
            ? .right : .left
    }

    /// The point on the aisle directly in front of a seat. A character walks
    /// here first, then steps back to its desk.
    public func seatApproach(_ index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x, y: aisleY)
    }

    /// Where a character walks in from: one seat-pitch beyond its own seat, on
    /// the outward side, in the aisle.
    ///
    /// Not the room edge. The camera frames the occupied seats, so a character
    /// starting at the far wall spends its entire walk-in off screen and the
    /// room just sits there looking empty while it happens. One pitch out is
    /// the edge of what the camera frames, so the walk is visible from its
    /// first frame.
    public func edgePosition(forSeat index: Int) -> ScenePoint {
        let seat = seatPosition(index)
        let outward = seat.x >= width / 2 ? 1.0 : -1.0
        return ScenePoint(
            x: seat.x + outward * Double(seatSpacingTiles * tile), y: aisleY)
    }

    /// The nearer edge to a point already on screen.
    public func nearestEdge(toX x: Double) -> ScenePoint {
        ScenePoint(
            x: x >= width / 2 ? width + Double(tile) : -Double(tile),
            y: aisleY)
    }

    /// The vertical strip the camera actually has to frame: from the bottom of
    /// the lowest nameplate to the top of the tallest badge.
    ///
    /// **Not `height`.** The room's nominal box is `rows * tile` = 192 px, and
    /// the camera used to fit that. At the panel's 720×400 the consequence was
    /// that the strip where anything happens — about 132 px of it — sat in the
    /// middle third with a flat band of wall above and a flat band of floor
    /// below, and `3x` was unreachable at any population because 192×3 does not
    /// fit in 400. Framing the strip instead puts one working agent at `3x`
    /// filling the panel, which is the case a glance surface exists for.
    ///
    /// Both arguments are measured from the manifest by the caller rather than
    /// written down here, so a taller badge or a taller font changes the frame
    /// instead of quietly overflowing it.
    ///
    /// - Parameters:
    ///   - badgeTopAboveFeet: highest pixel a seated character can put on
    ///     screen, relative to its own feet.
    ///   - plateDropBelowFeet: how far a nameplate hangs below the feet.
    public func contentBand(
        badgeTopAboveFeet: Double, plateDropBelowFeet: Double
    ) -> (bottom: Double, top: Double) {
        // The lowest plate belongs to a character in the aisle, not at a desk.
        (aisleY - plateDropBelowFeet, baselineY + badgeTopAboveFeet)
    }

    /// Bounding box in x of the given seats plus their desks, padded by a
    /// tile. Feeds the camera: the room is drawn full width but only the
    /// occupied part has to fit on screen.
    public func occupiedSpan(seats: some Collection<Int>) -> (minX: Double, maxX: Double) {
        guard !seats.isEmpty else {
            let centre = width / 2
            return (centre - Double(tile * 2), centre + Double(tile * 2))
        }
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        for seat in seats {
            let position = seatPosition(seat)
            minX = min(minX, position.x - Double(tile))
            maxX = max(maxX, position.x + Double(tile * 2))
        }
        return (max(0, minX - Double(tile)), min(width, maxX + Double(tile)))
    }
}
