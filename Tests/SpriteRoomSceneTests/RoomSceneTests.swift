import Foundation
import SpriteKit
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// The SpriteKit half. These run on the main actor because SpriteKit nodes do.
///
/// Mixed suite. The tests that need real pixels — anything that loads a texture,
/// plays an animation or places a prop — are gated on `SceneArt`, because
/// `assets/` is not in the repository; see `SceneFixtures.swift`. The layout,
/// camera and depth-ordering tests derive everything from the tracked
/// manifest and `RoomLayout`, so they run on any checkout and are not gated.
@MainActor
struct RoomSceneTests {

    static func store() throws -> TextureStore {
        TextureStore(manifest: try SceneFixtures.manifest())
    }

    /// The main agent plus `count - 1` subagents, in seat order. Ids are
    /// distinct so the plates are, which is what the geometry tests measure.
    static func cast(_ count: Int) -> [AgentRef] {
        (0..<count).map { index in
            AgentRef(
                project: "/p", session: "s",
                agent: index == 0 ? .mainThread : .subagent(String(format: "a%016x", index)))
        }
    }

    // MARK: The standing rule

    /// **`.nearest` on every texture, no mipmaps.** A single texture created
    /// without it looks wrong in a way that is very hard to trace later, so
    /// this checks the room, the characters, the badges and the generated
    /// bitmaps — every path a texture can be born through.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyTextureIsNearestFilteredWithNoMipmaps() throws {
        let store = try Self.store()
        var textures: [SKTexture] = []

        let tiles = store.roomTileChoice()
        textures += [tiles.floor, tiles.wall].compactMap { store.texture(path: $0) }
        for badge in ToolBadge.allCases {
            textures += [store.badgeTexture(badge)].compactMap { $0 }
        }
        for id in store.manifest.characters.orderedVariantIDs {
            for state in BodyState.allCases {
                for facing in Facing.allCases {
                    textures += store.frames(variant: id, state: state, facing: facing)
                }
            }
        }
        textures += [
            store.texture(
                bitmap: SceneBitmaps.nameplate(
                    NameplateText(lead: "MAIN"), accent: Bitmap.RGBA(255, 0, 0)),
                key: "test:nameplate"),
            store.texture(bitmap: SceneBitmaps.badgeCount(3), key: "test:count"),
            store.texture(bitmap: SceneBitmaps.placeholderDesk(), key: "test:desk"),
        ].compactMap { $0 }

