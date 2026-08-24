import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The floor plan, and the three routes it may never cross.** [ADR-007]
///
/// Most of this suite is **ungated**, deliberately. A plan is geometry and the
/// manifest that declares it is tracked, so a fresh clone with no art on disk
/// can still answer "does the shipped plan wall somebody in", and that is the
/// question whose wrong answer is a character walking through a wall, which no
/// still frame shows and no palette lint can see.
///
/// **The plan's hand-placed dressing is checked here for the same reason.** The
/// band lattice earned its route safety structurally (`sceneryColumns` *is*
/// the gaps between the seat columns, so a banded prop could not be in a
/// corridor however badly it was authored) and a hand-placed prop can be
/// anywhere, so the three clauses have to be asserted instead.
/// `RoomPlan.dressingViolations(in:resolve:)` is those clauses as a function,
/// this suite runs it over the shipped composition, and the three tests under
/// "the check is not vacuous" make it fail on purpose. A validator that cannot
/// fail is not a check.
struct RoomPlanTests {

    /// **The richest floor plan in the manifest**, by space count.
    ///
    /// It resolved "the alphabetically-first theme with a non-empty plan",
    /// which named `office` for exactly as long as `office` was the only theme
    /// with a plan. The moment a second one had one, the helper silently
    /// pointed somewhere else, and because `orderedIDs` is `keys.sorted()`,
    /// **four of the five themes that wanted a plan could not have one**:
    /// `briefing`, `broadcast`, `library` and `mission_control` all sort before
    /// `office`, so giving any of them a single-band plan redirected every test
    /// below onto it and failed `theShippedPlanIsMoreThanOneRoom`. A theme was
    /// left on a worse room to satisfy a test's idea of which plan it was
    /// looking at. That is the second time a proxy in this suite has decided
    /// the art; the first was a pinned `board`/`plant` count.
    ///
    /// Resolving by **most spaces** says what the callers below actually mean
    /// (they want the multi-room plan, the one with doorways and partitions and
    /// more than one finish) and it keeps meaning it however many themes gain
    /// a plain wall band. It is also stable: `spaces.count` is a property of
    /// the plan rather than of where its theme lands in an alphabet.
    static func richestPlan() throws -> RoomPlan {
        let manifest = try Manifest.load(root: SceneFixtures.repositoryRoot)
        let plans: [RoomPlan] = manifest.themes.orderedIDs
            .compactMap { manifest.themes.theme($0)?.room.plan }
            .filter { !$0.isEmpty }
        let richest = plans.max(by: { $0.spaces.count < $1.spaces.count })
        return try #require(
            richest,
            "no theme in the manifest declares a floor plan, so this suite checks nothing")
    }

    /// The theme that dresses its room by hand, as the two things the dressing
    /// checks need: the typed room the pieces resolve against, and its id, which
    /// is what the prose below is looked up under.
    static func handPlacedTheme() throws -> (id: String, room: Manifest.Room) {
        let manifest = try Manifest.load(root: SceneFixtures.repositoryRoot)
        let found = manifest.themes.orderedIDs
            .compactMap { id in manifest.themes.theme(id).map { (id: id, room: $0.room) } }
            .first { !$0.room.plan.dressing.isEmpty }
        return try #require(
            found,
            "no theme places its dressing by hand, so the dressing checks check nothing")
    }

    /// **The prose the typed manifest drops, read back off the same file.**
    ///
    /// `Manifest.PropRole` keeps a path and a measured box and nothing else:
    /// nothing the app *draws* reads a `what`, so the typed view does not carry
    /// one. `dressingViolations` does read it (a placement's `what` is the
    /// tripwire for somebody reordering the scenery list underneath it) so the
    /// check needs the strings, and it reads them out of `assets/manifest.json`
    /// rather than writing them down here. A transcription in the test would
    /// move with the list it exists to catch moving.
    ///
    /// A theme inherits any pool it does not declare, so `room`'s entries are
    /// collected first and the theme's own are laid over them, which is the
    /// order `Manifest.roomBindings(_:context:inheriting:)` resolves them in.
    static func descriptions(theme id: String) throws
    -> (scenery: [String], roles: [String: String]) {
        let url = SceneFixtures.repositoryRoot
            .appending(path: "assets").appending(path: "manifest.json")
        let root = try #require(
            try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        func props(_ scope: Any?) -> [String: Any] {
            ((scope as? [String: Any])?["props"] as? [String: Any]) ?? [:]
        }
        let roomProps = props(root["room"])
        let themeProps = props((root["themes"] as? [String: Any])
            .flatMap { ($0["sets"] as? [String: Any])?[id] })

        let scenery = ((themeProps["scenery"] ?? roomProps["scenery"]) as? [[String: Any]] ?? [])
            .map { ($0["what"] as? String) ?? "" }
        var roles: [String: String] = [:]
        for source in [roomProps, themeProps] {
            for (name, raw) in (source["roles"] as? [String: Any]) ?? [:] {
                if let what = (raw as? [String: Any])?["what"] as? String { roles[name] = what }
            }
        }
        return (scenery, roles)
    }

    /// What `dressingViolations` asks of a theme, answered from the theme's own
    /// declarations: **the measured content box** for the size, and the
    /// manifest's own `what` for the name. Not a number in this file: the
    /// clause under test is about the manifest's contents, so the manifest is
    /// what the test reads.
    static func resolver(
        room: Manifest.Room, descriptions: (scenery: [String], roles: [String: String])
    ) -> (RoomPlan.Piece) -> (what: String, width: Int, height: Int)? {
        { piece in
            guard let prop = room.piece(piece) else { return nil }
            let what: String
            switch piece {
            case let .role(name):
                what = descriptions.roles[name] ?? ""
            case let .scenery(index):
                what = descriptions.scenery.indices.contains(index)
                    ? descriptions.scenery[index] : ""
            }
            return (what, prop.contentBox.width, prop.contentBox.height)
        }
    }

    // MARK: The three clauses

    /// **The shipped plan stands in nobody's way.**
    ///
    /// `routeViolations(in:)` is the three sentences ADR-007 is written under,
    /// as a function: a clear column per seat from the delivery row to the wall
    /// line, an unobstructed lateral corridor, and nothing drawn nearer the
    /// camera than the front seat row. This runs it over the plan the app
    /// actually ships.
    @Test func theShippedPlanStandsInNobodysWay() throws {
        let plan = try Self.richestPlan()
        let violations = plan.routeViolations(in: RoomLayout())
        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "; ")))
    }

    /// The check is not vacuous: a plan that walls a seat column **is** caught.
    ///
    /// Written because the shipped plan puts its only band at the wall line,
    /// where the exit already ends, so `routeViolations` returns empty for it,
    /// and a check that returns empty for everything is indistinguishable from
    /// one that returns empty because it works.
    @Test func aBandAcrossASeatColumnIsCaught() throws {
        let layout = RoomLayout()
        let surface = RoomPlan.Surface(
            id: "s", floor: "f", cap: "c", body: "b",
            lineEdge: Bitmap.RGBA(0, 0, 0), lineFill: Bitmap.RGBA(255, 255, 255))
        // A band at rows 3 and 4: y 96 to 160, between the front seat row and
        // the wall line, straight across every column.
        let walled = RoomPlan(
            spaces: [RoomPlan.Space(name: "bad", surface: "s", x: 0, y: 0, w: 25, h: 5)],
            surfaces: ["s": surface])
        let violations = walled.routeViolations(in: layout)
        // One complaint per seat per band row: a band is a cap and a body, and
        // both of them are in the way.
        #expect(violations.count == layout.seatCapacity * RoomPlan.wallRowsFromTop,
                Comment(rawValue:
                    "expected two complaints per seat, got \(violations.count): \(violations)"))

        // …and cutting a doorway on every seat column clears it, which is the
        // rule stated the other way up.
        let seatColumns = (0..<layout.seatCapacity).map {
            Int(layout.seatPosition($0).x - Double(layout.tile) / 2) / layout.tile
        }
        let doored = RoomPlan(
            spaces: [RoomPlan.Space(
                name: "ok", surface: "s", x: 0, y: 0, w: 25, h: 5, doorways: seatColumns)],
            surfaces: ["s": surface])
        #expect(doored.routeViolations(in: layout).isEmpty)
    }

    /// A partition reaching downstage of the seat row is caught, because the
    /// delivery row is the one row a character travels *along* and a wall on it
    /// closes the corridor.
    @Test func aPartitionAcrossTheDeliveryCorridorIsCaught() throws {
        let layout = RoomLayout()
        let surface = RoomPlan.Surface(
            id: "s", floor: "f", cap: "c", body: "b",
            lineEdge: Bitmap.RGBA(0, 0, 0), lineFill: Bitmap.RGBA(255, 255, 255))
        let plan = RoomPlan(
            spaces: [RoomPlan.Space(name: "ok", surface: "s", x: 0, y: 7, w: 25, h: 2)],
            surfaces: ["s": surface],
            partitions: [RoomPlan.Partition(x: 5, y: 0, h: 9)])
        let violations = plan.routeViolations(in: layout)
        #expect(violations.contains { $0.contains("nearer the camera") }, Comment(
            rawValue: "a partition running to the floor was not reported: \(violations)"))
    }

    /// **Every doorway is on a seat column**, which is why there are three of
    /// them and not three somewhere else: a character leaving walks straight up
    /// its own column into the wall line, and a doorway there is the difference
    /// between walking out of the room and dissolving into a flat wall.
    @Test func everyDoorwayIsOnASeatColumn() throws {
        let plan = try Self.richestPlan()
        let layout = RoomLayout()
        let seatColumns = Set((0..<layout.seatCapacity).map {
            Int(layout.seatPosition($0).x - Double(layout.tile) / 2) / layout.tile
        })
        #expect(!plan.doorwayColumns.isEmpty, "the plan cuts no doorway at all")
        for column in plan.doorwayColumns {
            #expect(seatColumns.contains(column), Comment(rawValue:
                "a doorway at column \(column) is on no seat column \(seatColumns.sorted())"))
        }
    }

    // MARK: The dressing the plan places by hand

    /// **The shipped composition stands in nobody's way.**
    ///
    /// 37 hand-placed props on the same floor the band lattice used to put 20
    /// on, and the whole of what they gave up by leaving the lattice is the
    /// structural guarantee that came with it. This is that guarantee bought
    /// back as an assertion: nothing downstage of the front seat row, nothing in
    /// any seat's column below the wall line, nothing wholly buried by something
    /// drawn over it, no index past the end of the scenery list, and no `what`
    /// that has come loose from the entry it names.
    ///
    /// Ungated, like the rest of this suite: the plan and the boxes are both in
    /// the tracked manifest, so a fresh clone with no art still answers the
    /// question whose wrong answer is a plant standing in the aisle.
    @Test func theShippedDressingStandsInNobodysWay() throws {
        let theme = try Self.handPlacedTheme()
        let prose = try Self.descriptions(theme: theme.id)
        let resolve = Self.resolver(room: theme.room, descriptions: prose)
        let dressing = theme.room.plan.dressing

        // The check is only as good as what it resolved, so what it resolved is
        // asserted first: every piece found its art, and every piece it found
        // came with the prose the mismatch clause compares against.
        for item in dressing {
            let entry = resolve(item.piece)
            #expect(entry != nil, Comment(rawValue:
                "\(theme.id) places \(item.piece) ('\(item.what)') which resolves to no art"))
            #expect(entry.map { !$0.what.isEmpty } ?? false, Comment(rawValue:
                "\(theme.id)'s \(item.piece) has no `what` in the manifest, so the clause that"
                + " catches a reordered scenery list has nothing to compare"))
        }
        #expect(dressing.contains { !$0.what.isEmpty }, Comment(rawValue:
            "no placement in \(theme.id) records what it is, so nothing pins the list order"))

        let violations = theme.room.plan.dressingViolations(in: RoomLayout(), resolve: resolve)
        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "; ")))
    }

    // MARK: The check is not vacuous

    /// A theme's two pools, invented.
    ///
    /// The sizes are chosen rather than measured, and that is the difference
    /// between these three tests and the one above: there, the manifest is the
    /// subject and its own numbers are what the clauses are asked about; here,
    /// the clauses are the subject and the sizes are the input somebody has to
    /// choose to aim a placement at one.
    static let invented: [RoomPlan.Piece: (what: String, width: Int, height: Int)] = [
        .role("bin"): ("waste bin", 20, 20),
        .scenery(0): ("water cooler", 20, 40),
        .scenery(1): ("vending machine", 40, 60),
        // Deliberately tiny: the "small prop on a large one" arm of
        // `aStackedPairIsCaughtAndASmallPropOnALargeOneIsNot` needs a piece that
        // cannot approach the coverage threshold however it is placed.
        .scenery(2): ("desk lamp", 10, 12),
    ]

    static func inventedResolve(_ piece: RoomPlan.Piece) -> (what: String, width: Int, height: Int)? {
        invented[piece]
    }

    /// One placement that breaks nothing, so that every violation the tests
    /// below report is the one they added.
    ///
    /// It stands on a **scenery column** (the gaps between the seat columns,
    /// which is where the lattice put everything) at a depth low enough for the
    /// corridor clause to actually run over it. A control that trivially skipped
    /// the clause under test would not be a control.
    static func cleanDressing(_ layout: RoomLayout, column: Double) -> RoomPlan.Dressing {
        RoomPlan.Dressing(
            piece: .role("bin"), x: Int(column),
            y: Int(layout.wallBaseY) - layout.tile, what: "waste bin")
    }

    static func plan(_ dressing: [RoomPlan.Dressing]) -> RoomPlan {
        RoomPlan(spaces: [], surfaces: [:], partitions: [], dressing: dressing)
    }

    /// **A placement in somebody's way is caught**: the two route clauses, each
    /// aimed at on its own.
    ///
    /// A seat's column is a corridor from the delivery row to the wall line:
    /// `entranceRoute` climbs it, `homeRoute` returns up it and `upstageExit`
    /// leaves by it, so a bin in it is a bin three routes walk through. And
    /// nothing may stand nearer the camera than the front seat row, which is the
    /// rule that replaced M5's foreground row and which binds a hand-placed prop
    /// exactly as hard as it binds a wall band.
    @Test func aDressingPlacementInSomebodysWayIsCaught() throws {
        let layout = RoomLayout()
        let columns = layout.sceneryColumns
        try #require(columns.count >= 2, "the room has no clear column to stand a control on")
        let control = Self.cleanDressing(layout, column: columns[0])
        #expect(Self.plan([control])
            .dressingViolations(in: layout, resolve: Self.inventedResolve).isEmpty,
                "the control is not clean, so the counts below mean nothing")

        let inTheCorridor = Self.plan([control, RoomPlan.Dressing(
            piece: .role("bin"), x: Int(layout.seatPosition(0).x),
            y: Int(layout.wallBaseY) - layout.tile, what: "waste bin")])
            .dressingViolations(in: layout, resolve: Self.inventedResolve)
        #expect(inTheCorridor.count == 1, Comment(rawValue:
            "a bin standing in seat 0's own column was reported \(inTheCorridor.count) times:"
            + " \(inTheCorridor)"))
        #expect(inTheCorridor.first?.contains("corridor") ?? false, Comment(rawValue:
            "\(inTheCorridor) does not say the column is a corridor"))
        #expect(inTheCorridor.first?.contains("dressing[1]") ?? false, Comment(rawValue:
            "\(inTheCorridor) does not name the placement that is in the way"))

        let downstage = Self.plan([control, RoomPlan.Dressing(
            piece: .role("bin"), x: Int(columns[0]),
            y: Int(layout.baselineY) - 1, what: "waste bin")])
            .dressingViolations(in: layout, resolve: Self.inventedResolve)
        #expect(downstage.count == 1, Comment(rawValue:
            "a bin one pixel downstage of the front seat row was reported"
            + " \(downstage.count) times: \(downstage)"))
        #expect(downstage.first?.contains("nearer the camera") ?? false, Comment(rawValue:
            "\(downstage) does not say it stands in front of the cast"))
    }

    /// **A placement the theme cannot draw, and a placement that has come loose
    /// from the list it indexes, are both caught.**
    ///
    /// The first is the silence `RoomScene.dressingPlacements` produces on its
    /// own: a piece that resolves to nothing is skipped, so a room missing a
    /// prop looks exactly like a room that was never asked for one. The second
    /// is the failure that has no symptom at all: reorder the scenery list and
    /// every placement still resolves, still draws and still stands somewhere
    /// plausible, with the wrong object in it. `what` is what makes that loud.
    @Test func aDressingPlacementTheThemeCannotDrawIsCaught() throws {
        let layout = RoomLayout()
        let columns = layout.sceneryColumns
        try #require(columns.count >= 2, "the room has no clear column to stand a control on")
        let control = Self.cleanDressing(layout, column: columns[0])

        let unbound = Self.plan([control, RoomPlan.Dressing(
            piece: .role("nothing_binds_this"), x: Int(columns[1]),
            y: Int(layout.wallBaseY), what: "a role no theme declares")])
            .dressingViolations(in: layout, resolve: Self.inventedResolve)
        #expect(unbound.count == 1, Comment(rawValue:
            "a placement naming an unbound role was reported \(unbound.count) times: \(unbound)"))
        #expect(unbound.first?.contains("does not bind") ?? false, Comment(rawValue:
            "\(unbound) does not say the theme cannot draw it"))

        // `.scenery(0)` is the water cooler; this placement says it is the
        // vending machine, which is `.scenery(1)`. That is exactly the state a
        // list reordered under a composition leaves behind.
        let moved = Self.plan([control, RoomPlan.Dressing(
            piece: .scenery(0), x: Int(columns[1]),
            y: Int(layout.wallBaseY) - layout.tile, what: "vending machine")])
            .dressingViolations(in: layout, resolve: Self.inventedResolve)
        #expect(moved.count == 1, Comment(rawValue:
            "a placement whose `what` disagrees with its index was reported"
            + " \(moved.count) times: \(moved)"))
        #expect(moved.first?.contains("moved under the placement") ?? false, Comment(rawValue:
            "\(moved) does not say the list moved"))
    }

    /// **A placement nobody will ever see is caught.**
    ///
    /// `compose-scene.py`'s `report_hidden` as a rule rather than as a printout:
    /// a prop whose box is wholly inside the box of a nearer one is drawn,
    /// depth-sorted behind it, and completely covered, which costs a texture
    /// and a node and shows nothing. Nearer the camera is drawn later, so the
    /// one that disappears is the one with the *higher* y of the pair.
    @Test func aDressingPlacementBuriedByANearerOneIsCaught() throws {
        let layout = RoomLayout()
        let columns = layout.sceneryColumns
        try #require(columns.count >= 2, "the room has no clear column to stand a control on")
        let control = Self.cleanDressing(layout, column: columns[0])

        let buried = Self.plan([
            control,
            // A small prop on the wall line…
            RoomPlan.Dressing(
                piece: .role("bin"), x: Int(columns[1]),
                y: Int(layout.wallBaseY) - layout.tile, what: "waste bin"),
            // …and a tall wide one a row downstage of it, in the same column.
            RoomPlan.Dressing(
                piece: .scenery(1), x: Int(columns[1]),
                y: Int(layout.wallBaseY) - layout.tile * 2, what: "vending machine"),
        ]).dressingViolations(in: layout, resolve: Self.inventedResolve)
        #expect(buried.count == 1, Comment(rawValue:
            "a bin standing behind a vending machine that covers it was reported"
            + " \(buried.count) times: \(buried)"))
        // The message carries the *fraction*, because the rule is a fraction:
        // a prop 99% covered is as invisible as one 100% covered and used to
        // pass. Asserting the percentage rather than the word is what keeps
        // this test honest if the threshold ever moves.
        #expect(buried.first?.contains("% hidden behind") ?? false, Comment(rawValue:
            "\(buried) does not say how much of the bin is covered"))
        #expect(buried.first?.contains("dressing[1]") ?? false, Comment(rawValue:
            "\(buried) does not name the placement nobody sees"))
    }

    /// **A prop 99% covered is caught, and a real pile is not.** [task 8]
    ///
    /// The rule used to be containment, which a single pixel of offset defeats:
    /// a 26 px cabinet leaned on a 26 px cabinet one pixel across draws as one
    /// cabinet with a sliver of another behind it and reported nothing. That
    /// shipped in a draft of the office composition and was found by cropping a
    /// render at 5x: the work this check exists to save.
    ///
    /// Both arms matter. Catching the stack is worthless if it also refuses the
    /// pile the composition is *for*: a small prop on a large one, which is how
    /// `scripts/compose-scene.py`'s scenes reach a 1-2 px nearest neighbour.
    @Test func aStackedPairIsCaughtAndASmallPropOnALargeOneIsNot() throws {
        let layout = RoomLayout()
        let columns = layout.sceneryColumns
        func plan(_ near: (piece: RoomPlan.Piece, dx: Int)) -> [String] {
            RoomPlan(spaces: [], surfaces: [:], dressing: [
                RoomPlan.Dressing(
                    piece: .scenery(0), x: Int(columns[1]),
                    y: Int(layout.baselineY) + layout.tile, what: "behind"),
                RoomPlan.Dressing(
                    piece: near.piece, x: Int(columns[1]) + near.dx,
                    y: Int(layout.baselineY) + layout.tile - 1, what: "in front"),
            ]).dressingViolations(in: layout, resolve: Self.inventedResolve)
        }
        // Same box, one pixel across: the prop behind is invisible and reported.
        let stacked = plan((piece: .scenery(0), dx: 1))
        #expect(stacked.contains { $0.contains("% hidden behind") }, Comment(rawValue:
            "two props of one size stacked a pixel apart were not reported: \(stacked)"))
        // A narrower prop in front leaves the one behind showing on both sides.
        let piled = plan((piece: .scenery(2), dx: 1))
        #expect(!piled.contains { $0.contains("% hidden behind") }, Comment(rawValue:
            "a small prop piled on a larger one was refused, which is the composition"
            + " this rule exists to allow: \(piled)"))
    }

    // MARK: A plan may redress a room; it may never move a seat

    @Test func adoptingAPlanMovesNoRouteNumber() throws {
        let open = RoomLayout()
        let planned = open.adopting(plan: try Self.richestPlan())
        // Any metrics at all: the assertion is that a plan changes nothing, and
        // the two sides are asked the same question. [ADR-008]
        let metrics = RoomLayout.SeatMetrics(
            deskInkHeight: 24, chairInkHeight: 46, costumeTopAboveFeet: 22)
        #expect(planned.seatCapacity == open.seatCapacity)
        #expect(planned.width == open.width && planned.height == open.height)
        #expect(planned.wallBaseY == open.wallBaseY)
        #expect(planned.deliveryRowY == open.deliveryRowY)
        #expect(planned.aisleY == open.aisleY)
        #expect(planned.baselineY == open.baselineY)
        #expect(planned.backSeatRowY == open.backSeatRowY)
        #expect(planned.standingRows == open.standingRows)
        for seat in 0..<open.seatCapacity {
            #expect(planned.seatPosition(seat) == open.seatPosition(seat))
            #expect(planned.deskPosition(seat, metrics: metrics)
                    == open.deskPosition(seat, metrics: metrics))
            #expect(planned.chairPosition(seat, metrics: metrics)
                    == open.chairPosition(seat, metrics: metrics))
            #expect(planned.stationPropPosition(seat) == open.stationPropPosition(seat))
            #expect(planned.entranceRoute(forSeat: seat) == open.entranceRoute(forSeat: seat))
            #expect(planned.upstageExit(forSeat: seat, metrics: metrics)
                    == open.upstageExit(forSeat: seat, metrics: metrics))
            #expect(planned.homeRoute(forSeat: seat) == open.homeRoute(forSeat: seat))
        }
        #expect(planned.overflowPlatePosition == open.overflowPlatePosition)
        #expect(planned.decorationColumns.map(\.x) == open.decorationColumns.map(\.x))
    }

    // MARK: What the plan does move - the four scenery bands

    /// The open floor's anchors are pinned, so "five of the six themes are
    /// untouched by this work" is a measurement rather than an intention.
    @Test func theOpenFloorKeepsTheBandsItAlwaysHad() {
        let layout = RoomLayout()
        #expect(layout.plan.isEmpty)
        #expect(Set(layout.sceneryAnchors(.wall).map(\.y)) == [layout.wallBaseY + 64])
        #expect(Set(layout.sceneryAnchors(.wallLine).map(\.y)) == [layout.wallBaseY])
        #expect(Set(layout.sceneryAnchors(.backFloor).map(\.y)) == [layout.wallBaseY - 32])
        #expect(Set(layout.sceneryAnchors(.midFloor).map(\.y)) == [layout.backSeatRowY + 32])
        #expect(layout.sceneryAnchors(.wall).count == layout.seatCapacity)
    }

    /// Under a plan the two upper bands move onto the two things a plan gives
    /// the room that an open floor does not have: a wall **face**, and a strip
    /// of floor behind it.
    @Test func aPlanPutsTheUpperBandsOnTheWallFaceAndTheFarFloor() throws {
        let layout = RoomLayout().adopting(plan: try Self.richestPlan())
        let hung = layout.sceneryAnchors(.wall)
        #expect(!hung.isEmpty)
        for point in hung {
            #expect(point.y >= layout.wallFace.bottom && point.y < layout.wallFace.top,
                    "a picture is hung off the wall's own face")
            let bound = layout.sceneryInkBound(.wall)
            #expect(point.y + Double(bound.height) <= layout.wallFace.top,
                    "a picture the band admits would cross the wall's top line")
        }
        #expect(Set(layout.sceneryAnchors(.wallLine).map(\.y)) == [layout.farFloorY])
        // The two lower bands are unmoved: they stand on floor the plan did not
        // change.
        let open = RoomLayout()
        #expect(layout.sceneryAnchors(.backFloor) == open.sceneryAnchors(.backFloor))
        #expect(layout.sceneryAnchors(.midFloor) == open.sceneryAnchors(.midFloor))
    }

    /// **Nothing hangs in a doorway** (`06-SET-BUILDING.md` R1), and not a
    /// hypothetical: the doorways are on seat columns and the wall band uses
    /// seat columns.
    @Test func nothingHangsInADoorway() throws {
        let plan = try Self.richestPlan()
        let layout = RoomLayout().adopting(plan: plan)
        for point in layout.sceneryAnchors(.wall) {
            let column = Int((point.x - Double(layout.tile) / 2).rounded()) / layout.tile
            #expect(!plan.doorwayColumns.contains(column), Comment(rawValue:
                "a picture hangs across the doorway at column \(column)"))
        }
    }

    /// **Nothing stands on a partition** (R2 and R3), measured against the
    /// widest prop each band admits rather than against the props that happen to
    /// be declared today.
    /// **The plan and the art come from the same theme.** This paired
    /// `richestPlan()` with `handPlacedTheme().room`, which named one theme
    /// while there was one hand-placed theme and two the moment a second gained
    /// dressing: office's placements were then measured against another
    /// theme's content boxes, and a clearance office had always had failed
    /// against art it does not draw. Every theme that declares partitions is
    /// checked here, each against its own room.
    @Test func nothingStandsOnAPartition() throws {
        let manifest = try Manifest.load(root: SceneFixtures.repositoryRoot)
        let planned = manifest.themes.orderedIDs
            .compactMap { id in manifest.themes.theme(id).map { (id: id, room: $0.room) } }
            .filter { !$0.room.plan.partitions.isEmpty }
        #expect(!planned.isEmpty, "no theme declares a partition, so this checks nothing")
        for (id, room) in planned {
            try Self.checkPartitionClearance(id: id, room: room)
        }
    }

    private static func checkPartitionClearance(id: String, room: Manifest.Room) throws {
        let plan = room.plan
        let layout = RoomLayout().adopting(plan: plan)
        let half = Double(RoomPlan.partitionPx) / 2
        // **Whatever this plan actually draws**, which since the office was
        // hand-placed is not the bands. Walking `sceneryAnchors` here asserted a
        // clearance for props the room does not put anywhere: vacuously true
        // while the two interior partitions stood clear of the lattice, and
        // then loudly false the moment an outer wall landed on a band column
        // that nothing stands in. A test that fails about absent props is worse
        // than one that passes about them, because it invites deleting the rule.
        for placement in plan.dressing {
            guard let prop = room.piece(placement.piece) else { continue }
            let box = prop.contentBox
            let point = ScenePoint(x: Double(placement.x), y: Double(placement.y))
            let reach = Double(box.width) / 2
            for partition in plan.partitions {
                let low = Double(partition.y * layout.tile)
                let high = Double((partition.y + partition.h) * layout.tile)
                guard point.y >= low, point.y <= high else { continue }
                let gap = abs(point.x - Double(partition.x * layout.tile))
                #expect(gap >= reach + half, Comment(rawValue:
                    "\(id): '\(placement.what)' at x=\(Int(point.x)) reaches the partition "
                    + "at x=\(partition.x * layout.tile), \(Int(gap)) px apart, needs "
                    + "\(Int(reach + half))"))
            }
        }
    }

    /// Every partition is upstage of the wall line **or outside the span the
    /// cast travels**, which is the *reason* there is no north-south wall in the
    /// working half of the room and is worth pinning rather than leaving to the
    /// prose: below that line seven seat columns 96 px apart leave a 40 px gap
    /// between one seat's desk and the next seat's chair, and a station prop
    /// stands in the middle of every one.
    ///
    /// **The second arm is the building's outer wall and nothing else.** [ADR-013]
    /// That argument is about the gaps *between* seats; beyond the outermost
    /// seat column there are no gaps and no routes, so a wall there may run the
    /// full depth of the floor, and it has to, or it is a wall with a gap in it
    /// where the camera is looking. Written as a disjunction rather than
    /// loosened to "upstage or at the edge", so an interior partition that
    /// wandered downstage still fails on the first arm.
    @Test func everyPartitionIsUpstageOfTheWallLineOrOutsideEveryRoute() throws {
        let plan = try Self.richestPlan()
        let layout = RoomLayout()
        let seatXs = (0..<layout.seatCapacity).map { layout.seatPosition($0).x }
        let low = (seatXs.min() ?? 0) - Double(layout.tile) / 2
        let high = (seatXs.max() ?? 0) + Double(layout.tile) / 2
        #expect(!plan.partitions.isEmpty, "the plan draws no interior wall at all")
        var outside = 0
        for partition in plan.partitions {
            let left = Double(partition.x * layout.tile) - Double(RoomPlan.partitionPx) / 2
            let right = Double(partition.x * layout.tile) + Double(RoomPlan.partitionPx) / 2
            if right <= low || left >= high { outside += 1; continue }
            #expect(Double(partition.y * layout.tile) >= layout.wallBaseY, Comment(rawValue:
                "a partition starts at y=\(partition.y * layout.tile), downstage of the "
                + "wall line at \(Int(layout.wallBaseY)), inside the travelled span"))
        }
        #expect(outside == 2, Comment(rawValue:
            "the plan should carry exactly two walls outside every route (its own "
            + "left and right edges) and carries \(outside)"))
    }

    /// The plan is a plan: more than one room, more than one finish, and rooms
    /// that do not overlap. Cheap, and it is what fails if a regeneration drops
    /// half the table.
    @Test func theShippedPlanIsMoreThanOneRoom() throws {
        let plan = try Self.richestPlan()
        #expect(plan.spaces.count >= 3, "\(plan.spaces.count) spaces")
        #expect(Set(plan.spaces.map(\.surface)).count >= 3, "one finish over three rooms")
        #expect(plan.spaces.filter { $0.bandRows != nil }.count >= 2,
                "the plan draws fewer than two wall bands")
        #expect(plan.declaredPaths.count >= 3)
    }
}

