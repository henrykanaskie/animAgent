import Foundation

/// **An authored floor plan: the room drawn as a building rather than as a
/// stage.** [ADR-007]
///
/// `RoomLayout` says where people stand and walk; this says what the floor they
/// stand on is made of and where its walls are. The two are deliberately
/// separate types because they answer to different authorities: every number in
/// `RoomLayout` is derived from a nameplate, a body or a route and may not be
/// authored, and every number in here **is** authored — by somebody who looked
/// at `scripts/compose-scene.py`'s renders — and may not move a route.
///
/// ## What a plan may not do
///
/// The room's routes are the fixed point and the plan is fitted around them, in
/// exactly that order:
///
/// - every seat keeps a clear column from `deliveryRowY` to `wallBaseY`, because
///   `entranceRoute`, `homeRoute` and `upstageExit` are all "straight up its own
///   column";
/// - the delivery row keeps a clear lateral corridor across the whole width;
/// - nothing is drawn nearer the camera than the seat row **inside the span the
///   cast travels**. Beyond the outermost seat column there are no routes at
///   all, and that is where the building's own outer wall stands — it has to run
///   the full depth of the floor or it is a wall with a gap in it where the
///   camera is looking. [ADR-013]
///
/// `RoomPlan.routeViolations(in:)` is those three sentences as a function, and
/// `RoomPlanTests` runs it over the shipped plan. A plan that fails it is a bug
/// in the plan, not in the room.
///
/// ## Why it is manifest data
///
/// Because the alternative is a theme name in `Sources/`, which ADR-002 §8
/// item 5 forbids and a test asserts the absence of. The plan arrives through
/// `Manifest.Room.plan` like every other piece of art in this project, so a
/// second plan — or a redrawn first one — is a manifest swap with no code in it.
///
/// ## The vocabulary, measured off the pack's own rooms
///
/// `docs/06-SET-BUILDING.md` §2, which measured
/// `Modern_Office_Revamped_v1.2/6_Office_Designs/Office_Design_2.gif`:
///
/// - a **space** is a rect, not "a wall band across the top";
/// - its north wall is exactly **two tiles**, a *cap* tile carrying a 12 px
///   floor-plan line over 20 px of face and a *body* tile carrying 30 px more
///   face over a 2 px baseboard;
/// - a **doorway** is a gap cut clean through the band, with the floor showing
///   through — nothing is drawn in it;
/// - a **partition** is a 14 px floor-plan line, 2 px dark / 10 px light / 2 px
///   dark, drawn flat.
///
/// The one thing this file inverts is the axis: `compose-scene.py` draws a plan
/// y-down, so a space's wall is at the top of its rect and the space beyond it
/// is *above*. Here y is up, so a space's wall is at the **top of its own rect
/// in scene pixels** and the space beyond it stands upstage of that. Same
/// picture, opposite sign, and the sign is why `wallRowsFromTop` exists rather
/// than a comment saying "remember to flip it".
public struct RoomPlan: Sendable, Hashable {

    /// How many tile rows of a space's rect its north wall eats. Two, because
    /// the pack draws a cap and a body and nothing else. **A space's rect is not
    /// its floor** — the mistake `06-SET-BUILDING.md` §2 calls "the consequence
    /// people get wrong".
    public static let wallRowsFromTop = 2

    /// The dark skirting at the bottom of a body tile, in px. Measured in
    /// `Office_Design_2.gif` at x=200: the band's bottom 2 rows.
    public static let baseboardPx = 2
    /// The white floor-plan line at the top of a cap tile, in px. Same
    /// measurement: 2 px dark, 8 px white, 2 px dark.
    public static let planLinePx = 12
    /// How wide a vertical floor-plan line is. 2 px dark, 10 px light, 2 px
    /// dark, straddling the tile boundary.
    public static let partitionPx = 14

    /// One finish: a floor and the two tiles of the wall that stands on it.
    ///
    /// `lineEdge` and `lineFill` are the two colours of the floor-plan line,
    /// **measured from `cap` by `scripts/build-manifest.py`** rather than typed
    /// in here. The pack ships no free-standing line tile that survives the
    /// import pass — every plain run, every T and every jamb is a 12 or 14 px
    /// stripe on an otherwise transparent tile, and `process-assets.py` drops
    /// anything under 60% opaque because a mostly-transparent tile laid as floor
    /// would show the void. So the partitions are drawn from the cap tile's own
    /// two inks, which is the same relationship the accent hues have to the
    /// palette: the manifest says the colour, the scene draws the shape.
    public struct Surface: Sendable, Hashable {
        public let id: String
        public let floor: String
        public let cap: String
        public let body: String
        public let lineEdge: Bitmap.RGBA
        public let lineFill: Bitmap.RGBA

