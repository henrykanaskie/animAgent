import Foundation

/// A point in unscaled scene pixels, y-up. Deliberately not `CGPoint`: the
/// layout is pure arithmetic and unit-tests without any graphics framework.
public struct ScenePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Where everything stands, in unscaled scene pixels.
///
/// **A seat declares which way its occupant faces, and the occluder follows.**
/// [ADR-008]
///
/// This doc comment used to say the room was side-on "by necessity", because
/// both sit rows in Modern Interiors are side art in all four direction blocks
/// and there is no front- or back-facing *sitting* sprite at any size. The first
/// half of that is a measurement and is still true [M0]. The conclusion did not
/// follow: a seated figure can be drawn as a **standing** figure with something
/// in front of it, which is what the pack's own `Office_Design_2.gif` does at
/// every desk in its own room and what `scripts/compose-scene.py` reproduces.
/// The `idle` row is drawn in all four directions at six frames, and it has been
/// on disk since M0.
///
/// So the room mixes orientations, and what differs per facing is **what does
/// the occluding**:
///
/// | facing | pose drawn | occluder, and where it stands |
/// |---|---|---|
/// | toward the camera | `idle_down` | the **desk**, downstage of the feet |
/// | away from the camera | `idle_up` | the **chair back**, downstage of the feet; the desk goes upstage |
/// | side-on | `working` (the sit row) | nothing: it is a real seated pose |
///
/// See `seatFacing(_:)` for which seat gets which, and `SeatFacing` for what
/// each brings with it.
public struct RoomLayout: Sendable, Hashable {

    public let tile: Int
    /// **How many seats exist. Not a soft limit.**
    ///
    /// `seatColumn` and `ring` both wrap mod this number, so seat 7 resolves to
    /// seat 0's column *and* (because the two-row fold keys on ring parity)
    /// seat 0's row. That is a total overlap, not a near miss: two characters
    /// drawn on one spot, and a room that says seven when eight agents are
    /// running. It is the room asserting a false number [I1] and it is S5, the
    /// criterion this product is for, failing.
    ///
    /// **The number cannot be raised.** At `1x` (the only scale the app uses)
    /// the panel is 720 px and the seat pitch is 96, so `96 × 7 = 672` is the
    /// physical maximum across the visible width. More seats moves the failure
    /// from "two characters overlapping" to "characters off screen", which
    /// breaks S5 the same way and is harder to notice.
    ///
    /// **And the back row cannot be reused for a second lap.** Flipping
    /// `isBackRow` on odd laps gives 14 non-overlapping *positions*, and it
    /// falsifies `isBackRow`'s own clearance argument: seat 0's column would
    /// then contain back-row seat 7, so a front-row character walking upstage
    /// out of the room would walk through an occupied seat. Offsetting the
    /// second lap by an amount `s` does not rescue it: two plates clear each
    /// other only at `SceneBitmaps.maximumNameplateWidth` = **71 px** or more,
    /// so `s` would have to satisfy `s ≥ 71` **and** `96 − s ≥ 71` at once, and
    /// no `s` does: a 96 px pitch is not two plates wide. Half a pitch is 48.
    ///
    /// (Three numbers have been written in this file for that plate: 65 when the
    /// headline was one line, 77 when it was twelve glyphs, 71 since the limit
    /// was cut to eleven. It is measured (`SceneBitmaps.maximumNameplateWidth`)
    /// and every test that depends on it asks the measurement rather than the
    /// prose, which is why the prose could go stale without anything failing.)
    ///
    /// So the seats are the seats, and what overflows them is *said* rather than
    /// drawn: `SceneDirector` seats `seatCapacity` agents and counts the rest,
    /// and the room stands a plate at `overflowPlatePosition` that says how many
    /// it is not showing. Seven characters plus "+1" is still a count, and it
    /// asserts nothing false. See `isSeatable(_:)`.
    ///
    /// **Which `seatCapacity` agents is not "the first".** It was, and that was
    /// the defect: seats came free only on `agentDeparted`, so the seven filled
    /// with *dormant* subagents over a session's life and a working agent could
    /// sit in the overflow indefinitely, the room drawing six sleepers and
    /// hiding the one worker, which is S5 failing at the criterion this file's
    /// whole argument is in service of. A live agent with no seat now takes one
    /// from the longest-dormant character that has one. The number of seats is
    /// unchanged and every clearance argument below is untouched; what changed
    /// is only who is sitting in them. See `SceneDirector.settleSeats`.
    public let seatCapacity: Int
    /// Tiles between adjacent seats: one for the character, one for its desk,
    /// one of air.
    ///
    /// **The third tile is the nameplate's, not the air's**, and it is the only
    /// one that is negotiable: see `minimumSeatSpacingTiles(plateWidth:
    /// plateHeight:tile:)`, which is the pitch stated as a function of the plate
    /// rather than as the constant 3.
    public let seatSpacingTiles: Int
    public let columns: Int
    public let rows: Int
    /// Floor rows are below this; wall rows at and above it.
    public let wallRows: Int

    /// **The authored floor plan the room is drawn on**, or `RoomPlan.open` for
    /// the open floor five of the six themes still take. [ADR-007]
    ///
    /// It is a *drawing*, not a geometry: nothing in this file's route
    /// arithmetic reads it, and `RoomPlan.routeViolations(in:)` is the assertion
    /// that it never has to. What it does move is where the four **scenery
    /// bands** stand, because a plan gives the room two wall faces and a strip
    /// of floor behind the near one, and a band that stayed where it was would
    /// hang its pictures on nothing. See `sceneryAnchors(_:)`.
    ///
    /// It is `let` and arrives through `adopting(plan:)` rather than through
    /// `init`, so that every existing construction of a `RoomLayout` (and there
    /// are dozens, in tests and in the app) is the open floor unless something
    /// deliberately hands it a plan.
    public let plan: RoomPlan

    public init(
        tile: Int = 32, seatCapacity: Int = 7, seatSpacingTiles: Int = 3,
        plan: RoomPlan = .open
    ) {
        self.tile = max(1, tile)
        self.seatCapacity = max(1, seatCapacity)
        self.seatSpacingTiles = max(2, seatSpacingTiles)
        self.plan = plan
        // Enough columns for every seat plus its desk plus a margin each side.
        self.columns = self.seatCapacity * self.seatSpacingTiles + 4
        // **Seven floor rows, not four.** The room is drawn at `1x` whatever the
        // population, so the panel is a 720×400 window on it and the only
        // question composition can ask is what is inside that window. With four
        // floor rows the wall began at y=128 and everything above the tallest
        // badge (36% of the panel) was flat wall with nothing on it, because a
        // wall tile is an authored flat field (the pack's own wall tiles seam
        // every 32 px when repeated) and no pack we own draws anything that
        // hangs on one.
        //
        // Three more floor rows turn that dead band into *floor*, which is
        // something objects can stand on: the back seat row, a mid-depth accent
        // band, and the backdrops standing against the wall.
        //
        // **The wall's share of the frame is not this file's number and the
        // comment used to imply it was.** It said the wall keeps a deliberate
        // 84 px, which was a measurement of where the camera happened to be
        // aiming, not a property of nine rows: `wallBaseY` fixes where the wall
        // *starts*, and how much of it lands in frame is `RoomScene.cameraY`'s
        // to decide. It is ~112 px in `office` since the aim started accounting
        // for the backdrops, and it varies by theme, because the backdrops do.
        self.rows = 9
        self.wallRows = 2
    }

    /// The same layout, drawn on `plan`. Every route number is unchanged by
    /// construction (this initialiser copies them rather than recomputing them),
    /// which is what makes "a plan cannot move a seat" true in the type
    /// system rather than in a comment.
    public func adopting(plan: RoomPlan) -> RoomLayout {
        RoomLayout(
            tile: tile, seatCapacity: seatCapacity, seatSpacingTiles: seatSpacingTiles,
            plan: plan)
    }

    /// **The seat pitch as a function of the nameplate, in tiles.**
    ///
    /// The pitch has never been a composition number. It is 96 px because the
    /// widest plate the font can produce is 71 px, and two characters whose
    /// plates overlap are two characters the room cannot tell apart, which is
    /// an occlusion failure, not a crowding one. Bodies are 32 px of canvas over
    /// perhaps 18 px of ink and a desk's content box is 32 px; none of them needs
    /// anything like 96. So when the plate moves, this moves with it, and the
    /// formula is here so that the pitch is derived rather than remembered.
    ///
    /// **What has to clear what.** Under the one-column rule
    /// [`deliveryPosition(anchorSeat:reporterSeat:)`] two characters one pitch
    /// apart are always in *adjacent* columns, and adjacent columns are adjacent
    /// rings, so their **seats** are on different rows and 64 px apart in depth.
    /// The pairs that can genuinely share a horizontal strip are:
    ///
    /// | pair | needs a pitch of |
    /// |---|---|
    /// | two plates on one row: two reporters on the walkway | `W + m` |
    /// | a plate against a body across rows | `W/2 + 16 + m` |
    /// | a plate against a badge | `W/2 + 12 + m` |
    /// | a badge against a body | `28 + m` |
    /// | two bodies | `32 + m` |
    ///
    /// The first dominates every other for any `W ≥ 32`, and a plate that holds
    /// two lines of text is never narrower than that. So the whole table reduces
    /// to **one plate plus a margin**, rounded up to a whole tile, and floored at
    /// two tiles because a seat is a character and its desk whatever the plate
    /// does.
    ///
    /// `m` is the margin, and it is taken from the axis that already has one
    /// rather than chosen: rows are a tile apart and clear the tallest plate by
    /// `tile − plateHeight` = 21 px, which is the bound
    /// `noAdversarialPairingOfBeatsEverTouchesTwoPlates` pins. Using the same
    /// number across means the room clears by the same amount in both axes.
    ///
    /// It returns **3** for every plate the room has yet had (71 × 26 when this
    /// was derived, 63 × 11 as the plate stands), so stating it costs nothing
    /// today. The threshold worth knowing is where it returns **2**, a 64 px
    /// pitch and a room a third narrower: `plateWidth + tile − plateHeight ≤ 64`.
    /// At the plate's current 11 px height that is a width of **43 px or less**;
    /// at 21 px it was 53 and at 26 px it was 58.
    ///
    /// **The height cuts both ways and the sign is not the obvious one.** The
    /// margin is borrowed from the row axis, so a *shorter* plate leaves more
    /// room across the rows and therefore asks for more across the columns: the
    /// one-row plate made the two-tile pitch harder to reach, not easier. It
    /// also opened a band of plate widths, **44…48 px**, at which the pitch this
    /// returns is two plates wide: see
    /// `RoomCameraTests.noStaggerCanInterleaveTheTwoSeatRowsAtAnyPlateWidth`,
    /// which used to hold for every width from 33 up and now names the
    /// exception. Nothing in the room is in that band; a plate that lands there
    /// would need `isBackRow`'s refutation re-derived.
    ///
    /// **It is not wired to the default.** `RoomLayout()` still declares 3, and
    /// `theSeatPitchIsTheNarrowestTheseNameplatesAllow` is the tripwire that
    /// fails when the declared pitch and this formula disagree. Deriving the
    /// default would reflow the desks, the station props and the decoration
    /// columns the instant the plate moved, and those clearances are argued from
    /// content boxes in the manifest rather than from this file; they have to be
    /// re-derived by whoever narrows the plate, not silently inherited.
    public static func minimumSeatSpacingTiles(
        plateWidth: Int, plateHeight: Int, tile: Int
    ) -> Int {
        let tile = max(1, tile)
        let margin = max(0, tile - max(0, plateHeight))
        let needed = max(0, plateWidth) + margin
        return max(2, (needed + tile - 1) / tile)
    }

    /// Tiles are drawn past the room's nominal bounds so no zoom level ever
    /// shows the void behind the room. The *content* box the camera fits stays
    /// `width` × `height`; this is only what gets painted.
    ///
    /// **Overscan, not a margin that grows with the room.** It used to be
    /// `rows + 8`, which was six rows of overscan when the room was six rows
    /// tall and nine when it became nine, and the field then reached past the
    /// top of the 1600×900 viewport `scripts/preview-theme.py --verify` renders
    /// into, where a field touching an edge cannot be registered and the whole
    /// scene-agreement check fails with nothing wrong with the room. Six rows
    /// each way covers the 720×400 panel with a hundred pixels to spare at
    /// every scale on the ladder and stays inside that viewport.
    public var overscanRows: Int { 6 }
    public var drawnRows: ClosedRange<Int> {
        (-overscanRows)...(rows - 1 + overscanRows)
    }
    public var drawnColumns: ClosedRange<Int> { -8...(columns + 8) }

    public var width: Double { Double(columns * tile) }
    public var height: Double { Double(rows * tile) }
    public var floorRows: Int { rows - wallRows }

    /// Y of the **front** seat row: the top of the second floor row, so there is
    /// a clear tile of floor beneath for the nameplate.
    public var baselineY: Double { Double(tile * 2) }

    /// How far behind the front row the back row of seats sits.
    ///
    /// Two tiles is exactly one character's height, so the back row's feet land
    /// on the front row's head line: the rows read as receding rather than as
    /// two bands with a gap of nothing between them, and neither row is drawn
    /// over the other because they are a whole seat pitch apart in x.
    public var seatRowDepthTiles: Int { 2 }

    /// Y of the **back** seat row.
    public var backSeatRowY: Double { baselineY + Double(tile * seatRowDepthTiles) }

    /// The furthest-upstage row a character can sit on. The camera's ceiling is
    /// measured from this, not from `baselineY`.
    public var topSeatRowY: Double { backSeatRowY }

