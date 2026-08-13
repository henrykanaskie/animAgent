import Foundation
import Testing
@testable import SpriteRoomScene

/// **No route in this room walks through the furniture the room draws.**
///
/// The room had three route checks before this one and each of them proved
/// something about *characters*: `RoomSceneTests
/// .everyWaypointOfEveryRouteIsOnTheMovingCharactersOwnColumn` proves every leg
/// is vertical inside one seat column or lateral on the delivery row,
/// `ReportDeliveryTests.theRoomsOneLateralCorridorMeetsNoOtherRoute` proves that
/// the one lateral corridor meets nothing, and `RoomPlan.routeViolations` and
/// `RoomPlan.dressingViolations` prove that no wall, partition or hand-placed
/// prop stands in a column. Between them they cover everything in the room
/// except the thing every seat is built around: **its own workstation**. Nothing
/// checked a route against the desk, the chair, the screen rigs, the desktop kit
/// or the station prop that belong to the seat the route starts at, and that
/// absence is why a leaver from any of the four away-facing seats walked up
/// through its own desk and stood, half-faded, on top of two screen rigs, for as
/// long as ADR-008 and ADR-009 have been shipped.
///
/// ## The rule, and why it is a floor line rather than an ink box
///
/// > **A body may never be upstage of a piece of furniture whose ink it stands
/// > in front of** — with one exception, named below.
///
/// The obvious statement is "the body's ink box never overlaps a prop's ink
/// box", and it is *false of the room by design*, in both directions. A desk at
/// a camera-facing seat is drawn over its occupant's waist on purpose —
/// `deskCutAboveFeet` is the number and ADR-008 §2's table is the argument — and
/// a character crossing the walkway 32 px downstage of a 38 px desk overlaps it
/// in projection whatever anybody wants. Overlap in an oblique projection is
/// ubiquitous and says nothing.
///
/// What says something is the **floor**. A prop stands on a floor line: its
/// bottom-centre, which is where `Manifest.PropRole.anchor(inCanvas:)` puts it
/// and where every position function in `RoomLayout` returns. A body downstage
/// of that line is in front of the prop and reads as being in front of it; a
/// body upstage of it is behind the prop and — if the prop is a desk with its
/// back to that body — is standing where the furniture is. So the check is
/// per-sample and one-sided: `body.y <= prop.y` whenever their columns overlap.
///
/// **The exception is the occluder.** A piece standing *downstage of its own
/// seat* is there precisely so that the body is behind it: the camera-facing
/// desk that makes a standing figure read as seated, the kit on that desk, the
/// chair back an away-facing seat would take if one ever fitted. Every route to
/// that seat must pass such a piece or the seat is unreachable. So a piece is
/// exempt when `point.y < seatRowY(its seat)`, which is geometry rather than a
/// list of names — nothing has to be added here when a theme binds something
/// new, and nothing upstage can ever claim the exemption.
///
/// ## What the boxes are measured from
///
/// Every prop's width is its own `content_box.width` out of
/// `assets/manifest.json`, resolved through the same accessors `RoomScene`
/// resolves them through, and every position is `RoomLayout`'s own. Nothing here
/// is transcribed, so re-cutting a desk moves this check with it. The **body**
/// is `characters.canvas.width` — 32 px — and that is not a conservative
/// stand-in for a narrower silhouette: measured over every frame of every state
/// of all six shipped variants, the cast's ink spans column 0 to column 31, so
/// the canvas *is* the ink box in x. It is also the same 32 px column
/// `RoomPlan.dressingViolations` holds a hand-placed prop out of, so the two
/// checks cannot disagree about how wide a person is.
///
/// The overlap test is strict on purpose: a prop centred exactly one tile from a
/// seat occupies pixels `x−48 … x−17` against a body's `x−16 … x+15`, which
/// share no column. That is the bound the station prop sits exactly on, and the
/// reason `everyRouteClearsEveryPieceOfTheRoomsFurniture` is a real check of the
/// 32 px station-prop rule rather than a restatement of it.
///
/// ## What is not gated
///
/// All of it. Everything here is arithmetic over the tracked manifest, so a
/// fresh clone with no art runs the whole check — which is the point of a test
/// whose absence let a shipped defect run for two milestones.
struct RouteFurnitureTests {

    /// One thing the room draws, reduced to what a route can collide with.
    struct Piece {
        let what: String
        /// The seat it belongs to, or `nil` for scenery, decoration and the
        /// plan's hand-placed dressing, which belong to the room.
        let seat: Int?
        /// Bottom-centre, in scene pixels — the floor line.
        let point: ScenePoint
        /// `content_box.width`, and the ink height only so a failure can say
        /// what the reader would have seen.
        let width: Double
        let height: Double
    }