        public init(
            id: String, floor: String, cap: String, body: String,
            lineEdge: Bitmap.RGBA, lineFill: Bitmap.RGBA
        ) {
            self.id = id
            self.floor = floor
            self.cap = cap
            self.body = body
            self.lineEdge = lineEdge
            self.lineFill = lineFill
        }
    }

    /// One room of the plan, in **tile** units, y-up, on `RoomLayout`'s own grid.
    ///
    /// `h` counts the whole rect including the two wall rows at its top, which
    /// is `compose-scene.py`'s convention and the one the set-building doc is
    /// written in. `floorRows` is the part anything may stand on.
    public struct Space: Sendable, Hashable {
        public let name: String
        public let surface: String
        public let x: Int, y: Int, w: Int, h: Int
        /// Absolute tile columns where the north band is cut through. A doorway
        /// shows this space's own floor — step 1 lays it across the whole rect —
        /// so nothing is drawn in the gap. [06-SET-BUILDING §2]
        public let doorways: [Int]
        /// Whether this space draws a north wall at all. A space with no band is
        /// an open extension of whatever stands upstage of it.
        public let hasBand: Bool

        public init(
            name: String, surface: String, x: Int, y: Int, w: Int, h: Int,
            doorways: [Int] = [], hasBand: Bool = true
        ) {
            self.name = name
            self.surface = surface
            self.x = x; self.y = y; self.w = w; self.h = h
            self.doorways = doorways.sorted()
            self.hasBand = hasBand
        }

        /// The tile rows a person or a prop could stand on.
        public var floorRows: Range<Int> {
            y..<(y + max(0, h - (hasBand ? RoomPlan.wallRowsFromTop : 0)))
        }
        /// `(body, cap)` tile rows, low to high. `nil` when the space has none.
        public var bandRows: (body: Int, cap: Int)? {
            guard hasBand, h >= RoomPlan.wallRowsFromTop else { return nil }
            return (y + h - 2, y + h - 1)
        }
        public var columns: Range<Int> { x..<(x + w) }
        public func isDoorway(column: Int) -> Bool { doorways.contains(column) }
    }

    /// A vertical floor-plan line between two spaces, in tile units. Horizontal
    /// boundaries are drawn by the north band and never by a line, because a
    /// wall you look at head-on shows its face. [06-SET-BUILDING §2]
    public struct Partition: Sendable, Hashable {
        /// The tile boundary the 14 px line straddles.
        public let x: Int
        /// Tile rows spanned, low to high inclusive-exclusive.
        public let y: Int, h: Int

        public init(x: Int, y: Int, h: Int) {
            self.x = x; self.y = y; self.h = h
        }
    }

    /// **One piece of the room's dressing, placed by hand.**
    ///
    /// The band system this stands beside gives every prop one of four depths
    /// and one of eight columns, which is 32 slots on a perfect lattice — and a
    /// lattice is what the room *looked* like: four horizontal stripes of
    /// objects across a floor that had nothing else on it. `compose-scene.py`'s
    /// engineering office puts 45 objects on a floor of the same size and none
    /// of them share a row, because the gaps between clusters are the thing
    /// that reads as a room rather than as a shelf.
    ///
    /// So a placement carries **its own x and y**. `scenery` indexes the
    /// theme's own ordered scenery list — the same list and the same order the
    /// bands walk — and `what` echoes that entry's description so a reorder of
    /// the list shows up as a named mismatch in `dressingViolations` instead of
    /// as the wrong object quietly standing in the right place.
    ///
    /// `x` is the centre of the prop's content box and `y` its bottom, in room
    /// pixels, y-up, on `RoomLayout`'s grid — the same convention every other
    /// point in the scene uses, so `Character.Layer.rowDepth` sorts a hand-placed
    /// prop against the cast with no special case.
    ///
    /// **It buys no new licence.** The three route clauses the band system
    /// satisfied by construction, a hand-placed prop has to satisfy by
    /// assertion, and `dressingViolations(in:boxes:)` is that assertion.
    /// **Which object a placement draws.** A named prop role — the same four the
    /// theme already binds for a seat, of which `board` and `plant` are the two
    /// the decoration system used to stand on its own lattice — or an index into
    /// the theme's ordered scenery list. A hand-placed room places *all* of its
    /// dressing, so it needs to reach both pools.
    public enum Piece: Sendable, Hashable {
        case role(String)
        case scenery(Int)
    }