    /// The walkway one tile in front of the desk row, nearer the camera.
    ///
    /// It is the room's thoroughfare: every character reaches its chair from it,
    /// every character that leaves mid-beat comes back through it, and a
    /// reporter that could not get the delivery row hands its report over from
    /// it. **What nobody does is travel *along* it**: every character that
    /// touches this row is crossing it inside its own seat column. That is what
    /// lets any number of characters use it at once, and it is why the one
    /// lateral leg in the room is on `deliveryRowY` and not here. See
    /// `deliveryPosition(anchorSeat:reporterSeat:)`.
    public var aisleY: Double { baselineY - Double(tile) }

    /// **The one row in this room a character may travel *along*.** One tile
    /// downstage of the walkway, and the front of the room.
    ///
    /// A reporter drops onto it from its own column, walks to its anchor, hands
    /// over, walks back to its own column and climbs home. Nothing else in the
    /// room ever stands here, ever crosses here, or has a waypoint here:
    /// `entranceRoute` starts on the walkway, `homeRoute` and `upstageExit` only
    /// ever ascend, both seat rows are upstage, and every prop the room places is
    /// upstage of the seats [`RoomScene.decorationPlacements`]. So the lateral
    /// corridor this row carries meets **no other route at all**, which is the
    /// property the walkway cannot give it.
    ///
    /// It costs 32 px of `contentBand` and that is the whole price of the walk;
    /// see `deliveryPosition(anchorSeat:reporterSeat:)` for the ledger.
    public var deliveryRowY: Double { aisleY - Double(tile) }

    /// Every row a character can have its feet on, downstage first. Four:
    /// the delivery row, the walkway, and the two seat rows.
    ///
    /// Two characters on different rows cannot share a plate's horizontal strip,
    /// because the rows are a tile apart and a plate is
    /// `SceneBitmaps.maximumNameplateHeight` tall, which is the second block of
    /// `theRoomHasNoLateralMovementLeftToSeparate`, and the reason it is stated
    /// as a list here is so that a row added anywhere is a row that test sees.
    public var standingRows: [Double] { [deliveryRowY, aisleY] + seatRows }

    // MARK: The lattice [the aisle invariant]

    /// How far a seat sits from the centre, counted in seat pitches. Seat 0 is
    /// 0; seats 1 and 2 are 1; 3 and 4 are 2; and so on, because seats fill
    /// outward in pairs.
    ///
    /// Two seats of the same ring are on **opposite sides** of the room, and two
    /// seats of different rings are at least one pitch apart in x. Its parity is
    /// what picks a seat's row: see `isBackRow(seat:)`.
    ///
    /// It used to pick one more thing: a reporter's own delivery row, one row of
    /// floor per ring reserved in front of the walkway. **There is one delivery
    /// row now and every reporter uses it**, so the ring no longer names a row,
    /// what keeps two reporters off each other is `DeliveryFloor`, which
    /// separates them in x rather than in depth. See
    /// `deliveryPosition(anchorSeat:reporterSeat:)`.
    public func ring(ofSeat index: Int) -> Int {
        let wrapped = ((index % seatCapacity) + seatCapacity) % seatCapacity
        return (wrapped + 1) / 2
    }

    /// Y where the wall meets the floor.
    public var wallBaseY: Double { Double(floorRows * tile) }

    // MARK: The wall as a plan draws it [ADR-007]

    /// **The strip of the near wall a picture may hang on**, in scene y.
    ///
    /// The two numbers subtracted here are the pack's, measured in
    /// `docs/06-SET-BUILDING.md` §2 off `Office_Design_2.gif` and reproduced by
    /// `scripts/compose-scene.py`: a body tile is 30 px of face over a **2 px
    /// baseboard**, and a cap tile is 20 px more face under a **12 px
    /// floor-plan line**. So of the 64 px band, 50 px is face and the rest is
    /// the two edges that say where the wall starts and stops. Hanging a picture
    /// on either of them would be hanging it on the skirting or on the room's
    /// own outline.
    ///
    /// Meaningless without a plan: the open floor's wall is a single tile
    /// repeated to the top of the overscan and has no face, no baseboard and no
    /// line, which is why the two callers both ask `plan.isEmpty` first.
    public var wallFace: (bottom: Double, top: Double) {
        (wallBaseY + Double(RoomPlan.baseboardPx),
         wallBaseY + Double(wallRows * tile) - Double(RoomPlan.planLinePx))
    }

    /// Where a picture's bottom edge sits on that face: a quarter tile up, which
    /// centres the office's 34 px boards in the 50 px of face and leaves the
    /// baseboard visible under them.
    public var hungPropY: Double { wallBaseY + Double(tile) / 4 }

    /// The floor line of the space one wall band upstage of the seats: the
    /// **far** room. Where the `wallLine` scenery stands under a plan.
    public var farFloorY: Double { wallBaseY + Double(wallRows * tile) }

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

    /// **Which of the two rows a seat is on: its ring's parity.**
    ///
    /// This is not a new rule bolted onto the lattice: it is the lattice read
    /// one column further. Seats fill outward in pairs, so consecutive rings are
    /// consecutive columns on alternating sides, and *ring parity along x is
    /// perfect alternation*: columns in x order are seats 6, 4, 2, 0, 1, 3, 5,
    /// rings 3, 2, 1, 0, 1, 2, 3. Sending odd rings upstage therefore puts the
    /// rows in a checkerboard, every occupied column differing in depth from
    /// both its neighbours.
    ///
    /// **Nothing the lattice proves has to be re-proved, and that is the whole
    /// reason the row is keyed on the ring.** Every clearance argument in this
    /// file rests on one number: *any two seats are at least a seat pitch apart
    /// in x*, and folding the row does not touch x at all. `seatColumn` is
    /// unchanged, so the minimum column gap is still one pitch, still 96 px
    /// against a 71 px plate.
    ///
    /// What the fold *adds* is two new crossings, and both are closed by that
    /// same number rather than by anything new:
    ///
    /// - A front-row character walking upstage out of the room crosses the back
    ///   row's line. It does so **inside its own column**, and its own column is
    ///   a pitch from every back-row seat, because it is a pitch from every seat.
    /// - A back-row character walking down to the aisle, or up from it, crosses
    ///   the front row's line. Same column, same pitch, same conclusion.
    ///
    /// A staggered *pitch* would have needed a genuinely new argument and does
    /// not survive one: an offset `s` has to clear a 71 px plate on **both**
    /// sides, which needs `s ≥ 71` and `96 − s ≥ 71` together, and a 96 px pitch
    /// is not two plates wide. Depth is free where width is not, because two
    /// rows a character's height apart cannot share a horizontal strip at any x.
    ///
    /// ## Why the fold cannot also buy the room any width
    ///
    /// The obvious next move is the one that was asked for: if the seats were a
    /// *cluster* over the room's depth rather than a line, the occupied span
    /// would shrink and the camera could climb back off `1x`. It cannot, and the
    /// refutation is the one directly above, applied one step further out.
    ///
    /// A cluster narrower than seven columns means **two seats in one column**,
    /// because seven seats over fewer than seven columns is what "narrower"
    /// means. And every route into or out of a seat runs up or down that seat's
    /// own column: that is not an incidental choice, it is the property every
    /// argument in this file is built on, and it is what
    /// `entranceRoute(forSeat:)` and `upstageExit(forSeat:)` exist to state. So
    /// a stacked column puts one character's corridor through the other's chair
    /// at **zero** separation, in both directions:
    ///
    /// - the front seat's occupant walking upstage out of the room passes
    ///   through the back seat above it;
    /// - the back seat's occupant walking down to the walkway to report, or up
    ///   from it, passes through the front seat below it.
    ///
    /// Neither is a tight clearance to be widened. Sliding one row sideways is
    /// the staggered pitch again: an offset `s` must clear a plate on **both**
    /// sides, so `s ≥ W` and `pitch − s ≥ W`, which needs `pitch ≥ 2W`. At the
    /// shipped 96 px pitch and 71 px plate there is no such `s`. **Both numbers
    /// can move**: see `minimumSeatSpacingTiles(plateWidth:tile:)`, which is
    /// what ties them together, but they move in lockstep, because the pitch is
    /// derived from the plate: a pitch is one plate wide plus a margin, never
    /// two. So there is no plate width at which a stagger opens up.
    ///
    /// **What that leaves is one seat per column**, so the room's occupied width
    /// is `(seats − 1) × 96` plus the padding `occupiedSpan` adds, and the only
    /// way to narrow it is to seat fewer agents. `RoomCamera` carries what a
    /// `2x` frame could actually hold, which is three of them, and the shipped
    /// panel cannot hold three either, on height. The two seat rows bought
    /// depth: a room that reads as a place rather than a queue, and a badge line
    /// that does not sit on a neighbour's plate. They did not buy width and no
    /// arrangement of them can.
    public func isBackRow(seat index: Int) -> Bool {
        !ring(ofSeat: index).isMultiple(of: 2)
    }

    /// Whether the room has a seat for `index`: every position function below
    /// wraps, so anything else lands on top of an existing seat.
    ///
    /// This is the whole of the seat contract, stated once so a caller can ask
    /// rather than remember. `SceneDirector` is the only thing that hands seat
    /// numbers out and it never draws a character on an index this rejects.
    public func isSeatable(_ index: Int) -> Bool {
        index >= 0 && index < seatCapacity
    }

    /// Y of the row seat `index` sits on.
    public func seatRowY(_ index: Int) -> Double {
        isBackRow(seat: index) ? backSeatRowY : baselineY
    }

    /// Every row a seated character can be on, nearest the camera first.
    public var seatRows: [Double] { [baselineY, backSeatRowY] }

    /// Where the character's feet go when seated at `index`.
    public func seatPosition(_ index: Int) -> ScenePoint {
        ScenePoint(x: Double(seatColumn(index) * tile + tile / 2), y: seatRowY(index))
    }

    // MARK: Which way a seat faces, and what stands in front of it [ADR-008]

    /// **Which way the occupant of a seat faces the camera.**
    ///
    /// Not a costume and not a theme's choice: it decides which pose row the
    /// body draws and therefore what has to stand in front of the body for it to
    /// read as seated at all. The pack ships no front- or back-facing *sitting*
    /// sprite [M0], so the two turned facings draw the **standing** `idle` row
    /// and let furniture hide the legs: the technique the pack's own
    /// `Office_Design_2.gif` uses at every desk in its own room.
    public enum SeatFacing: String, Sendable, Hashable, CaseIterable {
        /// `idle_down`, with the **desk** downstage of the feet. You see the
        /// face; you lose the bottom of the costume to the desk.
        case towardCamera = "toward_camera"
        /// `idle_up`, with the **chair back** downstage of the feet and the desk
        /// upstage. You see the back of the head and the shoulders.
        case awayFromCamera = "away_from_camera"
        /// The sit row, which is a real seated pose and needs no occluder. **The front row takes it as of
        /// M9** (see `seatFacing(_:)`, ADR-014); it was unused before that, and
        /// `RoomSceneTests.everySeatedCharacterFacesADirectionThePackDrew` is that
        /// as a measurement rather than as a remark. It is kept because it is the only facing with true
        /// seated art, because the sit row, `Facing.seated`, the desk's
        /// near-edge cue and the held-object hand anchor are all *about* it, and
        /// because a room that ever seats a row side-on again needs no new code
        /// to do it.
        case sideOn = "side_on"

        /// Which way the body itself points.
        public var bodyFacing: Facing {
            switch self {
            case .towardCamera: return .down
            case .awayFromCamera: return .up
            case .sideOn: return .right
            }
        }

        /// **Which `props.roles` key this seat's chair comes from**, or `nil` for
        /// a seat that has no chair at all.
        ///
        /// A camera-facing occupant needs none: the body covers it entirely, and
        /// drawing one would be a chair nobody can see standing where a person
        /// is. That is what the pack's own room does, and it is the only reason
        /// the toward-camera seat costs one prop rather than two.
        ///
        /// ## An away-facing seat has none either, and it is a measurement: M8
        ///
        /// It was `chair_back` from ADR-008 until here. The maintainer, looking at
        /// the shipped room: *"the chairs that are facing forward, and they look
        /// weird. So I don't really think those are doing well, so they might be
        /// removed."* The sprite is not the problem: single 101 is genuinely the
        /// pack's back view, and a **vacant** away-facing pod renders correctly
        /// with it. What does not fit is the chair between the two things an
        /// *occupied* seat already draws in the same 32 px column:
        ///
        /// | bound | the furthest it may go | why |
        /// |---|---:|---|
        /// | the chair's top may not reach the head | feet **+22** | the head band of a turned body is canvas rows 0…40, `canvas.height − 1 − costumes.ink_top_px`, so row 41 (feet +22) is the highest row furniture may occupy. `StationAndCostumeTests.nothingTheRoomDrawsInFrontOfASeatedBodyCoversItsHead` is that as a shipped invariant, and a top at feet +33 reports up to 256 px of head covered per variant in all seven rooms |
        /// | the chair's base may not hang below the nameplate | feet **−13** | `RoomScene.seatedPlateDrop`, `maximumNameplateHeight + 2` |
        ///
        /// A chair standing on the second and reaching no higher than the first
        /// may be **36 px** tall. `chair_back` is **46**: it is 10 px too tall, so
        /// no standoff satisfies both. The shipped 30 satisfies the first and
        /// misses the second by 17 px, which is the picture that was reported: a
        /// grey column with the plate drawn across its back and a foot below it.
        /// Every candidate was rendered at the panel's own 720×400 before this was
        /// written: 30 (shipped), 24, 13, and none.
        ///
        /// **Neither side of the window can move.** Hanging the plate below the
        /// chair instead costs 17 px of `contentBand`, which stands at 192 against
        /// the 200 a `2x` view of that panel gives, so every room in the corpus
        /// would fall to `1x` to tidy one seat. Raising the chair to feet −13
        /// takes its top to feet +33 and breaks the head invariant, and it also
        /// cuts the occupant's visible ink from **68% to 28–33%** (measured on
        /// `idle_up`, variants 07 and 19, 1248 and 1256 ink px).
        ///
        /// **What it costs, named rather than discovered.** ADR-008's table gives
        /// the chair back as what hides an `idle_up` figure's legs, and nothing
        /// hides them now: an away-facing occupant is a whole standing back view
        /// at its own desk, and only its position says it is seated. The four
        /// vacant back seats of a normal room lose a prop each, and with
        /// `SeatFacing.towardCamera` already at `nil` and no seat in the shipped
        /// lattice side-on, **the room now draws no chair anywhere**; both `chair`
        /// roles stay bound and stay unread.
        ///
        /// **What would restore it**, so that this is a bound and not a verdict on
        /// chairs: a back view no taller than 36 px. The office suite has none,
        /// `chair_office_back` is the 46, but `scripts/compose-scene.py`'s own
        /// `CHAIR_SUITES` records two that would fit, `chair_school` at 30 and
        /// `chair_ornate` at 32, both up-views of families the manifest does not
        /// bind here and neither of them an office chair. Binding one is an
        /// `assets/` change and an ADR-008 amendment, and both are outside the
        /// change that found this.
        public var seatRole: String? {
            switch self {
            case .towardCamera, .awayFromCamera: return nil
            case .sideOn: return "chair"
            }
        }