    /// Every room the app can draw: the default and each theme.
    static func rooms(_ manifest: Manifest) -> [(id: String, room: Manifest.Room)] {
        [("default", manifest.room)]
            + manifest.themes.orderedIDs.compactMap { id in
                manifest.themes.theme(id).map { (id, $0.room) }
            }
    }

    /// **Everything one room stands on its floor, seat furniture first.**
    ///
    /// It mirrors `RoomScene.buildRoom` piece for piece — the chair its facing
    /// asks for, the desk, both pod rig slots, all four desktop kit slots, the
    /// station prop for *every* station the room declares (any agent may take
    /// any of them), the two decoration bands, the four scenery bands or the
    /// plan's dressing where there is one — and it is assembled from the
    /// manifest rather than from a `RoomScene`, so it needs no art on disk.
    static func furniture(
        room: Manifest.Room, manifest: Manifest, layout: RoomLayout
    ) -> [Piece] {
        let metrics = SceneFixtures.seatMetrics(room: room, manifest: manifest)
        var pieces: [Piece] = []

        func box(_ role: String) -> Manifest.PropRole.Box? { room.prop(role)?.contentBox }

        for seat in 0..<layout.seatCapacity {
            if let role = layout.seatFacing(seat).seatRole, let chair = box(role),
               let point = layout.chairPosition(seat, metrics: metrics) {
                pieces.append(Piece(
                    what: "seat \(seat)'s \(role)", seat: seat, point: point,
                    width: Double(chair.width), height: Double(chair.height)))
            }
            if let desk = box(RoomScene.surfaceRole) {
                pieces.append(Piece(
                    what: "seat \(seat)'s desk", seat: seat,
                    point: layout.deskPosition(seat, metrics: metrics),
                    width: Double(desk.width), height: Double(desk.height)))
            }
            if let rig = box(RoomScene.monitorRole) {
                for slot in RoomLayout.PodRigSlot.allCases {
                    guard let point = layout.monitorPosition(
                        seat, slot: slot, metrics: metrics) else { continue }
                    pieces.append(Piece(
                        what: "seat \(seat)'s \(slot) rig", seat: seat, point: point,
                        width: Double(rig.width), height: Double(rig.height)))
                }
            }
            // The kit's `variants` carry their own measured ink boxes and the
            // manifest declares one box for the role, so this places all four
            // slots at the role's own — which is what `PropRole.variant(_:box:)`
            // falls back to when the art cannot be measured. It costs nothing
            // here: the kit stands on a **camera-facing** desk, downstage of its
            // own seat, so every slot takes the occluder exemption at any height.
            if let kit = box(RoomScene.deskKitRole) {
                for slot in RoomLayout.PodKitSlot.allCases {
                    guard let point = layout.deskKitPosition(
                        seat, slot: slot, inkHeight: Double(kit.height), metrics: metrics)
                    else { continue }
                    pieces.append(Piece(
                        what: "seat \(seat)'s \(slot) kit", seat: seat, point: point,
                        width: Double(kit.width), height: Double(kit.height)))
                }
            }
            // Every station, not the one some agent happens to have: a station
            // is chosen by `agent_type` and any seat can end up with any of
            // them, so the clearance has to hold for all of them at once.
            for id in room.orderedStationIDs {
                guard let prop = room.station(id)?.prop else { continue }
                pieces.append(Piece(
                    what: "seat \(seat)'s '\(id)' station prop", seat: seat,
                    point: layout.stationPropPosition(seat),
                    width: Double(prop.contentBox.width),
                    height: Double(prop.contentBox.height)))
            }
        }

        for placement in RoomScene.decorationPlacements(layout: layout) {
            guard let prop = room.prop(placement.role) else { continue }
            pieces.append(Piece(
                what: "a \(placement.role)", seat: nil, point: placement.point,
                width: Double(prop.contentBox.width),
                height: Double(prop.contentBox.height)))
        }

        // The same either-or `buildRoom` makes: a plan with hand-placed dressing
        // draws that and no bands; a plan without draws the four bands.
        if room.plan.dressing.isEmpty {
            for band in RoomLayout.SceneryBand.allCases {
                let props = room.scenery(band)
                guard !props.isEmpty else { continue }
                for (index, point) in layout.sceneryAnchors(band).enumerated() {
                    let prop = props[index % props.count]
                    pieces.append(Piece(
                        what: "\(band) scenery '\(prop.file)'", seat: nil, point: point,
                        width: Double(prop.contentBox.width),
                        height: Double(prop.contentBox.height)))
                }
            }
        } else {
            for item in room.plan.dressing {
                guard let prop = room.piece(item.piece) else { continue }
                pieces.append(Piece(
                    what: "dressing '\(item.what)'", seat: nil,
                    point: ScenePoint(x: Double(item.x), y: Double(item.y)),
                    width: Double(prop.contentBox.width),
                    height: Double(prop.contentBox.height)))
            }
        }
        return pieces
    }