        #expect(textures.count > 100, "not enough textures were exercised")
        for texture in textures {
            #expect(texture.filteringMode == .nearest)
            #expect(texture.usesMipmaps == false)
        }
    }

    // MARK: Criterion 2 — all six body states play

    @Test(.enabled(if: SceneArt.isAvailable))
    func everyVariantHasPlayableFramesForAllSixStates() throws {
        let store = try Self.store()
        for id in store.manifest.characters.orderedVariantIDs {
            for state in BodyState.allCases {
                let facing: Facing = state == .working ? .right : .down
                let frames = store.frames(variant: id, state: state, facing: facing)
                #expect(!frames.isEmpty, "variant \(id) state \(state) has no frames")
            }
        }
    }

    /// Asking for a seated character facing the camera is asking for art that
    /// was never drawn; the store falls back to the nearest side view rather
    /// than rendering nothing.
    @Test(.enabled(if: SceneArt.isAvailable))
    func workingFacingUpOrDownFallsBackToASideView() throws {
        let store = try Self.store()
        let id = store.manifest.characters.orderedVariantIDs[0]
        let up = store.frames(variant: id, state: .working, facing: .up)
        let right = store.frames(variant: id, state: .working, facing: .right)
        #expect(!up.isEmpty)
        #expect(up == right)
    }

    @Test(.enabled(if: SceneArt.isAvailable))
    func aCharacterCanEnterEverySixStateAndReportsIt() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        var seen: Set<BodyState> = []
        for state in BodyState.allCases {
            character.apply(state: state, facing: state == .working ? .right : .down)
            if let current = character.state { seen.insert(current) }
        }
        #expect(seen == Set(BodyState.allCases))
    }

    // MARK: The animation state machine

    /// Re-applying the state a character already has must not restart the
    /// animation. This is what keeps a burst of short calls from stuttering.
    /// [I2/I3]
    @Test(.enabled(if: SceneArt.isAvailable))
    func reapplyingTheSameStateDoesNotRestartTheAnimation() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        character.advance(to: 0)
        character.apply(state: .working, facing: .right)
        character.advance(to: 0.30)      // ~frame 2 at 8 fps
        let before = character.currentTextureForTesting

        character.apply(state: .working, facing: .right)   // same state, same facing
        character.advance(to: 0.30)
        #expect(character.currentTextureForTesting === before)
    }

    /// `walk` rather than `idle`, and the swap is the point: `idle` is now a
    /// single held frame [`AmbientMotion.idleSequence`], so the looping-and-
    /// wrapping property this test exists for has to be checked on a state that
    /// still loops. `walk` is the same six-frame animation `idle` was.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aLoopingStateCyclesAndNeverRunsOffTheEnd() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        character.advance(to: 0)
        character.apply(state: .walk, facing: .down)
        var textures: Set<ObjectIdentifier> = []
        for step in 0..<200 {
            character.advance(to: Double(step) / 60.0)
            if let texture = character.currentTextureForTesting {
                textures.insert(ObjectIdentifier(texture))
            }
        }
        #expect(textures.count == 6, "walk should cycle its six frames")
    }

    /// **The same clock over an idle character puts one texture on screen.**
    ///
    /// The unit-level statement is `AmbientMotionTests.anIdleBodyHoldsOneFrame`;
    /// this is the same claim made where it is actually observable — through the
    /// texture the node is wearing, over 200 frames of the room's own clock. The
    /// defect it pins was measured in pixels, so it deserves an assertion nearer
    /// the pixels than the sequence array.
    @Test(.enabled(if: SceneArt.isAvailable))
    func anIdleCharacterPutsOneTextureOnScreenForever() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        character.advance(to: 0)
        character.apply(state: .idle, facing: .down)
        var textures: Set<ObjectIdentifier> = []
        for step in 0..<200 {
            character.advance(to: Double(step) / 60.0)
            if let texture = character.currentTextureForTesting {
                textures.insert(ObjectIdentifier(texture))
            }
        }
        #expect(textures.count == 1, "an idle body moved")
    }

    // MARK: Choreography

    @Test(.enabled(if: SceneArt.isAvailable))
    func aSpawningCharacterWalksUpItsOwnColumnAndSettles() throws {
        let store = try Self.store()
        let layout = RoomLayout()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        character.advance(to: 0)
        character.setResting(.idle, facing: .right)
        let route = layout.entranceRoute(forSeat: 3)
        character.enter(along: route)
        character.advance(to: 0)
        #expect(character.state == .spawn)
        #expect(character.position == CGPoint(x: route[0].x, y: route[0].y))
        #expect(Double(character.position.y) == layout.aisleY,
                "the walk-in does not start on the walkway")

        // Every frame of it is inside seat 3's column and every step of it is
        // upstage — the two properties the lattice rests on, checked over the
        // walk rather than at its ends.
        var previous = Double(character.position.y)
        var strayed = 0
        for step in 1...600 {
            character.advance(to: Double(step) / 60.0)
            if abs(Double(character.position.x) - layout.seatPosition(3).x) > 1e-6 { strayed += 1 }
            #expect(Double(character.position.y) >= previous, "the walk-in moved downstage")
            previous = Double(character.position.y)
        }
        #expect(strayed == 0, "the walk-in left its own column")
        #expect(character.position == CGPoint(
            x: layout.seatPosition(3).x, y: layout.seatPosition(3).y),
            "the walk-in ends at the desk, not the aisle")
        #expect(character.state == .idle, "the walk-in must hand back to the data's state")
    }

    /// **The walk-in is visible from its first frame**, which is what the old
    /// outward-aisle start bought and what moving it had to keep. The walkway is
    /// inside the band the camera frames, by construction rather than by
    /// measurement of one case: the band's bottom *is* a walkway character's
    /// plate.
    @Test func everySeatWalksInFromInsideTheFrame() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let band = scene.contentBand
        let layout = scene.layout
        let plateDrop = Double(SceneBitmaps.maximumNameplateHeight + 2)
        for seat in 0..<layout.seatCapacity {
            let start = layout.entranceRoute(forSeat: seat)[0]
            #expect(start.y - plateDrop >= band.bottom, Comment(rawValue:
                "seat \(seat) starts its walk-in"
                + " \(band.bottom - (start.y - plateDrop)) px below the frame"))
            #expect(start.y <= band.top, "seat \(seat) starts its walk-in above the frame")
            #expect(start.x == layout.seatPosition(seat).x,
                    "seat \(seat) starts its walk-in outside its own column")
        }
    }

    /// The one dramatisation the event model licenses: walk, deliver, **walk
    /// back**. All of it has to actually play, in that order, and it has to end
    /// with the character in the chair it started in.
    ///
    /// This is the whole beat now. It used to be the front half of an exit — the
    /// walk-off was carried by the `agentDeparted` that `SubagentStop` emitted
    /// behind `reportDelivered`. A subagent that stops goes dormant in its seat,
    /// so nothing follows the report and the round trip is the entire
    /// choreography.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theReportWalkGoesToTheAnchorDeliversAndComesHome() throws {
        let store = try Self.store()
        let character = Character(
            variant: "07", nameplate: NameplateText(lead: "6E7", role: "Explore"), store: store)
        character.advance(to: 0)
        character.setResting(.idle, facing: .right)
        let seat = ScenePoint(x: 496, y: 64)
        character.position = CGPoint(x: seat.x, y: seat.y)
        var finished = false
        // Out along the real route: one leg, straight down the character's own
        // column onto the walkway. Nothing in this beat moves sideways any more.
        character.reportAndReturn(
            out: [ScenePoint(x: 496, y: 32)],
            facing: .left,
            home: [seat],
            onFinished: { finished = true })

        var states: [BodyState] = []
        var deliveredAt: CGPoint?
        var time = 0.0
        while time < 20 {
            character.advance(to: time)
            if let state = character.state, states.last != state { states.append(state) }
            if character.state == .deliver, deliveredAt == nil { deliveredAt = character.position }
            time += 1.0 / 60.0
        }
        #expect(states == [.walk, .deliver, .walk, .idle])
        #expect(deliveredAt == CGPoint(x: 496, y: 32),
                "the hand-over happens on the walkway, in the reporter's own column")
        #expect(finished)
        #expect(character.position == CGPoint(x: seat.x, y: seat.y),
                "the round trip has to end in the chair it started in")
        #expect(!character.isScripted)
        #expect(character.state == .idle, "the walk hands the body back to the data's state")
    }

    /// The truncated form: reported *and* departed in the same frame, which is
    /// a `SessionEnd` landing on top of a `SubagentStop`. Walk, deliver, depart.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theReportWalkPlaysWalkThenDeliverThenDepart() throws {
        let store = try Self.store()
        let character = Character(variant: "07", nameplate: NameplateText(lead: "6E7", role: "Explore"), store: store)
        character.advance(to: 0)
        character.position = CGPoint(x: 496, y: 64)
        var finished = false
        character.reportAndDepart(
            out: [ScenePoint(x: 496, y: 32)],
            facing: .left,
            home: [ScenePoint(x: 496, y: 64)],
            thenExitAt: ScenePoint(x: 496, y: 224)) { finished = true }

        var states: [BodyState] = []
        var time = 0.0
        while time < 20 {
            character.advance(to: time)
            if let state = character.state, states.last != state { states.append(state) }
            time += 1.0 / 60.0
        }
        // The scene removes the node the moment `onFinished` fires; anything
        // the character does after that is never drawn, so only the prefix is
        // the observable behaviour.
        #expect(states.prefix(3) == [.walk, .deliver, .depart])
        #expect(finished)
    }

    @Test(.enabled(if: SceneArt.isAvailable))
    func aPlainDepartureJustWalksOff() throws {
        let store = try Self.store()
        let character = Character(variant: "09", nameplate: NameplateText(lead: "6E7", role: "Explore"), store: store)
        character.advance(to: 0)
        character.position = CGPoint(x: 400, y: 64)
        var finished = false
        character.departOffScreen(
            via: [ScenePoint(x: 400, y: 32)],
            to: ScenePoint(x: -32, y: 32)) { finished = true }
        character.advance(to: 0)
        #expect(character.state == .depart)
        character.advance(to: 10)
        #expect(finished)
        #expect(character.position.x == -32)
    }

    /// State the data reports while a script is running lands when the script
    /// ends, rather than fighting the choreography for the body.
    @Test(.enabled(if: SceneArt.isAvailable))
    func dataStateArrivingMidWalkIsAppliedWhenTheWalkEnds() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        character.advance(to: 0)
        character.enter(along: RoomLayout().entranceRoute(forSeat: 2))
        character.advance(to: 0.5)
        character.setResting(.working, facing: .right)
        #expect(character.state == .spawn, "the walk still owns the body")
        character.advance(to: 10)
        #expect(character.state == .working)
    }

    // MARK: Badge

    @Test(.enabled(if: SceneArt.isAvailable))
    func theBadgeShowsAndHidesWithTheSelection() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        #expect(!character.isBadgeVisible)
        character.apply(badge: BadgeSelection(badge: .terminal, count: 1))
        #expect(character.isBadgeVisible)
        character.apply(badge: .none)
        #expect(!character.isBadgeVisible)
    }

    @Test func everyCharacterHasANameplate() throws {
        let store = try Self.store()
        for id in store.manifest.characters.orderedVariantIDs {
            let character = Character(variant: id, nameplate: NameplateText(lead: "6E7", role: "Explore"), store: store)
            #expect(character.isNameplateVisible)
        }
    }

    /// Two variants must not produce the same accent, or the nameplate's second
    /// identity channel is doing nothing.
    @Test func theCastDoesNotShareAccentColours() throws {
        let store = try Self.store()
        var accents: [Bitmap.RGBA: String] = [:]
        for id in store.manifest.characters.orderedVariantIDs {
            let accent = store.accent(variant: id)
            if let clash = accents[accent] {
                Issue.record("variant \(id) has the same accent as \(clash)")
            }
            accents[accent] = id
        }
    }

    // MARK: The room

    @Test(.enabled(if: SceneArt.isAvailable))
    func theFloorAndWallAreChosenByMeasurementNotByFilename() throws {
        let store = try Self.store()
        let tiles = store.roomTileChoice()
        #expect(store.manifest.room.builderTiles.contains(tiles.floor))
        #expect(store.manifest.room.builderTiles.contains(tiles.wall))
        #expect(tiles.floor != tiles.wall)

        // The floor must be the darker of the two, so the room's lightest
        // surface is behind rather than underfoot. [I7]
        func meanValue(_ path: String) throws -> Double {
            let bitmap = try PixelImage.bitmap(contentsOf: store.manifest.url(path))
            var total = 0.0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    let pixel = bitmap.at(x, y)
                    total += Double(max(pixel.r, max(pixel.g, pixel.b))) / 255
                }
            }
            return total / Double(bitmap.width * bitmap.height)
        }
        #expect(try meanValue(tiles.floor) < meanValue(tiles.wall))
    }

    @Test func seatsFillOutwardFromTheCentreAndNeverCollide() {
        let layout = RoomLayout()
        var columns: Set<Int> = []
        for seat in 0..<layout.seatCapacity {
            let column = layout.seatColumn(seat)
            #expect(!columns.contains(column), "seat \(seat) collides")
            columns.insert(column)
            #expect(column >= 0 && column < layout.columns)
        }
        #expect(layout.seatColumn(0) == layout.columns / 2)
    }

    @Test func theDeliveryPointIsBesideTheAnchorOnTheDeliveryRow() {
        let layout = RoomLayout()
        // The convenience point is seat 2 reporting to seat 0, and seat 2 is
        // left of centre — so it stands left of the anchor and turns right to
        // face it.
        #expect(layout.deliveryPosition.x < layout.seatPosition(0).x)
        #expect(layout.deliveryFacing == .right)
        #expect(layout.deliveryPosition.x == layout.seatPosition(0).x - layout.deliveryGap,
                "the reporter did not reach its anchor")
        // On the delivery row — the one row in the room a character travels
        // *along*, and the one row nothing else in the room ever touches.
        #expect(layout.deliveryPosition.y == layout.deliveryRowY)
        #expect(layout.deliveryRowY < layout.aisleY)
        #expect(layout.aisleY < layout.baselineY)
        for seat in 0..<layout.seatCapacity {
            #expect(layout.seatPosition(seat).y != layout.deliveryPosition.y)
        }
        // And the beat it falls back to when the row is taken is the one that
        // shipped between M6f and now: the reporter's own column, on the walkway.
        for seat in 0..<layout.seatCapacity {
            #expect(layout.inPlaceDeliveryPosition(reporterSeat: seat)
                    == layout.seatApproach(seat))
        }
    }

    /// **A reporter walks to its anchor's side, and turns to face it.**
    ///
    /// This test has been through three claims. It began as
    /// `aReporterApproachesItsAnchorFromItsOwnSide…`; M6f rewrote it as
    /// `aReporterDeliversInItsOwnColumn…` when the walk was deleted; the walk is
    /// back, one shared row instead of three, so the original claim is the claim
    /// again. What was never in doubt is the half [I1] cares about — it turns to
    /// face the person it is reporting to, because delivering with your back
    /// turned would be a small lie about a real event.
    @Test func aReporterStopsShortOfItsAnchorOnItsOwnSideAndTurnsToFaceIt() {
        let layout = RoomLayout()
        for anchor in 0..<layout.seatCapacity {
            let anchorX = layout.seatPosition(anchor).x
            // Seat 0 is the anchor, never a reporter — the main agent has no
            // `SubagentStop` — and `RoomScene` guards that self-report rather
            // than leaving it to arithmetic.
            for reporter in 1..<layout.seatCapacity where reporter != anchor {
                let side = layout.deliverySide(anchorSeat: anchor, reporterSeat: reporter)
                let delivery = layout.deliveryPosition(anchorSeat: anchor, reporterSeat: reporter)
                #expect(abs(delivery.x - anchorX) == layout.deliveryGap,
                        "reporter \(reporter) did not reach seat \(anchor)")
                #expect(delivery.y == layout.deliveryRowY)
                #expect(layout.deliveryFacing(side: side)
                        == (delivery.x < anchorX ? .right : .left))
            }
        }
    }

    /// **Every waypoint of every route except a report's is on the moving
    /// character's own column, and a report leaves that column only on the
    /// delivery row.**
    ///
    /// M6f's version of this asserted the first clause of *every* route with no
    /// exception, which it could because it had deleted the one route that
    /// crosses columns. The exception is back — see
    /// `RoomLayout.deliveryPosition(anchorSeat:reporterSeat:)` — and it is stated
    /// here as an exception with a boundary rather than dropped: a report's
    /// waypoints are on its own column *until* it is on `deliveryRowY`, and the
    /// only waypoint that is not is on that row. `ReportDeliveryTests
    /// .theRoomsOneLateralCorridorMeetsNoOtherRoute` carries what that buys.
    @Test func everyWaypointOfEveryRouteIsOnTheMovingCharactersOwnColumn() {
        let layout = RoomLayout()
        for seat in 0..<layout.seatCapacity {
            let column = layout.seatPosition(seat).x
            var routes: [(String, [ScenePoint])] = [
                ("entrance", layout.entranceRoute(forSeat: seat)),
                ("home", layout.homeRoute(forSeat: seat)),
                ("exit", [layout.upstageExit(forSeat: seat)]),
                ("approach", [layout.seatApproach(seat)]),
                ("seat", [layout.seatPosition(seat)]),
                ("in-place report", layout.inPlaceDeliveryRoute(reporterSeat: seat)),
                ("delivery lane entry", [layout.deliveryLaneEntry(forSeat: seat)]),
            ]
            for anchor in 0..<layout.seatCapacity where anchor != seat {
                routes.append(("report to \(anchor)",
                               layout.deliveryRoute(anchorSeat: anchor, reporterSeat: seat)))
            }
            for (name, route) in routes {
                for point in route {
                    #expect(point.x == column || point.y == layout.deliveryRowY,
                            Comment(rawValue:
                        "seat \(seat)'s \(name) route leaves its column at y=\(point.y),"
                        + " which is not the delivery row: \(point.x) against \(column)"))
                }
            }
        }
    }

    /// **Every walk runs at the same speed, however far it goes.**
    ///
    /// There used to be a four-second ceiling on a single walk, which meant a
    /// longer walk ran faster. Two characters leaving in the same direction then
    /// converge — the one with further to go is the one that was sped up — and
    /// `SessionEnd` sends the whole cast out at once, so that is not a corner.
    @Test func aWalkTakesTimeInProportionToItsLengthAtEveryLength() {
        func seconds(_ distance: Double) -> TimeInterval {
            Character.duration(
                from: ScenePoint(x: 0, y: 0), to: ScenePoint(x: distance, y: 0))
        }
        // Well past the old ceiling: 4 s × 72 px/s was 288 px, and the room is
        // wider than that.
        for distance in [100.0, 288.0, 500.0, 900.0] {
            #expect(abs(seconds(distance) - distance / Character.walkSpeed) < 1e-9,
                    "\(distance) px did not run at the walk speed")
        }
        // A floor stays, so a zero-length step still takes a moment rather than
        // teleporting.
        #expect(seconds(0) > 0)
    }

    /// **Every seat faces a direction the pack actually drew, in the row that
    /// draws it.** [ADR-008]
    ///
    /// It used to read `#expect(layout.seatedFacing.isSideView)` — one facing
    /// for the whole room, and the property being checked was that a seated
    /// character never asks for a sit frame that does not exist, because both
    /// sit rows are side art in all four blocks [M0]. **That property has not
    /// changed and this is it, restated for a room whose seats can turn.** A
    /// turned seat does not ask for a sit frame at all: it draws the standing
    /// `idle` row, which the manifest declares in all four directions at six
    /// frames each, and lets the seat's own occluder do the sitting. So the
    /// assertion is on `BodyState.artState(facing:)` — the function that makes
    /// the choice — rather than on a constant that no longer exists.
    @Test func everySeatedCharacterFacesADirectionThePackDrew() throws {
        let layout = RoomLayout()
        let manifest = try SceneFixtures.manifest()
        var seen: Set<RoomLayout.SeatFacing> = []
        for seat in 0..<layout.seatCapacity {
            let facing = layout.seatFacing(seat)
            seen.insert(facing)
            let body = layout.seatedFacing(seat)
            #expect(body == facing.bodyFacing)
            let art = BodyState.working.artState(facing: body)
            // A sit row is only ever asked for a side view, and every other
            // facing draws the idle row.
            #expect(art == .working ? body.isSideView : art == .idle)
            for id in manifest.characters.orderedVariantIDs {
                let frames = manifest.characters.variant(id)?
                    .animation(art)?.frames(facing: art == .working ? body.seated : body)
                #expect(frames?.isEmpty == false, Comment(rawValue:
                    "variant \(id) has no \(art) frames facing \(body) for seat \(seat)"))
            }
        }
        // **No seat in the shipped lattice is side-on**, and that is a
        // measurement rather than a remark: the whole point of ADR-008 is that
        // the room turned, and a lattice that quietly left a seat side-on would
        // draw a held object at it and nothing would fail.
        #expect(seen == [.towardCamera, .awayFromCamera])
    }

    /// **A seat gets a chair exactly when one would fit between its occupant's
    /// head and its occupant's own nameplate**, and the shipped `chair_back` does
    /// not. [M8, `RoomLayout.SeatFacing.seatRole`]
    ///
    /// The maintainer, on the shipped room: *"the chairs that are facing forward,
    /// and they look weird."* The sprite is right — 101 is genuinely the pack's
    /// back view — and a vacant away-facing pod renders correctly with it. What
    /// does not fit is the chair between the two things an occupied seat draws in
    /// the same 32 px column, and the two bounds are both already in the codebase:
    ///
    /// - the head band of a turned body is everything above `ink_top_px`, so
    ///   furniture may reach no higher than **feet + `ink_top_px`** —
    ///   `SeatedHeadOcclusionTests.nothingTheRoomDrawsInFrontOfASeatedBodyCovers
    ///   ItsHead` is that as a shipped invariant;
    /// - a plate hangs `maximumNameplateHeight + 2` below the feet, so a chair
    ///   standing lower than that is drawn through the character's own label.
    ///
    /// **This is written as a biconditional on purpose.** It is not "there is no
    /// chair"; it is "there is a chair if and only if the art allows one". A
    /// manifest that ever binds a back view inside the window — the same manifest
    /// swap the art direction promises is all final art costs — fails this test
    /// until the seat draws it again, and a manifest that keeps this one fails it
    /// the moment somebody puts the chair back.
    @Test func aTurnedSeatTakesAChairOnlyIfOneFitsUnderItsOwnNameplate() throws {
        let manifest = try SceneFixtures.manifest()
        let plateDrop = Double(SceneBitmaps.maximumNameplateHeight + 2)
        let headFloor = Double(manifest.characters.costumes.inkTopAboveFeet)
        // A chair based at the plate's own lowest row and reaching no higher than
        // the head's lowest row occupies `plateDrop + headFloor + 1` rows.
        let window = plateDrop + headFloor + 1
        #expect(window == 36, Comment(rawValue:
            "the window is \(window)px; 36 is what M8 measured it at, and every"
            + " number in it is the manifest's or `SceneBitmaps`'"))

        var checked = 0
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let room = manifest.room(theme: theme)
            let chair = try #require(room.prop(RoomScene.backSeatRole), Comment(rawValue:
                "\(theme ?? "room") binds no \(RoomScene.backSeatRole) role at all"))
            let height = Double(chair.contentBox.height)
            checked += 1
            let fits = height <= window
            #expect(!fits, Comment(rawValue:
                "\(theme ?? "room") binds a \(height)px back view, which fits the"
                + " \(window)px window — so `SeatFacing.awayFromCamera.seatRole` should"
                + " be drawing it again and the measurement in its doc comment is stale"))
            #expect(RoomLayout.SeatFacing.awayFromCamera.seatRole == nil, Comment(rawValue:
                "\(theme ?? "room")'s \(height)px back view is \(height - window)px too"
                + " tall for the \(window)px window, and the seat draws it anyway"))
        }
        #expect(checked >= 7, "only \(checked) rooms were measured")

        // And the side-on seat is untouched: its chair is a profile, it stands on
        // the seat's own point, and nothing above bears on it.
        #expect(RoomLayout.SeatFacing.sideOn.seatRole == RoomScene.seatRole)
        #expect(RoomLayout.SeatFacing.towardCamera.seatRole == nil)
    }

    // MARK: Criterion 1, end to end

    /// Drives the real fixture through the real model, director and scene, and
    /// checks that a character node exists for every agent that is alive.
    @Test func replayingTheFixturePutsACharacterOnScreenForEveryLiveAgent() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)

        var live: Set<AgentRef> = []
        var peak = 0
        var time = 0.0
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for delta in batch {
                switch delta {
                case let .agentAppeared(agent, _, _): live.insert(agent)
                case let .agentDeparted(agent): live.remove(agent)
                default: break
                }
            }
            scene.apply(director.apply(batch))
            time += 1.0 / 60.0
            scene.advance(to: time)
            #expect(scene.population == live.count)
            for agent in live { #expect(scene.character(for: agent) != nil) }
            peak = max(peak, scene.population)
        }
        #expect(peak == 4, "main plus three subagents")
        #expect(scene.population == 0, "everyone left")
    }

    /// Criterion 6, measured on the nodes rather than on the intents: over a
    /// real-time replay of `three-subagents`, no character's badge changes more
    /// often than its open-call set does.
    ///
    /// Note what this does *not* forbid. The main agent's `Agent` calls open
    /// and close ~16 ms apart, so its badge really does appear for about one
    /// frame, three times. That is the data being honest about an
    /// asynchronously-launched subagent, not flicker — and suppressing it would
    /// mean a minimum-duration hack, which is exactly what [I2/I3] rules out.
    /// **Measured on the pixels, and on the fixture's own clock.** Two things
    /// changed with ADR-003 and both are the beat being taken seriously rather
    /// than worked around.
    ///
    /// The comparison is on `BadgeSelection.drawn`, because the close that
    /// empties an agent's set now moves `count` from 1 to 0 while the glyph
    /// stays put — a change in the value and none in the picture, since the `×N`
    /// is drawn only above one. A test named for flicker has to count what an
    /// eye could catch.
    ///
    /// The beat does not leave that count alone — see the same assertion in
    /// `SceneDirectorTests` for the measurement — but it only ever raises it for
    /// a call whose open and close landed inside one frame and which therefore
    /// drew *nothing* before. Such a call still changes the open-call set twice,
    /// so the bound holds, and the bound is what this test is for.
    ///
    /// And the replay steps fixture time at 1/60 rather than one batch per
    /// frame, because a beat that ends 500 ms after a close cannot be observed
    /// on a clock that only advances when an event arrives — a compressed replay
    /// would show every beat still up at the end of the run and would prove
    /// nothing about the transition this test exists to bound.
    @Test func noCharacterOnScreenChangesBadgeMoreOftenThanItsCallSet() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)

        var callChanges: [AgentRef: Int] = [:]
        var badgeChanges: [AgentRef: Int] = [:]
        var lastBadge: [AgentRef: BadgeSelection.Drawn] = [:]

        let entries = try HookLog.load(contentsOf: SceneFixtures.url("three-subagents"))
        let origin = try #require(entries.first?.receivedAt)
        let end = try #require(entries.last?.receivedAt)
        let model = WorldModel()
        var index = entries.startIndex
        var time = 0.0
        let step = 1.0 / 60.0

        while time <= end.timeIntervalSince(origin) + 10 {
            var pending: [WorldDelta] = []
            let cutoff = origin.addingTimeInterval(time)
            while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                if let event = entries[index].event {
                    pending += await model.ingest(event, at: entries[index].receivedAt)
                }
                index += 1
            }
            for delta in pending {
                switch delta {
                case let .callOpened(agent, _),
                     let .callClosed(agent, _, _, _),
                     let .callAbandoned(agent, _, _, _):
                    callChanges[agent, default: 0] += 1
                default: break
                }
            }
            scene.apply(director.apply(pending, at: cutoff))
            scene.advance(to: time)

            for (agent, _) in callChanges {
                guard let character = scene.character(for: agent) else { continue }
                if lastBadge[agent] != character.badgeSelection.drawn {
                    lastBadge[agent] = character.badgeSelection.drawn
                    badgeChanges[agent, default: 0] += 1
                }
            }
            time += step
        }

        #expect(!badgeChanges.isEmpty)
        for (agent, changes) in badgeChanges {
            // +1 for the initial "no badge" reading.
            #expect(changes <= (callChanges[agent] ?? 0) + 1, "\(agent) flickered")
        }
    }

    // MARK: Criterion 5, as geometry rather than as assertion

    /// **No two nameplates may intersect, at any frame of `three-subagents`.**
    ///
    /// This exists because criterion 5 was passing on assertion. The aisle was
    /// introduced so that a reporting subagent's plate would not land on the
    /// anchor's — and it did stop the plates intersecting, but nothing checked
    /// it, so nothing noticed that the *body* had moved onto the anchor's plate
    /// instead. A room whose cast is not separable by silhouette cannot afford
    /// an unreadable nameplate, least of all during the report beat.
    @Test func noTwoNameplatesEverIntersect() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))

        var frames = 0
        var checkedPairs = 0
        var peakOnScreen = 0
        var overlaps: [String] = []

        _ = try await SceneFixtures.replayInFixtureTime(
            "three-subagents", into: scene, director: SceneDirector(manifest: manifest)
        ) { time in
            frames += 1
            let onScreen = scene.charactersOnScreen
            peakOnScreen = max(peakOnScreen, onScreen.count)
            for (index, first) in onScreen.enumerated() {
                for second in onScreen[onScreen.index(after: index)...] {
                    checkedPairs += 1
                    if first.nameplateRect.intersects(second.nameplateRect) {
                        overlaps.append(
                            "t=\(String(format: "%.3f", time)) "
                            + "\(first.nameplateRect) vs \(second.nameplateRect)")
                    }
                }
            }
        }

        #expect(
            overlaps.isEmpty,
            "nameplates overlapped on \(overlaps.count) frame(s), first: \(overlaps.first ?? "")")
        #expect(frames > 2000, "the whole fixture was not stepped")
        #expect(peakOnScreen >= 4, "the crowded frames were never reached")
        #expect(checkedPairs > 0)
    }

    /// The same assertion over `four-subagents` — the capture the whole dormancy
    /// change came from. Five characters, two agents that stop and are resumed
    /// and stop again, and two reports in flight at once, which is what makes
    /// the delivery rows earn their keep.
    ///
    /// Additive: `noTwoNameplatesEverIntersect` above is untouched and still
    /// runs `three-subagents` at fixture pace.
    @Test func noTwoNameplatesEverIntersectAcrossResumedSubagents() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))

        var frames = 0
        var peakOnScreen = 0
        var overlaps: [String] = []

        _ = try await SceneFixtures.replayInFixtureTime(
            "four-subagents", into: scene, director: SceneDirector(manifest: manifest)
        ) { time in
            frames += 1
            let onScreen = scene.charactersOnScreen
            peakOnScreen = max(peakOnScreen, onScreen.count)
            for (index, first) in onScreen.enumerated() {
                for second in onScreen[onScreen.index(after: index)...]
                where first.nameplateRect.intersects(second.nameplateRect) {
                    overlaps.append(
                        "t=\(String(format: "%.3f", time)) "
                        + "\(first.nameplateRect) vs \(second.nameplateRect)")
                }
            }
        }

        #expect(
            overlaps.isEmpty,
            "nameplates overlapped on \(overlaps.count) frame(s), first: \(overlaps.first ?? "")")
        #expect(frames > 8000, "the whole fixture was not stepped")
        #expect(peakOnScreen >= 5, "main plus four subagents were never all drawn")
    }

    /// **The whole cast leaving in one frame.** `SessionEnd` departs every agent
    /// in the session together — four `agentDeparted` in one batch — and the
    /// exit routing had only ever been exercised against staggered departures.
    ///
    /// Two rules hold it, and both are checked here rather than argued: every
    /// leaver goes out through its own desk's aisle station, so the convoy sets
    /// off spaced by the seat pitch; and every walk runs at the same speed, so a
    /// convoy that starts spaced stays spaced. Widest plates throughout —
    /// `general-purpose` is the type that draws the full 65 px.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theWholeCastCanLeaveInOneFrame() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)
        let cast = Self.cast(5)

        scene.apply(director.apply(cast.enumerated().map { index, ref in
            .agentAppeared(
                agent: ref, agentType: index == 0 ? nil : "general-purpose",
                lifecycle: index == 0 ? .active : .spawning)
        }))
        var time = 0.0
        var overlaps = 0
        func step(_ seconds: TimeInterval) {
            let end = time + seconds
            while time < end {
                time += 1.0 / 60.0
                scene.advance(to: time)
                let onScreen = scene.charactersOnScreen
                for (index, first) in onScreen.enumerated() {
                    for second in onScreen[onScreen.index(after: index)...]
                    where first.nameplateRect.intersects(second.nameplateRect) { overlaps += 1 }
                }
            }
        }

        step(4)                                     // everyone walks in and sits
        #expect(scene.charactersOnScreen.allSatisfy { !$0.isScripted }, "still walking in")
        // One frame, five departures. Exactly what `SessionEnd` produces.
        scene.apply(director.apply(cast.map { .agentDeparted(agent: $0) }))
        #expect(scene.population == 0)
        step(14)
        #expect(overlaps == 0, "\(overlaps) frames with intersecting nameplates")
        #expect(scene.charactersOnScreen.isEmpty, "someone never finished leaving")
    }

    /// A leaver goes out **up its own column**, not along the front of everyone
    /// else's desk. A character caught mid-report is over at its anchor on the
    /// delivery row when the session ends, so its exit is the one place in this
    /// room where getting back into the column is part of the route: it walks
    /// home along the row it came out on, and everything after that is one
    /// continuous ascent of its own column.
    ///
    /// **The lateral part is measured rather than excused.** The test counts the
    /// frames the leaver is off its column and requires every one of them to be
    /// on the delivery row — a leaver that got its lateral leg anywhere else
    /// would be crossing a row somebody could be standing on.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aLeaverCaughtMidReportComesHomeUpItsOwnColumnAndLeavesUpstage() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)
        let cast = Self.cast(4)
        scene.apply(director.apply(cast.enumerated().map { index, ref in
            .agentAppeared(
                agent: ref, agentType: index == 0 ? nil : "Explore",
                lifecycle: index == 0 ? .active : .spawning)
        }))
        var time = 0.0
        func step(_ seconds: TimeInterval) {
            let end = time + seconds
            while time < end { time += 1.0 / 60.0; scene.advance(to: time) }
        }
        step(4)
        scene.apply(director.apply([.reportDelivered(agent: cast[3])]))
        // Stepped to the moment of the hand-over rather than waited out. Catching
        // the character *while it is off its chair* is the whole point of the
        // test, so the test asks when that is rather than guessing a duration.
        let reporter = try #require(scene.character(for: cast[3]))
        let station = scene.layout.seatPosition(3)
        while reporter.state != .deliver, time < 20 { step(1.0 / 60.0) }
        #expect(reporter.state == .deliver, "the reporter never delivered")
        #expect(Double(reporter.position.y) == scene.layout.deliveryRowY,
                "the reporter is not out on the delivery row")
        #expect(Double(reporter.position.y) != station.y, "the reporter never left its chair")
        #expect(Double(reporter.position.x)
                == scene.layout.deliveryPosition(anchorSeat: 0, reporterSeat: 3).x,
                "the reporter did not reach its anchor")

        scene.apply(director.apply([.agentDeparted(agent: cast[3])]))
        // It comes home along the delivery row into its own column and never
        // leaves that column again, all the way out through the back of the
        // room. There is no corner cut: every frame it is off its column is a
        // frame on the delivery row, which is the second clause of
        // `RoomLayout.deliveryPosition(anchorSeat:reporterSeat:)`'s rule asserted
        // on the frames rather than on the waypoints.
        var offColumn = 0
        var offColumnAndOffTheRow = 0
        let end = time + 20
        while time < end {
            time += 1.0 / 60.0
            scene.advance(to: time)
            guard abs(Double(reporter.position.x) - station.x) > 1e-6 else { continue }
            offColumn += 1
            if abs(Double(reporter.position.y) - scene.layout.deliveryRowY) > 1e-6 {
                offColumnAndOffTheRow += 1
            }
        }
        #expect(offColumn > 0, "the leaver was never off its column; the walk did not happen")
        #expect(offColumnAndOffTheRow == 0, Comment(rawValue:
            "the leaver was off its own column on \(offColumnAndOffTheRow) frames that"
            + " were not on the delivery row — a diagonal, across rows other"
            + " characters stand on"))
        #expect(reporter.position == CGPoint(
            x: scene.layout.upstageExit(forSeat: 3).x,
            y: scene.layout.upstageExit(forSeat: 3).y))
        #expect(Double(reporter.position.y) >= scene.layout.wallBaseY,
                "the leaver did not go out through the back of the room")
        #expect(reporter.alpha == 0, "the leaver was still visible when it was retired")
    }

    /// **What the room guarantees, as arithmetic.**
    ///
    /// This test has been through three arguments and is on its third name. It
    /// began as `theAisleIsGuaranteedClear`, which said the opposite of what it
    /// checked; it became `…AtTheStationsAndNotBetweenThem` and five blocks of
    /// lattice arithmetic, because a report was a walk *to the anchor* and a
    /// lateral corridor across the room needs a great deal of proving. Blocks 3
    /// and 4 of that version — a delivery row carries one ring, and a reporter's
    /// column clears every other ring's corridor — existed only to keep that one
    /// lateral leg out of everyone's way, and they cost 96 px of floor to state.
    ///
    /// **The leg is gone, so the argument is one sentence.**
    ///
    /// > Every leg of every route in this room is vertical and inside the moving
    /// > character's own seat column, so two characters' separation in x is a
    /// > constant of the lattice.
    ///
    /// Two plates meet only if they share a horizontal strip **and** come within
    /// a plate width in x. Nothing can change a character's x, so the second
    /// condition is decided once, by `seatColumn`, for every pairing at every
    /// instant — and it is decided by a seat pitch against a plate width. The
    /// strip half is kept for the rows, and for the two crossings the second seat
    /// row adds, because those are real and still need the same number.
    ///
    /// `everyWaypointOfEveryRouteIsOnTheMovingCharactersOwnColumn` is the other
    /// half of this: it checks the premise, this checks what the premise buys.
    /// `noAdversarialPairingOfBeatsEverTouchesTwoPlates` then drives it.
    ///
    /// **The one lateral leg is back and this test's scope is now stated rather
    /// than universal.** A report crosses columns on `deliveryRowY`; what keeps
    /// two reporters off each other there is `DeliveryFloor`, and
    /// `ReportDeliveryTests.twoGrantedCorridorsAreAlwaysAPlateApart` is where that
    /// is proved. Everything below is about every *other* pairing in the room,
    /// which is every pairing that does not involve a granted delivery corridor —
    /// and block 4, which used to be about two reporters on the walkway, still is:
    /// the walkway is where a refused reporter delivers.
    @Test func theRoomHasNoLateralMovementLeftToSeparate() {
        let layout = RoomLayout()
        let widest = Double(SceneBitmaps.maximumNameplateWidth)
        let tallest = Double(SceneBitmaps.maximumNameplateHeight)
        let pitch = layout.seatPosition(1).x - layout.seatPosition(0).x

        // 1. Columns are further apart than a plate is wide, and neighbouring
        //    columns are the closest two characters can ever be in x — because
        //    a character's x *is* its column's, always.
        #expect(pitch >= widest, "two characters at neighbouring stations overlap")
        var columnGaps: [Double] = []
        for seat in 0..<layout.seatCapacity {
            for other in (seat + 1)..<layout.seatCapacity {
                columnGaps.append(abs(layout.seatPosition(seat).x - layout.seatPosition(other).x))
            }
        }
        #expect(columnGaps.min() == pitch)

        // 2. Rows are further apart than a plate is tall, so two characters on
        //    different rows cannot share a horizontal strip at any x. There are
        //    exactly four rows: the two seat rows, the walkway, and the delivery
        //    row. It was six (one delivery row per ring), then three, and it is
        //    four — one shared delivery row is what buys the walk back.
        //
        //    Asked of `RoomLayout.standingRows` rather than assembled here, so a
        //    row added to the room is a row this block sees.
        let rows = layout.standingRows
        let sorted = rows.sorted()
        for (lower, upper) in zip(sorted, sorted.dropFirst()) {
            #expect(upper - lower > tallest,
                    "rows \(lower) and \(upper) put two plates in one strip")
        }
        #expect(Set(rows).count == rows.count, "two of the room's rows are the same line")
        #expect(rows.count == 4, "the room grew a row; every row is a row two plates can share")
        #expect(sorted.first == layout.deliveryRowY,
                "the delivery row is no longer the front of the room")

        // 3. **The crossings.** A character moving in its own column passes
        //    through every row between where it started and where it is going,
        //    and on each of those rows there may be a seated neighbour. One
        //    number closes all of them, and it is block 1's: the mover's column
        //    is a full pitch from every seat that is not its own.
        //
        //    This subsumes what used to be blocks 3, 4 and 5. The old block 5
        //    checked only the pairs on *different* rows, because same-row pairs
        //    were argued elsewhere; there is no elsewhere now, so this checks
        //    every pair.
        for crossing in 0..<layout.seatCapacity {
            let column = layout.seatPosition(crossing).x
            for other in 0..<layout.seatCapacity where other != crossing {
                let seat = layout.seatPosition(other)
                let why = "seat \(crossing) moves through seat \(other)'s row"
                    + " with \(abs(column - seat.x)) px to spare"
                #expect(abs(column - seat.x) >= widest, Comment(rawValue: why))
            }
        }

        // 4. And the one row any number of characters can stand on at once: the
        //    walkway, where every reporter refused the delivery row delivers.
        //    They are in their own columns, so the tightest pair is two adjacent
        //    columns and the bound is block 1's again. This is why the fallback
        //    needs no exclusion of its own and can be handed out to everybody in
        //    the same frame.
        for seat in 1..<layout.seatCapacity {
            for other in (seat + 1)..<layout.seatCapacity {
                let first = layout.inPlaceDeliveryPosition(reporterSeat: seat)
                let second = layout.inPlaceDeliveryPosition(reporterSeat: other)
                #expect(first.y == second.y, "two reporters no longer share the walkway")
                #expect(abs(first.x - second.x) >= widest, Comment(rawValue:
                    "reporters \(seat) and \(other) deliver"
                    + " \(abs(first.x - second.x)) px apart"))
            }
        }
    }

    /// **The seat pitch is the nameplate's, and this is the tripwire that says
    /// so.**
    ///
    /// The pitch is 96 px for one reason: two characters whose plates overlap
    /// are two characters the room cannot tell apart, and the widest plate the
    /// font can produce is 71 px. It is not a comfort number — bodies are 32 px
    /// of canvas over about 18 px of ink, and a desk's content box is 32 px, so
    /// nothing else in the room needs anything like it.
    ///
    /// So when the plate narrows the pitch should narrow with it, and
    /// `RoomLayout.minimumSeatSpacingTiles(plateWidth:plateHeight:tile:)` is
    /// that relation written down. This test asserts the shipped pitch *is* what
    /// the formula gives for the shipped plate — **it fails in both directions**.
    /// Too wide and the room is spending width it does not need; too narrow and
    /// two plates can touch.
    ///
    /// It is deliberately not wired to `RoomLayout.init`. A pitch that followed
    /// the plate automatically would also move every desk, station prop and
    /// decoration column, and those clearances are argued from content boxes in
    /// the manifest rather than from `RoomLayout` — so whoever narrows the plate
    /// has to re-derive them, and this failing is how they find out.
    @Test func theSeatPitchIsTheNarrowestTheseNameplatesAllow() {
        let layout = RoomLayout()
        let wanted = RoomLayout.minimumSeatSpacingTiles(
            plateWidth: SceneBitmaps.maximumNameplateWidth,
            plateHeight: SceneBitmaps.maximumNameplateHeight,
            tile: layout.tile)
        #expect(layout.seatSpacingTiles == wanted, Comment(rawValue:
            "a \(SceneBitmaps.maximumNameplateWidth) px plate allows a"
            + " \(wanted)-tile pitch (\(wanted * layout.tile) px) and the room"
            + " ships \(layout.seatSpacingTiles) (\(layout.seatSpacingTiles * layout.tile) px)."
            + " Narrowing it also moves every desk, station prop and decoration"
            + " column — re-derive those before changing the constant."))

        // The formula itself, at the widths worth knowing. The threshold is
        // `width + tile − height ≤ 64`, so it moves with the plate's *height*
        // too — 58 px bought the 2-tile pitch at a 26 px plate and 53 px buys it
        // at 21.
        #expect(RoomLayout.minimumSeatSpacingTiles(
            plateWidth: 71, plateHeight: 26, tile: 32) == 3)
        #expect(RoomLayout.minimumSeatSpacingTiles(
            plateWidth: 59, plateHeight: 26, tile: 32) == 3)
        #expect(RoomLayout.minimumSeatSpacingTiles(
            plateWidth: 58, plateHeight: 26, tile: 32) == 2)
        #expect(RoomLayout.minimumSeatSpacingTiles(
            plateWidth: 54, plateHeight: 21, tile: 32) == 3)
        #expect(RoomLayout.minimumSeatSpacingTiles(
            plateWidth: 53, plateHeight: 21, tile: 32) == 2)
        // The floor: a seat is a character and its desk whatever the plate does.
        #expect(RoomLayout.minimumSeatSpacingTiles(
            plateWidth: 0, plateHeight: 26, tile: 32) == 2)
    }

    /// **The seats are on two rows, and which row is the parity of the ring.**
    ///
    /// The picture this exists for is the one the maintainer complained about:
    /// every character on a single line across the middle of the panel, with
    /// flat wall above and bare floor below. What makes the fold safe is that it
    /// is a function of the ring and therefore leaves `seatColumn` alone —
    /// asserted here as *both* halves, because "the seats moved" and "nothing
    /// else moved" are different claims and only the pair is the fix.
    @Test func theSeatsAlternateDepthAlongXWithoutMovingAnyColumn() {
        let layout = RoomLayout()

        // Both rows are actually used, and by the seats that fill first — a
        // second row nobody reaches until the seventh agent is not composition.
        #expect(layout.seatRows.count == 2)
        #expect(layout.seatPosition(0).y == layout.baselineY, "the anchor is downstage")
        #expect(layout.seatPosition(1).y == layout.backSeatRowY,
                "the first subagent is still on the anchor's own row")

        // In x order, the rows alternate: every occupied column differs in
        // depth from both its neighbours. This is the whole composition claim.
        let byColumn = (0..<layout.seatCapacity)
            .map { layout.seatPosition($0) }
            .sorted { $0.x < $1.x }
        for (left, right) in zip(byColumn, byColumn.dropFirst()) {
            #expect(left.y != right.y, Comment(rawValue:
                "columns \(left.x) and \(right.x) are on the same row, so the"
                + " seats read as a line again"))
        }

        // And nothing moved sideways. `RoomLayout` is free to change the
        // *shape* of the room; it is not free to change the one number every
        // clearance argument in it rests on.
        let pitch = Double(layout.tile * layout.seatSpacingTiles)
        var gaps: [Double] = []
        for seat in 0..<layout.seatCapacity {
            for other in (seat + 1)..<layout.seatCapacity {
                gaps.append(abs(layout.seatPosition(seat).x - layout.seatPosition(other).x))
            }
        }
        #expect(gaps.min() == pitch)
        #expect(Double(SceneBitmaps.maximumNameplateWidth) <= pitch)

        // The rows are a character's height apart, which is what makes them
        // read as depth rather than as two characters standing on one another.
        #expect(layout.backSeatRowY - layout.baselineY
                == Double(layout.tile * layout.seatRowDepthTiles))
        // The back row still has floor behind it. Every exit in this room walks
        // upstage to `wallBaseY` and fades; a back row *at* the wall would give
        // its occupants a zero-length departure.
        #expect(layout.backSeatRowY < layout.wallBaseY,
                "the back row has no floor behind it to walk out through")
        #expect(layout.upstageExit(forSeat: 1).y - layout.seatPosition(1).y
                >= Double(layout.tile * 2))
    }

    /// **Two same-side reporters at once, which is what the slots were for.**
    ///
    /// The old bookkeeping claimed a sideways slot lowest-free, which was not
    /// seat-ordered: the *farther* of two same-side reporters could take the
    /// nearer slot and then walk home **through** the nearer one's station. And
    /// even claimed in the right order the two shared a line, so one's corridor
    /// ran through the other's slot.
    ///
    /// **There is a claim again and it is not that claim.** `DeliveryFloor`
    /// hands out a *stretch of one row*, refuses anything that would come within
    /// a plate of a live one, and a reporter it refuses does not queue — it
    /// delivers in its own column on the walkway, in the same frame. So the pair
    /// under test here is the pair the old bookkeeping got wrong, seats 1 and 3,
    /// both right of the anchor and therefore both wanting the same stretch: one
    /// walks to the anchor on the delivery row and the other stands in its own
    /// column a row upstage. They are on **different rows**, which is the
    /// strongest separation this room has, and the plates are checked every frame
    /// of both beats regardless.
    ///
    /// This is the test the three delivery rows were built for; it had to keep
    /// passing without them at M6f and it has to keep passing with one of them
    /// back. `ReportDeliveryTests` carries what the one row is for.
    @Test(.enabled(if: SceneArt.isAvailable))
    func twoSameSideReportersDeliverClearOfEachOther() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)
        let cast = Self.cast(4)
        // Seats 1 and 3 are both right of the anchor. Seat 2 is only there to
        // push seat 3 out.
        scene.apply(director.apply(cast.enumerated().map { index, ref in
            .agentAppeared(
                agent: ref, agentType: index == 0 ? nil : "general-purpose",
                lifecycle: index == 0 ? .active : .spawning)
        }))
        #expect(director.seats[cast[1]] == 1 && director.seats[cast[3]] == 3)

        var time = 0.0
        var overlaps = 0
        var stations: [AgentRef: ScenePoint] = [:]
        func step(_ seconds: TimeInterval) {
            let end = time + seconds
            while time < end {
                time += 1.0 / 60.0
                scene.advance(to: time)
                for ref in [cast[1], cast[3]] {
                    if let character = scene.character(for: ref), character.state == .deliver {
                        stations[ref] = ScenePoint(
                            x: Double(character.position.x), y: Double(character.position.y))
                    }
                }
                let onScreen = scene.charactersOnScreen
                for (index, first) in onScreen.enumerated() {
                    for second in onScreen[onScreen.index(after: index)...]
                    where first.nameplateRect.intersects(second.nameplateRect) { overlaps += 1 }
                }
            }
        }

        step(4)
        scene.apply(director.apply([.reportDelivered(agent: cast[1])]))
        // Fire the second the instant the first is actually delivering, so both
        // are out of their chairs together — the window the old bookkeeping got
        // wrong, and the one the delivery row exists to close. Stepped to the
        // event rather than waited out, so the overlap is real rather than hoped
        // for.
        while stations[cast[1]] == nil, time < 20 { step(1.0 / 60.0) }
        #expect(stations[cast[1]] != nil, "the first reporter never delivered")
        #expect(scene.character(for: cast[1])?.isScripted == true,
                "the first reporter is already home; the overlap under test never happened")
        scene.apply(director.apply([.reportDelivered(agent: cast[3])]))
        step(12)

        // Different rows: the first took the delivery row and walked to the
        // anchor, the second was refused it and delivered in its own column on
        // the walkway. A row apart is 32 px against an 11 px plate.
        let first = try #require(stations[cast[1]])
        let second = try #require(stations[cast[3]])
        #expect(first.y == scene.layout.deliveryRowY,
                "the first reporter did not get the delivery row")
        #expect(second.y == scene.layout.aisleY,
                "the second reporter was not refused the row it could not have")
        #expect(abs(first.y - second.y) > Double(SceneBitmaps.maximumNameplateHeight),
                "the two reporters delivered in one horizontal strip")
        #expect(second.x > first.x, "the refused reporter is not further out")
        #expect(overlaps == 0, "\(overlaps) frames with intersecting nameplates")
        // Both are home and sitting again: a report takes nobody out of the room.
        #expect(scene.population == 4)
        for ref in [cast[1], cast[3]] {
            let seat = scene.layout.seatPosition(try #require(director.seats[ref]))
            #expect(scene.character(for: ref)?.position == CGPoint(x: seat.x, y: seat.y))
        }
    }

    /// The invariant that makes the occlusion impossible rather than unlikely:
    /// every nameplate and every badge outranks every body, always.
    @Test func nameplatesAndBadgesAlwaysOutrankEveryBody() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))

        var checked = 0
        var violations = 0
        _ = try await SceneFixtures.replayInFixtureTime(
            "three-subagents", into: scene, director: SceneDirector(manifest: manifest)
        ) { _ in
            let onScreen = scene.charactersOnScreen
            guard let deepestPlate = onScreen.map(\.nameplateDepth).min(),
                  let deepestBadge = onScreen.map(\.badgeDepth).min(),
                  let shallowestBody = onScreen.map(\.bodyDepth).max() else { return }
            if deepestPlate <= shallowestBody || deepestBadge <= shallowestBody {
                violations += 1
            }
            checked += 1
        }
        #expect(violations == 0, "a body outranked a nameplate or a badge")
        #expect(checked > 1000)
    }

    /// A desk stands on the same row as the character sitting at it, so the tie
    /// has to be broken on purpose. It is broken towards the desk — and the
    /// nameplate still outranks both.
    /// **However a seat is turned, its desk draws in front of its occupant and
    /// behind anyone walking past, and the nameplate outranks all of it.**
    ///
    /// The original read the side-on case only, and it read it as a *tie*: a
    /// desk and its occupant stand on one row, so `rowDepth` alone leaves the
    /// order to chance and `surfaceInFrontBias` breaks it on purpose. ADR-008
    /// turns three of the seven seats, and at a turned seat there is no tie to
    /// break — a camera-facing desk is genuinely downstage of the body, so the
    /// row does the work and the bias is zero. Both cases are asserted, because
    /// the property the room needs ("the desk crosses the body it belongs to")
    /// is the same one and only the mechanism differs.
    @Test func aDeskOutranksTheSeatedBodyButNotTheNameplate() throws {
        let layout = RoomLayout()
        let metrics = SceneFixtures.seatMetrics(try SceneFixtures.manifest())
        let aisle = Character.Layer.rowDepth(layout.aisleY)
        for seat in 0..<layout.seatCapacity {
            let facing = layout.seatFacing(seat)
            let seated = Character.Layer.rowDepth(layout.seatRowY(seat))
            let bias: CGFloat = facing == .sideOn ? RoomScene.surfaceInFrontBias : 0
            let desk = Character.Layer.rowDepth(
                layout.deskPosition(seat, metrics: metrics).y) + bias
            switch facing {
            case .sideOn, .towardCamera:
                #expect(desk > seated,
                        "seat \(seat)'s desk must cross the body it belongs to")
            case .awayFromCamera:
                // Its occupant has its back to it, so the desk is upstage and
                // the **chair** is what stands in front. Asserted rather than
                // skipped: a desk that crept in front of an away-facing body
                // would cover the one thing that seat shows.
                #expect(desk < seated, "an away-facing desk stands behind its occupant")
            }
            if let chair = layout.chairPosition(seat, metrics: metrics), facing != .sideOn {
                #expect(Character.Layer.rowDepth(chair.y) > seated,
                        "seat \(seat)'s chair back must stand in front of its occupant")
            }
            #expect(aisle > desk,
                    "a character walking past is always in front of the furniture")
            #expect(seated + Character.Layer.nameplate > aisle, "no body may hide a nameplate")
        }
    }

    // MARK: Composition [M5]

    /// The camera frames the strip where characters, plates and badges live,
    /// not the room's nominal 192 px box. The strip has to be big enough to
    /// contain everything a character can draw, or something gets cropped.
    @Test func theContentBandContainsEveryPixelACharacterCanDraw() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let band = scene.contentBand
        let layout = scene.layout

        // **Every variant on every seat row.** Measured from `baselineY` alone
        // this passed with the back row's badges a full two tiles above the top
        // of the frame — the band's ceiling has to be the furthest-upstage row
        // anyone sits on, not the nearest.
        for id in manifest.characters.orderedVariantIDs {
            let variant = manifest.characters.variant(id)!
            for row in layout.seatRows {
                let badgeTop = row + Character.badgeSlotTopAboveFeet(
                    canvasHeight: manifest.characters.canvas.height,
                    headTopPx: variant.headTopPx)
                #expect(badgeTop <= band.top, Comment(rawValue:
                    "variant \(id) on row \(row) pokes its badge out of the frame"))
            }
        }
        // The **tallest** plate, not a sample one: the plate grew a second row
        // at the wide default, and a band derived from `MAIN` alone would have
        // cropped every subagent's type line.
        let plateHeight = Double(SceneBitmaps.maximumNameplateHeight)
        // The lowest plate belongs to a character on the **delivery row** — the
        // nearest the camera any character can stand, and where a reporter is
        // when it hands its report over.
        #expect(layout.deliveryRowY - 2 - plateHeight >= band.bottom)
        // Every row the choreography can stand a character on is inside it —
        // asked of `standingRows`, so a row added to the room is a row this
        // checks rather than a row it forgets.
        for row in layout.standingRows {
            #expect(row - 2 - plateHeight >= band.bottom, "a plate on row \(row) is cropped")
        }
        // The band is what the characters occupy and nothing else. It used to be
        // asserted smaller than the room's nominal box, which was a proxy for
        // "not a flat band of empty wall and floor"; the delivery rows made the
        // occupied strip genuinely taller than the nominal box, so the proxy is
        // replaced by the thing it stood for.
        #expect(band.bottom == layout.deliveryRowY
                - Double(SceneBitmaps.maximumNameplateHeight + 2))

        // **And the whole of it, as one number.** The band is the badge, the
        // plate, the two seat rows, the walkway and the delivery row, and nothing
        // else. Written as the sum rather than as a literal so that a taller badge
        // moves it instead of breaking it.
        let seatRows = Double(layout.tile * layout.seatRowDepthTiles)
        let walkway = layout.baselineY - layout.aisleY
        let deliveryRow = layout.aisleY - layout.deliveryRowY
        let badgeTop = Character.badgeSlotTopAboveFeet(
            canvasHeight: manifest.characters.canvas.height,
            headTopPx: manifest.characters.variants.values.map(\.headTopPx).min() ?? 0)
        #expect(band.top - band.bottom
                == badgeTop + plateHeight + 2 + seatRows + walkway + deliveryRow,
                "the content band is carrying a term the room does not draw")
    }

    /// One agent gets the **wide** view, not a close-up of one desk.
    ///
    /// This test used to assert `3x`, from M5's finding that the top rung was
    /// unreachable in the product's own panel — the nominal room box is 192 px
    /// and 192 × 3 does not fit in 400. That finding was real and the framing
    /// fix it produced stays: the scene frames the manifest-derived content
    /// band, not the nominal box, which is what made the ladder reachable at
    /// all.
    ///
    /// What changed is the preference on top of it, and it has now changed
    /// twice. It first went to `1x` at every population, because the maintainer
    /// asked for the room to be bigger from the start. It is `2x` for a small
    /// room again as of M6f — not by reversing that decision, but because the
    /// reason it was cheap has gone: the content band was 300 px against the
    /// 200 a `2x` view of this panel gives, so nothing closer fitted anyway.
    /// M6f spent 96 px of delivery rows and 34 px of badge slot and brought it
    /// to 170.
    ///
    /// The original complaint still holds where it was aimed. `2x` at one agent
    /// frames 360×200 of room — a place with somebody in it, not a close-up of
    /// one desk, which is what `3x` gave and what was objected to. The ladder
    /// is untouched and still integer [I6].
    @Test func oneAgentIsDrawnCloseButStillInsideARoom() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest)
        let ref = AgentRef(project: "/p", session: "s", agent: .mainThread)
        scene.apply(director.apply([
            .agentAppeared(agent: ref, agentType: nil, lifecycle: .active)]))
        #expect(scene.currentScale == 2)
        // The framing claim, which is the half the maintainer actually cared
        // about: a 2x view still shows a room, not a desk. 360x200 unscaled
        // pixels against a 96px seat pitch is three seats wide.
        #expect(720 / scene.currentScale == 360)
    }

    /// Whatever the camera prefers, it may never crop an identity. The
    /// preference exists to stop the foreground filling with empty floor; it is
    /// clamped by the slack the scale actually left.
    @Test func theCameraNeverCropsTheContentBandAtAnyScale() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let band = scene.contentBand
        for height in stride(from: band.top - band.bottom, through: 600, by: 7.0) {
            let y = scene.cameraY(band: band, sceneHeight: height)
            #expect(y - height / 2 <= band.bottom + 1e-9, "plate cropped at \(height)")
            #expect(y + height / 2 >= band.top - 1e-9, "badge cropped at \(height)")
        }
    }

    /// **No scale on the ladder ever shows the void behind the room.** [I6]
    ///
    /// `drawnRows`/`drawnColumns` paint past the room's nominal bounds precisely
    /// so this holds, and until now it was a comment. It became worth asserting
    /// when the floor went from four rows to seven: the overscan was written
    /// `rows + 8`, which is a *margin that grows with the room*, and a taller
    /// room pushed the painted field past the top of the 1600×900 viewport
    /// `scripts/preview-theme.py --verify` registers its picture in — failing
    /// the whole scene-agreement check with nothing wrong with the room. A fixed
    /// overscan fixes that and needs a check at the other end, which is this:
    /// enough tiles are still painted to fill the panel at every rung.
    @Test func noScaleOnTheLadderEverShowsTheVoidBehindTheRoom() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let layout = scene.layout
        let band = scene.contentBand
        let tile = Double(layout.tile)
        let fieldBottom = Double(layout.drawnRows.lowerBound) * tile
        let fieldTop = Double(layout.drawnRows.upperBound + 1) * tile
        let fieldLeft = Double(layout.drawnColumns.lowerBound) * tile
        let fieldRight = Double(layout.drawnColumns.upperBound + 1) * tile

        // The widest and the narrowest the camera's x ever gets: every seat
        // occupied, and seat 0 alone (which is what an empty room frames).
        let spans = [layout.occupiedSpan(seats: 0..<layout.seatCapacity),
                     layout.occupiedSpan(seats: [0])]

        for scale in RoomCamera(manifest: manifest).scales {
            let height = 400.0 / Double(scale)
            let width = 720.0 / Double(scale)
            let y = scene.cameraY(band: band, sceneHeight: height).rounded()
            #expect(y - height / 2 >= fieldBottom, Comment(rawValue:
                "\(scale)x shows void below the floor"))
            #expect(y + height / 2 <= fieldTop, Comment(rawValue:
                "\(scale)x shows void above the wall"))
            for span in spans {
                let x = ((span.minX + span.maxX) / 2).rounded()
                #expect(x - width / 2 >= fieldLeft, Comment(rawValue:
                    "\(scale)x shows void off the left of the room"))
                #expect(x + width / 2 <= fieldRight, Comment(rawValue:
                    "\(scale)x shows void off the right of the room"))
            }
        }
    }

    /// Once there is slack, the frame is biased upwards — towards the wall the
    /// backdrops stand against, rather than down into floor nobody stands on.
    @Test func spareVerticalRoomGoesToTheWallRatherThanTheForeground() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let band = scene.contentBand
        let tight = scene.cameraY(band: band, sceneHeight: band.top - band.bottom)
        let loose = scene.cameraY(band: band, sceneHeight: 400)
        #expect(loose > tight)
    }

    /// **The camera aims at something the room draws.** [`RoomScene.cameraY`]
    ///
    /// The aim used to be the midpoint of the seated plate and `band.top` — the
    /// top of the *badge slot*, which is not the top of anything: `office`'s
    /// board stands 91 px above it and `broadcast`'s softbox 125. So the surplus
    /// the camera declined to spend upward went underneath the room instead, and
    /// at `1x` on the shipped panel that was 131 px of bare floor below the
    /// lowest nameplate — a third of the frame, most of it `drawnRows` overscan.
    ///
    /// This is the assertion that would have caught it, and it is written over
    /// **every theme** because the old aim was a constant while the backdrops
    /// are not: the same frame that left `office`'s board 36 px of headroom left
    /// `broadcast`'s softbox 2 px. A per-theme check is what turns "it looks all
    /// right in the default room" into a claim about the six that ship.
    @Test func theFrameAtTheWideScaleHoldsTheTallestBackdropInEveryTheme() throws {
        let manifest = try SceneFixtures.manifest()
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let scene = RoomScene(manifest: manifest, themeID: theme)
            let name = theme ?? "manifest.room"
            let band = scene.contentBand
            let decorationTop = scene.decorationTopY
            // The wall line is the floor of the measurement — a theme that binds
            // no backdrop still gets a real number rather than nonsense.
            #expect(decorationTop >= scene.layout.wallBaseY, Comment(rawValue:
                "\(name): decorationTopY fell below the wall line"))

            // `1x` on the shipped panel, which is what four or more agents get.
            let height = 400.0
            let y = scene.cameraY(band: band, sceneHeight: height)
            let frame = (bottom: y - height / 2, top: y + height / 2)

            // Nothing the room stands on the wall line is cropped...
            #expect(frame.top >= decorationTop, Comment(rawValue:
                "\(name): the backdrop reaches \(decorationTop) and the frame stops"
                + " at \(frame.top)"))
            // ...and the surplus is *split*, not dumped under the room. Half of
            // it, to the pixel, because the aim is the drawn strip's midpoint —
            // written as the comparison rather than the equality so a future aim
            // that biases deliberately still passes if it stays honest.
            let above = frame.top - decorationTop
            let below = band.bottom - frame.bottom
            #expect(below <= above + 1, Comment(rawValue:
                "\(name): \(below)px of frame below the lowest plate against"
                + " \(above)px above the tallest backdrop — the slack is going"
                + " under the room again"))
            // The band still fits, which is the thing the aim may never cost.
            #expect(frame.bottom <= band.bottom + 1e-9)
            #expect(frame.top >= band.top - 1e-9)
        }
    }

    /// **The close view is decided by the clamp, not by the aim**, so no change
    /// to where the camera prefers to point can make a small room emptier.
    /// [`RoomScene.cameraY`]
    ///
    /// At `2x` the panel gives 200 px of scene height against a content band
    /// that is deeper than 200 − (band's own depth): `band.bottom + half` lands
    /// below any aim the preference can produce, so the clamp is what returns.
    /// Pinned as an equality against `highest` rather than as "the picture did
    /// not change", because the latter is only checkable by rendering and this
    /// is checkable by arithmetic — and because if the band ever shrinks far
    /// enough for the aim to become reachable at `2x`, this fails and says so
    /// instead of quietly moving the close view.
    @Test func theCloseViewIsUnmovedByWhereTheCameraPrefersToAim() throws {
        let manifest = try SceneFixtures.manifest()
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let scene = RoomScene(manifest: manifest, themeID: theme)
            let band = scene.contentBand
            let height = 400.0 / 2      // `2x` of the shipped panel
            let y = scene.cameraY(band: band, sceneHeight: height)
            #expect(y == band.bottom + height / 2, Comment(rawValue:
                "\(theme ?? "manifest.room"): 2x is no longer clamp-decided — the"
                + " band is \(band.top - band.bottom) px against \(height) px of"
                + " frame, and the aim has become reachable"))
        }
    }

    // MARK: Props [M5]

    /// The room draws real furniture only where the manifest names it. Anything
    /// unnamed stays a placeholder — the pack ships 339 singles by index and
    /// picking a desk-shaped one would be a guess. [I1]
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyPropRoleTheSceneDrawsIsOneTheManifestNames() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let nodes = scene.propNodesForTesting
        #expect(!nodes.isEmpty)
        // Every prop is drawn at the manifest's own prop canvas, so the anchor
        // maths and the measured box are in the same units.
        let canvas = CGSize(
            width: manifest.room.propCanvas.width, height: manifest.room.propCanvas.height)
        #expect(nodes.allSatisfy { $0.size == canvas })
    }

    /// **Nothing the room draws is nearer the camera than the characters.**
    ///
    /// M5 kept the foreground row honest geometrically: strictly below the
    /// content band, so it fell out of frame at the tightest fitting scale and
    /// only appeared as the camera pulled back. That was I7's "remove the detail
    /// that competes with the characters" answered by geometry rather than by
    /// taste — and the wide camera retired it, because `1x` became the only
    /// scale a normal room uses and "out of frame at the tightest scale" stopped
    /// meaning anything. The row was permanently on screen: seven identical
    /// plants under every glance.
    ///
    /// The rule that replaced it is about depth rather than about zoom, so no
    /// camera policy can retire it: **no prop is drawn in front of the seat
    /// row.** Everything nearer the camera than the desks is choreography — the
    /// aisle and the delivery rows — so the foreground is occupied by the thing
    /// the user is supposed to be looking at, and there is nothing left to
    /// compete with it.
    ///
    /// **ADR-008 narrows this to *decoration*, and the narrowing is the whole of
    /// what it takes from the rule.** A seat's own desk and chair now stand
    /// downstage of their occupant — that is what makes a standing figure read
    /// as a seated one, and it is the only reason a camera-facing seat exists at
    /// all. What the rule protects is that **nothing the room decorates itself
    /// with** comes between the viewer and a character, and that is untouched:
    /// no scenery, no backdrop, no accent, no station prop moved a pixel. The
    /// seat furniture is excluded by identity rather than by position, and it is
    /// held to its own bound instead — it may come downstage of its own row, and
    /// it may not reach `aisleY`, the row every character in the room walks
    /// across. A chair on the walkway would be furniture standing in a route,
    /// which is the thing `RoomPlan.routeViolations` exists to refuse.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theRoomDrawsNoDecorationInFrontOfTheCharacters() throws {
        let manifest = try SceneFixtures.manifest()
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let scene = RoomScene(manifest: manifest, themeID: theme)
            let nodes = scene.propNodesForTesting
            #expect(!nodes.isEmpty, "\(theme ?? "room") drew no furniture at all")
            let seatFurniture = Set(
                scene.seatFurnitureNodesForTesting.map(ObjectIdentifier.init))
            var decorative = 0, seated = 0
            for node in nodes {
                if seatFurniture.contains(ObjectIdentifier(node)) {
                    seated += 1
                    let why = "\(theme ?? "room") drew a seat's own furniture at"
                        + " y=\(node.position.y), on or past the walkway"
                    #expect(Double(node.position.y) > scene.layout.aisleY,
                            Comment(rawValue: why))
                    continue
                }
                decorative += 1
                let why = "\(theme ?? "room") drew a prop at y=\(node.position.y),"
                    + " in front of the seat row"
                #expect(Double(node.position.y) >= scene.layout.baselineY, Comment(rawValue: why))
            }
            // Both branches ran, so neither assertion is vacuous.
            #expect(decorative > 0 && seated > 0, Comment(rawValue:
                "\(theme ?? "room"): \(decorative) decorative, \(seated) seat pieces"))
        }
    }

    /// **The decoration is spread across the room, and stands at two depths on
    /// the lattice or at many when it is placed by hand.**
    ///
    /// The room's two decorative roles — a `board` against the wall and a
    /// `plant` a tile behind the back seat row — reach the floor by one of two
    /// mechanisms now, and this test has an arm for each. The reason for two
    /// arms rather than one loose assertion is that the *count* is the thing
    /// being pinned, and the two mechanisms pin different ones.
    ///
    /// ## The lattice arm — five themes
    ///
    /// Both halves of it are corrections to a real picture, and neither is
    /// visible in a manifest:
    ///
    /// - The role used to be picked on `seat % 2`, and seats fill *outward in
    ///   pairs* — so `seat % 2` is not "alternating", it is **which side of the
    ///   room**. Every backdrop stood in the left half and every accent in the
    ///   right, and the shipped panel read as two rooms stitched at the centre.
    /// - One row of decoration a tile behind the seats left the whole band of
    ///   the panel above the characters as flat wall. The backdrops now stand
    ///   against that wall.
    ///
    /// Counts are asserted too, because they are what the motion budget is
    /// priced on: this rearrangement had to be free. [ADR-002 §14b]
    ///
    /// **`scenery` is excluded, and only `scenery`.** M8 Phase 2b added a second,
    /// larger band of furniture upstage of these two, and it is priced by
    /// `SceneryContractTests` rather than here — the motion budget's own
    /// question, *how many copies of the role that carries the animation does
    /// the room draw*, is still exactly the count below. Excluding it by
    /// identity (`sceneryNodesForTesting`) rather than by position is deliberate:
    /// a position filter would silently start counting a scenery band that moved
    /// onto one of these rows.
    ///
    /// ## The hand-placed arm — the theme whose plan carries `dressing`
    ///
    /// A plan that places its own dressing places its boards and plants too,
    /// and the lattice does not run for it **at all**: leaving it running under
    /// an authored composition would keep two of the four stripes the
    /// composition exists to break. So the pinned count for that theme is
    /// **zero** decorative props outside `sceneryNodesForTesting` — every copy
    /// of both roles is a hand placement now, and it arrives through the same
    /// list as the printers and the bins.
    ///
    /// What the two roles have to keep, they keep in different words:
    ///
    /// - *Two depths* becomes **more than two**. The lattice's answer was
    ///   exactly two rows, which is the stripe this composition was authored to
    ///   break, so asserting two here would be asserting the defect.
    /// - *Nothing in front of the back seat row* becomes **nothing in front of
    ///   the front seat row** — clause 1 of `RoomPlan.dressingViolations`, which
    ///   is the rule that actually binds a hand-placed prop. A plant standing in
    ///   the lane between two stations is 28 px downstage of the back row and
    ///   that is the point of it; a prop downstage of `baselineY` would be drawn
    ///   over somebody's legs, and that is still forbidden.
    /// - *Neither depth is confined to one half* becomes **neither role is**,
    ///   which is the failure the original line was written against: every copy
    ///   of one role on one side of the room. Per-depth is not available to a
    ///   composition where a depth may hold one object.
    @Test(.enabled(if: SceneArt.isAvailable))
    func decorationIsSpreadAcrossTheRoomAndStandsAtTwoDepths() throws {
        let manifest = try SceneFixtures.manifest()
        var banded = 0, handPlaced = 0
        for theme in [nil] + manifest.themes.orderedIDs.map({ Optional($0) }) {
            let scene = RoomScene(manifest: manifest, themeID: theme)
            let layout = scene.layout
            let centre = layout.seatPosition(0).x
            // Only the two decorative roles; the desks and chairs at every seat
            // are placed by the seat, not by this band.
            // **By identity, not by position.** [ADR-008] This filtered out
            // anything standing on a seat row, which was exact only while every
            // desk and chair shared its occupant's row; a turned seat's
            // furniture stands downstage of it, and a position filter would
            // have quietly started counting seven desks as decoration. The
            // comment below already argued identity is the right key for
            // scenery; it is the right key for both.
            let excluded = Set(
                (scene.sceneryNodesForTesting + scene.seatFurnitureNodesForTesting)
                    .map(ObjectIdentifier.init))
            let decoration = scene.propNodesForTesting.filter {
                !excluded.contains(ObjectIdentifier($0))
            }

            guard !scene.store.room.plan.dressing.isEmpty else {
                banded += 1
                #expect(decoration.count == layout.seatCapacity, Comment(rawValue:
                    "\(theme ?? "room") drew \(decoration.count) decorative props"))

                let depths = Set(decoration.map { Double($0.position.y) })
                #expect(depths.count == 2, Comment(rawValue:
                    "\(theme ?? "room") stands all its decoration on \(depths)"))
                for depth in depths {
                    #expect(depth > layout.backSeatRowY, Comment(rawValue:
                        "\(theme ?? "room") put decoration on \(depth), level with"
                        + " or in front of the back seat row"))
                }
                #expect(depths.contains(layout.wallBaseY),
                        "nothing stands against the back wall")

                // Neither depth is confined to one half of the room: the failure
                // this replaces was every copy of one role on one side.
                for depth in depths {
                    let xs = decoration
                        .filter { Double($0.position.y) == depth }
                        .map { Double($0.position.x) }
                    #expect(xs.contains { $0 < centre } && xs.contains { $0 > centre },
                            Comment(rawValue:
                                "\(theme ?? "room")'s \(depth) band is all on one side"))
                }
                continue
            }

            handPlaced += 1
            let name = theme ?? "room"
            #expect(decoration.isEmpty, Comment(rawValue:
                "\(name) places its dressing by hand and still drew \(decoration.count)"
                + " decorative props off the board/plant lattice — the two mechanisms are"
                + " all-or-nothing per theme, and both of them ran"))

            // The two roles as the plan places them. Read off the plan rather
            // than off the nodes, because *which role* a node draws is not
            // something a node knows — and then checked against the nodes, so
            // the arm cannot pass on a placement nobody drew.
            let placed = scene.store.room.plan.dressing.compactMap { item -> (String, Int, Int)? in
                guard case let .role(role) = item.piece,
                      role == RoomScene.backdropRole || role == RoomScene.accentRole
                else { return nil }
                return (role, item.x, item.y)
            }
            // **How many is the composition's business; that there are some,
            // of both, is this test's.**
            //
            // This pinned `== 8` — office's own 3 boards and 5 plants — and the
            // number then propagated: when five more themes were composed, each
            // was shaped to place exactly 8 so this would pass. That is the test
            // deciding the art, and the number it was deciding by describes one
            // room's furniture rather than any rule. A composition is allowed to
            // want four plants or seven.
            //
            // What is worth pinning, and still is below: the lattice did not also
            // run, every authored placement was actually drawn, the decoration
            // stands on more than the lattice's two depths, and something is on
            // the wall line. Those are claims about the mechanism. Eight was a
            // claim about a floorplan.
            #expect(!placed.isEmpty, Comment(rawValue:
                "\(name) places by hand and hand-placed no board or plant at all, so the"
                + " depth and spread checks below run over nothing"))
            let roles = Set(placed.map(\.0))
            #expect(roles.count == 2, Comment(rawValue:
                "\(name) hand-places only \(roles.sorted()) — the room needs both the"
                + " backdrop standing on the wall line and the accent on the floor, which is"
                + " what the two depths below are measured across"))
            let drawn = Set(scene.sceneryNodesForTesting
                .map { "\(Int($0.position.x)),\(Int($0.position.y))" })
            for (role, x, y) in placed {
                #expect(drawn.contains("\(x),\(y)"), Comment(rawValue:
                    "\(name) authored a \(role) at (\(x), \(y)) and drew nothing there"))
            }

            let depths = Set(placed.map { Double($0.2) })
            #expect(depths.count > 2, Comment(rawValue:
                "\(name) stands its hand-placed decoration on \(depths.count) depths —"
                + " the lattice's own answer was 2, and breaking that stripe is what the"
                + " hand placement is for"))
            #expect(depths.contains(layout.wallBaseY),
                    "nothing stands against the back wall")
            for depth in depths {
                #expect(depth >= layout.baselineY, Comment(rawValue:
                    "\(name) put decoration on \(depth), nearer the camera than the front"
                    + " seat row at \(layout.baselineY)"))
            }

            for role in [RoomScene.backdropRole, RoomScene.accentRole] {
                let xs = placed.filter { $0.0 == role }.map { Double($0.1) }
                #expect(!xs.isEmpty, Comment(rawValue: "\(name) hand-places no \(role) at all"))
                #expect(xs.contains { $0 < centre } && xs.contains { $0 > centre },
                        Comment(rawValue: "\(name)'s \(role)s are all on one side"))
            }
        }
        #expect(handPlaced > 0, Comment(rawValue:
            "no theme places its dressing by hand, so that arm ran over nothing"))
        if banded == 0 {
            print("""
                NOTICE: all \(handPlaced) themes place by hand, so the two-depth                 decoration lattice was not checked against a room that draws it. It is                 still the fallback for a theme that declares no dressing.
                """)
        }
    }

    /// A prop is placed by putting its measured content box's bottom-centre on
    /// the target point. Checked against the desk, whose art sits 8 px above the
    /// bottom of its canvas — a naive bottom-anchor would bury it in the floor.
    @Test func aPropIsAnchoredOnItsContentBoxNotOnItsCanvas() throws {
        let manifest = try SceneFixtures.manifest()
        let desk = try #require(manifest.room.prop("desk"))
        let canvas = manifest.room.propCanvas
        let anchor = desk.anchor(inCanvas: canvas)
        // The art does not reach the bottom of the canvas, so the anchor must
        // sit above it.
        #expect(desk.contentBox.y + desk.contentBox.height < canvas.height)
        #expect(anchor.y > 0)
        let bottomRow = Double(desk.contentBox.y + desk.contentBox.height - 1)
        #expect(abs(anchor.y * Double(canvas.height)
                    - Double(canvas.height - 1) + bottomRow) < 1e-9)
    }

    @Test func theSceneOnlyEverSitsAtAnIntegerScale() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            scene.apply(director.apply(batch))
            #expect([3, 2, 1].contains(scene.currentScale))
        }
    }

    /// **A departure fades as it walks upstage, and only a departure fades.**
    ///
    /// The exit used to end off the side of the frame, where the frame edge did
    /// the hiding. There is no edge behind the desks — only a flat wall — so a
    /// character walking away has nothing to disappear behind, and would either
    /// slide up the wall in full view or blink out at an invisible line. It
    /// fades over the last leg instead. Nothing else in the room ever changes a
    /// character's opacity, which is what keeps "faded" readable as "gone".
    @Test(.enabled(if: SceneArt.isAvailable))
    func onlyADepartureFadesAndItFadesAllTheWayOut() throws {
        let store = try Self.store()
        let layout = RoomLayout()
        let character = Character(
            variant: "09", nameplate: NameplateText(lead: "6E7", role: "Explore"), store: store)
        character.advance(to: 0)
        character.position = CGPoint(x: layout.seatPosition(1).x, y: layout.baselineY)

        // The report round trip is not an exit and must not fade — the character
        // comes home and sits down.
        character.reportAndReturn(
            out: layout.deliveryRoute(anchorSeat: 0, reporterSeat: 1), facing: .left,
            home: layout.homeRoute(forSeat: 1), onFinished: {})
        for step in 0...900 { character.advance(to: Double(step) / 60.0) }
        #expect(character.alpha == 1, "a reporter faded on its way home")

        var finished = false
        character.departOffScreen(
            via: layout.homeRoute(forSeat: 1, fromY: layout.baselineY),
            to: layout.upstageExit(forSeat: 1)) { finished = true }
        character.advance(to: 15.0)
        #expect(character.alpha == 1, "the exit faded before it started walking")
        var faded: [CGFloat] = []
        for step in 0...240 {
            character.advance(to: 15.0 + Double(step) / 60.0)
            faded.append(character.alpha)
        }
        #expect(finished)
        #expect(character.alpha == 0, "the leaver is still visible when it is retired")
        #expect(faded.contains { $0 > 0.2 && $0 < 0.8 }, "it blinked out rather than fading")
        #expect(zip(faded, faded.dropFirst()).allSatisfy { $0 >= $1 }, "the fade went backwards")
        #expect(Double(character.position.y) == layout.wallBaseY)
    }

    // MARK: The synthetic worst case

    /// One adversarial pairing: what happens to a full six-agent room, and what
    /// happens `offset` seconds later.
    struct AdversarialScript: Sendable {
        var first: [WorldDelta]
        var second: [WorldDelta]
    }

    /// **Every pairing of beats that can put two characters near each other.**
    ///
    /// The fixtures pass, and passing was partly luck: `three-subagents` cleared
    /// by 20 px in x and got there by timing rather than by geometry. So the
    /// pairings are enumerated instead of waited for. Six agents — S4's
    /// population — and one beat fired against another at every tenth of a
    /// second of relative offset, through the window where they overlap.
    ///
    /// The pairs that matter and why:
    ///
    /// - two same-side reports, which is what the delivery slots existed for and
    ///   where lowest-free claiming put the farther reporter through the nearer
    ///   one's station;
    /// - a report against a departure, which is a leaver crossing the room
    ///   against a reporter crossing it the other way — the case no seat pitch
    ///   can fix, because two characters walking one line in opposite directions
    ///   meet at zero separation whatever the pitch;
    /// - a report against an arrival, which is the same thing with the arrival
    ///   walking in along the aisle;
    /// - the whole cast leaving at once, which is `SessionEnd`;
    /// - a seat vacated and immediately refilled, which is the one case that
    ///   puts an arrival's corridor across an occupied station.
    ///
    /// **The refill pairing was here and was aimed at the wrong seat, and that
    /// is worth recording rather than quietly fixing.** It vacated seat 1 and
    /// reported from seat 5 — two rings apart, so the arrival's corridor and the
    /// reporter's station were never the same place, and the sweep cleared at
    /// the lattice's own 6 px margin while an overlap of **−25.6 px** sat one
    /// ring away. The corridor of an arrival at seat *n* ended on seat *n+2*'s
    /// station — the next ring out on the same side — and nothing here fired
    /// those two against each other. The three pairings below are that case, at
    /// every same-side adjacent-ring pair the room has, plus the handover that
    /// puts two characters in one column at once. A sweep that enumerates
    /// pairings is only as good as the pairings it enumerates.
    static let adversarialScripts: [(String, AdversarialScript)] = {
        let cast = RoomSceneTests.cast(6)
        let newcomer = AgentRef(project: "/p", session: "s", agent: .subagent("aFEEDFACE00000001"))
        func appear(_ ref: AgentRef) -> WorldDelta {
            .agentAppeared(agent: ref, agentType: "general-purpose", lifecycle: .spawning)
        }
        return [
            ("two same-side reports (near first)",
             .init(first: [.reportDelivered(agent: cast[1])],
                   second: [.reportDelivered(agent: cast[5])])),
            ("two same-side reports (far first)",
             .init(first: [.reportDelivered(agent: cast[5])],
                   second: [.reportDelivered(agent: cast[1])])),
            ("three same-side reports",
             .init(first: [.reportDelivered(agent: cast[5]), .reportDelivered(agent: cast[3])],
                   second: [.reportDelivered(agent: cast[1])])),
            ("report against a departure the other way",
             .init(first: [.reportDelivered(agent: cast[5])],
                   second: [.agentDeparted(agent: cast[1])])),
            ("departure against a report the other way",
             .init(first: [.agentDeparted(agent: cast[1])],
                   second: [.reportDelivered(agent: cast[5])])),
            ("report against an arrival",
             .init(first: [.reportDelivered(agent: cast[5])], second: [appear(newcomer)])),
            ("the whole cast leaves at once",
             .init(first: [.reportDelivered(agent: cast[3])],
                   second: cast.map { .agentDeparted(agent: $0) })),
            ("a seat vacated and refilled under an outer report",
             .init(first: [.agentDeparted(agent: cast[1]), .reportDelivered(agent: cast[5])],
                   second: [appear(newcomer)])),
            // The three same-side adjacent-ring refills. Seats 1/3/5 sit at one,
            // two and three pitches right of centre and 2/4 at one and two left,
            // so these are every pair whose columns are one pitch apart on one
            // side — which is exactly the reach the old aisle walk-in had.
            ("a seat vacated and refilled under the next ring out reporting (1 under 3)",
             .init(first: [.agentDeparted(agent: cast[1]), .reportDelivered(agent: cast[3])],
                   second: [appear(newcomer)])),
            ("a seat vacated and refilled under the next ring out reporting (3 under 5)",
             .init(first: [.agentDeparted(agent: cast[3]), .reportDelivered(agent: cast[5])],
                   second: [appear(newcomer)])),
            ("a seat vacated and refilled under the next ring out reporting (2 under 4)",
             .init(first: [.agentDeparted(agent: cast[2]), .reportDelivered(agent: cast[4])],
                   second: [appear(newcomer)])),
            // A seat is free the instant its occupant starts walking out, so the
            // newcomer and the leaver are in one column together. Nothing else
            // in the room can put two characters on one column, and it is the
            // case that decides which *way* a walk-in runs: both move upstage,
            // so they are a convoy and the gap they start with is the gap they
            // keep.
            ("a seat refilled while its leaver is still in the column",
             .init(first: [.agentDeparted(agent: cast[1])], second: [appear(newcomer)])),
        ]
    }()

    /// Runs one pairing and returns the tightest the plates ever came, and when.
    /// Negative means they intersected.
    static func runAdversarial(
        manifest: Manifest, script: AdversarialScript, offset: TimeInterval
    ) -> (gap: Double, at: TimeInterval) {
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest)
        scene.apply(director.apply(cast(6).enumerated().map { index, ref in
            .agentAppeared(
                agent: ref, agentType: index == 0 ? nil : "general-purpose",
                lifecycle: index == 0 ? .active : .spawning)
        }))

        var time = 0.0
        var worst = Double.greatestFiniteMagnitude
        var worstAt = 0.0
        func step(_ seconds: TimeInterval) {
            let end = time + seconds
            while time < end {
                time += 1.0 / 60.0
                scene.advance(to: time)
                let onScreen = scene.charactersOnScreen
                for (index, first) in onScreen.enumerated() {
                    for second in onScreen[onScreen.index(after: index)...] {
                        let a = first.nameplateRect, b = second.nameplateRect
                        let gap = Double(max(max(b.minX - a.maxX, a.minX - b.maxX),
                                             max(b.minY - a.maxY, a.minY - b.maxY)))
                        if gap < worst { worst = gap; worstAt = time }
                    }
                }
            }
        }
        // Everyone in and seated first, so the beats under test are the only
        // thing moving. A walk-in is 128 px at 72 px/s, so three seconds is
        // clear of it; the tail outlasts the longest route the room can produce,
        // which is a report out and back followed by an exit.
        step(3)
        scene.apply(director.apply(script.first))
        step(max(1.0 / 60.0, offset))
        scene.apply(director.apply(script.second))
        step(15)
        return (worst, worstAt)
    }

    /// **The guarantee, exercised rather than argued.**
    ///
    /// `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem` proves the
    /// lattice from the numbers. This drives it: every adversarial pairing at
    /// every offset, and no two plates may come closer than touching. The bound
    /// asserted is a real gap rather than mere non-intersection, so a change
    /// that leaves the rooms *just* clearing fails here instead of shipping.
    @Test(.enabled(if: SceneArt.isAvailable))
    func noAdversarialPairingOfBeatsEverTouchesTwoPlates() throws {
        let manifest = try SceneFixtures.manifest()
        var worst = Double.greatestFiniteMagnitude
        var worstLabel = ""
        for (label, script) in Self.adversarialScripts {
            for offset in stride(from: 0.0, through: 6.0, by: 0.5) {
                let result = Self.runAdversarial(
                    manifest: manifest, script: script, offset: offset)
                if result.gap < worst {
                    worst = result.gap
                    worstLabel = "\(label), fired \(String(format: "%.1f", offset))s apart,"
                        + " at t=\(String(format: "%.2f", result.at))"
                }
            }
        }
        #expect(worst > 0, Comment(rawValue:
            "plates came within \(worst) px — \(worstLabel)"))
        // The lattice's own margin: rows are a tile apart and plates 26 px tall,
        // so anything on two different rows clears by 6 px. Anything less means
        // two characters found their way onto one row.
        #expect(worst >= 6, Comment(rawValue:
            "only \(worst) px of clearance — \(worstLabel)"))
    }

    // MARK: The overflow plate [I1, S5]

    /// A box in scene coordinates, bottom-centre anchored the way every prop and
    /// the plate itself are.
    static func box(bottomCentre point: ScenePoint, width: Double, height: Double)
    -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        (point.x - width / 2, point.x + width / 2, point.y, point.y + height)
    }

    static func intersects(
        _ a: (minX: Double, maxX: Double, minY: Double, maxY: Double),
        _ b: (minX: Double, maxX: Double, minY: Double, maxY: Double)
    ) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// **Nothing else stands where the plate stands, in any theme.**
    ///
    /// The point is `RoomLayout.overflowPlatePosition` and the props are read
    /// from `RoomScene.decorationPlacements` — the same function the room
    /// builds from, not a copy of it — so a theme with a taller accent or a
    /// change to the alternation fails here rather than quietly putting the
    /// room's only caption behind a bookcase.
    @Test func theOverflowPlateStandsWhereNoThemePutsAProp() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let plate = SceneBitmaps.overflowPlate(9)
        let plateBox = Self.box(
            bottomCentre: layout.overflowPlatePosition,
            width: Double(plate.width), height: Double(plate.height))

        var themes: [(String, Manifest.Room)] = [("room", manifest.room)]
        for id in manifest.themes.orderedIDs {
            themes.append((id, try #require(manifest.themes.theme(id)).room))
        }
        #expect(themes.count > 1)

        for (id, room) in themes {
            for placement in RoomScene.decorationPlacements(layout: layout) {
                let prop = try #require(room.prop(placement.role),
                                        "\(id) binds no \(placement.role)")
                let propBox = Self.box(
                    bottomCentre: placement.point,
                    width: Double(prop.contentBox.width),
                    height: Double(prop.contentBox.height))
                #expect(!Self.intersects(plateBox, propBox), Comment(rawValue:
                    "\(id): the overflow plate overlaps the \(placement.role) at"
                    + " x=\(placement.point.x)"))
            }
        }
    }

    /// **The caption is on screen, or it is silence.** The panel is 720×400 and
    /// the plate only ever appears with every seat taken, so the frame is fixed
    /// when it matters — but `--render` and `--window` take a size, so the
    /// clamp is checked over a sweep rather than at the one size that ships.
    @Test func theOverflowPlateIsInsideTheFrameAtEverySizeTheAppCanBeGiven() throws {
        let manifest = try SceneFixtures.manifest()
        for width in [720.0, 480.0, 1600.0] {
            for height in [400.0, 300.0, 900.0] {
                let scene = RoomScene(manifest: manifest)
                scene.setViewport(CGSize(width: width, height: height))
                scene.apply([.setOverflow(6)])
                let plate = try #require(scene.overflowPlateBoxForTesting())
                let camera = try #require(scene.camera)
                let frame = (
                    minX: Double(camera.position.x) - Double(scene.size.width) / 2,
                    maxX: Double(camera.position.x) + Double(scene.size.width) / 2,
                    minY: Double(camera.position.y) - Double(scene.size.height) / 2,
                    maxY: Double(camera.position.y) + Double(scene.size.height) / 2)
                let label = "\(Int(width))x\(Int(height))"
                #expect(plate.x >= frame.minX, "\(label): the plate is off the left edge")
                #expect(plate.x + plate.width <= frame.maxX, "\(label): off the right edge")
                #expect(plate.y >= frame.minY, "\(label): off the bottom edge")
                #expect(plate.y + plate.height <= frame.maxY, "\(label): off the top edge")
            }
        }
    }

    /// It says the number it was given, it stops saying anything at zero, and it
    /// is not a prop — §6 rule 1's "zero prop-node rebuilds" must stay a
    /// statement about the room's furniture.
    @Test func theOverflowPlateAppearsOnlyWhenThereIsSomethingToSay() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        let props = scene.propNodesForTesting.count

        #expect(scene.overflowPlateBoxForTesting() == nil, "it spoke before it had to")
        scene.apply([.setOverflow(3)])
        let three = try #require(scene.overflowPlateBoxForTesting())
        #expect(scene.overflowShown == 3)

        scene.apply([.setOverflow(12)])
        let twelve = try #require(scene.overflowPlateBoxForTesting())
        // **The plate widens with the count again**, because the count and
        // `MORE` share one line now — `+3 MORE` against `+12 MORE`. It stopped
        // doing so while they were two rows and `MORE` set the width; that note
        // is what this replaces. The number is still checked directly, since a
        // width is only a proxy for it.
        #expect(twelve.width > three.width)
        #expect(SceneBitmaps.overflowPlate(12).pixels != SceneBitmaps.overflowPlate(3).pixels,
                "the plate drew the same thing for 3 and 12")

        scene.apply([.setOverflow(0)])
        #expect(scene.overflowPlateBoxForTesting() == nil, "it kept saying it at zero")
        #expect(scene.propNodesForTesting.count == props, "the plate was registered as a prop")
        #expect(scene.roomBuildCount == 1)
    }

    /// The plate reads the number, and reads as *not* an agent: every character
    /// plate carries a saturated accent band assigned 60° apart, and this one
    /// carries the plate colour, so there is nobody it could be mistaken for.
    @Test func theOverflowPlateSaysTheCountAndBelongsToNobody() {
        let plate = SceneBitmaps.overflowPlate(4)
        let named = SceneBitmaps.nameplate(
            NameplateText(lead: "+4 \(SceneBitmaps.overflowLabel)"),
            accent: Bitmap.RGBA(220, 40, 40))
        #expect(plate.width == named.width, "the two plates are the same construction")
        #expect(plate.height == named.height)

        var accented = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) != named.at(x, y) { accented += 1 }
        }
        #expect(accented > 0, "the overflow plate wears a character's accent")

        // **The count and the word share the plate's one line.** They had a row
        // each until the nameplate lost its rows; keeping them both is what
        // makes the plate a sentence rather than a bare number. The count leads,
        // because it is the half that differs.
        var ink = 0
        for y in 0..<plate.height {
            for x in 0..<plate.width where plate.at(x, y) == SceneBitmaps.nameplateInk {
                ink += 1
            }
        }
        #expect(ink == PixelFont.standard
                    .render("+4 MORE", colour: SceneBitmaps.nameplateInk).opaquePixelCount,
                "the plate does not read `+4 MORE`")
        #expect(plate.height == SceneBitmaps.maximumNameplateHeight,
                "the overflow plate is not the room's one-row plate")
    }
}

// MARK: - Test hooks

extension Character {
    /// The texture currently on the body. Read-only, for tests that need to
    /// prove an animation did or did not advance.
    var currentTextureForTesting: SKTexture? {
        (children.first as? SKSpriteNode)?.texture
    }
}