/// The plan as the scene actually paints it. Art-gated: these read textures.
@MainActor
struct RoomPlanSceneTests {

    static func plannedScene() throws -> (RoomScene, String)? {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.themes.orderedIDs {
            guard let theme = manifest.themes.theme(id), !theme.room.plan.isEmpty else { continue }
            let scene = RoomScene(manifest: manifest, themeID: id)
            scene.setViewport(CGSize(width: 720, height: 400))
            return (scene, id)
        }
        return nil
    }

    /// **The room is drawn from the plan, not from one floor tile and one wall
    /// tile.** Paths rather than node counts, because the failure this has to
    /// catch (a plan that decoded to nothing and fell back to the open floor)
    /// produces a perfectly plausible set of nodes.
    @Test(.enabled(if: SceneArt.isAvailable))
    func thePlannedRoomDrawsSeveralFinishesAndMoreThanOneWallBand() throws {
        let found = try #require(try Self.plannedScene(), "no theme ships a plan")
        let art = Set(found.0.planArtForTesting)
        let plan = found.0.layout.plan
        for surface in plan.surfaces.values where plan.spaces.contains(where: {
            $0.surface == surface.id
        }) {
            #expect(art.contains(surface.floor), "\(found.1) drew no \(surface.id) floor")
        }
        let banded = Set(plan.spaces.filter { $0.bandRows != nil }.map(\.surface))
        for id in banded {
            let surface = try #require(plan.surface(id))
            #expect(art.contains(surface.cap) && art.contains(surface.body),
                    "\(found.1) drew no wall band for \(id)")
        }
        #expect(art.contains("outside"), "the surround was left to the compositor")
        #expect(art.contains { $0.hasPrefix("partition@") }, "no interior wall was drawn")
        #expect(art.contains("jamb"), "a doorway was cut with no jamb")
        #expect(art.contains("shadow"), "the wall band casts no contact shadow")
    }

    /// **The camera keeps the plan's top edge in frame.** That edge (12 px of
    /// white floor-plan line with the surround above it) is the single thing
    /// that makes the picture read as a building rather than as a stage with an
    /// infinite backcloth, and a frame that crops it undoes the whole change.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theCameraFramesThePlansTopEdge() throws {
        let found = try #require(try Self.plannedScene(), "no theme ships a plan")
        let scene = found.0
        let top = try #require(scene.layout.plan.topRow())
        #expect(scene.decorationTopY >= Double((top + 1) * scene.layout.tile), Comment(
            rawValue: "the camera aims below the plan's own top edge"))
    }

    /// Every plan node is behind every prop and every character, because a plan
    /// is what the room is drawn *on*. A wall that sorted in front of a
    /// character would be a wall between the viewer and the cast, which is what
    /// ADR-002 spent M5's foreground row to avoid.
    @Test(.enabled(if: SceneArt.isAvailable))
    func nothingThePlanDrawsIsEverInFrontOfAnything() throws {
        let found = try #require(try Self.plannedScene(), "no theme ships a plan")
        let scene = found.0
        let deepestProp = scene.propNodesForTesting.map(\.zPosition).min() ?? 0
        for node in scene.planNodesForTesting {
            #expect(node.zPosition < deepestProp, Comment(rawValue:
                "a plan node at z=\(node.zPosition) sorts at or in front of the room's "
                + "furniture at z=\(deepestProp)"))
        }
    }
}