    /// **Every route one seat's occupant can walk**, each as the full list of
    /// points it passes through — its chair first, because a character starts a
    /// beat wherever it is standing and every beat but the entrance starts in
    /// the chair.
    static func routes(
        seat: Int, layout: RoomLayout, metrics: RoomLayout.SeatMetrics
    ) -> [(what: String, path: [ScenePoint])] {
        let chair = layout.seatPosition(seat)
        var out: [(what: String, path: [ScenePoint])] = [
            ("entrance", layout.entranceRoute(forSeat: seat)),
            ("exit", [chair, layout.upstageExit(forSeat: seat, metrics: metrics)]),
            ("in-place report",
             [chair] + layout.inPlaceDeliveryRoute(reporterSeat: seat)
                + layout.homeRoute(forSeat: seat, fromY: layout.aisleY)),
        ]
        for anchor in 0..<layout.seatCapacity where anchor != seat {
            let there = layout.deliveryRoute(anchorSeat: anchor, reporterSeat: seat)
            let home = layout.homeRoute(forSeat: seat, fromY: layout.deliveryRowY)
            out.append(("report to \(anchor)", [chair] + there + home))
            // A `SubagentStop` and a `SessionEnd` in one frame: the report beat
            // truncated into an exit. [`Character.reportAndDepart`]
            out.append(("report to \(anchor), then leave",
                        [chair] + there + home
                        + [layout.upstageExit(forSeat: seat, metrics: metrics)]))
        }
        return out
    }