    public struct Dressing: Sendable, Hashable {
        public let piece: Piece
        public let x: Int
        public let y: Int
        public let what: String

        public init(piece: Piece, x: Int, y: Int, what: String = "") {
            self.piece = piece
            self.x = x; self.y = y
            self.what = what
        }
    }

    public let spaces: [Space]
    public let surfaces: [String: Surface]
    public let partitions: [Partition]
    /// Hand-placed dressing, in draw order. Empty for every theme that still
    /// takes the four bands, which is the default and not a degraded state.
    public let dressing: [Dressing]

    public init(
        spaces: [Space], surfaces: [String: Surface], partitions: [Partition] = [],
        dressing: [Dressing] = []
    ) {
        self.spaces = spaces
        self.surfaces = surfaces
        self.partitions = partitions
        self.dressing = dressing
    }

    /// **No plan: the open floor this app drew for eight milestones.** Five of
    /// the six themes still take it, and it is not a degraded state — a theme
    /// whose builder sheet has one floor tile and one wall tile cannot be drawn
    /// as a plan and should not pretend to be. [ADR-007 §6]
    public static let open = RoomPlan(spaces: [], surfaces: [:])

    public var isEmpty: Bool { spaces.isEmpty || surfaces.isEmpty }

    public func surface(_ id: String) -> Surface? { surfaces[id] }

    /// Every manifest path the plan draws. Read by the art gate, so a plan that
    /// names a tile nobody shipped is a missing-art failure rather than a room
    /// with a hole in it.
    public var declaredPaths: Set<String> {
        Set(surfaces.values.flatMap { [$0.floor, $0.cap, $0.body] })
    }

    /// The space a tile belongs to, or `nil` for a tile the plan does not cover.
    /// First match wins, so a plan whose spaces overlap draws the earlier one —
    /// which `overlappingSpaces` reports rather than leaving to chance.
    public func space(atTileX x: Int, tileY y: Int) -> Space? {
        spaces.first { $0.columns.contains(x) && (($0.y)..<($0.y + $0.h)).contains(y) }
    }

    /// The highest tile row the plan paints. The camera aims to keep it in
    /// frame, and everything above it is the surround.
    public func topRow() -> Int? { spaces.map { $0.y + $0.h - 1 }.max() }

    /// The tile columns of every doorway in every space, deduplicated.
    public var doorwayColumns: Set<Int> {
        Set(spaces.flatMap(\.doorways))
    }

    // MARK: What a plan must not break

