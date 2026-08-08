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
    /// short of the anchor's seat. On the aisle rather than the seat row so
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

    /// **Which side of the anchor a reporter stands on: its own.**
    ///
    /// It used to be the left, always. That was harmless while a report was the
    /// front half of an exit — the reporter walked to the anchor and then off
    /// the near edge, and never came back through the room. A report is now a
    /// round trip, and a reporter seated to the *right* of its anchor would walk
    /// past the anchor on the way in and past it again on the way home: two
    /// crossings of the one seat every other character in the room is anchored
    /// to, held for the length of a walk each time.
    ///
    /// Approaching from its own side removes both. It also halves the traverse —
    /// a reporter now only ever crosses the aisle between its own desk and the
    /// anchor's, never the far side of the room — and it is the more natural
    /// read besides: you walk over to the person you report to, you do not walk
    /// round them.
    public func deliverySide(anchorSeat: Int, reporterSeat: Int) -> Facing {
        seatPosition(reporterSeat).x >= seatPosition(anchorSeat).x ? .right : .left
    }

    /// Subagents can stop within a second of each other, so the delivery point
    /// is a row of slots rather than a single spot. Slot 0 is nearest the
    /// anchor and each further slot steps one pitch away, outward on `side`.
    ///
    /// The pitch is wider than the widest nameplate the font will draw, so two
    /// reporters delivering at once cannot land their plates on top of one
    /// another. Slots rather than a queue because queueing would mean a
    /// character standing about waiting, and nothing in the data says it
    /// waited. [I1]
    ///
    /// **The two sides are separate rows of slots**, so a reporter arriving from
    /// the left is never pushed a pitch out because someone is delivering on the
    /// right. Slot 0 on each side is 1.5 tiles from the anchor, so the two are a
    /// full seat pitch apart — wider than the widest plate, by the same argument
    /// that sizes the pitch.
    ///
    /// `anchorSeat` is whose seat the reporter delivers to. It is 0 — the main
    /// agent — unless `tool_response.agentId` linked the reporter to a
    /// different parent that is still in the room.
    public func deliveryPosition(
        anchorSeat: Int = 0, side: Facing = .left, slot: Int
    ) -> ScenePoint {
        let outward = side == .right ? 1.0 : -1.0
        return ScenePoint(
            x: seatPosition(anchorSeat).x
                + outward * (Double(tile) * 1.5 + Double(max(0, slot)) * Self.deliverySlotPitch),
            y: aisleY)
    }

    /// Clear of `SceneBitmaps.maximumNameplateWidth`, which is 65 px since the
    /// plate went to two rows — it was 77 px on one row, so this number used to
    /// be nearly spent and is not any more. `NameplateTests` checks the bound
    /// rather than trusting this comment.
    public static let deliverySlotPitch: Double = 80

    /// Which way the reporter faces to hand its report over: at the anchor.
    /// Delivering with your back to the person you are delivering to would be a
    /// small lie about a real event. [I1]
    public var deliveryFacing: Facing { deliveryFacing(side: .left) }

    public func deliveryFacing(side: Facing) -> Facing {
        side == .right ? .left : .right
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
