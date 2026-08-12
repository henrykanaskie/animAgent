import Foundation
import Testing
@testable import SpriteRoomScene

/// **The desk pod.** [ADR-009]
///
/// The office theme's seat furniture is `scripts/compose-scene.py`'s `desk_pod`:
/// a 64×38 slab with a screen rig on it where a screen is honest, and an
/// orientation-neutral object where it is not. Everything here is arithmetic over
/// the shipped manifest, so it runs on a fresh clone with no art — the numbers
/// that decide whether a pod fits are content boxes, not pixels.
///
/// Every assertion is measured off the manifest rather than written down, with
/// one exception that is named where it happens: `monitorScreenClearance`, which
/// is `compose-scene.py`'s own 20 px with that file's citation behind it.
@Suite struct DeskPodTests {

    static func metrics(_ manifest: Manifest, theme: String?) -> RoomLayout.SeatMetrics {
        SceneFixtures.seatMetrics(manifest, theme: theme)
    }

    /// Every room the manifest can dress the scene in, the default included.
    static func everyRoom(_ manifest: Manifest) -> [(String, String?)] {
        [("room", nil)] + manifest.themes.orderedIDs.map { ($0, Optional($0)) }
    }

    /// **Exactly one shipped theme is a pod, and it is the one that was asked
    /// for.** The other five keep the desk they had, so `isDeskPod` is false for
    /// them and every accessor below returns what it returned before ADR-009.
    @Test func exactlyTheOfficeThemeIsAPod() throws {
        let manifest = try SceneFixtures.manifest()
        var pods: [String] = []
        for (name, id) in Self.everyRoom(manifest) where Self.metrics(manifest, theme: id).isDeskPod {
            pods.append(name)
        }
        #expect(pods == ["office"], "pods: \(pods)")

        // And it is a pod because of its *art*, not because it is called office:
        // a 64px slab and a 32px rig, so the slab holds two rigs exactly.
        let office = Self.metrics(manifest, theme: "office")
        #expect(office.deskInkWidth == 64 && office.deskInkHeight == 38)
        #expect(office.monitorInkWidth == 32 && office.monitorInkHeight == 42)
        #expect(office.deskInkWidth == office.monitorInkWidth * 2, Comment(rawValue:
            "the pod's two kit slots tile its desktop exactly; \(office.deskInkWidth)"
            + " against 2 × \(office.monitorInkWidth) does not"))
    }

    /// **A pod stands its kit on its desktop rather than on its back edge**, and
    /// that is the whole reason `deskTopLift` exists beside `surface_y`.
    ///
    /// `surface_y` is the topmost row of an 80%-of-box-width ink run, which for a
    /// desk drawn in near profile is the desktop and for a slab whose top surface
    /// is 25 rows deep is the **back** edge. Placing a rig there would draw it
    /// standing behind its own desk. The pod derives the lift from its own two
    /// measured heights instead, and the derivation is checked here as the thing
    /// it is for: the screen clears the desk's back edge by exactly
    /// `monitorScreenClearance`.
    @Test func aPodStandsItsKitOnItsDesktopRatherThanOnItsBackEdge() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        for (name, id) in Self.everyRoom(manifest) {
            let room = manifest.room(theme: id)
            let desk = try #require(room.prop(RoomScene.surfaceRole))
            let surfaceY = Double(desk.surfaceY ?? desk.contentBox.height)
            let metrics = Self.metrics(manifest, theme: id)
            let lift = layout.deskTopLift(
                surfaceHeightAboveFloor: surfaceY, metrics: metrics)
            guard metrics.isDeskPod else {
                #expect(lift == surfaceY, Comment(rawValue:
                    "\(name) is not a pod and its kit moved off `surface_y` anyway"))
                continue
            }
            #expect(lift == 16, "\(name): the shipped pod's lift is 16")
            #expect(surfaceY == metrics.deskInkHeight, Comment(rawValue:
                "\(name): the slab's measured surface is its own back edge, which is"
                + " the case this lift exists for; it measured \(surfaceY) against an"
                + " ink height of \(metrics.deskInkHeight)"))
            #expect(lift < surfaceY, Comment(rawValue:
                "\(name): the kit stands at or behind the desk's back edge"))
            #expect(lift + metrics.monitorInkHeight - metrics.deskInkHeight
                    == RoomLayout.monitorScreenClearance, Comment(rawValue:
                "\(name): the rig's screen clears the desk's back edge by"
                + " \(lift + metrics.monitorInkHeight - metrics.deskInkHeight)px, not"
                + " \(RoomLayout.monitorScreenClearance)"))
        }
    }

    /// **A screen belongs to an away-facing seat and to no other**, and a
    /// camera-facing seat gets the orientation-neutral object instead.
    ///
    /// This is the one rule in the pod that is a fact about the art rather than a
    /// preference: every screen in either pack is drawn face-on with its keyboard
    /// below it, and there is no rear view of a monitor anywhere in the
    /// 12,279-prop catalogue, so a rig at a camera-facing seat is drawn being
    /// looked at from below by the person sitting between it and the viewer.
    @Test func onlyAnAwayFacingSeatGetsAScreenAndOnlyACameraFacingOneGetsTheKit() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let metrics = Self.metrics(manifest, theme: "office")
        var rigs: [Int] = []
        var kits: [Int] = []
        for seat in 0..<layout.seatCapacity {
            if layout.monitorPosition(seat, metrics: metrics) != nil { rigs.append(seat) }
            if layout.deskKitPosition(seat, metrics: metrics) != nil { kits.append(seat) }
        }
        #expect(rigs == (0..<layout.seatCapacity)
            .filter { layout.seatFacing($0) == .awayFromCamera })
        #expect(kits == (0..<layout.seatCapacity)
            .filter { layout.seatFacing($0) == .towardCamera })
        #expect(Set(rigs).isDisjoint(with: kits), "a seat carries one or the other")
        #expect(!rigs.isEmpty && !kits.isEmpty, "the lattice exercises neither branch")

        // And a theme that is not a pod carries neither, at any seat.
        for (name, id) in Self.everyRoom(manifest) {
            let other = Self.metrics(manifest, theme: id)
            guard !other.isDeskPod else { continue }
            for seat in 0..<layout.seatCapacity {
                #expect(layout.monitorPosition(seat, metrics: other) == nil, "\(name)")
                #expect(layout.deskKitPosition(seat, metrics: other) == nil, "\(name)")
            }
        }
    }

    /// **The pod has two kit slots and they hold two different things.**
    ///
    /// The theme's screen rig takes the left one; ADR-006's work-kind object —
    /// the thing that says what this agent is doing — takes the right. Drawing a
    /// rig in both would leave nowhere for the live signal, which is why this
    /// asserts the two are a whole slot apart rather than merely different.
    @Test func theTwoPodSlotsHoldTwoDifferentThingsAWholeSlotApart() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let metrics = Self.metrics(manifest, theme: "office")
        let slot = layout.podSlotOffsetX(metrics: metrics)
        #expect(slot == 16, "the shipped pod's slots are ±16 of its desk's centre")
        #expect(slot * 2 == metrics.monitorInkWidth, Comment(rawValue:
            "the two slots are \(slot * 2)px apart against a \(metrics.monitorInkWidth)px"
            + " rig, so they overlap or leave a gap"))

        for seat in 0..<layout.seatCapacity {
            let desk = layout.deskPosition(seat, metrics: metrics)
            guard let rig = layout.monitorPosition(seat, metrics: metrics) else { continue }
            #expect(rig.x == desk.x - slot)
            // Both slots are wholly on the desk they stand on.
            let deskLeft = desk.x - metrics.deskInkWidth / 2
            let deskRight = desk.x + metrics.deskInkWidth / 2
            #expect(rig.x - metrics.monitorInkWidth / 2 >= deskLeft)
            #expect(desk.x + slot + metrics.monitorInkWidth / 2 <= deskRight)
        }
    }

    /// **Nothing standing on a camera-facing pod's desktop can cover a face**,
    /// and it is arithmetic rather than care.
    ///
    /// ADR-008 §5 left a camera-facing desk bare for two independent reasons, and
    /// the geometric one — *"the theme desk is 32 px wide and the body occupies
    /// all of it"* — expired when the desk became 64. What replaces it is this:
    /// the kit's lift plus its own ink height reaches no higher than the desk's
    /// back edge, so whatever its width it stands in front of pixels the desk was
    /// already covering. The honesty reason is untouched and is why the object
    /// there is a paper stack and not a screen.
    @Test func aCameraFacingPodsKitNeverRisesAboveItsOwnDeskEdge() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let room = manifest.room(theme: "office")
        let metrics = Self.metrics(manifest, theme: "office")
        let kit = try #require(room.prop(RoomScene.deskKitRole))
        let lift = layout.deskTopLift(
            surfaceHeightAboveFloor: metrics.deskInkHeight, metrics: metrics)
        #expect(lift + Double(kit.contentBox.height) <= metrics.deskInkHeight, Comment(
            rawValue: "the kit reaches \(lift + Double(kit.contentBox.height))px above the"
            + " desk's floor point against a \(metrics.deskInkHeight)px desk, so it"
            + " crosses the face the orientation exists to show"))
        // And it is inside its own desk in x, at every camera-facing seat.
        for seat in 0..<layout.seatCapacity {
            guard let point = layout.deskKitPosition(seat, metrics: metrics) else { continue }
            let desk = layout.deskPosition(seat, metrics: metrics)
            #expect(point.x - Double(kit.contentBox.width) / 2
                    >= desk.x - metrics.deskInkWidth / 2)
            #expect(point.x + Double(kit.contentBox.width) / 2
                    <= desk.x + metrics.deskInkWidth / 2)
        }
    }

    /// **A pod is centred on its occupant at both facings, and a narrow desk is
    /// not** — ADR-008 §7's own condition, as arithmetic.
    ///
    /// That section kept the away-facing desk beside its occupant and closed with
    /// the case in which it would not: *"The pack can centre its figure because
    /// its desk is 64 px wide with two monitors at ±16 and the person between
    /// them; ours is 32."* Ours is 64 now, so it centres — which is what puts a
    /// rig at each shoulder in `output/01-engineering-office.png`.
    @Test func aPodCentresItsAwayFacingOccupantAndANarrowDeskDoesNot() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        for (name, id) in Self.everyRoom(manifest) {
            let metrics = Self.metrics(manifest, theme: id)
            let offset = layout.awayDeskOffsetX(metrics: metrics)
            #expect(offset == (metrics.isDeskPod ? 0 : layout.sideOnDeskOffsetX),
                    "\(name): away desk offset \(offset)")
            for seat in 0..<layout.seatCapacity
            where layout.seatFacing(seat) == .awayFromCamera {
                let desk = layout.deskPosition(seat, metrics: metrics)
                #expect(desk.x == layout.seatPosition(seat).x + offset, "\(name)")
            }
            // A camera-facing desk was always centred and still is: nothing here
            // may move the facing that already had the reference's arrangement.
            for seat in 0..<layout.seatCapacity
            where layout.seatFacing(seat) == .towardCamera {
                #expect(layout.deskPosition(seat, metrics: metrics).x
                        == layout.seatPosition(seat).x, "\(name)")
            }
        }
    }

    /// **A pod does not reach into the next seat's lane, and it reaches less far
    /// than the bench it replaced.**
    ///
    /// The measured overhang from a desk's right edge to the lane the *next*
    /// seat's station prop stands in, per facing:
    ///
    /// | theme | desk | camera-facing | away-facing |
    /// |---|---|---:|---:|
    /// | five themes | 32×h | −32 | **−4** |
    /// | `mission_control` | 40×36 | −28 | **0** |
    /// | `office` | 64×38 | **−16** | **−16** |
    ///
    /// So the widest desk in the room is the one furthest from its neighbour,
    /// because a pod is centred on its column where a 32px desk stands seven
    /// eighths of a tile to its occupant's right. The risk a 64px desk looks like
    /// it carries is inverted by the placement it comes with.
    ///
    /// `everyStationFitsTheSeatItIsDrawnAt` asserts the same bound over every
    /// theme; this states the numbers, so a change that keeps the bound and moves
    /// the margin still has to be looked at.
    @Test func aPodDoesNotReachIntoTheNextSeatsLane() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let pitch = layout.seatPosition(1).x - layout.seatPosition(0).x
        let laneHalf = Double(manifest.characters.canvas.width) / 2
        // **The lane one pitch to the right, by column rather than by seat
        // index.** `seat + 1` is not the seat to the right — seats fill outward
        // in pairs, so seat 1 is a pitch right of seat 0 and seat 2 is a pitch
        // *left* of it. Every column in this room is some seat's, and a station
        // prop stands a tile to its own character's left, so the lane a pitch
        // over starts at `x + pitch − tile − halfCanvas` whichever seat owns it.
        func laneLeft(_ seat: Int) -> Double {
            layout.seatPosition(seat).x + pitch - Double(layout.tile) - laneHalf
        }
        func overhang(_ id: String?, seat: Int) -> Double {
            let metrics = Self.metrics(manifest, theme: id)
            return layout.deskPosition(seat, metrics: metrics).x
                + metrics.deskInkWidth / 2 - laneLeft(seat)
        }
        // The rule is the same one `stationPropPosition` is written against, so
        // it is checked against that function rather than merely stated.
        #expect(laneLeft(0)
                == layout.stationPropPosition(1).x
                    - Double(manifest.characters.canvas.width) / 2)
        // Seat 0 faces the camera, seat 1 faces away — one of each, and the two
        // are a pitch apart so the lane arithmetic is the same shape at both.
        #expect(layout.seatFacing(0) == .towardCamera)
        #expect(layout.seatFacing(1) == .awayFromCamera)
        #expect(overhang("office", seat: 0) == -16)
        #expect(overhang("office", seat: 1) == -16)
        #expect(overhang("mission_control", seat: 1) == 0)
        #expect(overhang("library", seat: 1) == -4)
        #expect(pitch == 96, "these numbers are derived from the seat pitch")

        // The office pod overlaps its **own** station-prop lane by 16px, and that
        // is stated rather than discovered. The lane is a tile to the character's
        // left and 32px wide, so it spans `x−48 … x−16`, and a 64px desk centred
        // on the column reaches `x−32`. The two are on **different rows** — the
        // prop stands on the seat row, the desk a facing's depth away from it —
        // so `Character.Layer.rowDepth` sorts them deterministically and neither
        // is a character. Nothing about a body or a nameplate is touched: the
        // prop still stops a whole half-canvas short of the seat's own column,
        // which `everyStationFitsTheSeatItIsDrawnAt` asserts.
        let office = Self.metrics(manifest, theme: "office")
        let ownLaneRight = layout.stationPropPosition(0).x + laneHalf
        let deskLeft = layout.deskPosition(0, metrics: office).x - office.deskInkWidth / 2
        #expect(ownLaneRight - deskLeft == 16, Comment(rawValue:
            "the office pod laps its own station-prop lane by"
            + " \(ownLaneRight - deskLeft)px, and 16 is the number ADR-009 records"))
        #expect(layout.deskPosition(0, metrics: office).y != layout.seatRowY(0),
                "the lap would be a tie on one row rather than a depth sort")
    }

    /// **The room draws what the layout says, in every theme.** The arithmetic
    /// above is only worth having if the scene reads it, and the failure it has
    /// to catch — a pod whose kit was placed at `surface_y`, or drawn at a
    /// camera-facing seat — produces perfectly correct node counts.
    @MainActor @Test(.enabled(if: SceneArt.isAvailable))
    func theRoomDrawsAScreenRigAtEveryAwayFacingSeatOfThePodAndNowhereElse() throws {
        let manifest = try SceneFixtures.manifest()
        for (name, id) in Self.everyRoom(manifest) {
            guard id != nil else { continue }   // `room` is not a theme the scene dresses in
            let scene = RoomScene(manifest: manifest, themeID: id)
            scene.setViewport(CGSize(width: 720, height: 400))
            let metrics = Self.metrics(manifest, theme: id)
            let room = manifest.room(theme: id)
            var rigs = 0
            var kits = 0
            for seat in 0..<scene.layout.seatCapacity {
                let drawn = scene.furnitureForTesting(seat: seat)
                for piece in drawn where piece.path == room.prop(RoomScene.monitorRole)?.file {
                    rigs += 1
                    let point = try #require(scene.layout.monitorPosition(seat, metrics: metrics))
                    #expect(piece.x == point.x && piece.y == point.y, "\(name) seat \(seat)")
                }
                for piece in drawn where piece.path == room.prop(RoomScene.deskKitRole)?.file {
                    kits += 1
                    let point = try #require(scene.layout.deskKitPosition(seat, metrics: metrics))
                    #expect(piece.x == point.x && piece.y == point.y, "\(name) seat \(seat)")
                }
            }
            let away = (0..<scene.layout.seatCapacity)
                .filter { scene.layout.seatFacing($0) == .awayFromCamera }.count
            let toward = scene.layout.seatCapacity - away
            #expect(rigs == (metrics.isDeskPod ? away : 0), "\(name) drew \(rigs) rigs")
            #expect(kits == (metrics.isDeskPod ? toward : 0), "\(name) drew \(kits) kits")
        }
    }
}