    /// **Every way this plan could stand in somebody's way**, as strings, empty
    /// when it stands in nobody's.
    ///
    /// It is written as a check rather than as a comment because the three
    /// clauses are the whole reason the plan is authored around the lattice
    /// instead of the other way round, and because the failure it prevents —
    /// a character walking through a wall — is invisible in a still.
    ///
    /// The three clauses, each with the route it protects:
    ///
    /// 1. **A seat column is clear of solid wall from the delivery row to the
    ///    wall line.** `entranceRoute`, `homeRoute` and `upstageExit` are all
    ///    vertical inside one column. A north band across a seat column is
    ///    admissible **only** where it is cut by a doorway — which is what the
    ///    doorways in the shipped plan are for and why they sit exactly on seat
    ///    columns.
    /// 2. **The delivery row is clear across the whole width.** It is the one
    ///    row a character travels *along*, so a partition crossing it would
    ///    close the corridor. Partitions in the shipped plan stand entirely
    ///    upstage of the seat rows.
    /// 3. **Nothing is drawn nearer the camera than the front seat row.** The
    ///    rule that replaced M5's foreground row. A plan may extend its floor
    ///    downstage as far as it likes — floor is not a thing drawn *in front
    ///    of* anybody — but a band or a partition there would be.
    public func routeViolations(in layout: RoomLayout) -> [String] {
        var out: [String] = []
        let tile = layout.tile

        for seat in 0..<layout.seatCapacity {
            let column = Int((layout.seatPosition(seat).x - Double(tile) / 2).rounded()) / tile
            let lowRow = Int((layout.deliveryRowY / Double(tile)).rounded(.down))
            let highRow = Int((layout.wallBaseY / Double(tile)).rounded(.down))
            for space in spaces {
                guard let band = space.bandRows, space.columns.contains(column) else { continue }
                for row in [band.body, band.cap] where (lowRow..<highRow).contains(row) {
                    if !space.isDoorway(column: column) {
                        out.append(
                            "seat \(seat)'s column \(column) is walled by '\(space.name)' "
                            + "at row \(row) with no doorway")
                    }
                }
            }
            for partition in partitions {
                let left = Double(partition.x * tile) - 7, right = Double(partition.x * tile) + 7
                let body = layout.seatPosition(seat).x
                if right > body - Double(tile) / 2, left < body + Double(tile) / 2 {
                    for row in partition.y..<(partition.y + partition.h)
                    where (Double(row * tile) < layout.wallBaseY) {
                        out.append(
                            "a partition at x=\(partition.x) stands in seat \(seat)'s column "
                            + "at row \(row)")
                    }
                }
            }
        }

        let frontRow = layout.baselineY
        for partition in partitions {
            // **Clause 3 binds a partition inside the span characters travel.**
            // [ADR-013]
            //
            // It used to be positional: any partition reaching downstage of the
            // front seat row was rejected, full stop. That is right for every
            // partition the plan had, and wrong for the one it needs — the
            // building's own outer wall, which has to run the full depth of the
            // floor or it is a wall with a gap where the camera is looking.
            //
            // **The exemption is "outside the travel span", and the first thing
            // tried was "clear of every seat body", which is wrong.** Clause 2
            // is that the delivery row is clear across the whole width, because
            // it is the one row a character moves *along*: a reporter walking
            // from seat 6's column to seat 0's crosses every lane between them.
            // A partition standing in one of those lanes touches no seat and
            // closes the corridor anyway.
            // `RoomPlanTests.aPartitionAcrossTheDeliveryCorridorIsCaught` is
            // that case and it is what refuted the first rule.
            //
            // So the test is whether the line falls outside the whole lateral
            // reach of the cast — beyond the outermost seat column plus half a
            // body, where no route of any kind goes. The plan's edges do; the
            // interior partitions between the back rooms do not, and they are
            // upstage of the seat row anyway, so nothing that passed before
            // stops passing.
            let seatXs = (0..<layout.seatCapacity).map { layout.seatPosition($0).x }
            let travelLow = (seatXs.min() ?? 0) - Double(tile) / 2
            let travelHigh = (seatXs.max() ?? 0) + Double(tile) / 2
            let left = Double(partition.x * tile) - 7
            let right = Double(partition.x * tile) + 7
            let insideTravelSpan = right > travelLow && left < travelHigh
            let lowY = Double(partition.y * tile)
            if lowY < frontRow, insideTravelSpan {
                out.append(
                    "a partition at x=\(partition.x) reaches y=\(Int(lowY)), "
                    + "nearer the camera than the seat row at \(Int(frontRow)), "
                    + "inside the span characters travel")
            }
        }
        for space in spaces {
            guard let band = space.bandRows else { continue }
            if Double(band.body * tile) < frontRow {
                out.append(
                    "'\(space.name)' puts a wall band at y=\(band.body * tile), "
                    + "nearer the camera than the seat row at \(Int(frontRow))")
            }
        }

        for (index, one) in spaces.enumerated() {
            for other in spaces[(index + 1)...] where overlaps(one, other) {
                out.append("'\(one.name)' and '\(other.name)' cover the same tiles")
            }
        }
        for space in spaces where surfaces[space.surface] == nil {
            out.append("'\(space.name)' names surface '\(space.surface)', which is not declared")
        }
        for space in spaces {
            for column in space.doorways where !space.columns.contains(column) {
                out.append("'\(space.name)' cuts a doorway at column \(column), outside its rect")
            }
        }
        return out
    }

