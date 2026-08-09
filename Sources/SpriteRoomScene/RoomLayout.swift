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
    /// Entering and leaving move along this line rather than through the seats.
    /// Without it an arriving character walks straight through whoever is
    /// already sitting between it and its own desk.
    ///
    /// **The report walk is no longer on it** — see `deliveryRowY(ring:)`.
    public var aisleY: Double { baselineY - Double(tile) }

    // MARK: The lattice [the aisle invariant]

    /// How far a seat sits from the centre, counted in seat pitches. Seat 0 is
    /// 0; seats 1 and 2 are 1; 3 and 4 are 2; and so on, because seats fill
    /// outward in pairs.
    ///
    /// This is the number the whole plate-clearance argument is built on: two
    /// seats of the same ring are on **opposite sides** of the room, and two
    /// seats of different rings are at least one pitch apart in x.
    public func ring(ofSeat index: Int) -> Int {
        let wrapped = ((index % seatCapacity) + seatCapacity) % seatCapacity
        return (wrapped + 1) / 2
    }

    /// The outermost ring the floor is drawn for.
    public var maximumRing: Int { ring(ofSeat: seatCapacity - 1) }

    /// **One delivery row per ring, in front of the aisle.**
    ///
    /// A reporter walks to its anchor along the row that belongs to its own
    /// ring, and delivers standing on it. Physically it is what you actually do
    /// when you walk over to someone: you go *round* the people between you and
    /// them, which in a side-on room means in front of them. Geometrically it is
    /// what makes the beat safe, and the argument is short enough to check:
    ///
    /// - Rows are one tile apart and a tile is taller than the tallest plate, so
    ///   two characters on different rows can never share a horizontal strip
    ///   however close they get in x.
    /// - A row carries at most one seat per side — one ring is two seats, one
    ///   each side — and the two sides deliver a seat pitch apart, which is
    ///   wider than the widest plate.
    /// - A reporter reaches its row by walking straight down **its own seat's
    ///   column**, and its column meets a lower ring's row outside that row's
    ///   corridor by at least a full seat pitch, because that corridor stops at
    ///   that ring's own station and that station is at least a pitch further
    ///   in.
    ///
    /// So no reporter's plate can meet any other plate at any phase of the beat,
    /// for any population and any timing. That is the guarantee the seat pitch
    /// alone could never give: half a pitch is 48 px against a 65 px plate, and
    /// widening the pitch to fix it does not even work — two characters walking
    /// the same line in opposite directions cross at zero separation whatever
    /// the pitch is. `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem`
    /// holds the arithmetic.
    ///
    /// Ring 0 is the main agent's own seat and it is the *anchor*, never a
    /// reporter, so it is folded onto row 1 rather than given a row nothing
    /// stands on.
    public func deliveryRowY(ring: Int) -> Double {
        aisleY - Double(tile * max(1, min(ring, maximumRing)))
    }

    /// The delivery row a character seated at `index` uses.
    public func deliveryRowY(forSeat index: Int) -> Double {
        deliveryRowY(ring: ring(ofSeat: index))
    }

    /// The point on a reporter's own delivery row directly in front of its own
    /// desk. It steps down to here from its station and comes back to here
    /// before it steps up again, so every vertical move it makes is inside its
    /// own column.
    public func deliveryLaneEntry(forSeat index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x, y: deliveryRowY(forSeat: index))
    }

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

    /// Bottom-centre of a station's one optional adjacent prop: a tile to the
    /// character's **left**, on the seat row. [ADR-002 §7]
    ///
    /// The left because the right is the desk, and the arithmetic that keeps it
    /// out of everyone else's way is worth writing down rather than eyeballing.
    /// A seat pitch is three tiles. Within one pitch the desk's 32 px box spans
    /// `x+12 … x+44` and this prop's spans `x−48 … x−16`, so a station occupies
    /// `x−48 … x+44` — 92 px of a 96 px pitch, with the next station's prop
    /// starting at `x+48`. Nothing overlaps and nothing is on a column any
    /// character walks down, because every column in this room is a seat's own
    /// and this is beside one, not on it.
    ///
    /// It is on `baselineY`, so it is furniture on the seat row rather than
    /// decoration in front of the characters — the rule that replaced M5's
    /// foreground row, and it is not weakened by anything a theme can declare.
    public func stationPropPosition(_ index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x - Double(tile), y: baselineY)
    }

    public var seatedFacing: Facing { .right }

    /// Where a reporting subagent walks to before it delivers: onto its own
    /// delivery row, short of the anchor's seat.
    ///
    /// The gap is a tile and a half, not a quarter-tile, and the number is
    /// load-bearing: at three quarters of a tile the reporter's 32px-wide body
    /// stood squarely on top of the anchor's nameplate. That was legible only
    /// because the plate is drawn in an overlay band; standing clear as well
    /// means the anchor's identity is not merely on top of a body but
    /// unobstructed by one, at the exact moment the room is dramatising a
    /// report. [criterion 5]
    public var deliveryPosition: ScenePoint {
        deliveryPosition(anchorSeat: 0, reporterSeat: 2)
    }

    /// How far short of the anchor a reporter stops, and the same distance is
    /// the closest either side ever comes to the room's centre line.
    public var deliveryGap: Double { Double(tile) * 1.5 }

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

    /// Where a reporter seated at `reporterSeat` stands to hand its report to
    /// the character at `anchorSeat`.
    ///
    /// **Depth, not width.** Subagents can stop within a second of each other,
    /// and the delivery point used to be a row of slots stepping *sideways* away
    /// from the anchor, claimed lowest-free. That had two faults, and they are
    /// both closed here by the same change:
    ///
    /// - *Lowest-free was not seat-ordered.* The farther of two same-side
    ///   reporters could claim the nearer slot and then walk home **through** the
    ///   nearer one's station. The slot is now a pure function of the reporter's
    ///   own seat, so there is nothing left to claim and no order to get wrong.
    /// - *Sideways slots share a row.* Two reporters a slot apart are 80 px
    ///   apart at rest but pass within a plate width in transit, because one
    ///   reporter's corridor runs through the other's slot. Stacking them in
    ///   **depth** — one row per ring — makes their corridors different lines
    ///   rather than different stretches of the same line, and lines a tile
    ///   apart cannot share a plate's horizontal strip at all.
    ///
    /// `anchorSeat` is whose seat the reporter delivers to. It is 0 — the main
    /// agent — unless `tool_response.agentId` linked the reporter to a different
    /// parent that is still in the room. **A reporter never crosses the room's
    /// centre line to reach a parent on the far side**: it stops a delivery gap
    /// short of centre instead. That keeps every corridor inside its own half,
    /// which is what lets the two seats of one ring share a row.
    public func deliveryPosition(anchorSeat: Int, reporterSeat: Int) -> ScenePoint {
        let side = deliverySide(anchorSeat: anchorSeat, reporterSeat: reporterSeat)
        let outward = side == .right ? 1.0 : -1.0
        let centre = seatPosition(0).x
        let atAnchor = seatPosition(anchorSeat).x + outward * deliveryGap
        // The reporter's own half of the room, and the nearest it may come to
        // the centre line without entering the other half's corridors.
        let ownHalf = seatPosition(reporterSeat).x >= centre ? 1.0 : -1.0
        let limit = centre + ownHalf * deliveryGap
        return ScenePoint(
            x: ownHalf > 0 ? max(atAnchor, limit) : min(atAnchor, limit),
            y: deliveryRowY(forSeat: reporterSeat))
    }

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

    /// **The report walk, as waypoints.** Down the reporter's own column to its
    /// own delivery row, and only then sideways. The route is built here rather
    /// than at the call site because its *shape* is the guarantee: a caller that
    /// cut the corner from the desk straight to the anchor would drag the plate
    /// diagonally through every row in between and the invariant would be gone
    /// with nothing failing.
    public func deliveryRoute(anchorSeat: Int, reporterSeat: Int) -> [ScenePoint] {
        [seatApproach(reporterSeat),
         deliveryLaneEntry(forSeat: reporterSeat),
         deliveryPosition(anchorSeat: anchorSeat, reporterSeat: reporterSeat)]
    }

    /// The same route reversed: back along the delivery row to the reporter's
    /// own column, then up it to the chair.
    ///
    /// `fromY` trims the legs a character is already above, so a leaver caught
    /// on the aisle does not walk *down* to a delivery row it never reached.
    public func homeRoute(forSeat index: Int, fromY: Double = -.greatestFiniteMagnitude)
    -> [ScenePoint] {
        var route: [ScenePoint] = []
        if fromY < aisleY { route.append(deliveryLaneEntry(forSeat: index)) }
        if fromY < baselineY { route.append(seatApproach(index)) }
        route.append(seatPosition(index))
        return route
    }

    /// **The walk-in, as waypoints: straight up the character's own column,
    /// from its own ring's delivery row into its chair.**
    ///
    /// It used to start one seat pitch *outward* in the aisle and walk sideways
    /// to its own station, and that was the last beat in the room the lattice
    /// did not close by construction. One pitch outward on the aisle is not a
    /// clear patch of floor — it is **exactly the next ring's own aisle
    /// station** — so an arrival's corridor ran from one occupied column to
    /// another along the one row every character steps through. It needed a
    /// seat vacated and refilled while the next seat out was mid-report, and
    /// then the newcomer stood on the reporter as it passed: measured at
    /// **−25.6 px**, a real overlap rather than a tight clearance.
    ///
    /// The repair is the rule the exits already follow, stated the other way up:
    ///
    /// > **Every vertical move in the room goes upstage.** Out of the aisle into
    /// > a chair, home up a reporter's own column, out through the back wall —
    /// > every one of them increases `y`.
    ///
    /// That is why the arrival comes up from the front rather than down from the
    /// back, which is the other way to put a walk-in inside its own column. Two
    /// characters in one column is not hypothetical — a seat is free the instant
    /// its occupant starts walking out, so a refill can begin while the leaver
    /// is still in the column — and a *downstage* arrival would meet that leaver
    /// head-on at zero separation, which no spacing fixes. Arriving upstage makes
    /// the pair a convoy instead: same direction, same speed, so a gap that
    /// starts at a tile stays at a tile. It is the argument
    /// `theWholeCastCanLeaveInOneFrame` already rests on.
    ///
    /// **Nothing new has to be proved about the rows it crosses.** The route is
    /// a character ascending its own column from its own ring's delivery row,
    /// which is the report walk's descent reversed — so block 4 of
    /// `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem` covers it
    /// unchanged: a column clears every *other* ring's corridor by at least a
    /// seat pitch, on exactly the rows at or behind that column's own row.
    ///
    /// **It is still visible from its first frame**, which is what the outward
    /// aisle start was for. `contentBand` runs from the outermost delivery row's
    /// plate to the tallest badge, so every ring's delivery row is inside the
    /// frame by construction — the walk-in now begins on the same floor the
    /// report beat plays out on rather than at the edge of what the camera
    /// happens to be framing.
    public func entranceRoute(forSeat index: Int) -> [ScenePoint] {
        [deliveryLaneEntry(forSeat: index), seatApproach(index), seatPosition(index)]
    }

    // `edgePosition(forSeat:)` lived here and is gone with the lateral walk-in
    // it served, as `nearestEdge(toX:)` went with the sideways exit. Nothing
    // enters or leaves along the aisle any more; every arrival and every
    // departure is one column, one direction.

    /// **Where a character goes when it leaves: straight back, up its own
    /// column, and out through the back of the room.**
    ///
    /// It used to walk out sideways along the aisle to the nearer edge, and that
    /// is the one route in the room that cannot be made safe. A lateral corridor
    /// that reaches the frame edge passes through *every* column outside it, so
    /// a leaver crossed the exact patch of floor every other character steps
    /// onto — and `noTwoNameplatesEverIntersect` caught it doing so in
    /// `three-subagents`, 44 seconds in, walking through a reporter that was on
    /// its way home up its own column.
    ///
    /// Going upstage costs nothing to guarantee, because there is nothing behind
    /// the desk row: no corridor, no station, no other character's route. A
    /// leaver's whole exit is inside its own column, and columns are a seat pitch
    /// apart. It also reads as what it is — you stand up and walk out the back
    /// rather than squeezing along the front of everyone's desk.
    ///
    /// It walks as far as the line where the floor meets the wall, **fading as
    /// it goes** — see `Character.departOffScreen`. The old exit walked off the
    /// side of the frame, which needed no fade because the frame edge did the
    /// hiding; there is no edge behind the desks, and a flat wall gives a
    /// character walking up it nothing to disappear behind. A fade is not a
    /// dramatisation of anything the data did not say: the agent is gone, and
    /// this is the room saying so. [I1]
    public func upstageExit(forSeat index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x, y: wallBaseY)
    }

    /// The same, for a character whose seat is not known — it leaves from
    /// wherever it is standing.
    public func upstageExit(fromX x: Double) -> ScenePoint {
        ScenePoint(x: x, y: wallBaseY)
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
        // The lowest plate belongs to a character on the outermost delivery
        // row — the only place in the room a character can stand that is nearer
        // the camera than the aisle.
        (deliveryRowY(ring: maximumRing) - plateDropBelowFeet, baselineY + badgeTopAboveFeet)
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
