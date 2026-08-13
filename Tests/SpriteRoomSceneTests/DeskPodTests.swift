import Foundation
import Testing
import SpriteRoomCore
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
        let kit = try #require(manifest.room(theme: "office").prop(RoomScene.deskKitRole))
        let kitHeight = Double(kit.contentBox.height)
        var rigs: [Int] = []
        var kits: [Int] = []
        for seat in 0..<layout.seatCapacity {
            if layout.monitorPosition(seat, metrics: metrics) != nil { rigs.append(seat) }
            if RoomLayout.PodKitSlot.allCases.contains(where: {
                layout.deskKitPosition(
                    seat, slot: $0, inkHeight: kitHeight, metrics: metrics) != nil
            }) { kits.append(seat) }
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
                for slot in RoomLayout.PodKitSlot.allCases {
                    #expect(layout.deskKitPosition(
                        seat, slot: slot, inkHeight: kitHeight, metrics: other) == nil, "\(name)")
                }
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
    /// an object's lift plus its own ink height reaches no higher than the desk's
    /// back edge, so whatever its width it stands in front of pixels the desk was
    /// already covering. The honesty reason is untouched and is why the objects
    /// there are paper and a mug and not a screen.
    ///
    /// Stated over **every ink height a desktop object could have**, not over the
    /// one the shipped stock happens to carry: this is the property
    /// `deskKitLift` is written to hold by construction, so the test that would
    /// catch it being written some other way has to quantify over heights. What
    /// the shipped four measure is
    /// `everyObjectTheShippedStockPutsOnADesktopClearsTheFace`.
    @Test func noDesktopObjectOfAnyHeightRisesAboveItsOwnDeskEdge() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let metrics = Self.metrics(manifest, theme: "office")
        var refused: [Double] = []
        for height in stride(from: 1.0, through: metrics.deskInkHeight + 8, by: 1) {
            for slot in RoomLayout.PodKitSlot.allCases {
                guard let lift = layout.deskKitLift(
                    inkHeight: height, slot: slot, metrics: metrics) else {
                    refused.append(height)
                    continue
                }
                #expect(lift >= 0, Comment(rawValue:
                    "\(slot) hangs a \(height)px object \(-lift)px below its desk's own"
                    + " floor point, which is off the front edge rather than on the top"))
                #expect(lift + height <= metrics.deskInkHeight, Comment(rawValue:
                    "\(slot) reaches \(lift + height)px above the desk's floor point with a"
                    + " \(height)px object, against a \(metrics.deskInkHeight)px desk — so it"
                    + " crosses the face the orientation exists to show"))
            }
        }
        // The refusal is a real branch and it is exactly the objects taller than
        // the desk: there is no lift for those that is both on the desktop and
        // under its back edge, so I1's answer is to draw nothing.
        #expect(Set(refused) == Set(stride(from: metrics.deskInkHeight + 1,
                                           through: metrics.deskInkHeight + 8, by: 1)),
                "refused heights: \(Set(refused).sorted())")
    }

    /// **The shipped desktop stock, each object measured, against that bound.**
    ///
    /// The test above quantifies over heights the room might one day carry; this
    /// one is the four objects it carries today, at their own measured ink — the
    /// manifest declares one `content_box` for the `desk_kit` role and the stock
    /// is four singles cut from four source sheets, so an object's clearance
    /// cannot be read out of the role.
    ///
    /// It is also where the reference's own arithmetic is checked and where it is
    /// **not** followed: `scripts/compose-scene.py`'s `desk_pod` draws the folder
    /// at `on_desk(16)`, and the folder is 24 px, so 16 + 24 = 40 against a 38 px
    /// desk. Transcribing that lift would put two rows of folder into the torso
    /// of the character the camera-facing seat exists to show a face of. The lift
    /// is derived per object instead and the folder sits 2 px lower than the
    /// reference draws it.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyObjectTheShippedStockPutsOnADesktopClearsTheFace() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let metrics = Self.metrics(manifest, theme: "office")
        let kit = try #require(manifest.room(theme: "office").prop(RoomScene.deskKitRole))
        #expect(kit.variants.count == 4, "the office stock is \(kit.variants.count) objects")

        var checked = 0
        for (index, path) in kit.variants.enumerated() {
            let box = try #require(SceneFixtures.inkBox(manifest, path: path),
                                   "no ink measured in \(path)")
            let height = Double(box.height)
            for slot in RoomLayout.PodKitSlot.allCases {
                let lift = try #require(
                    layout.deskKitLift(inkHeight: height, slot: slot, metrics: metrics),
                    Comment(rawValue:
                        "stock \(index) (\(path), \(box.width)×\(box.height)) is too tall for"
                        + " a \(metrics.deskInkHeight)px desk and would have to be refused"))
                #expect(lift + height <= metrics.deskInkHeight, Comment(rawValue:
                    "stock \(index) at \(slot) reaches \(lift + height)px against a"
                    + " \(metrics.deskInkHeight)px desk"))
                // In x too, at every seat that draws one.
                for seat in 0..<layout.seatCapacity {
                    guard let point = layout.deskKitPosition(
                        seat, slot: slot, inkHeight: height, metrics: metrics) else { continue }
                    let desk = layout.deskPosition(seat, metrics: metrics)
                    #expect(point.x - Double(box.width) / 2 >= desk.x - metrics.deskInkWidth / 2,
                            "stock \(index) at \(slot) hangs off the left of seat \(seat)'s desk")
                    #expect(point.x + Double(box.width) / 2 <= desk.x + metrics.deskInkWidth / 2,
                            "stock \(index) at \(slot) hangs off the right of seat \(seat)'s desk")
                    checked += 1
                }
            }
        }
        #expect(checked > 0, "no seat drew any of the stock, so this checked nothing")

        // The reference's own lift for the folder, stated as the thing that was
        // refused rather than left as a silence.
        let folder = try #require(SceneFixtures.inkBox(manifest, path: kit.variants[1]))
        #expect(16 + Double(folder.height) > metrics.deskInkHeight, Comment(rawValue:
            "compose-scene.py's on_desk(16) now clears the desk edge for a"
            + " \(folder.height)px folder, so the paragraph above is stale"))
        #expect(layout.deskKitLift(inkHeight: Double(folder.height), slot: .backLeft,
                                   metrics: metrics) == 14)
    }

    /// **The point this room already drew a kit at is still a point it draws a
    /// kit at.** [ADR-009]
    ///
    /// The paper stack stood in the right-hand slot at a lift of 16, which was
    /// `deskTopLift` — the rig's number. `backRight` is that slot, and its lift
    /// for that object is now `deskInkHeight − inkHeight`, which is the object's
    /// own art's number, and 38 − 22 is also 16. Two derivations meeting is worth
    /// pinning: if a future desk or a future rig separates them, the diff should
    /// say so rather than quietly moving a prop that nothing in this change was
    /// about.
    ///
    /// **Which object stands there is the seat's**, so the paper stack itself
    /// holds this slot at seat 0 and rotates out of it at seat 2 —
    /// `everyCameraFacingSeatCarriesTheWholeStockAndTwoSeatsArrangeItDifferently`
    /// is where that is stated. What does not move is the geometry.
    @Test func theSlotThisRoomAlreadyDrewAKitInIsExactlyWhereItWas() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let metrics = Self.metrics(manifest, theme: "office")
        let kit = try #require(manifest.room(theme: "office").prop(RoomScene.deskKitRole))
        let height = Double(kit.contentBox.height)
        let lift = try #require(
            layout.deskKitLift(inkHeight: height, slot: .backRight, metrics: metrics))
        #expect(lift == layout.deskTopLift(
            surfaceHeightAboveFloor: metrics.deskInkHeight, metrics: metrics))
        for seat in 0..<layout.seatCapacity {
            guard let point = layout.deskKitPosition(
                seat, slot: .backRight, inkHeight: height, metrics: metrics) else { continue }
            let desk = layout.deskPosition(seat, metrics: metrics)
            #expect(point.x == desk.x + layout.podSlotOffsetX(metrics: metrics))
            #expect(point.y == desk.y + lift)
        }
        // And entry 0 of the stock is that same object: the manifest's `file`.
        #expect(kit.variants.first == kit.file)
        #expect(kit.variant(0).file == kit.file)
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
            let rigStock = Set(room.prop(RoomScene.monitorRole)?.variants ?? [])
            let kitStock = Set(room.prop(RoomScene.deskKitRole)?.variants ?? [])
            var rigs = 0
            var kits = 0
            for seat in 0..<scene.layout.seatCapacity {
                let drawn = scene.furnitureForTesting(seat: seat)
                for piece in drawn where rigStock.contains(piece.path) {
                    rigs += 1
                    let point = try #require(scene.layout.monitorPosition(seat, metrics: metrics))
                    #expect(piece.x == point.x && piece.y == point.y, "\(name) seat \(seat)")
                }
                // **Each object against the slot the layout puts it in**, at its
                // own measured ink height — the whole point of the stock being
                // four objects rather than four alternatives is that they are not
                // interchangeable in y.
                let kitPieces = drawn.filter { kitStock.contains($0.path) }
                kits += kitPieces.count
                for piece in kitPieces {
                    let box = try #require(SceneFixtures.inkBox(manifest, path: piece.path))
                    let points = RoomLayout.PodKitSlot.allCases.compactMap {
                        scene.layout.deskKitPosition(
                            seat, slot: $0, inkHeight: Double(box.height), metrics: metrics)
                    }
                    #expect(points.contains { $0.x == piece.x && $0.y == piece.y }, Comment(
                        rawValue: "\(name) seat \(seat) drew \(piece.path) at"
                        + " \(piece.x),\(piece.y); its four slots are \(points)"))
                }
            }
            let away = (0..<scene.layout.seatCapacity)
                .filter { scene.layout.seatFacing($0) == .awayFromCamera }.count
            let toward = scene.layout.seatCapacity - away
            let slots = RoomLayout.PodKitSlot.allCases.count
            #expect(rigs == (metrics.isDeskPod ? away : 0), "\(name) drew \(rigs) rigs")
            #expect(kits == (metrics.isDeskPod ? toward * slots : 0),
                    "\(name) drew \(kits) desktop objects")
        }
    }

    // MARK: Stock — `variants` [I1, ADR-002 §6 rule 1]

    /// **A role with no `variants` draws its `file`, and that is the whole of
    /// what a variant-blind reader sees.**
    ///
    /// Stated over every role of every theme, so the five themes that declare no
    /// stock at all are covered by construction rather than by inspection: for
    /// them `variants` is `[file]` and `variant(n)` is the role itself at every
    /// `n`, including negative ones and ones past the end.
    @Test func aRoleWithNoStockDrawsItsFileAtEverySeat() throws {
        let manifest = try SceneFixtures.manifest()
        var stocked: [String] = []
        var plain = 0
        for (name, id) in Self.everyRoom(manifest) {
            let room = manifest.room(theme: id)
            for (role, prop) in room.propRoles.sorted(by: { $0.key < $1.key }) {
                #expect(prop.variants.first == prop.file, Comment(rawValue:
                    "\(name).\(role) leads its stock with \(prop.variants.first ?? "nothing"),"
                    + " not with its own \(prop.file) — a variant-blind reader and this one"
                    + " would draw different pictures"))
                #expect(Set(prop.variants).count == prop.variants.count,
                        "\(name).\(role) declares the same file twice")
                guard prop.variants.count > 1 else {
                    plain += 1
                    for index in -3...11 {
                        #expect(prop.variant(index) == prop, Comment(rawValue:
                            "\(name).\(role) has no stock and variant \(index) is not itself"))
                    }
                    continue
                }
                stocked.append("\(name).\(role)")
            }
        }
        #expect(plain > 0 && !stocked.isEmpty, "stocked: \(stocked), plain: \(plain)")
        #expect(stocked == ["office.desk_kit", "office.monitor"], "stocked: \(stocked)")
    }

    /// **A malformed `variants` costs the room its stock and never its props.**
    ///
    /// The decoder is total over this key by construction — `PropRole.init` is
    /// the only way to build one and it discards anything that does not lead with
    /// `file`. The cases are the ones a hand-edited or half-generated manifest
    /// produces: the key absent, an empty list, a list that leads with something
    /// else, and a list carrying an empty path.
    @Test func aMalformedStockListDegradesToTheFileItself() throws {
        let box = Manifest.PropRole.Box(x: 0, y: 0, width: 8, height: 8)
        func role(_ variants: [String]?) -> Manifest.PropRole {
            Manifest.PropRole(
                file: "a.png", contentBox: box, animation: nil, surfaceY: nil,
                variants: variants)
        }
        #expect(role(nil).variants == ["a.png"])
        #expect(role([]).variants == ["a.png"])
        #expect(role(["b.png", "a.png"]).variants == ["a.png"])
        #expect(role(["a.png", ""]).variants == ["a.png"])
        #expect(role(["a.png", "b.png"]).variants == ["a.png", "b.png"])
        // And the wrap is total, including on a negative index — a caller hands
        // this a seat number without knowing how much stock there is.
        let stocked = role(["a.png", "b.png", "c.png"])
        #expect((0...6).map { stocked.variant($0).file }
                == ["a.png", "b.png", "c.png", "a.png", "b.png", "c.png", "a.png"])
        #expect(stocked.variant(-1).file == "c.png")
        // A variant is drawn from its own file, so it cannot inherit frames whose
        // frame 0 is a different picture.
        let animated = Manifest.PropRole(
            file: "a.png", contentBox: box,
            animation: Manifest.PropRole.Animation(
                frames: ["a.png", "a1.png"], fps: 8, loops: true),
            surfaceY: nil, variants: ["a.png", "b.png"])
        #expect(animated.variant(0).animation != nil)
        #expect(animated.variant(1).animation == nil)
        // Stock is art the room draws, so the gate has to know about it.
        #expect(animated.declaredPaths == ["a.png", "a1.png", "b.png"])
    }

    /// **Variant 0's measured box is the one the manifest declares.**
    ///
    /// This is what ties the scene's measurement (`TextureStore.inkBox`) to the
    /// manifest generator's (`scripts/build-manifest.py`'s `content_box`) and to
    /// the tests' own third copy (`SceneFixtures.inkBox`). They agree on the file
    /// all three can see, which is what makes it credible that the measured box
    /// is the right thing to place entries 1…N against — the entries no
    /// `content_box` exists for.
    @Test(.enabled(if: SceneArt.isAvailable))
    func variantZeroSMeasuredBoxIsTheOneTheManifestDeclares() throws {
        let manifest = try SceneFixtures.manifest()
        var checked = 0
        for (name, id) in Self.everyRoom(manifest) {
            let room = manifest.room(theme: id)
            for (role, prop) in room.propRoles.sorted(by: { $0.key < $1.key }) {
                // An animated role's box is the union over its frames, which is
                // deliberately not one frame's ink. [Manifest.PropRole.contentBox]
                guard prop.animation == nil else { continue }
                let measured = try #require(SceneFixtures.inkBox(manifest, path: prop.file),
                                            "\(name).\(role): no ink in \(prop.file)")
                #expect(measured == prop.contentBox, Comment(rawValue:
                    "\(name).\(role) declares \(prop.contentBox) and its file measures"
                    + " \(measured)"))
                checked += 1
            }
        }
        #expect(checked > 0)
    }

    /// **Every camera-facing pod carries the whole stock, and two seats arrange
    /// it differently.** This is the visible half of the change: seven desks that
    /// drew one identical paper stack now draw four objects each, and not in the
    /// same order.
    ///
    /// **The key is the seat and nothing else.** Entry `(slot + seat) % count`,
    /// evaluated when the room is built and never again — no agent, no tool, no
    /// open-call count, nothing hashed out of a payload. `theSameSeatDrawsTheSame
    /// StockWhoeverIsSittingInIt` is the other half of that sentence.
    @MainActor @Test(.enabled(if: SceneArt.isAvailable))
    func everyCameraFacingSeatCarriesTheWholeStockAndTwoSeatsArrangeItDifferently() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest, themeID: "office")
        scene.setViewport(CGSize(width: 720, height: 400))
        let metrics = Self.metrics(manifest, theme: "office")
        let kit = try #require(manifest.room(theme: "office").prop(RoomScene.deskKitRole))
        let rig = try #require(manifest.room(theme: "office").prop(RoomScene.monitorRole))

        var arrangements: [Int: [String]] = [:]
        var rigs: [Int: String] = [:]
        for seat in 0..<scene.layout.seatCapacity {
            let pieces = scene.podFurniture(seat: seat, metrics: metrics)
            let kits = pieces.filter { $0.role == RoomScene.deskKitRole }
            if scene.layout.seatFacing(seat) == .towardCamera {
                #expect(Set(kits.map(\.prop.file)) == Set(kit.variants), Comment(rawValue:
                    "seat \(seat) carries \(kits.map(\.prop.file)) of \(kit.variants)"))
                arrangements[seat] = kits.map(\.prop.file)
            } else {
                #expect(kits.isEmpty, "seat \(seat) faces away and carries kit anyway")
            }
            if let piece = pieces.first(where: { $0.role == RoomScene.monitorRole }) {
                #expect(rig.variants.contains(piece.prop.file))
                rigs[seat] = piece.prop.file
            }
        }
        #expect(arrangements.count >= 2 && rigs.count >= 2)
        #expect(Set(arrangements.values.map { $0.joined(separator: ",") }).count > 1, Comment(
            rawValue: "every camera-facing seat arranges its stock identically:"
            + " \(arrangements.sorted { $0.key < $1.key })"))
        #expect(Set(rigs.values).count > 1, Comment(rawValue:
            "every away-facing seat drew the same rig: \(rigs.sorted { $0.key < $1.key })"))

        // Entry 0 is where a variant-blind reader would have put it — the right
        // back slot of seat 0 — so the change did not move the picture this room
        // already drew, it added to it.
        #expect(arrangements[0]?.first == kit.file)
        for (seat, file) in rigs {
            #expect(file == rig.variants[seat % rig.variants.count],
                    "seat \(seat) drew \(file)")
        }

        // And the room drew it: `podFurniture` is only worth checking because
        // `buildRoom` reads it.
        let drawn = Set((0..<scene.layout.seatCapacity)
            .flatMap { scene.furnitureForTesting(seat: $0) }.map(\.path))
        for file in kit.variants {
            #expect(drawn.contains(file), "the room never drew \(file)")
        }

        // **Two of the four rigs never reach the screen, and that is a fact
        // about the lattice rather than about this mechanism.** Every away-facing
        // seat is a back-row seat, the back row is seats 1, 2, 5 and 6, and
        // `seat % 4` over those is 1, 2, 1, 2 — so the stock's entries 0 and 3
        // have no seat to stand at. Pinned rather than left to be noticed later:
        // the desktop stock does not have the problem (every camera-facing seat
        // carries all four objects), so it is the rig's key that would have to
        // change, and changing it is a decision about the lattice.
        let away = (0..<scene.layout.seatCapacity)
            .filter { scene.layout.seatFacing($0) == .awayFromCamera }
        #expect(away == [1, 2, 5, 6], "away-facing seats: \(away)")
        #expect(Set(rigs.values).count == 2, Comment(rawValue:
            "the away-facing seats now reach \(Set(rigs.values).count) of"
            + " \(rig.variants.count) rigs; if that is 4 the note above is stale"))
    }

    /// **The same seat draws the same stock whoever is sitting in it**, and an
    /// empty seat draws what an occupied one does.
    ///
    /// The failure this exists to catch is the one ADR-002 §6 rule 1 and I1 both
    /// forbid: a prop that changed because an agent did something. Two different
    /// agents — different variant, different type, different work — take seat 0
    /// in two scenes, and the desktop is identical.
    @MainActor @Test(.enabled(if: SceneArt.isAvailable))
    func theSameSeatDrawsTheSameStockWhoeverIsSittingInIt() throws {
        let manifest = try SceneFixtures.manifest()

        func desktop(agent: AgentRef?, type: String?) -> [String: [String]] {
            let scene = RoomScene(manifest: manifest, themeID: "office")
            scene.setViewport(CGSize(width: 720, height: 400))
            if let agent {
                var director = SceneDirector(manifest: manifest)
                scene.apply(director.apply(
                    [.agentAppeared(agent: agent, agentType: type, lifecycle: .active)],
                    at: Date(timeIntervalSince1970: 0)))
                let start = Date(timeIntervalSince1970: 1)
                scene.apply(director.apply(
                    [.callOpened(agent: agent, call: OpenCall(
                        toolUseID: "c1", toolName: "Bash", startedAt: start,
                        deadline: start.addingTimeInterval(60)))],
                    at: start))
            }
            var out: [String: [String]] = [:]
            let stock = Set((manifest.room(theme: "office").prop(RoomScene.deskKitRole)?.variants
                             ?? []) + (manifest.room(theme: "office")
                                        .prop(RoomScene.monitorRole)?.variants ?? []))
            for seat in 0..<scene.layout.seatCapacity {
                out["\(seat)"] = scene.furnitureForTesting(seat: seat)
                    .filter { stock.contains($0.path) }
                    .map { "\($0.path)@\(Int($0.x)),\(Int($0.y))" }.sorted()
            }
            return out
        }

        let main = AgentRef(project: "/p", session: "s", agent: .mainThread)
        let sub = AgentRef(project: "/p", session: "s2", agent: .subagent("a0000000000000ff"))
        let empty = desktop(agent: nil, type: nil)
        let first = desktop(agent: main, type: "Explore")
        let second = desktop(agent: sub, type: "security-reviewer")
        #expect(!empty.values.flatMap { $0 }.isEmpty, "no seat drew any stock at all")
        #expect(first == empty, "an occupied desktop differs from an empty one")
        #expect(second == empty, "the desktop is a function of who is sitting at it")
    }
}