    /// **Every way this plan's hand-placed dressing could stand in somebody's
    /// way, or in its own**, as strings, empty when it stands in nobody's.
    ///
    /// The band system earned its route safety structurally: `sceneryColumns` is
    /// *defined* as the gaps between the seat columns, so a banded prop could
    /// not be in a corridor however badly it was authored. A hand-placed prop
    /// can be anywhere, so the same three clauses are checked here instead —
    /// `RoomPlanTests` runs this over the shipped plan for the same reason it
    /// runs `routeViolations`, and a placement that fails is a bug in the
    /// placement rather than a licence to move a route.
    ///
    /// 1. **Nothing nearer the camera than the front seat row.** Clause 3 of
    ///    `routeViolations`, which that function states for bands and partitions
    ///    and which binds a prop just as hard: a bin in front of the front row
    ///    is a bin drawn over somebody's legs.
    /// 2. **Nothing in a seat's column.** Every seat's column is a corridor from
    ///    the delivery row to the wall line, walked by `entranceRoute`,
    ///    `homeRoute` and `upstageExit`. A prop clears it when its box clears one
    ///    tile centred on the seat. Wall props — anything whose base stands at or
    ///    above `wallBaseY` — are exempt, because a leaver's feet stop at that
    ///    line and it passes under them; that is the same exemption the `wall`
    ///    band has always had.
    /// 3. **Nothing is drawn on top of something it hides.** A placement whose
    ///    box is wholly inside the box of a nearer one is a prop nobody will see,
    ///    which is `compose-scene.py`'s `report_hidden` as a rule rather than as
    ///    a printout.
    ///
    /// And two that are about the manifest rather than the room: an index past
    /// the end of the scenery list, and a `what` that no longer matches the entry
    /// it indexes — the tripwire for somebody reordering the list under a
    /// placement.
    public func dressingViolations(
        in layout: RoomLayout,
        resolve: (Piece) -> (what: String, width: Int, height: Int)?
    ) -> [String] {
        var out: [String] = []
        let tile = Double(layout.tile)

        struct Box { let x0: Double, x1: Double, y0: Double, y1: Double }
        var boxes: [(index: Int, box: Box)] = []

        for (n, item) in dressing.enumerated() {
            guard let entry = resolve(item.piece) else {
                out.append("dressing[\(n)] names \(item.piece), which the theme does not bind")
                continue
            }
            let label = "dressing[\(n)] '\(item.what.isEmpty ? entry.what : item.what)'"
            if !item.what.isEmpty, !entry.what.hasPrefix(item.what) {
                out.append(
                    "\(label) names \(item.piece), which is "
                    + "'\(entry.what)' — the list moved under the placement")
            }
            let halfWidth = Double(entry.width) / 2
            let x = Double(item.x), y = Double(item.y)

            if y < layout.baselineY {
                out.append(
                    "\(label) stands at y=\(item.y), nearer the camera than the "
                    + "seat row at \(Int(layout.baselineY))")
            }
            if y < layout.wallBaseY {
                for seat in 0..<layout.seatCapacity {
                    let seatX = layout.seatPosition(seat).x
                    if abs(x - seatX) < (tile + Double(entry.width)) / 2 {
                        out.append(
                            "\(label) reaches into seat \(seat)'s column at "
                            + "x=\(Int(seatX)), which is a corridor")
                    }
                }
            }
            boxes.append((n, Box(
                x0: x - halfWidth, x1: x + halfWidth,
                y0: y, y1: y + Double(entry.height))))
        }

        // **Every ordered pair, not just the ones later in the list.** What
        // paints over what is decided by `Character.Layer.rowDepth(y)` and not
        // by declaration order, so a burying prop declared *earlier* buries
        // just as completely. The first draft of this loop scanned
        // `boxes[(i + 1)...]` and would have missed exactly half the cases —
        // and silently, because a hidden prop looks like a prop nobody placed.
        for one in boxes {
            for other in boxes
            where other.index != one.index
                && other.box.y0 < one.box.y0
                && other.box.x0 <= one.box.x0 && other.box.x1 >= one.box.x1
                && other.box.y1 >= one.box.y1 {
                out.append(
                    "dressing[\(one.index)] is wholly hidden behind "
                    + "dressing[\(other.index)]")
            }
        }
        return out
    }

    private func overlaps(_ a: Space, _ b: Space) -> Bool {
        a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    }
}
