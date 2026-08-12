import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The floor plan, and the three routes it may never cross.** [ADR-007]
///
/// Most of this suite is **ungated**, deliberately. A plan is geometry and the
/// manifest that declares it is tracked, so a fresh clone with no art on disk
/// can still answer "does the shipped plan wall somebody in" — and that is the
/// question whose wrong answer is a character walking through a wall, which no
/// still frame shows and no palette lint can see.
struct RoomPlanTests {

    static func officePlan() throws -> RoomPlan {
        let manifest = try Manifest.load(root: SceneFixtures.repositoryRoot)
        let planned = manifest.themes.orderedIDs
            .compactMap { manifest.themes.theme($0) }
            .first { !$0.room.plan.isEmpty }
        let plan = try #require(
            planned?.room.plan,
            "no theme in the manifest declares a floor plan, so this suite checks nothing")
        return plan
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
        let plan = try Self.officePlan()
        let violations = plan.routeViolations(in: RoomLayout())
        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "; ")))
    }

    /// The check is not vacuous: a plan that walls a seat column **is** caught.
    ///
    /// Written because the shipped plan puts its only band at the wall line,
    /// where the exit already ends, so `routeViolations` returns empty for it —
    /// and a check that returns empty for everything is indistinguishable from
    /// one that returns empty because it works.
    @Test func aBandAcrossASeatColumnIsCaught() throws {
        let layout = RoomLayout()
        let surface = RoomPlan.Surface(
            id: "s", floor: "f", cap: "c", body: "b",
            lineEdge: Bitmap.RGBA(0, 0, 0), lineFill: Bitmap.RGBA(255, 255, 255))
        // A band at rows 3 and 4 — y 96 to 160, between the front seat row and
        // the wall line, straight across every column.
        let walled = RoomPlan(
            spaces: [RoomPlan.Space(name: "bad", surface: "s", x: 0, y: 0, w: 25, h: 5)],
            surfaces: ["s": surface])
        let violations = walled.routeViolations(in: layout)
        // One complaint per seat per band row — a band is a cap and a body, and
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
        let plan = try Self.officePlan()
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

    // MARK: A plan may redress a room; it may never move a seat

    @Test func adoptingAPlanMovesNoRouteNumber() throws {
        let open = RoomLayout()
        let planned = open.adopting(plan: try Self.officePlan())
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
            #expect(planned.upstageExit(forSeat: seat) == open.upstageExit(forSeat: seat))
            #expect(planned.homeRoute(forSeat: seat) == open.homeRoute(forSeat: seat))
        }
        #expect(planned.overflowPlatePosition == open.overflowPlatePosition)
        #expect(planned.decorationColumns.map(\.x) == open.decorationColumns.map(\.x))
    }

    // MARK: What the plan does move — the four scenery bands

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
        let layout = RoomLayout().adopting(plan: try Self.officePlan())
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

    /// **Nothing hangs in a doorway** — `06-SET-BUILDING.md` R1, and not a
    /// hypothetical: the doorways are on seat columns and the wall band uses
    /// seat columns.
    @Test func nothingHangsInADoorway() throws {
        let plan = try Self.officePlan()
        let layout = RoomLayout().adopting(plan: plan)
        for point in layout.sceneryAnchors(.wall) {
            let column = Int((point.x - Double(layout.tile) / 2).rounded()) / layout.tile
            #expect(!plan.doorwayColumns.contains(column), Comment(rawValue:
                "a picture hangs across the doorway at column \(column)"))
        }
    }

    /// **Nothing stands on a partition** — R2 and R3, measured against the
    /// widest prop each band admits rather than against the props that happen to
    /// be declared today.
    @Test func nothingStandsOnAPartition() throws {
        let plan = try Self.officePlan()
        let layout = RoomLayout().adopting(plan: plan)
        let half = Double(RoomPlan.partitionPx) / 2
        for band in RoomLayout.SceneryBand.allCases {
            let reach = Double(layout.sceneryInkBound(band).width) / 2
            for point in layout.sceneryAnchors(band) {
                for partition in plan.partitions {
                    let low = Double(partition.y * layout.tile)
                    let high = Double((partition.y + partition.h) * layout.tile)
                    guard point.y >= low, point.y <= high else { continue }
                    let gap = abs(point.x - Double(partition.x * layout.tile))
                    #expect(gap >= reach + half, Comment(rawValue:
                        "a \(band) prop at x=\(Int(point.x)) reaches the partition at "
                        + "x=\(partition.x * layout.tile) — \(Int(gap)) px apart, needs "
                        + "\(Int(reach + half))"))
                }
            }
        }
    }

    /// Every partition is upstage of the wall line, which is the *reason* there
    /// is no north-south wall in the working half of the room and is worth
    /// pinning rather than leaving to the prose: below that line seven seat
    /// columns 96 px apart leave a 40 px gap between one seat's desk and the
    /// next seat's chair, and a station prop stands in the middle of every one.
    @Test func everyPartitionIsUpstageOfTheWallLine() throws {
        let plan = try Self.officePlan()
        let layout = RoomLayout()
        #expect(!plan.partitions.isEmpty, "the plan draws no interior wall at all")
        for partition in plan.partitions {
            #expect(Double(partition.y * layout.tile) >= layout.wallBaseY, Comment(rawValue:
                "a partition starts at y=\(partition.y * layout.tile), downstage of the "
                + "wall line at \(Int(layout.wallBaseY))"))
        }
    }

    /// The plan is a plan: more than one room, more than one finish, and rooms
    /// that do not overlap. Cheap, and it is what fails if a regeneration drops
    /// half the table.
    @Test func theShippedPlanIsMoreThanOneRoom() throws {
        let plan = try Self.officePlan()
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
    /// catch — a plan that decoded to nothing and fell back to the open floor —
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

    /// **The camera keeps the plan's top edge in frame.** That edge — 12 px of
    /// white floor-plan line with the surround above it — is the single thing
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