        /// Whether an object may stand on this seat's desk. [ADR-008 §5]
        ///
        /// **False toward the camera**, for two independent reasons, either of
        /// which is sufficient: the desk is between the occupant and the viewer,
        /// so an object on it faces *upstage* and every screen in 12,279
        /// catalogue props is drawn face-on: a lit monitor there is somebody
        /// staring at the back of their own screen; and the desk is 32 px wide
        /// with the body occupying all of it, so there is no column on that desk
        /// an object can stand in without crossing the face the orientation
        /// exists to show.
        public var showsDeskTopObject: Bool { self != .towardCamera }

        /// **Whether this seat's posture channel says anything.** [ADR-008 §6]
        ///
        /// ADR-005 keys posture to the turn: the sit row while a turn is in
        /// progress, the standing row between them. A turned seat draws the
        /// standing row for *both*, because that is the only row it has, so the
        /// two states are the same picture pixel for pixel and the channel is
        /// mute. Something else has to carry the fact, and `Character`'s dim is
        /// what does: see `Character.setDimsOutOfTurn(_:)`.
        public var showsPosture: Bool { self == .sideOn }
    }

    /// **Which way seat `index` faces: the back row away from the camera, the
    /// front row toward it.**
    ///
    /// It is keyed on the row, and the row decides it because the *floor*
    /// decides it. An away-facing seat needs its chair 30 px downstage of the
    /// occupant's feet (`awayChairStandoff`), and the front row has 32 px of
    /// floor between it and `aisleY`: the one row every character in the room
    /// walks across. A chair there would stand 2 px off the walkway. The back
    /// row has 64 px and the chair lands in the middle of it.
    /// [docs/M8-MEASUREMENTS-phase1c.md §3]
    ///
    /// **The result is the reference composition, for free.** Seats fill outward
    /// in pairs and ring parity puts them in a checkerboard, so in x order the
    /// rows run back, front, back, front, and the facings therefore alternate
    /// across the whole room, which is exactly what `Office_Design_2` and
    /// `scripts/compose-scene.py`'s own office do, and it is not arranged here,
    /// it falls out of `isBackRow(seat:)`.
    /// **M9 amends this: the front row is `.sideOn`, not `.towardCamera`.**
    /// [ADR-014]
    ///
    /// The maintainer, looking at the shipped room: *"only sitting front. You
    /// could probably be sitting sideways."* They are right twice over, and the
    /// second one is not about seating at all:
    ///
    /// 1. **Nothing in the shipped room was drawn seated.** `working` is
    ///    side-only art, so both turned facings resolve to the standing `idle`
    ///    row [`BodyState.artState(facing:)`]. Seven seats, seven standing
    ///    sprites, and `showsPosture` false at every one of them.
    /// 2. **The camera-facing desk was the reason bodies walked through
    ///    furniture.** It stands `deskDepth` *downstage* of its occupant
    ///    precisely to cut a standing sprite at the waist, and
    ///    `entranceRoute(forSeat:)` is a 32 px leg of which 25 are inside that
    ///    desk's own ink. `RouteFurnitureTests` exempts the piece by name
    ///    because with a standing sprite the occluder is load-bearing.
    ///
    /// A side-on seat needs **no occluder**: it draws the real sit row, its desk
    /// stands *beside* it at `sideOnDeskOffsetX` on the seat's own row, and its
    /// chair stands on the seat's own point behind the body. So one change
    /// answers both, which is why ADR-014 supersedes ADR-008 §12 on this point.
    ///
    /// **Why the front row and not all seven.** ADR-008 §12 refused a mixed room
    /// for want of a principled rule picking which seats turn. There is one now,
    /// and it is the same floor argument this comment already made: **the
    /// occluder is a property of the camera-facing seat alone.** Replace exactly
    /// the seats that had one. The back row keeps `.awayFromCamera`, which keeps
    /// ADR-009's monitor rigs (`monitorPosition` gates on it) and ADR-012's pod,
    /// so the workstation survives intact where it was actually built.
    ///
    /// **And the front row is the row that can afford it.** The comment below
    /// records that an away-facing chair needs 30 px downstage and the front row
    /// has only 32 px before `aisleY`. A side-on chair needs **zero**: it stands
    /// on the seat's own point [`chairPosition`]. The facing that fits the front
    /// row's floor is the one that asks nothing of it.
    ///
    /// The alternation survives: in x order the rows still run back, front,
    /// back, front, so the room now reads up, side, up, side rather than up,
    /// down, up, down. Three of seven seats are side-on at a full room; at the
    /// common four-agent peak it is two of four.
    ///
    /// ---
    ///
    /// **Which way seat `index` faces: the back row away from the camera, the
    /// front row toward it.**
    ///
    /// It is keyed on the row, and the row decides it because the *floor*
    /// decides it. An away-facing seat needs its chair 30 px downstage of the
    /// occupant's feet (`awayChairStandoff`), and the front row has 32 px of
    /// floor between it and `aisleY`: the one row every character in the room
    /// walks across. A chair there would stand 2 px off the walkway. The back
    /// row has 64 px and the chair lands in the middle of it.
    /// [docs/M8-MEASUREMENTS-phase1c.md §3]
    public func seatFacing(_ index: Int) -> SeatFacing {
        isBackRow(seat: index) ? .awayFromCamera : .sideOn
    }

    /// Which way the *body* faces at a seat.
    ///
    /// It was `var seatedFacing: Facing { .right }`: one constant for the whole
    /// room, and the `.right` in it is the reason `Facing.seated` folds `up` and
    /// `down` onto the side views. Both are still correct **for a side-on seat**
    /// and neither is the room's answer any more.
    public func seatedFacing(_ index: Int) -> Facing { seatFacing(index).bodyFacing }

    /// **The measured art a seat's furniture is placed against.**
    ///
    /// `RoomLayout` opens no PNG and reads no manifest: that is what makes it
    /// unit-testable as arithmetic, so the three numbers a turned seat needs
    /// arrive as a parameter, the same shape
    /// `deskSurfacePosition(seat:surfaceHeightAboveFloor:)` and
    /// `contentBand(badgeTopAboveFeet:plateDropBelowFeet:)` already take theirs.
    ///
    /// It is a required argument on every accessor that needs it, deliberately.
    /// A default would place a toward-camera desk at a depth of
    /// `0 − 1 − deskCutAboveFeet`: *upstage* of the character it is supposed to
    /// be in front of, and the room would draw a person standing in front of
    /// their own desk with nothing failing.
    public struct SeatMetrics: Sendable, Hashable {
        /// The desk's own ink height, from its `content_box`.
        public var deskInkHeight: Double
        /// The chair's ink height, from `chair_back`'s `content_box`.
        public var chairInkHeight: Double
        /// `characters.costumes.ink_top_px`: how far above the feet a costume's
        /// ink reaches.
        public var costumeTopAboveFeet: Double
        /// The desk's own ink **width**. `0` for a theme with no desk role at
        /// all, which is the placeholder path.
        ///
        /// It arrives because the pod arithmetic below is entirely about how much
        /// desktop there is: how many kit slots a desk has, and whether an
        /// away-facing occupant can be centred on it. [ADR-009]
        public var deskInkWidth: Double
        /// The screen rig's ink, from the theme's `monitor` role, or `(0, 0)` for
        /// a theme that binds none.
        ///
        /// **A theme with no rig is not a pod**, and every accessor below asks
        /// `isDeskPod` rather than testing this directly, so "this theme has no
        /// rig" and "this desk is too narrow to hold one" are answered in one
        /// place. Five of the six shipped themes are in that case and draw
        /// exactly the picture they drew before this existed.
        public var monitorInkWidth: Double
        public var monitorInkHeight: Double

        /// **Whether this seat's desk is a pod**: a slab wide enough to carry a
        /// screen rig either side of its occupant, and a theme that binds one.
        ///
        /// Two conditions and both are load-bearing. A theme with no `monitor`
        /// role has nothing to stand, and a desk narrower than two rigs has no
        /// second slot, which is the arrangement ADR-008 §7 described as an art
        /// fact rather than a taste one when it kept the away-facing desk beside
        /// its occupant: *"The pack can centre its figure because its desk is
        /// 64 px wide with two monitors at ±16 and the person between them; ours
        /// is 32."* This is that sentence as arithmetic, so the office desk
        /// becoming 64 px wide moves the room and nothing else does.
        public var isDeskPod: Bool {
            monitorInkWidth > 0 && monitorInkHeight > 0
                && deskInkWidth >= monitorInkWidth * 2
        }

        public init(
            deskInkHeight: Double, chairInkHeight: Double, costumeTopAboveFeet: Double,
            deskInkWidth: Double = 0,
            monitorInkWidth: Double = 0, monitorInkHeight: Double = 0
        ) {
            self.deskInkHeight = deskInkHeight
            self.chairInkHeight = chairInkHeight
            self.costumeTopAboveFeet = costumeTopAboveFeet
            self.deskInkWidth = deskInkWidth
            self.monitorInkWidth = monitorInkWidth
            self.monitorInkHeight = monitorInkHeight
        }
    }

    // MARK: The desk pod [ADR-009]

    /// **How far above the desk's own back edge a screen rig's top must reach.**
    ///
    /// 20 px, and it is `scripts/compose-scene.py`'s number with that file's own
    /// citation behind it: *"its screen rises 20 px above the back edge the way
    /// the pack's own office GIF draws a monitor"*. It is the one chosen constant
    /// in the pod and everything else here is measured off the art, which is why
    /// it is named rather than folded into `deskTopLift`.
    public static let monitorScreenClearance: Double = 20

    /// **Where a prop standing on this desk puts its feet**, above the desk's own
    /// floor point.
    ///
    /// For every desk in the room this has always been the manifest's
    /// `surface_y`: the topmost row of an 80%-of-box-width ink run, which for a
    /// desk drawn in near profile *is* the desktop. A pod's slab is not drawn in
    /// near profile: 25 of its 38 rows are top surface seen at an angle, so
    /// `surface_y` finds its **back** edge and a prop placed there stands behind
    /// the desk rather than on it.
    ///
    /// So a pod derives the lift instead, from the two heights it already
    /// measured: `deskInkHeight + monitorScreenClearance − monitorInkHeight`,
    /// which is 38 + 20 − 42 = **16** for the shipped office pod and is
    /// `compose-scene.py`'s `on_desk(16)` re-derived rather than copied. The
    /// keyboard lands near the front of the desktop and the screen clears the
    /// back edge, which is the whole of what makes a rig read as standing *on* a
    /// desk.
    ///
    /// Clamped into `0...deskInkHeight`: a rig taller than the desk plus its
    /// clearance stands on the floor point rather than below it, and one shorter
    /// than the clearance stands on the back edge rather than in the air.
    public func deskTopLift(surfaceHeightAboveFloor: Double, metrics: SeatMetrics) -> Double {
        guard metrics.isDeskPod else { return surfaceHeightAboveFloor }
        return min(max(0, metrics.deskInkHeight + Self.monitorScreenClearance
                          - metrics.monitorInkHeight),
                   metrics.deskInkHeight)
    }

    /// **How far either side of the desk's centre a pod's two kit slots sit.**
    ///
    /// Half the desktop that a rig does not cover: `(64 − 32) / 2 = 16`, so the
    /// two 32 px slots tile the 64 px slab exactly and neither hangs off an edge.
    /// It is `compose-scene.py`'s `x ± 16` measured off the art rather than
    /// written down, so a re-cut desk or a re-cut rig moves the slots with it.
    ///
    /// `0` for a desk that is not a pod, which is the same as saying it has one
    /// slot and the slot is the middle.
    public func podSlotOffsetX(metrics: SeatMetrics) -> Double {
        guard metrics.isDeskPod else { return 0 }
        return (metrics.deskInkWidth - metrics.monitorInkWidth) / 2
    }

