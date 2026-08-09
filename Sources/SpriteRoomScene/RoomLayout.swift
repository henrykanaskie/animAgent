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
    /// **How many seats exist. Not a soft limit.**
    ///
    /// `seatColumn` and `ring` both wrap mod this number, so seat 7 resolves to
    /// seat 0's column *and* — because the two-row fold keys on ring parity —
    /// seat 0's row. That is a total overlap, not a near miss: two characters
    /// drawn on one spot, and a room that says seven when eight agents are
    /// running. It is the room asserting a false number [I1] and it is S5, the
    /// criterion this product is for, failing.
    ///
    /// **The number cannot be raised.** At `1x` — the only scale the app uses —
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
    /// no `s` does — a 96 px pitch is not two plates wide. Half a pitch is 48.
    ///
    /// (Three numbers have been written in this file for that plate: 65 when the
    /// headline was one line, 77 when it was twelve glyphs, 71 since the limit
    /// was cut to eleven. It is measured — `SceneBitmaps.maximumNameplateWidth`
    /// — and every test that depends on it asks the measurement rather than the
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
    /// sit in the overflow indefinitely — the room drawing six sleepers and
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
    /// one that is negotiable — see `minimumSeatSpacingTiles(plateWidth:
    /// plateHeight:tile:)`, which is the pitch stated as a function of the plate
    /// rather than as the constant 3.
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
        // **Seven floor rows, not four.** The room is drawn at `1x` whatever the
        // population, so the panel is a 720×400 window on it and the only
        // question composition can ask is what is inside that window. With four
        // floor rows the wall began at y=128 and everything above the tallest
        // badge — 36% of the panel — was flat wall with nothing on it, because a
        // wall tile is an authored flat field (the pack's own wall tiles seam
        // every 32 px when repeated) and no pack we own draws anything that
        // hangs on one.
        //
        // Three more floor rows turn that dead band into *floor*, which is
        // something objects can stand on: the back seat row, a mid-depth accent
        // band, and the backdrops standing against the wall. The wall keeps a
        // deliberate 84 px of the frame — enough to read as a wall, not enough
        // to be the subject.
        self.rows = 9
        self.wallRows = 2
    }

    /// **The seat pitch as a function of the nameplate, in tiles.**
    ///
    /// The pitch has never been a composition number. It is 96 px because the
    /// widest plate the font can produce is 71 px, and two characters whose
    /// plates overlap are two characters the room cannot tell apart — which is
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
    /// | two plates on one row — two reporters on the walkway | `W + m` |
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
    /// `tile − plateHeight` = 6 px, which is the bound
    /// `noAdversarialPairingOfBeatsEverTouchesTwoPlates` pins. Using the same
    /// number across means the room clears by the same amount in both axes.
    ///
    /// It returns **3** for every plate the room has yet had — 71 × 26 when this
    /// was derived, 63 × 21 as the plate stands — so stating it costs nothing
    /// today. The threshold worth knowing is where it returns **2**, a 64 px
    /// pitch and a room a third narrower: `plateWidth + tile − plateHeight ≤ 64`.
    /// At the plate's current 21 px height that is a width of **53 px or less**;
    /// at 26 px it was 58. The height matters because the margin is borrowed
    /// from the row axis, so a shorter plate buys width as well as height.
    ///
    /// **It is not wired to the default.** `RoomLayout()` still declares 3, and
    /// `theSeatPitchIsTheNarrowestTheseNameplatesAllow` is the tripwire that
    /// fails when the declared pitch and this formula disagree. Deriving the
    /// default would reflow the desks, the station props and the decoration
    /// columns the instant the plate moved, and those clearances are argued from
    /// content boxes in the manifest rather than from this file — they have to be
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
    /// tall and nine when it became nine — and the field then reached past the
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
    /// It is the front of the room and the only floor downstage of the seats:
    /// every character reaches its chair from it, every character that leaves
    /// mid-beat comes back through it, and a reporter steps out onto it to hand
    /// its report over. What nobody does is *travel along* it — see
    /// `deliveryPosition(anchorSeat:reporterSeat:)`, which is where the rule
    /// that makes this safe is stated and proved.
    public var aisleY: Double { baselineY - Double(tile) }

    // MARK: The lattice [the aisle invariant]

    /// How far a seat sits from the centre, counted in seat pitches. Seat 0 is
    /// 0; seats 1 and 2 are 1; 3 and 4 are 2; and so on, because seats fill
    /// outward in pairs.
    ///
    /// Two seats of the same ring are on **opposite sides** of the room, and two
    /// seats of different rings are at least one pitch apart in x. Its parity is
    /// what picks a seat's row — see `isBackRow(seat:)`.
    ///
    /// It used to pick one more thing: a reporter's own delivery row, one row of
    /// floor per ring reserved in front of the walkway. Those rows are gone and
    /// so is the ring's part in the clearance argument; see
    /// `deliveryPosition(anchorSeat:reporterSeat:)`.
    public func ring(ofSeat index: Int) -> Int {
        let wrapped = ((index % seatCapacity) + seatCapacity) % seatCapacity
        return (wrapped + 1) / 2
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

    /// **Which of the two rows a seat is on: its ring's parity.**
    ///
    /// This is not a new rule bolted onto the lattice — it is the lattice read
    /// one column further. Seats fill outward in pairs, so consecutive rings are
    /// consecutive columns on alternating sides, and *ring parity along x is
    /// perfect alternation*: columns in x order are seats 6, 4, 2, 0, 1, 3, 5 —
    /// rings 3, 2, 1, 0, 1, 2, 3. Sending odd rings upstage therefore puts the
    /// rows in a checkerboard, every occupied column differing in depth from
    /// both its neighbours.
    ///
    /// **Nothing the lattice proves has to be re-proved, and that is the whole
    /// reason the row is keyed on the ring.** Every clearance argument in this
    /// file rests on one number — *any two seats are at least a seat pitch apart
    /// in x* — and folding the row does not touch x at all. `seatColumn` is
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
    /// own column — that is not an incidental choice, it is the property every
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
    /// can move** — see `minimumSeatSpacingTiles(plateWidth:tile:)`, which is
    /// what ties them together — but they move in lockstep, because the pitch is
    /// derived from the plate: a pitch is one plate wide plus a margin, never
    /// two. So there is no plate width at which a stagger opens up.
    ///
    /// **What that leaves is one seat per column**, so the room's occupied width
    /// is `(seats − 1) × 96` plus the padding `occupiedSpan` adds, and the only
    /// way to narrow it is to seat fewer agents. `RoomCamera` carries what a
    /// `2x` frame could actually hold, which is three of them — and the shipped
    /// panel cannot hold three either, on height. The two seat rows bought
    /// depth: a room that reads as a place rather than a queue, and a badge line
    /// that does not sit on a neighbour's plate. They did not buy width and no
    /// arrangement of them can.
    public func isBackRow(seat index: Int) -> Bool {
        !ring(ofSeat: index).isMultiple(of: 2)
    }

    /// Whether the room has a seat for `index` — every position function below
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
        ScenePoint(x: seatPosition(index).x + Double(tile) * 0.875, y: seatRowY(index))
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
    /// It is on its seat's **own** row, so it is furniture beside the character
    /// rather than decoration in front of the characters — the rule that
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
    ///   seven — an *accent* column, so the backdrops are a full seat pitch
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
    /// nearer the camera than the seat row" — see `RoomScene.buildRoom`.
    public var overflowPlatePosition: ScenePoint {
        ScenePoint(x: propColumnX(forSeat: 0), y: wallBaseY + Double(tile))
    }

    public var seatedFacing: Facing { .right }

    /// Where a reporting subagent stands to deliver: out of its chair, one row
    /// downstage onto the walkway, still in its own column.
    public var deliveryPosition: ScenePoint {
        deliveryPosition(anchorSeat: 0, reporterSeat: 2)
    }

    /// **Which side of its anchor a reporter is on.**
    ///
    /// This used to choose where the reporter walked *to*: its own side of the
    /// anchor rather than the far one, so that a round trip did not cross the
    /// anchor's chair twice. Nobody walks to the anchor any more, so it no longer
    /// chooses anything — it reads off where the reporter already sits, and its
    /// one consumer is `deliveryFacing(side:)`. Seat 0 sits on the centre line
    /// and is the anchor rather than a reporter, so the tie goes right and is
    /// never reached. [see `deliveryPosition(anchorSeat:reporterSeat:)`]
    public func deliverySide(anchorSeat: Int, reporterSeat: Int) -> Facing {
        seatPosition(reporterSeat).x >= seatPosition(anchorSeat).x ? .right : .left
    }

    /// **Where a reporter stands to hand its report over: out of its chair, one
    /// row downstage onto the walkway, in its own column. It never goes to the
    /// anchor at all.**
    ///
    /// ## The rule this is an instance of
    ///
    /// > **No character ever moves sideways.** Every leg of every route in this
    /// > room is vertical and inside the moving character's own seat column:
    /// > arriving (`entranceRoute`), stepping out to report (`deliveryRoute`),
    /// > coming home (`homeRoute`), leaving (`upstageExit`).
    ///
    /// Two plates can meet only if they share a horizontal strip **and** come
    /// within a plate width in x. Columns are one seat pitch apart — 96 px,
    /// `seatSpacingTiles * tile`, and `seatColumn` is what nothing in the
    /// choreography touches — and the widest plate is
    /// `SceneBitmaps.maximumNameplateWidth` = 71 px. So the horizontal
    /// separation between any two characters in this room is a **constant of the
    /// lattice**: 96 px between neighbours, 25 px clear of the plate, at every
    /// instant of every beat, for any population, any timing, any pairing. There
    /// is no phase to reason about because x never changes.
    ///
    /// The single exception is two characters in **one** column, which the room
    /// can produce exactly once: a seat is free the instant its occupant starts
    /// walking out, so a refill can begin while the leaver is still in the
    /// column. Both move upstage, so they are a convoy — same direction, same
    /// speed, the gap they start with is the gap they keep — and that is the
    /// argument `entranceRoute(forSeat:)` and `theWholeCastCanLeaveInOneFrame`
    /// already rest on, unchanged.
    ///
    /// ## What this replaced, and why it is a better argument
    ///
    /// The reporter used to *walk to the anchor*, and the whole floor plan was
    /// built round that one lateral leg. Because it crossed columns, it had to
    /// be given floor nobody else was standing on, and one row was not enough:
    /// three same-side reporters (seats 1, 3 and 5) can be walking at once, so
    /// it took **one delivery row per ring** — three rows, 96 px of depth
    /// reserved below the walkway. The proof then needed four separate parts:
    /// rows a tile apart cannot share a strip; a row carries one seat per side;
    /// the two sides stop a delivery gap short of centre; and a reporter's own
    /// column meets a lower ring's corridor outside it by a full pitch.
    ///
    /// Every part of that was about keeping one lateral leg out of everyone's
    /// way. Delete the leg and there is nothing left to separate — and the 96 px
    /// goes back to the camera. `contentBand` falls from **300 px to 204**,
    /// which is what a `2x` room is measured against.
    ///
    /// ## What it costs, plainly
    ///
    /// **The reporter no longer arrives at the anchor's desk.** A report used to
    /// say *who* it was to by ending up next to them; it now says it only by
    /// which way the reporter turns — `deliveryFacing(side:)` — so on the near
    /// side of the room a reporter to the main agent and a reporter to a nested
    /// parent further in turn the same way and are told apart by nothing. That
    /// is a real loss of information and it is recorded rather than dressed up.
    /// What is kept is the beat itself: the character genuinely stands up,
    /// steps to the front of the room, turns to the person it is reporting to,
    /// and hands something over — every frame of which traces to one real
    /// `reportDelivered`. [I1]
    ///
    /// The alternative that would have kept the walk was to serialise it: one
    /// shared row and a rule that at most one reporter is ever on it. That is
    /// 32 px rather than 96 and still leaves the band at 236, it makes the
    /// guarantee depend on a scheduler rather than on the lattice, and it puts a
    /// lateral corridor back across the one row every arrival steps through. It
    /// was weighed and rejected; the arithmetic is in `notes.md`.
    ///
    /// `anchorSeat` is whose seat the reporter delivers to — 0, the main agent,
    /// unless `tool_response.agentId` linked it to a parent that is still in the
    /// room. It reaches the facing and nothing else.
    public func deliveryPosition(anchorSeat: Int, reporterSeat: Int) -> ScenePoint {
        seatApproach(reporterSeat)
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

    /// **The report walk, as waypoints.** One leg, straight down the reporter's
    /// own column onto the walkway.
    ///
    /// It is still built here rather than at the call site, and still returned as
    /// a list rather than a point, because the *shape* is the guarantee and the
    /// shape is the thing a caller could get wrong. It used to be three legs —
    /// down to the aisle, down to the ring's delivery row, then sideways to the
    /// anchor — and the danger was a caller cutting the corner into a diagonal.
    /// The danger now is a caller reintroducing the sideways leg at all.
    public func deliveryRoute(anchorSeat: Int, reporterSeat: Int) -> [ScenePoint] {
        [deliveryPosition(anchorSeat: anchorSeat, reporterSeat: reporterSeat)]
    }

    /// The same route reversed: **one leg, straight up the character's own
    /// column, into its chair** — or no legs at all when it is already in it.
    ///
    /// It used to be three waypoints and `fromY` trimmed the ones a character
    /// was already above, because home could begin on a delivery row, on the
    /// walkway or in the chair. One waypoint is enough now: wherever a character
    /// is, it is in this column, so the segment from where it stands to its own
    /// seat is vertical whatever `fromY` was.
    ///
    /// **What `fromY` still decides is whether there is a leg at all**, and that
    /// turned out to be load-bearing rather than tidiness. A zero-length walk
    /// still costs `Character.duration`'s 0.2 s floor, and a leaver spends those
    /// 0.2 s standing still in a column that its replacement is already climbing
    /// — a seat is free the instant its occupant starts walking out. The dwell
    /// was free while the walk-in started up to 96 px below the seats; it is not
    /// free now that it starts one tile below, because 0.2 s at 72 px/s is 14 px
    /// of a 32 px convoy gap. `noAdversarialPairingOfBeatsEverTouchesTwoPlates`
    /// measured the two plates 8 px *inside* each other before this guard.
    public func homeRoute(forSeat index: Int, fromY: Double = -.greatestFiniteMagnitude)
    -> [ScenePoint] {
        fromY >= seatRowY(index) ? [] : [seatPosition(index)]
    }

    /// **The walk-in, as waypoints: straight up the character's own column,
    /// from the walkway into its chair.**
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
    /// **Nothing new has to be proved about the rows it crosses.** The route is a
    /// character ascending its own column, which is every other route in the room
    /// — see `deliveryPosition(anchorSeat:reporterSeat:)`. It began on the
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
    /// **Not `height`.** The room's nominal box is `rows * tile` — 192 px when
    /// this was written, 288 px now that the floor is seven rows deep — and the
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
    /// | nameplate below the feet | 23 |
    /// | the two seat rows | 64 |
    /// | the walkway | 32 |
    /// | **content band** | **170** |
    ///
    /// A `2x` view of a 720×400 panel has 200 px of height, and 170 is inside it
    /// with 30 to spare. **It was 300.** Two terms went, in the same pass and
    /// from opposite sides of the boundary this file draws: 96 px of delivery
    /// row, which was the layout's, and 34 px of badge, which was not. The
    /// layout's own share is 96 now and cannot go lower — a room needs its seats
    /// and it needs one row of floor in front of them for people to arrive on and
    /// report from.
    ///
    /// The 96 was one delivery row per ring, floor below the walkway that existed
    /// to keep one lateral corridor out of everyone's way; see
    /// `deliveryPosition(anchorSeat:reporterSeat:)`. `RoomCamera.init` carries
    /// what the camera does with the result and
    /// `theBandFitsACloserScaleAndWidthDecidesWhoGetsIt` keeps these numbers
    /// honest. **Width is what holds the camera now**, not height.
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
        // The lowest plate belongs to a character on the walkway — the only row
        // in the room nearer the camera than the seats, and the only place a
        // character can be that is not a chair.
        // The highest pixel belongs to a character on the **back** seat row —
        // the furthest upstage anyone sits, and the row whose badge would be
        // cropped by a band measured from `baselineY`.
        (aisleY - plateDropBelowFeet, topSeatRowY + badgeTopAboveFeet)
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