    /// Every point on a path, one scene pixel apart. A pixel, because the room's
    /// shortest leg is 7 px and its narrowest clearance is 1 px, so anything
    /// coarser could step over the thing it is looking for.
    static func samples(_ path: [ScenePoint]) -> [ScenePoint] {
        guard let first = path.first else { return [] }
        var out = [first]
        for (from, to) in zip(path, path.dropFirst()) {
            let dx = to.x - from.x, dy = to.y - from.y
            let steps = max(1, Int(max(abs(dx), abs(dy)).rounded(.up)))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                out.append(ScenePoint(x: from.x + dx * t, y: from.y + dy * t))
            }
        }
        return out
    }

    /// **The check, over every room the app can draw.**
    ///
    /// It fails on the shipped room before `RoomLayout.upstageClearance` exists:
    /// 252 reports over the seven rooms, every one of them an away-facing seat's
    /// exit "88 px upstage of a desk whose ink stands 136…174 in its own column",
    /// and in `office` its two screen rigs as well. Nothing else in the room
    /// reported, then or now — which is the half of this check that says the
    /// decoration, the scenery, the plan's hand-placed dressing and every
    /// station's prop are clear, rather than assuming it.
    ///
    /// **One rule for both, and sharing a column is not the rule.** Standing in
    /// front of something is what the delivery row is *for*: a reporter walking
    /// along `deliveryRowY` passes under the whole back half of the room, 96 px
    /// downstage of the nearest thing in it, and it is in front of every one of
    /// them. The first draft of this test forbade the shared column outright and
    /// reported 250 lecterns, curtains and plants in `briefing` alone. Only the
    /// far side is a defect, for scenery exactly as for a desk — what differs is
    /// that scenery gets no occluder exemption, because scenery is nobody's seat.
    @Test func everyRouteClearsEveryPieceOfTheRoomsFurniture() throws {
        let manifest = try SceneFixtures.manifest()
        let halfBody = Double(manifest.characters.canvas.width) / 2
        #expect(halfBody == 16, "the cast changed width; every clearance here is derived from it")
        var comparedToSeatFurniture = 0, comparedToScenery = 0

        for (id, room) in Self.rooms(manifest) {
            let layout = RoomLayout().adopting(plan: room.plan)
            let metrics = SceneFixtures.seatMetrics(room: room, manifest: manifest)
            let pieces = Self.furniture(room: room, manifest: manifest, layout: layout)
            #expect(!pieces.isEmpty, Comment(rawValue: "\(id) draws no furniture at all"))

            // The occluder exemption, applied once: a piece downstage of its own
            // seat is what that seat is composed behind, and every route to that
            // seat has to pass it.
            let solid = pieces.filter { piece in
                piece.seat.map { piece.point.y >= layout.seatRowY($0) } ?? true
            }

            for seat in 0..<layout.seatCapacity {
                for (what, path) in Self.routes(seat: seat, layout: layout, metrics: metrics) {
                    // **One issue per route and piece, not per sample.** A leaver
                    // walking 88 px through a desk is one defect, and reporting
                    // it 88 times buries every other line of the run — which is
                    // what the first draft of this did.
                    var worst: [Int: (piece: Piece, at: ScenePoint)] = [:]
                    for point in Self.samples(path) {
                        for (index, piece) in solid.enumerated() {
                            // Columns first: everything else is decided by how
                            // far apart the two centres are against half a body
                            // plus half the prop's own ink.
                            guard abs(point.x - piece.point.x)
                                    < halfBody + piece.width / 2 else { continue }
                            if piece.seat == nil { comparedToScenery += 1 }
                            else { comparedToSeatFurniture += 1 }
                            guard point.y > piece.point.y else { continue }
                            if let held = worst[index], held.at.y >= point.y { continue }
                            worst[index] = (piece, point)
                        }
                    }
                    for (_, hit) in worst.sorted(by: { $0.key < $1.key }) {
                        Issue.record(Comment(rawValue:
                            "\(id): seat \(seat)'s \(what) route reaches"
                            + " (\(hit.at.x), \(hit.at.y)), \(hit.at.y - hit.piece.point.y) px"
                            + " upstage of \(hit.piece.what), whose ink stands"
                            + " \(hit.piece.point.y)…\(hit.piece.point.y + hit.piece.height)"
                            + " across x \(hit.piece.point.x - hit.piece.width / 2)…"
                            + "\(hit.piece.point.x + hit.piece.width / 2)"))
                    }
                }
            }
        }
        // A rule nothing was ever tested against passes. Both halves had
        // something to be tested against: every seat's route runs the length of
        // its own workstation, and the delivery row runs under the scenery.
        #expect(comparedToSeatFurniture > 0, "no route came within a body of any seat furniture")
        #expect(comparedToScenery > 0, "no route came within a body of any scenery")
    }

    /// **What the away-facing seats actually get, as numbers rather than as a
    /// property.** The test above says "no route crosses furniture"; this says
    /// what that costs, so a change that quietly took the exit away entirely
    /// would be a failure rather than a still-green invariant.
    @Test func anAwayFacingSeatsExitIsTheFloorItsOwnDeskLeavesIt() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        var away = 0, toward = 0

        for (id, room) in Self.rooms(manifest) {
            let metrics = SceneFixtures.seatMetrics(room: room, manifest: manifest)
            for seat in 0..<layout.seatCapacity {
                let exit = layout.upstageExit(forSeat: seat, metrics: metrics)
                let chair = layout.seatPosition(seat)
                #expect(exit.x == chair.x, "the exit left its column")
                switch layout.seatFacing(seat) {
                case .towardCamera:
                    // Nothing stands behind a camera-facing occupant, so its
                    // exit is the walk to the wall line it has always been.
                    toward += 1
                    #expect(exit.y == layout.wallBaseY, Comment(rawValue:
                        "\(id): seat \(seat) faces the camera and stops at \(exit.y)"))
                case .awayFromCamera:
                    // Its desk stands `awayDeskUpstage` behind it, so it has a
                    // quarter tile less one pixel and no more.
                    away += 1
                    let desk = layout.deskPosition(seat, metrics: metrics)
                    #expect(exit.y == desk.y - 1, Comment(rawValue:
                        "\(id): seat \(seat)'s exit ends at \(exit.y) against a desk"
                        + " standing at \(desk.y)"))
                    #expect(exit.y - chair.y == layout.awayDeskUpstage - 1)
                    #expect(exit.y > chair.y, Comment(rawValue:
                        "\(id): seat \(seat) has no floor behind it at all"))
                case .sideOn:
                    Issue.record("no seat in the shipped lattice is side-on")
                }
            }
        }
        // Four away-facing seats and three camera-facing ones, in each of the
        // seven rooms — the checkerboard `isBackRow(seat:)` produces.
        #expect(away == 4 * 7 && toward == 3 * 7, Comment(rawValue:
            "\(away) away-facing and \(toward) camera-facing seats were measured"))
    }

    /// **A character with no seat stops at the furniture of whatever column it is
    /// standing in.** `RoomScene` falls back to `upstageExit(fromX:metrics:)` for
    /// a leaver whose seat is already gone, and that path has to answer the same
    /// question — a body 32 px wide standing on a seat's column is in front of
    /// that seat's desk whether or not the room still thinks it owns the seat.
    @Test func aSeatlessLeaverStopsAtWhicheverColumnItIsStandingIn() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let metrics = SceneFixtures.seatMetrics(manifest, theme: "office")

        for seat in 0..<layout.seatCapacity {
            let x = layout.seatPosition(seat).x
            #expect(layout.upstageExit(fromX: x, metrics: metrics).y
                    == layout.upstageClearance(forSeat: seat, metrics: metrics))
        }
        // Half a pitch out is nobody's column — the gap the scenery stands in —
        // so there is nothing to stop short of and the wall line is the answer.
        #expect(layout.upstageExit(fromX: layout.propColumnX(forSeat: 0), metrics: metrics).y
                == layout.wallBaseY)
    }
}