    /// **Which of a pod's two kit slots a screen rig stands in.**
    ///
    /// Both of them, and that is the correction. See
    /// `monitorPosition(_:slot:metrics:)`.
    public enum PodRigSlot: Int, CaseIterable, Sendable, Hashable {
        case left, right

        /// The sign `podSlotOffsetX` is applied with.
        public var offsetSign: Double { self == .left ? -1 : 1 }
    }

    /// **Bottom-centre of a screen rig standing on a seat's desk**, or `nil`
    /// for a seat that may not have one.
    ///
    /// **Away-facing seats only, and that is a fact about the art rather than a
    /// preference.** Every screen in either pack is drawn face-on with its
    /// keyboard below it, and there is no rear view of a monitor anywhere in the
    /// 12,279-prop catalogue, so a rig at a camera-facing seat is drawn being
    /// looked at from below by the person sitting between it and the viewer.
    /// `compose-scene.py`'s `desk_pod` refuses it for the same reason and says
    /// the first three renders of that scene showed exactly that, six times over.
    /// A camera-facing pod carries `deskKitPosition(_:metrics:)` instead.
    ///
    /// ## Two rigs, because the `monitor` role is not a monitor
    ///
    /// This took the left slot alone until M8, on the argument that the right one
    /// was ADR-006's and *"drawing a rig in both would be the second of those
    /// competing with a prop that means nothing"*. That argument is about what
    /// the two slots **mean** and it is still right. It was wrong about what the
    /// left slot alone **draws**, and the maintainer saw the consequence before
    /// anyone re-read the sentence: *"you have, like, the computer that should be
    /// on the corner of a desk, but it's actually not because it's, like, flipped
    /// the wrong way."*
    ///
    /// The `monitor` role is `workstation_composite`: a 32×42 rig carrying **its
    /// own desk surface, front edge, keyboard and mouse**, drawn in the pack's
    /// oblique projection. One of them on a 64 px slab covers the left half in
    /// desktop-seen-from-a-workstation and leaves the right half in
    /// slab-seen-from-the-room, with the rig's own front edge stopping dead in the
    /// middle of the desk. Two surfaces, two apparent angles, abutting: the pod
    /// reads as two desks rather than as one.
    ///
    /// `compose-scene.py`'s `desk_pod` never had the defect and its own comment
    /// says why: *"Ink 32 wide against 64, so x-16 and x+16 tile it exactly"*,
    /// so this is that file's arrangement rather than a new one.
    ///
    /// **What ADR-006 keeps, and what was tried first.** The right slot is still
    /// where the work-kind object stands [`RoomScene.showDeskObject(_:for:)`], and
    /// the object now stands **in front of** that slot's rig rather than in place
    /// of it: one depth step nearer the camera, on the rig's own desktop, the way
    /// anything else on a desk sits in front of the screen behind it.
    ///
    /// The first attempt had the object *replace* the rig, hiding it for as long
    /// as one stood there. It is the smaller change and it is wrong, and the thing
    /// that says so is a shipped test rather than an opinion:
    /// `DeskPodTests.theSameSeatDrawsTheSameStockWhoeverIsSittingInIt` fails,
    /// because a *theme prop* would then be absent because an agent had run a
    /// tool. ADR-006 licenses an **object appearing** in that slot; it does not
    /// license the room's own furniture disappearing, which is the failure
    /// ADR-002 §6 rule 1 and I1 both name. Standing the object in front costs
    /// nothing that mattered: the rig's screen is 24 px of its 42 and the tallest
    /// object is 22, so what an object covers is the keyboard, the stalk and at
    /// most the screen's bottom four rows, and it buys the whole of the defect
    /// above, at an occupied seat as well as an empty one. [I2] Nothing animates
    /// either way.
    public func monitorPosition(_ index: Int, slot: PodRigSlot, metrics: SeatMetrics)
    -> ScenePoint? {
        guard metrics.isDeskPod, seatFacing(index) == .awayFromCamera else { return nil }
        let desk = deskPosition(index, metrics: metrics)
        return ScenePoint(
            x: desk.x + slot.offsetSign * podSlotOffsetX(metrics: metrics),
            y: desk.y + deskTopLift(surfaceHeightAboveFloor: metrics.deskInkHeight,
                                    metrics: metrics))
    }

    /// **The four places an object may stand on a camera-facing pod's desktop**,
    /// in draw order: both back-row objects, then both front-row ones, so a
    /// front-row object is always added to the tree after the thing it stands in
    /// front of.
    ///
    /// `scripts/compose-scene.py`'s `desk_pod` puts four objects on a
    /// camera-facing desktop: *"folder, clipboard on the left, paper stack and
    /// mug on the right"*: where this file used to put one, and these are those
    /// four places. Two columns, because a pod has exactly two kit slots
    /// (`podSlotOffsetX`); two rows, because the desktop is 38 px deep and one
    /// row of objects across a slab that wide reads as a shelf.
    ///
    /// **The declaration order is the office theme's own stock order**, so a seat
    /// that takes `variants[slot.rawValue]` gets the reference's arrangement: the
    /// paper stack (`variants[0]`, the only object this room drew before) stays
    /// in the right-hand slot it has always stood in, and the folder, clipboard
    /// and mug land where `desk_pod` draws them. `RoomScene` rotates that by the
    /// seat, which is why the order has to be a fact rather than a preference.
    public enum PodKitSlot: Int, CaseIterable, Sendable, Hashable {
        case backRight, backLeft, frontLeft, frontRight

        /// Which of the pod's two kit slots this stands in.
        var isLeft: Bool { self == .backLeft || self == .frontLeft }
        /// **Whether the object's top lands on the desk's back edge**: the back
        /// row, or on the desktop's mid-line, which is the front row.
        var isBackRow: Bool { self == .backLeft || self == .backRight }
        /// The back row first, so a front-row object is added to the tree after
        /// the object it overlaps. The depth bias is what actually sorts them;
        /// this makes the order deterministic rather than relying on it.
        public static var drawOrder: [PodKitSlot] {
            allCases.filter(\.isBackRow) + allCases.filter { !$0.isBackRow }
        }
        /// How many objects stand between this one and the desk. The depth rank
        /// `RoomScene` turns into a bias, so a front-row object draws over the
        /// back-row one it overlaps rather than tying with it on the desk's own
        /// row.
        var depthRank: Int { isBackRow ? 0 : 1 }
    }

    /// **How far above the desk's floor point an object of ink height `h`
    /// stands** in one of the four desktop slots.
    ///
    /// This is where "it cannot cover a face" is enforced, and it is enforced by
    /// construction rather than by checking afterwards:
    ///
    /// | row | lift | the object's top |
    /// |---|---|---|
    /// | back | `H − h` | exactly the desk's back edge |
    /// | front | `(H − h) / 2` | the desktop's mid-line, `(H + h) / 2` |
    ///
    /// so for any object no taller than the desk, every pixel of it is inside
    /// the band the desk already covers and it stands in front of pixels the
    /// viewer could not see anyway. Whatever its width.
    ///
    /// **The lift is derived per object rather than shared, and that is the
    /// change.** One lift for every object is what the single-kit version had,
    /// and it survived only because the one object it placed was 22 px tall
    /// against a 38 px desk and a 16 px lift. The office folder is 24 px: at that
    /// same 16 it reaches 40 and crosses the desk's back edge into the torso,
    /// which is why `compose-scene.py`'s own `on_desk(16)` for that object cannot
    /// be transcribed. Deriving it costs the reference 2 px on one object of four
    /// and makes the sentence true for every object anyone adds later.
    ///
    /// The shipped 24×22 paper stack does not move: `38 − 22 = 16` is the same
    /// number `deskTopLift` returns for the office pod, reached from the object's
    /// own art instead of from the rig's.
    ///
    /// `nil` for an object **taller than the desk**, which has no lift that
    /// satisfies the bound: its top can only reach the back edge by hanging its
    /// base below the desk's front edge. Nothing in the shipped stock is: the
    /// tallest is 24 against 38, and I1's answer where you cannot draw something
    /// truthfully is to draw nothing.
    public func deskKitLift(inkHeight: Double, slot: PodKitSlot, metrics: SeatMetrics)
    -> Double? {
        guard inkHeight > 0, inkHeight <= metrics.deskInkHeight else { return nil }
        let onBackEdge = metrics.deskInkHeight - inkHeight
        return slot.isBackRow ? onBackEdge : onBackEdge / 2
    }

    /// **Bottom-centre of one orientation-neutral object on a camera-facing pod's
    /// desktop**, or `nil` for a seat that has none and for an object this slot
    /// cannot hold.
    ///
    /// ADR-008 §5 left a camera-facing desk bare and gave two independent reasons.
    /// The first still holds and is why none of these is a rig: an object there
    /// faces upstage, and a screen has no honest rear view. **The second has
    /// expired.** It was geometric: *"the theme desk is 32 px wide and the body
    /// occupies all of it"*, and a pod is 64 px wide with 16 px of desktop
    /// outside the body's canvas on either side.
    ///
    /// What stands here is therefore theme furniture that says nothing about any
    /// agent [I1]: paper, a folder, a clipboard, a mug: objects that read the
    /// same from either side. It is still not ADR-006's work-kind slot, and a
    /// camera-facing seat still carries none of that,
    /// `SeatFacing.showsDeskTopObject` is unchanged.
    ///
    /// **It cannot cover a face, and that is arithmetic rather than care.** See
    /// `deskKitLift(inkHeight:slot:metrics:)`, which is the whole of it.
    ///
    /// **Both slots, where the rig gets one.** An away-facing pod keeps its left
    /// slot for the rig and its right for ADR-006's object, so it has nowhere
    /// else to put anything; a camera-facing pod carries neither of those and its
    /// whole desktop is free. Nothing here can collide with the work-kind object
    /// because that object is never drawn at this facing.
    public func deskKitPosition(
        _ index: Int, slot: PodKitSlot, inkHeight: Double, metrics: SeatMetrics
    ) -> ScenePoint? {
        guard metrics.isDeskPod, seatFacing(index) == .towardCamera,
              let lift = deskKitLift(inkHeight: inkHeight, slot: slot, metrics: metrics)
        else { return nil }
        let desk = deskPosition(index, metrics: metrics)
        let offset = podSlotOffsetX(metrics: metrics)
        return ScenePoint(x: desk.x + (slot.isLeft ? -offset : offset), y: desk.y + lift)
    }

    /// **Which row of the body a toward-camera desk's top edge lands on**, above
    /// the feet.
    ///
    /// The desk is the whole of what makes a standing figure read as a seated
    /// one, so where it cuts is the whole design, and it was measured against
    /// what it costs before it was chosen [docs/M8-MEASUREMENTS-phase1c.md §2]:
    ///
    /// | cut at | body kept | costume kept | reads as |
    /// |---:|---:|---:|---|
    /// | h4 | 94% | 79% | standing behind a low table |
    /// | h8 | 86% | 55% | at a desk, hips hidden |
    /// | **h12** | **75%** | **29%** | **at a desk, waist hidden** |
    /// | h17 | 62% | 0% | the whole costume is gone |
    /// | h23 | 48% | 0% | a head on a slab |
    ///
    /// The anatomy is measured too: legs h0–h7, torso and arms h8–h21, head and
    /// hair h22 up. **There is no cut that keeps the costume and sells "seated"**
    ///: at h8 you keep 55% of the costume and you can see the hips, and a chibi
    /// with visible hips is standing. h12 is the waist: the first cut that reads
    /// as a desk rather than as a table, and it is bought with 71% of the
    /// costume. Toward-camera buys a **face**, which no other orientation gives
    /// at all, and this is what it pays.
    public var deskCutAboveFeet: Double { 12 }

    /// How far **upstage** of the feet an away-facing seat's desk stands.
    ///
    /// A quarter tile, and it is `scripts/compose-scene.py`'s own `SEAT_STANDOFF
    /// = 8` in that file's frame of reference: it seats its away-facing figure
    /// 8 px downstage of the desk's floor point, which is this number seen from
    /// the desk instead of from the feet. Nothing has to be derived here because
    /// nothing is being occluded: the desk is *behind* the occupant, so it sorts
    /// behind by row and the only thing the number decides is how much of it
    /// shows around the body.
    public var awayDeskUpstage: Double { Double(tile) / 4 }

    /// **How far downstage of the feet an away-facing seat's chair stands**: the
    /// one number in this file that decides whether a costume survives.
    ///
    /// ## The two numbers, and which frame of reference each is in
    ///
    /// `docs/M8-HANDOFF.md` says "roughly a 30 px standoff so head and shoulders
    /// clear the backrest". `scripts/compose-scene.py` ships `SEAT_STANDOFF = 8`
    /// and the maintainer likes how it looks. They are **the same composition**
    /// measured from two different points:
    ///
    /// | | measured from | value |
    /// |---|---|---:|
    /// | `compose-scene.py` `SEAT_STANDOFF` | the **desk's** floor point, to the figure's feet | 8 |
    /// | `compose-scene.py` `CHAIR_DROP` | the **desk's** floor point, to the chair's feet | 38 |
    /// | this | the **figure's** feet, to the chair's feet | **38 − 8 = 30** |
    ///
    /// So the spike's chair sits 30 px downstage of its occupant, and the
    /// handoff's number is the spike's number. Neither was copied: the two were
    /// reconciled by measuring, and 30 is what this returns for the 46 px chair
    /// every theme binds.
    ///
    /// ## The floor under it is measured, and it is not the head
    ///
    /// A 46 px chair back is *taller than four of the six variants*, so "does the
    /// head clear" is the wrong question: the head clears at 24 and the costume
    /// does not appear until 25. The binding number is the **costume**: its ink
    /// tops out at `costumeTopAboveFeet` (22 px, measured over all twelve sets,
    /// `characters.costumes.ink_top_px`), so a chair of height `H` hides *every*
    /// costume pixel at any standoff below `H − 22`, and the identity channel the
    /// wardrobe exists for is gone with nothing failing.
    /// [docs/M8-MEASUREMENTS-phase1c.md §1]
    ///
    /// This returns `H − costumeTop + collar`, so the chair's top edge always
    /// lands `collar` px *inside* the costume band and six rows of collar show
    /// above the backrest. `collar` is the one chosen number here and it is
    /// chosen at 6 because 46 − 22 + 6 = 30 reproduces the composition the
    /// maintainer approved. A shorter chair moves down with it rather than
    /// floating: a 24 px chair asks for 8, which is where a chair sits.
    ///
    /// **What it costs, stated rather than discovered in review:** six rows out
    /// of twenty-two is 24% of the costume, so an away-facing seat spends three
    /// quarters of its occupant's costume on the chair. The accent, the
    /// nameplate and the badge are untouched: they are drawn in the overlay
    /// band far above anything furniture sorts in, and at `1x` the costume was
    /// already measured at a 0.00% silhouette difference [ADR-005 §9.6], so what
    /// is being spent is the weakest identity channel the room owns, on the only
    /// orientation that shows the back of a head.
    ///
    /// **Nothing asks for this at an away-facing seat any more**, and the reason
    /// is one subtraction. See `SeatFacing.seatRole`: a 46 px chair back does not
    /// fit between an occupant's chin and the bottom of its own nameplate, at any
    /// standoff. This is kept because it is still the right answer to *where a
    /// chair stands behind a figure*, it is what `chairPosition(_:metrics:)`
    /// computes, and a room that ever binds a shorter back view needs it
    /// unchanged.
    public func awayChairStandoff(metrics: SeatMetrics) -> Double {
        max(0, metrics.chairInkHeight - metrics.costumeTopAboveFeet + Self.collarRowsAboveChair)
    }

    /// How many rows of costume an away-facing chair leaves showing above its
    /// own top edge. See `awayChairStandoff(metrics:)`.
    public static let collarRowsAboveChair: Double = 6

    /// Bottom-**centre** of the desk for a seat, in the place its facing puts it.
    ///
    /// | facing | where | why |
    /// |---|---|---|
    /// | side-on | `x + 0.875·tile`, same row | seven eighths of a tile puts a 32 px desk's near edge four pixels *inside* the body, and at 32 px that overlap is the only cue that a character is sitting **at** a desk rather than beside one |
    /// | toward camera | same column, `deskInkHeight − 1 − deskCutAboveFeet` downstage | so the desk's top edge lands on the body's waist |
    /// | away from camera | `x + 0.875·tile`, `awayDeskUpstage` upstage | the occupant's back is to it, and the object on it has to be somewhere a viewer can see |
    ///
    /// **The away-facing desk keeps the side-on seat's x and moves only in
    /// depth, and that is a decision worth its own paragraph.** Centring it on
    /// the column is the obvious arrangement and it was tried first: it puts a
    /// 32 px desk directly behind a 20 px body, so six pixels of desk show at
    /// each side, and (much worse) the object standing on it has nowhere to be
    /// except behind the occupant's head. `docs/M8-PLAN-face-the-camera.md`'s
    /// complaint #3 is "still no laptops, the desk objects are not readable";
    /// a layout that hides the desk object at every seat in the room would be
    /// answering complaint #4 by making #3 worse. Keeping the desk beside the
    /// occupant keeps `RoomScene.deskObjectNearEdgeX`'s rule exactly as ADR-006
    /// §2c wrote it: one character half-canvas to the right, the first column
    /// strictly outside the body, so the object is as visible at an away-facing
    /// seat as it has ever been, and the depth offset is what says the occupant
    /// is *at* the desk rather than beside it.
    ///
    /// The pack's own room can centre its figure because its desk is 64 px wide
    /// with two monitors at ±16 and the person between them. Ours is 32. That is
    /// the whole of the difference and it is an art fact, not a taste one.
    ///
    /// **The turned cases need no depth bias and that is the point of moving
    /// them.** `Character.Layer.rowDepth` sorts by row, so a desk genuinely
    /// downstage of a body draws in front of it and one genuinely upstage draws
    /// behind it, with no constant to pick and no tie to break.
    /// `RoomScene.surfaceDepthBias` exists because a side-on desk shares its
    /// occupant's row; a turned one does not.
    ///
    /// **The depth is per-theme and derived, because a constant fails every
    /// theme in one direction or the other**: at 0 all six cut at or above the
    /// collarbone (four leave a head on a slab, `mission_control` cuts into the
    /// head, `library` decapitates) and at one whole floor row four of six do not
    /// occlude at all and the room draws people standing behind furniture. The
    /// six shipped desks want 11, 11, 11, 11, 23 and 31 px.
    /// [docs/M8-MEASUREMENTS-phase1c.md §2]
    ///
    /// It is the **ink height** rather than `surface_y` that decides it, and the
    /// two are the same in five themes and differ by 8 px in `library`, whose box
    /// top is a standing book and not the slab. `surface_y` answers "where could
    /// something stand"; occlusion asks "where does the ink stop", and reaching
    /// for the more natural-sounding of the two would be wrong exactly once.
    /// How far to a side-on occupant's right its desk is centred. Seven eighths
    /// of a tile: see `deskPosition(_:metrics:)`. Named because
    /// `RoomScene.surfaceNearEdgeX` is the *only* other thing that needs it, and
    /// it needs it for a seat it may not be able to ask about: the near-edge cue
    /// is a property of the side-on arrangement, not of whichever seat happens
    /// to be seat 0.
    /// The offset a side-on desk *wants*: seven eighths of a tile to the
    /// occupant's right. `sideOnDeskOffsetX(metrics:)` is what it gets.
    public var preferredSideOnDeskOffsetX: Double { Double(tile) * 0.875 }

    /// **How far to a side-on occupant's right its desk is centred, clamped so
    /// the desk stays inside its own seat's prop lane.** [ADR-014]
    ///
    /// The bare `preferredSideOnDeskOffsetX` was written when no seat was
    /// side-on, so it was never measured against a desk wider than the narrow
    /// ones it was chosen for. ADR-014 seats the front row side-on and
    /// `office`'s pod is **64 px**, which at 28 px of offset reaches 12 px into
    /// the next seat's lane. `everyStationFitsTheSeatItIsDrawnAt` caught it, and
    /// its own comment had already published the arithmetic that predicts it:
    /// side-on desks reach **-4** at 32 px of art and **0** at
    /// `mission_control`'s 40 px, while the 64 px pod reaches **-16** only
    /// because at its two turned facings it is *centred* on the column.
    ///
    /// The lane starts at `seat.x + pitch - tile - halfCanvas`, so a desk of
    /// width `w` centred at `seat.x + d` stays inside it while
    /// `d <= pitch - tile - halfCanvas - w/2`. That is the whole rule: **a desk
    /// stands beside its occupant, as far over as its own lane allows.**
    ///
    /// It changes nothing for the two desks that fit: 32 px art clamps at 32 and
    /// keeps its 28, `mission_control`'s 40 clamps at 28 and keeps its 28. Only
    /// the pod moves, to 16.
    public func sideOnDeskOffsetX(metrics: SeatMetrics) -> Double {
        sideOnDeskOffsetX(deskInkWidth: metrics.deskInkWidth)
    }

    /// The same clamp, from the desk's own ink width, for the callers that hold
    /// the prop rather than a `SeatMetrics`.
    public func sideOnDeskOffsetX(deskInkWidth: Double) -> Double {
        let halfCanvas = Double(tile) / 2
        let laneLimit = Double(seatSpacingTiles * tile) - Double(tile) - halfCanvas
            - deskInkWidth / 2
        return min(preferredSideOnDeskOffsetX, max(0, laneLimit))
    }

    /// **How far to an away-facing occupant's right its desk is centred: `0` for
    /// a pod.** [ADR-009]
    ///
    /// ADR-008 §7 kept the away-facing desk beside its occupant rather than
    /// behind it, and argued the decision on one number: a 32 px desk centred on a
    /// 32 px body shows six pixels at each side and leaves the object standing on
    /// it nowhere to be except behind the occupant's head. That argument closed
    /// with the condition under which it stops holding, in as many words: *"The
    /// pack can centre its figure because its desk is 64 px wide with two monitors
    /// at ±16 and the person between them; ours is 32. That is an art fact, not a
    /// taste one."*
    ///
    /// The office desk is 64 px wide with two rig slots now, so the condition is
    /// met and the desk centres, which is what puts a rig at each shoulder in
    /// `output/01-engineering-office.png`. Nothing else in the room changes,
    /// because `SeatMetrics.isDeskPod` is false for every other theme and this
    /// returns exactly what it returned before.
    public func awayDeskOffsetX(metrics: SeatMetrics) -> Double {
        metrics.isDeskPod ? 0 : sideOnDeskOffsetX(metrics: metrics)
    }

    public func deskPosition(_ index: Int, metrics: SeatMetrics) -> ScenePoint {
        let seat = seatPosition(index)
        switch seatFacing(index) {
        case .sideOn:
            return ScenePoint(x: seat.x + sideOnDeskOffsetX(metrics: metrics), y: seat.y)
        case .towardCamera:
            return ScenePoint(x: seat.x, y: seat.y - deskDepth(metrics: metrics))
        case .awayFromCamera:
            return ScenePoint(
                x: seat.x + awayDeskOffsetX(metrics: metrics), y: seat.y + awayDeskUpstage)
        }
    }

    /// How far downstage of the feet a toward-camera desk's floor point sits, so
    /// that its top edge lands on `deskCutAboveFeet`. Never negative: a desk
    /// shorter than the cut stands on the character's own row and cuts wherever
    /// its own height puts it.
    public func deskDepth(metrics: SeatMetrics) -> Double {
        max(0, metrics.deskInkHeight - 1 - deskCutAboveFeet)
    }

    /// Bottom-centre of a seat's chair, or `nil` for a seat that has none.
    ///
    /// Side-on keeps what it always had: the chair on the seat's own point, with
    /// the body drawn a hair in front of it. **Neither turned facing has a chair
    /// at all**: `SeatFacing.seatRole`, which carries the measurement that took
    /// the away-facing one away.
    ///
    /// The away-facing arm is kept rather than deleted, and it is not dead: it is
    /// where a 36-px-or-shorter back view would stand, it is the only reader of
    /// `awayChairStandoff(metrics:)`, and it is what the two callers ask before
    /// they ask for a role. A seat with a `nil` role draws nothing whatever this
    /// returns.
    public func chairPosition(_ index: Int, metrics: SeatMetrics) -> ScenePoint? {
        let seat = seatPosition(index)
        switch seatFacing(index) {
        case .sideOn: return seat
        case .towardCamera: return nil
        case .awayFromCamera:
            return ScenePoint(x: seat.x, y: seat.y - awayChairStandoff(metrics: metrics))
        }
    }

    /// **The desk's top surface for a seat**: the plane an object could stand
    /// on, not the desk's own bottom-centre anchor. [ADR-006 §2b, §2c]
    ///
    /// `content_box` measures a desk's ink footprint, and for most desks that
    /// footprint's top row *is* the surface, but not always: `library` binds a
    /// desk with a book already drawn on it, whose box top is 8 px above the
    /// slab underneath. `surfaceHeightAboveFloor` is the manifest's answer to
    /// which row is really the surface (`room.props.roles.desk.surface_y`, or a
    /// theme's own), measured by `scripts/build-manifest.py` rather than
    /// guessed here: this file has no access to the manifest and never reads a
    /// PNG, so the height above the floor is a parameter, the same shape
    /// `contentBand(badgeTopAboveFeet:plateDropBelowFeet:)` already takes its
    /// own manifest-measured heights in.
    ///
    /// `x` matches `deskPosition(_:)`'s own: this point sits directly above
    /// the desk's bottom-centre anchor, on the same column. Where *on* that
    /// surface an object's own near edge goes, and how it depth-sorts against
    /// the desk, is §2c's placement rule for the step that draws something
    /// here; this accessor only answers "where is the surface", which is a
    /// question every future object needs the same answer to and none of them
    /// should answer by eyeballing a second time.
    ///
    /// **A pod answers it from its own art instead**, because `surface_y` finds
    /// the back edge of a slab whose top surface is 25 rows deep. See
    /// `deskTopLift(surfaceHeightAboveFloor:metrics:)`, which is where the two
    /// answers meet, and which returns the parameter unchanged for every theme
    /// that is not a pod.
    public func deskSurfacePosition(
        seat index: Int, surfaceHeightAboveFloor: Double, metrics: SeatMetrics
    ) -> ScenePoint {
        let anchor = deskPosition(index, metrics: metrics)
        return ScenePoint(
            x: anchor.x,
            y: anchor.y + deskTopLift(
                surfaceHeightAboveFloor: surfaceHeightAboveFloor, metrics: metrics))
    }

    /// Bottom-centre of a station's one optional adjacent prop: a tile to the
    /// character's **left**, on the seat row. [ADR-002 §7]
    ///
    /// The left because at a side-on seat the right is the desk, and the
    /// arithmetic that keeps it out of everyone else's way is worth writing down
    /// rather than eyeballing. A seat pitch is three tiles. Within one pitch a
    /// side-on desk's 32 px box spans `x+12 … x+44` and this prop's spans
    /// `x−48 … x−16`, so a station occupies `x−48 … x+44`: 92 px of a 96 px
    /// pitch, with the next station's prop starting at `x+48`. Nothing overlaps
    /// and nothing is on a column any character walks down, because every column
    /// in this room is a seat's own and this is beside one, not on it.
    ///
    /// **A turned seat stacks its occluder in depth rather than beside the
    /// body**, so it spans `x−48 … x+16` instead and the bound above still holds
    /// with 28 px to spare. The measured footprints are 92 px side-on against
    /// 32–40 px turned; the plan expected the opposite and the seat pitch is the
    /// nameplate's anyway, so no mix of facings moves the scale the camera picks.
    /// [ADR-008 §7, docs/M8-MEASUREMENTS-phase1c.md §3]
    ///
    /// It is on its seat's **own** row, so it is furniture beside the character
    /// rather than decoration in front of the characters: the rule that
    /// replaced M5's foreground row, and it is not weakened by anything a theme
    /// can declare.
    public func stationPropPosition(_ index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x - Double(tile), y: seatRowY(index))
    }

    /// The x of the decoration column that belongs to a seat: a tile and a half
    /// outward from the seat's own centre, which is the gap between this seat's
    /// desk and the next seat's station prop.
    ///
    /// `RoomScene` stands one backdrop or one accent on each of these, sorted
    /// along x and alternating, so consecutive copies of one role are two seat
    /// pitches apart. It lives here rather than in the scene because
    /// `overflowPlatePosition` is derived from it and the two must not drift.
    public func propColumnX(forSeat index: Int) -> Double {
        seatPosition(index).x + Double(tile) * 1.5
    }

    /// **Where the room says how many agents it has no seat for.**
    ///
    /// Bottom-centre of a plate standing against the back wall, a tile above
    /// the wall line. Two properties are being bought and both are geometric
    /// rather than a matter of taste:
    ///
    /// - **Nothing else stands there.** The decoration columns alternate
    ///   backdrop/accent along x, and seat 0's column is the middle one of the
    ///   seven: an *accent* column, so the backdrops are a full seat pitch
    ///   away on either side and the accent itself stands two tiles downstage
    ///   against the back seat row. The tallest accent any theme ships reaches
    ///   `accentRowY + 78 = 238`, which is under this line.
    /// - **It is in frame whenever it exists.** The plate only ever appears when
    ///   every seat is taken, and a full room's camera span is fixed, so the
    ///   point is a constant rather than something that moves with the
    ///   population. `RoomScene` still clamps it into the frame, because a
    ///   viewport this app does not ship could be shorter than the one it does
    ///   and a caption that is off screen is the same silence it exists to
    ///   break.
    ///
    /// It is upstage of both seat rows, so it does not weaken "nothing is drawn
    /// nearer the camera than the seat row": see `RoomScene.buildRoom`.
    public var overflowPlatePosition: ScenePoint {
        ScenePoint(x: propColumnX(forSeat: 0), y: wallBaseY + Double(tile))
    }

    // MARK: Scenery [M8 Phase 2b]

    /// **The eight columns a piece of scenery may stand on, in x order.**
    ///
    /// Every seat's `propColumnX` (half a pitch outward from the seat) plus
    /// the one half a pitch outward from the leftmost seat, which no seat claims
    /// because the seats fill outward in pairs and there are seven of them.
    ///
    /// **They are the only floor a prop may have**, and that is a fact about the
    /// room's routes rather than a choice about composition. Every seat column
    /// is a corridor from the delivery row to the wall line: `entranceRoute`,
    /// `homeRoute` and `upstageExit` are all "straight up its own column", so a
    /// prop on one stands in somebody's way at some point in every session. The
    /// gaps between the columns meet no route at all: nothing travels laterally
    /// anywhere except on `deliveryRowY`, which is two rows downstage of the
    /// nearest thing scenery is allowed to touch.
    ///
    /// A pitch is 96 px and a body is 32, so a gap is 64 px of clear floor with
    /// the prop centred in it. `sceneryClearance` is the half-width that leaves.
    public var sceneryColumns: [Double] {
        let claimed = (0..<seatCapacity).map { propColumnX(forSeat: $0) }
        let leftmost = (0..<seatCapacity).map { seatPosition($0).x }.min() ?? 0
        return ([leftmost - Double(tile) * 1.5] + claimed)
            .filter { $0 > 0 && $0 < width }
            .sorted()
    }

    /// How far from a scenery column's centre a prop's ink may reach before it
    /// touches a seat column. Half a pitch, less half a body.
    public var sceneryClearance: Double { Double(tile) * 1.5 - Double(tile) / 2 }

    /// **The seven decoration columns and which of the two bands each carries**,
    /// in x order: `true` for the backdrop standing on the wall line, `false`
    /// for the accent a tile behind the back seat row.
    ///
    /// It lives here rather than in `RoomScene` because two other things now
    /// need it and neither may re-derive it: the overflow plate's clearance is
    /// argued against these points, and under a plan the wall band has to know
    /// which columns already have a full-height board standing in front of them,
    /// since a picture hung behind one is a picture nobody will ever see.
    /// `RoomScene.decorationPlacements` reads this rather than repeating the
    /// alternation: a transcription checked against a transcription is not a
    /// check, and this file has paid for that twice.
    public var decorationColumns: [(isBackdrop: Bool, x: Double)] {
        (0..<seatCapacity)
            .map { propColumnX(forSeat: $0) }
            .filter { $0 < width }
            .sorted()
            .enumerated()
            .map { (isBackdrop: $0.offset.isMultiple(of: 2), x: $0.element) }
    }

    /// **The four depths scenery stands at**, far to near.
    ///
    /// They are declared by the *manifest* per prop and resolved to a point
    /// here, so the art can be swapped without the room moving. The vocabulary
    /// is closed and an unrecognised band draws nothing: the same answer the
    /// identity model gives an ambiguous attribution. [I1]
    public enum SceneryBand: String, Sendable, CaseIterable {
        /// Hung on the wall face, two tiles above the line where the wall meets
        /// the floor. Nothing stands here: a leaver's feet stop at `wallBaseY`
        ///, so this band alone may use the **seat** columns, and it is behind
        /// everything the room draws.
        case wall
        /// Standing on the line where the floor meets the wall, in the gaps the
        /// backdrops leave.
        case wallLine = "wall_line"
        /// One row downstage of the wall line.
        case backFloor = "back_floor"
        /// One row upstage of the back seat row: the nearest the camera any
        /// scenery ever comes, and still a whole row behind the furthest-upstage
        /// character.
        case midFloor = "mid_floor"
    }

    /// Where the props of one band stand, bottom-centre, in x order.
    ///
    /// **Every column carries at most one prop per band, and the bands are
    /// assigned so that no column stacks two things that would bury each
    /// other.** The existing decoration is the fixed point this is built around:
    /// `RoomScene` stands a backdrop on the wall line at the odd columns and an
    /// accent a tile behind the back seat row at the even ones.
    ///
    /// | band | y | columns | why those |
    /// |---|---|---|---|
    /// | `wall` | `wallBaseY + 2·tile` | the seven **seat** columns | disjoint in x from every floor prop, and behind all of them |
    /// | `wallLine` | `wallBaseY` | the even columns, less the overflow plate's | the odd ones hold the backdrops |
    /// | `backFloor` | `wallBaseY − tile` | column 0 and the odd ones | an accent column already carries a full-height prop a row in front |
    /// | `midFloor` | `backSeatRowY + tile` | column 0 and the odd ones | the even ones are the accent row itself |
    ///
    /// The one column that carries three floor props: 0, and the odd ones with
    /// their backdrop: stacks them a row apart with the shortest nearest the
    /// camera, which is what lets all three read. `sceneryInkBound(_:)` is that
    /// argument as a number.
    public func sceneryAnchors(_ band: SceneryBand) -> [ScenePoint] {
        let columns = sceneryColumns
        switch band {
        case .wall:
            // **Under a plan the near wall is a wall you can see the face of**,
            // 50 px of it between a 2 px baseboard and the 12 px floor-plan
            // line, so a picture hangs *on* it rather than floating two tiles up
            // an infinite field of wall tiles. Without a plan the wall runs to
            // the top of the overscan and the old point is still the only one
            // that reads.
            //
            // **And a doorway column carries nothing.** A picture hung across a
            // gap cut clean through the band is `06-SET-BUILDING.md`'s R1, and
            // the doorways are on seat columns: the very columns this band
            // uses, so it is not a hypothetical. [ADR-007 §4]
            let seats = (0..<seatCapacity).map { seatPosition($0).x }
            guard !plan.isEmpty else {
                return seats.sorted().map {
                    ScenePoint(x: $0, y: wallBaseY + Double(tile * 2))
                }
            }
            // A face 50 px tall and 25 tiles wide is the largest empty surface
            // the room has, so it takes every column that has nothing standing
            // in front of it: the seat columns **and** the accent columns, less
            // the doorways, less the column a backdrop or the overflow plate
            // already occupies. A picture hung behind a 46 px board on a stand
            // is a picture nobody sees.
            let doorways = plan.doorwayColumns
            let blocked = Set(decorationColumns.filter(\.isBackdrop).map(\.x))
                .union([overflowPlatePosition.x])
            return (seats + sceneryColumns)
                .filter { !blocked.contains($0) }
                .filter { !doorways.contains(Int(($0 - Double(tile) / 2).rounded()) / tile) }
                .sorted()
                .map { ScenePoint(x: $0, y: hungPropY) }
        case .wallLine:
            // The line where the floor meets the wall, and under a plan that
            // is the **far** room's floor line, one wall band upstage, because
            // the near room's own is where the backdrops stand. The tall props
            // this band carries (a cooler, a vending machine, a coffee counter,
            // 60–68 px) then stand against a second wall face instead of poking
            // out of the top of the first one.
            let y = plan.isEmpty ? wallBaseY : farFloorY
            return columns.enumerated()
                .filter { $0.offset.isMultiple(of: 2) && $0.element != overflowPlatePosition.x }
                .map { ScenePoint(x: $0.element, y: y) }
        case .backFloor:
            return columns.enumerated()
                .filter { $0.offset == 0 || !$0.offset.isMultiple(of: 2) }
                .map { ScenePoint(x: $0.element, y: wallBaseY - Double(tile)) }
        case .midFloor:
            return columns.enumerated()
                .filter { $0.offset == 0 || !$0.offset.isMultiple(of: 2) }
                .map { ScenePoint(x: $0.element, y: backSeatRowY + Double(tile)) }
        }
    }

    /// **How big a prop in this band may be**, as `(width, height)` of ink.
    ///
    /// Width is one number everywhere: half a pitch less half a body, with 8 px
    /// kept back so the clearance is visible rather than exactly zero. On the
    /// floor that is the gap between two seat columns. On the wall it is the gap
    /// to the nearest backdrop, and the same number covers it: the three themes
    /// whose backdrop reaches above this band's own floor bind one 38, 32 and 30
    /// px wide, which leaves 58 px of column even at the worst of them.
    ///
    /// Height is what stops one prop burying the one behind it [R7]. A row is a
    /// tile, so a prop no taller than a tile tops out exactly where the prop a
    /// row upstage of it begins and the two abut instead of overlapping. The two
    /// floor bands are given a tile and a quarter rather than a tile, which
    /// costs the prop behind them 8 px of its base and buys a pool of props
    /// worth placing: a 32 px ceiling excludes almost every printer, cabinet
    /// and bin in either pack. The wall-line band is the far plane of the floor
    /// and has nothing behind it, so it takes the whole two tiles of wall face.
    public func sceneryInkBound(_ band: SceneryBand) -> (width: Int, height: Int) {
        switch band {
        case .wall:
            // Under a plan the ceiling is the wall's own top line, measured
            // rather than budgeted: a picture may reach it and may not cross it.
            guard plan.isEmpty else {
                return (Int(sceneryClearance * 2) - 8, Int(wallFace.top - hungPropY))
            }
            return (Int(sceneryClearance * 2) - 8, tile + tile / 2)
        case .wallLine: return (Int(sceneryClearance * 2) - 8, tile * 2 + 8)
        case .backFloor, .midFloor: return (Int(sceneryClearance * 2) - 8, tile + tile / 4)
        }
    }

    /// Where a reporting subagent stands to deliver: down onto the delivery row
    /// and along it, to a spot beside the character it is reporting to.
    public var deliveryPosition: ScenePoint {
        deliveryPosition(anchorSeat: 0, reporterSeat: 2)
    }

    /// **Which side of its anchor a reporter is on, and therefore which side it
    /// approaches from.**
    ///
    /// Its own, so a round trip never crosses the anchor's chair. Seat 0 sits on
    /// the centre line and is the anchor rather than a reporter, so the tie goes
    /// right and is never reached.
    /// [see `deliveryPosition(anchorSeat:reporterSeat:)`]
    public func deliverySide(anchorSeat: Int, reporterSeat: Int) -> Facing {
        seatPosition(reporterSeat).x >= seatPosition(anchorSeat).x ? .right : .left
    }

    /// How far short of the anchor a reporter stops: a tile and a half.
    ///
    /// Near enough that the hand-over is between two characters and not into
    /// space, far enough that the reporter's body does not stand on the anchor's
    /// nameplate, which is the defect `noTwoNameplatesEverIntersect` was written
    /// against, and the reason the number is 48 rather than a tile.
    public var deliveryGap: Double { Double(tile) * 1.5 }

    /// The point on the delivery row directly below a seat. A reporter drops to
    /// here out of its own column before it goes anywhere sideways, and comes
    /// back to here before it climbs, so every *vertical* move it makes is
    /// inside its own column and every *lateral* one is on this row.
    public func deliveryLaneEntry(forSeat index: Int) -> ScenePoint {
        ScenePoint(x: seatPosition(index).x, y: deliveryRowY)
    }

    /// **Where a reporter stands to hand its report over: a delivery gap short
    /// of its anchor, on its own side of it, on the delivery row.**
    ///
    /// It walks there. The maintainer watched the shipped app and said the
    /// reporters "aren't walking to the main agent, they just walk down and pass
    /// the envelope to no one", and they were right: M6f deleted the lateral leg
    /// to buy 96 px of band, and what was left was a beat that mimes a hand-over
    /// with nothing within a seat pitch to hand anything to. That is not a
    /// composition complaint. The beat *depicts* a transfer between two
    /// characters, and one of them was not there: a picture asserting something
    /// no arrangement of the data supports. [I1]
    ///
    /// ## The rule this is an instance of
    ///
    /// > **Every leg of every route in this room is either vertical and inside
    /// > the moving character's own seat column, or lateral and on
    /// > `deliveryRowY`.**
    ///
    /// The first clause is M6f's, unchanged, and it still covers arriving
    /// (`entranceRoute`), stepping out (`deliveryRoute`'s first two legs), coming
    /// home (`homeRoute`) and leaving (`upstageExit`). Two plates meet only if
    /// they share a horizontal strip **and** come within a plate width in x, and
    /// for every pair of characters that both obey the first clause the second
    /// condition is decided once by `seatColumn`: 96 px between neighbouring
    /// columns against a `SceneBitmaps.maximumNameplateWidth` plate.
    ///
    /// The exception is two characters in **one** column, which the room produces
    /// exactly once: a seat is free the instant its occupant starts walking out,
    /// so a refill can begin while the leaver is still in the column. Both move
    /// upstage, so they are a convoy: same direction, same speed, the gap they
    /// start with is the gap they keep. `entranceRoute(forSeat:)` and
    /// `theWholeCastCanLeaveInOneFrame` rest on that and are untouched.
    ///
    /// ## The second clause, which is what this change adds back
    ///
    /// **1. The corridor meets no other route.** `deliveryRowY` is a row nothing
    /// else in the room can be on. Arrivals begin on the walkway a row upstage of
    /// it; `homeRoute` and `upstageExit` only ever increase `y`; both seat rows
    /// and every prop the room places are upstage
    /// [`RoomScene.decorationPlacements`]. A reporter reaches the row down its
    /// **own column** and leaves it up its **own column**, so the only thing that
    /// crosses the walkway during a report is one character inside one column,
    /// which is the first clause again.
    ///
    /// That is the direct answer to the objection this option was rejected on at
    /// M6f: that it "puts a lateral corridor back across the one row every
    /// arrival steps through". It does not, because the corridor is not on that
    /// row. The objection was written when the arrival began one seat pitch
    /// outward *along the walkway*; M6f itself deleted that, so by the time the
    /// trade was refused the reason had already expired.
    ///
    /// **2. Two reporters cannot be on the row together unless their corridors
    /// are clear of each other**, which is `DeliveryFloor`, and it is a
    /// statement about x, not about time. A beat claims the closed interval
    /// `deliveryCorridor(anchorSeat:reporterSeat:)`, every x its body will occupy
    /// from the moment it drops onto the row to the moment it leaves it. A second
    /// claim is granted only if it clears every live one by
    /// `DeliveryFloor.clearance` = one plate plus the lattice's own margin. A
    /// reporter that is not granted the row does not wait: it plays the beat it
    /// plays today, in its own column on the walkway. See
    /// `inPlaceDeliveryRoute(reporterSeat:)`.
    ///
    /// So the scheduler decides which of **two truthful pictures** a report gets.
    /// It cannot decide whether the room is correct, and it cannot delay
    /// anything, so there is no queue to drain and nothing to reap but the claim
    /// itself. [I4]
    ///
    /// ## The ledger
    ///
    /// One row, 32 px, `contentBand` **160 → 192** against the 200 a `2x` view of
    /// the 720×400 panel gives. It is affordable now and was not at M6f because
    /// the nameplate paid for it: `2806f5c` put the task on the plate and cost
    /// 8 px (170 → 178), and `2caa864` cut the plate to one row and gave back 18
    /// (178 → 160). Three rows (one per ring, which is what M6f deleted) would
    /// be 96 px and a band of 256, and does not fit. That is the whole of the
    /// difference between the option refused then and the one taken here: **one
    /// row instead of three, paid for out of the plate.**
    ///
    /// ## What it costs, plainly
    ///
    /// A report that does not get the row is told apart from one that does, and
    /// the same agent's report can look different on two different occasions.
    /// That is a real inconsistency and it is recorded rather than dressed up.
    /// What is bought is that when the walk plays, which is most of the time;
    /// `mostReportsInTheCorpusGetTheWalk` measures it on `fixtures/`: the
    /// envelope goes to a character rather than to the floor.
    ///
    /// `anchorSeat` is whose seat the reporter delivers to: 0, the main agent,
    /// unless `tool_response.agentId` linked it to a parent that is still in the
    /// room.
    public func deliveryPosition(anchorSeat: Int, reporterSeat: Int) -> ScenePoint {
        let outward = deliverySide(anchorSeat: anchorSeat, reporterSeat: reporterSeat) == .right
            ? 1.0 : -1.0
        return ScenePoint(
            x: seatPosition(anchorSeat).x + outward * deliveryGap, y: deliveryRowY)
    }

    /// **Every x a report beat occupies on the delivery row**, from the
    /// reporter's own column to where it stands to hand over.
    ///
    /// The claim `DeliveryFloor` grants is this interval and it is held for the
    /// whole beat, out and back, so a granted claim is a statement about the
    /// reporter's position at every instant it is on the row, not about the
    /// instant it was granted. That is what makes the exclusion geometric rather
    /// than a matter of scheduling: two granted claims are two disjoint stretches
    /// of one row, and the characters inside them are as far apart as the
    /// stretches are.
    public func deliveryCorridor(anchorSeat: Int, reporterSeat: Int) -> ClosedRange<Double> {
        let from = deliveryLaneEntry(forSeat: reporterSeat).x
        let to = deliveryPosition(anchorSeat: anchorSeat, reporterSeat: reporterSeat).x
        return min(from, to)...max(from, to)
    }

    /// **The beat a reporter plays when the delivery row is not free: the one
    /// that shipped between M6f and now.** One row downstage onto the walkway,
    /// in its own column, turned towards the anchor.
    ///
    /// It says less (it does not say *who*) and it says nothing false. Every
    /// frame of it still traces to one real `reportDelivered`, and it is
    /// available at every instant for any number of reporters at once, because
    /// the walkway is crossed in-column by construction. That is what lets the
    /// delivery row be a lock with no queue behind it. [I1, I4]
    public func inPlaceDeliveryPosition(reporterSeat: Int) -> ScenePoint {
        seatApproach(reporterSeat)
    }

    public func inPlaceDeliveryRoute(reporterSeat: Int) -> [ScenePoint] {
        [inPlaceDeliveryPosition(reporterSeat: reporterSeat)]
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

    /// **The report walk, as waypoints.** Three legs: down the reporter's own
    /// column to the walkway, down its own column again onto the delivery row,
    /// and only then sideways along that row to the anchor.
    ///
    /// It is built here rather than at the call site, and returned as a list
    /// rather than a point, because the *shape* is the guarantee and the shape is
    /// the thing a caller could get wrong. A caller that cut the corner: a
    /// straight desk-to-anchor diagonal: would drag the plate across three rows
    /// of the room and the second clause of
    /// `deliveryPosition(anchorSeat:reporterSeat:)`'s rule would be gone with
    /// nothing failing.
    public func deliveryRoute(anchorSeat: Int, reporterSeat: Int) -> [ScenePoint] {
        [seatApproach(reporterSeat),
         deliveryLaneEntry(forSeat: reporterSeat),
         deliveryPosition(anchorSeat: anchorSeat, reporterSeat: reporterSeat)]
    }

    /// The same route reversed: **back along the delivery row into the
    /// character's own column, then straight up it into the chair**, or no legs
    /// at all when it is already in it.
    ///
    /// **`fromY` decides how much of that is needed, and it is load-bearing in
    /// both directions.**
    ///
    /// - *At or below the delivery row* the character may be off its own column
    /// (the delivery row is the one place in the room where that is true) so
    ///   the lane entry goes in front and the climb starts from the column. A
    ///   caller that omitted it would produce the diagonal `deliveryRoute` is
    ///   written to prevent, on the way home instead of on the way out.
    /// - *Above it* the character is in its own column already and one vertical
    ///   leg is the whole route.
    /// - *At or above the seat row* there is no leg at all, and that guard is not
    ///   tidiness: a zero-length walk still costs `Character.duration`'s 0.2 s
    ///   floor, and a leaver spends those 0.2 s standing still in a column its
    ///   replacement is already climbing: a seat is free the instant its
    ///   occupant starts walking out. 0.2 s at 72 px/s is 14 px of a 32 px convoy
    ///   gap; `noAdversarialPairingOfBeatsEverTouchesTwoPlates` measured the two
    ///   plates 8 px *inside* each other before it was added.
    ///
    /// The default is the furthest downstage the room goes, so a caller that does
    /// not say gets the full route rather than a diagonal.
    public func homeRoute(forSeat index: Int, fromY: Double = -.greatestFiniteMagnitude)
    -> [ScenePoint] {
        guard fromY < seatRowY(index) else { return [] }
        guard fromY <= deliveryRowY else { return [seatPosition(index)] }
        return [deliveryLaneEntry(forSeat: index), seatPosition(index)]
    }

    /// **The walk-in, as waypoints: straight up the character's own column,
    /// from the walkway into its chair.**
    ///
    /// It used to start one seat pitch *outward* in the aisle and walk sideways
    /// to its own station, and that was the last beat in the room the lattice
    /// did not close by construction. One pitch outward on the aisle is not a
    /// clear patch of floor: it is **exactly the next ring's own aisle
    /// station**, so an arrival's corridor ran from one occupied column to
    /// another along the one row every character steps through. It needed a
    /// seat vacated and refilled while the next seat out was mid-report, and
    /// then the newcomer stood on the reporter as it passed: measured at
    /// **−25.6 px**, a real overlap rather than a tight clearance.
    ///
    /// The repair is the rule the exits already follow, stated the other way up:
    ///
    /// > **Every vertical move in the room goes upstage.** Out of the aisle into
    /// > a chair, home up a reporter's own column, out through the back wall,
    /// > every one of them increases `y`.
    ///
    /// That is why the arrival comes up from the front rather than down from the
    /// back, which is the other way to put a walk-in inside its own column. Two
    /// characters in one column is not hypothetical: a seat is free the instant
    /// its occupant starts walking out, so a refill can begin while the leaver
    /// is still in the column, and a *downstage* arrival would meet that leaver
    /// head-on at zero separation, which no spacing fixes. Arriving upstage makes
    /// the pair a convoy instead: same direction, same speed, so a gap that
    /// starts at a tile stays at a tile. It is the argument
    /// `theWholeCastCanLeaveInOneFrame` already rests on.
    ///
    /// **Nothing new has to be proved about the rows it crosses.** The route is a
    /// character ascending its own column, which is every other route in the room
    ///: see `deliveryPosition(anchorSeat:reporterSeat:)`. It began on the
    /// character's own ring's delivery row until those rows were removed and now
    /// begins on the walkway, which is the same claim one row up.
    ///
    /// **It is still visible from its first frame**, which is what the outward
    /// aisle start was for. `contentBand` runs from a walkway character's plate
    /// to the tallest badge, so the walkway is inside the frame by construction.
    public func entranceRoute(forSeat index: Int) -> [ScenePoint] {
        [seatApproach(index), seatPosition(index)]
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
    /// onto, and `noTwoNameplatesEverIntersect` caught it doing so in
    /// `three-subagents`, 44 seconds in, walking through a reporter that was on
    /// its way home up its own column.
    ///
    /// Going upstage costs nothing to guarantee *in x*, because no other
    /// character's route is behind the desk row: a leaver's whole exit is inside
    /// its own column, and columns are a seat pitch apart. It also reads as what
    /// it is: you stand up and walk out the back rather than squeezing along the
    /// front of everyone's desk.
    ///
    /// It walks **as far as its own furniture leaves floor to walk on**, fading
    /// as it goes: see `Character.departOffScreen` and
    /// `upstageClearance(forSeat:metrics:)`. The old exit walked off the side of
    /// the frame, which needed no fade because the frame edge did the hiding;
    /// there is no edge behind the desks, and a flat wall gives a character
    /// walking up it nothing to disappear behind. A fade is not a dramatisation
    /// of anything the data did not say: the agent is gone, and this is the room
    /// saying so. [I1]
    ///
    /// **It used to walk to `wallBaseY` unconditionally, and for the four
    /// away-facing seats that was a walk through their own desks.** The paragraph
    /// above this one said "there is nothing behind the desk row" and it was
    /// written when that was true of every seat. ADR-008 put a desk
    /// `awayDeskUpstage` (8 px) behind an away-facing occupant and ADR-009
    /// stood two screen rigs on it, so those four seats have 8 px of floor behind
    /// them and 58 px of furniture above it. The metrics argument is what makes
    /// the difference visible in the type system rather than in a comment, and it
    /// is required for the same reason `deskPosition(_:metrics:)`'s is: a default
    /// would put the exit back through the desk, silently.
    public func upstageExit(forSeat index: Int, metrics: SeatMetrics) -> ScenePoint {
        ScenePoint(
            x: seatPosition(index).x, y: upstageClearance(forSeat: index, metrics: metrics))
    }

    /// The same, for a character whose seat is not known: it leaves from
    /// wherever it is standing, and stops at whatever furniture its column has.
    ///
    /// A body 32 px wide standing at `x` may overlap at most two seat columns, so
    /// this takes the lowest ceiling of every seat it is standing in front of.
    /// A character clear of every seat column walks to the wall line, which is
    /// what this returned for everybody before the ceiling existed.
    public func upstageExit(fromX x: Double, metrics: SeatMetrics) -> ScenePoint {
        var ceiling = wallBaseY
        for seat in 0..<seatCapacity where abs(x - seatPosition(seat).x) < Double(tile) {
            ceiling = min(ceiling, upstageClearance(forSeat: seat, metrics: metrics))
        }
        return ScenePoint(x: x, y: max(deliveryRowY, ceiling))
    }

    /// **The furthest upstage a body may stand in a seat's own column: one pixel
    /// downstage of the nearest thing that seat stands behind its occupant, or
    /// the wall line for a seat that stands nothing there.**
    ///
    /// ## What it is for
    ///
    /// Every route in this room is vertical inside one seat column, so the column
    /// is the seat's private corridor and nothing else can be in it. That was the
    /// whole of the clearance argument until ADR-008 and ADR-009 put the *seat's
    /// own furniture* in it: an away-facing occupant's desk stands
    /// `awayDeskUpstage` = 8 px behind it, and on a pod that desk carries two
    /// screen rigs whose ink reaches 58 px further. The exit walked to
    /// `wallBaseY` regardless, so a leaver from any away-facing seat rose through
    /// 38 px of desk and 42 px of rig and stood, half-faded, on top of its own
    /// workstation. `RouteFurnitureTests` is that as a check; this is the number
    /// that answers it.
    ///
    /// ## Which furniture counts, and why only two pieces of it
    ///
    /// A piece counts when it is **upstage of the seat** and reaches into the
    /// seat's own one-tile column: the same "clears one tile centred on the
    /// seat" test `RoomPlan.dressingViolations` applies to a hand-placed prop,
    /// and the same 32 px body every clearance argument in this file is written
    /// against. Only two pieces can ever satisfy the first half:
    ///
    /// | piece | where it stands | counts |
    /// |---|---|---|
    /// | away-facing desk | `awayDeskUpstage` upstage | **yes** |
    /// | pod rigs | on that desk, `deskTopLift` above it | **yes** |
    /// | camera-facing desk | `deskDepth` downstage | no |
    /// | desktop kit | on a camera-facing desk | no |
    /// | chair | `awayChairStandoff` downstage | no |
    /// | station prop | the seat's own row, a tile to its left | no, and it is exactly a tile, so it does not reach the column either |
    ///
    /// The four that do not count are the occluders a seat is deliberately
    /// composed *behind* [ADR-008], and a route to that seat has to pass them or
    /// the seat is unreachable. They are excluded by their own geometry rather
    /// than by name.
    ///
    /// ## What this costs
    ///
    /// An away-facing leaver's exit is 7 px rather than 96, so it fades where it
    /// sits instead of walking out the back: `Character.duration`'s 0.2 s floor
    /// is the whole of its departure. The room said the opposite until now:
    /// `theSeatsAlternateDepthAlongXWithoutMovingAnyColumn` asserted that the back
    /// row keeps two tiles of floor behind it to leave through, which stopped
    /// being true when the desk moved onto that floor and was simply not noticed.
    /// **There is no route that buys the walk back**: a lateral step out of the
    /// column has 16 px to work with between the desk's right edge (`x + 32`) and
    /// the column's own edge (`x + 48`) against a 32 px body, and a downstage exit
    /// meets a refill climbing the same column head-on, which is the argument
    /// `entranceRoute(forSeat:)` already rests on. So the floor is what it is, and
    /// what changed is that the room stops at it.
    public func upstageClearance(forSeat index: Int, metrics: SeatMetrics) -> Double {
        let seat = seatPosition(index)
        var ceiling = wallBaseY
        func consider(_ point: ScenePoint?, width: Double) {
            guard let point, point.y > seat.y,
                  abs(point.x - seat.x) < (Double(tile) + width) / 2 else { return }
            ceiling = min(ceiling, point.y - 1)
        }
        consider(deskPosition(index, metrics: metrics), width: metrics.deskInkWidth)
        for slot in PodRigSlot.allCases {
            consider(monitorPosition(index, slot: slot, metrics: metrics),
                     width: metrics.monitorInkWidth)
        }
        // The chair is not asked, and it is the one omission by name rather than
        // by the `point.y > seat.y` guard: `SeatMetrics` carries its height and
        // not its width, because nothing has ever needed the width. It is
        // `chairPosition(_:metrics:)`'s own arithmetic that makes the omission
        // safe: a side-on chair is *on* the seat's point and an away-facing one
        // is `awayChairStandoff` downstage of it, so neither is ever upstage, and
        // a camera-facing seat has none at all.
        return max(seat.y, ceiling)
    }

    /// The vertical strip the camera actually has to frame: from the bottom of
    /// the lowest nameplate to the top of the tallest badge.
    ///
    /// **Not `height`.** The room's nominal box is `rows * tile`: 192 px when
    /// this was written, 288 px now that the floor is seven rows deep, and the
    /// camera used to fit it. At the panel's 720×400 the consequence was that
    /// the strip where anything happens sat in the middle third with a flat band
    /// of wall above and a flat band of floor below, and `3x` was unreachable at
    /// any population because 192×3 does not fit in 400. Framing the strip
    /// instead puts one working agent at `3x` filling the panel, which is the
    /// case a glance surface exists for.
    ///
    /// The strip is no longer a thin one: seats sit on two rows, so it runs from
    /// a walkway character's plate to the **back** row's badge. See
    /// `isBackRow(seat:)`.
    ///
    /// **The split, measured against the shipped manifest**, because it is worth
    /// having in front of you before changing anything here:
    ///
    /// | | px |
    /// |---|---:|
    /// | badge slot above the feet | 51 |
    /// | nameplate below the feet | 13 |
    /// | the two seat rows | 64 |
    /// | the walkway | 32 |
    /// | the delivery row | 32 |
    /// | **content band** | **192** |
    ///
    /// A `2x` view of a 720×400 panel has 200 px of height, and 192 is inside it
    /// with 8 to spare. **It was 300, then 160.** The history is worth the four
    /// lines because the last two rows of this table were bought and sold twice:
    ///
    /// - M6f spent 96 px of delivery row (one row per ring) and 34 px of badge,
    ///   taking 300 to 170. The rows were floor the report beat reserved so that a
    ///   reporter walking to its anchor crossed nobody, and deleting them deleted
    ///   the walk.
    /// - `2806f5c` put the task on the plate (170 → 178) and `2caa864` cut the
    ///   plate to one row (178 → **160**), which is 40 px of headroom against
    ///   `2x`.
    /// - This change spends 32 of that 40 on **one** delivery row, shared by every
    ///   reporter rather than one per ring, and the walk is back. Three rows would
    ///   be 256 and does not fit; one does, with 8 px to spare.
    ///
    /// The layout's own share is 128 and cannot go lower without giving the walk
    /// back up: a room needs its two seat rows, one row of floor in front of them
    /// for people to arrive on and report from, and one row for the walk itself.
    /// See `deliveryPosition(anchorSeat:reporterSeat:)`. `RoomCamera.init` carries
    /// what the camera does with the result and
    /// `theBandFitsACloserScaleAndWidthDecidesWhoGetsIt` keeps these numbers
    /// honest. **Width is what holds the camera now**, not height: 192 still fits
    /// `2x`, and it is the seat pitch that says only three agents do.
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
        // The lowest plate belongs to a character on the **delivery row**: the
        // furthest downstage anyone ever stands, and the row a reporter walks
        // along to reach its anchor. It is `standingRows.first`, and it is
        // written that way so that a row added to the room is a row the camera
        // frames rather than a row it crops.
        // The highest pixel belongs to a character on the **back** seat row,
        // the furthest upstage anyone sits, and the row whose badge would be
        // cropped by a band measured from `baselineY`.
        ((standingRows.min() ?? aisleY) - plateDropBelowFeet,
         topSeatRowY + badgeTopAboveFeet)
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

    /// **The exclusion rule for the one row characters travel along**, as a
    /// number rather than as a policy: a plate plus the margin the lattice
    /// already clears by everywhere else.
    ///
    /// It is `minimumSeatSpacingTiles`' own `needed`: the seat pitch *before*
    /// it is rounded up to a whole tile, so the delivery row separates two
    /// reporters by the same amount the seat rows separate two neighbours, for
    /// the same reason, computed from the same two measurements. Two claims that
    /// clear each other by this leave their plates at least `tile − plateHeight`
    /// apart, which is 21 px at the shipped plate and is the bound
    /// `noAdversarialPairingOfBeatsEverTouchesTwoPlates` asserts against.
    public static func deliveryClearance(plateWidth: Int, plateHeight: Int, tile: Int) -> Double {
        Double(max(0, plateWidth) + max(0, max(1, tile) - max(0, plateHeight)))
    }
}

/// **Who is on the delivery row.**
///
/// The report walk crosses seat columns, so unlike every other route in this
/// room it cannot be made safe by `seatColumn` alone. This is what makes it
/// safe instead, and the thing to understand about it is that **it is not a
/// scheduler**: it grants a claim on a stretch of one row, refuses claims that
/// would overlap a live one, and never makes anybody wait. A reporter that is
/// refused plays `RoomLayout.inPlaceDeliveryRoute(reporterSeat:)` immediately,
/// the beat that shipped before this row existed, in its own column, where any
/// number of characters can be at once.
///
/// So there is no queue. Nothing is deferred, nothing accumulates, and the
/// answer to "what happens if it never drains" is that there is nothing to
/// drain. [I4]
///
/// **What can still go wrong is a claim that is never given back**: a callback
/// that does not fire, a character retired between two frames, and that is a
/// stuck *room* rather than a stuck character: the holder finishes its walk and
/// sits down normally, and only later reports are affected, and only by being
/// given the in-place beat. It is closed twice over anyway:
///
/// - `RoomScene` releases on the beat's own completion, and every frame drops
///   any claim whose character has stopped running a script or has left the
///   scene: the condition itself rather than a proxy for it;
/// - and `reap(at:)` drops a claim held past `budget`, which `RoomScene` sets to
///   twice the beat it is timing. A deadline is the reaper of last resort here,
///   not the mechanism, which is why it can afford to be generous.
///
/// **It is keyed by an opaque id, one per beat, not by seat and not by agent.**
///
/// A seat looks like the natural key and is the wrong one. A subagent goes
/// dormant on the same event that starts its report, which makes it the
/// longest-dormant character in the room and therefore the first candidate
/// `SceneDirector.settleSeats` evicts, so its seat can be handed to a new agent
/// while it is still several seconds from the end of its walk. Keyed by seat,
/// that new agent's own report would overwrite a claim whose holder is standing
/// in the corridor. A per-beat id has no such collision, and it keeps this type
/// free of `SpriteRoomCore` so it unit-tests as arithmetic.
public struct DeliveryFloor: Sendable, Hashable {

    public struct Claim: Sendable, Hashable {
        public var corridor: ClosedRange<Double>
        /// How long this claim may be held before `reap(at:)` takes it back.
        public var budget: TimeInterval
        /// When the clock first saw it. `nil` until the first `reap(at:)` after
        /// the claim, so the floor never has to be told what time it is at claim
        /// time and cannot mis-reap against an unstarted clock: `RoomScene`'s
        /// clock is the render loop's, whose origin is system uptime.
        public var startedAt: TimeInterval?
    }

    /// How far two claims must clear each other.
    /// [`RoomLayout.deliveryClearance(plateWidth:plateHeight:tile:)`]
    public let clearance: Double
    private var claims: [Int: Claim] = [:]

    public init(clearance: Double) { self.clearance = max(0, clearance) }

    public var occupiedIDs: Set<Int> { Set(claims.keys) }
    public func claim(id: Int) -> Claim? { claims[id] }
    public var isEmpty: Bool { claims.isEmpty }

    /// Whether `corridor` clears every live claim except `id`'s own.
    ///
    /// A re-claim under an id that already holds the row is always allowed: it
    /// is the same beat being restarted, and a beat is one character.
    public func admits(corridor: ClosedRange<Double>, forID id: Int) -> Bool {
        for (held, claim) in claims where held != id {
            let gap = max(corridor.lowerBound - claim.corridor.upperBound,
                          claim.corridor.lowerBound - corridor.upperBound)
            if gap < clearance { return false }
        }
        return true
    }

    /// Take the stretch if it is free. `false` means the caller plays the
    /// in-place beat: it does **not** mean "try again later", and there is no
    /// later to try at.
    @discardableResult
    public mutating func claim(
        id: Int, corridor: ClosedRange<Double>, budget: TimeInterval
    ) -> Bool {
        guard admits(corridor: corridor, forID: id) else { return false }
        claims[id] = Claim(corridor: corridor, budget: max(0, budget), startedAt: nil)
        return true
    }

    public mutating func release(id: Int) { claims[id] = nil }
    public mutating func releaseAll() { claims.removeAll() }

    /// Drops every claim held past its budget and returns their ids.
    ///
    /// The first call after a claim starts its clock rather than expiring it, so
    /// the floor is correct against any clock origin.
    @discardableResult
    public mutating func reap(at time: TimeInterval) -> [Int] {
        var expired: [Int] = []
        for (id, claim) in claims {
            guard let started = claim.startedAt else {
                claims[id]?.startedAt = time
                continue
            }
            if time - started >= claim.budget { expired.append(id) }
        }
        for id in expired { claims[id] = nil }
        return expired.sorted()
    }
}
