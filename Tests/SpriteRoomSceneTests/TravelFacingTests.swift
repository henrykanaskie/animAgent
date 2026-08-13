import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **M8 #73 — a character walking up its own column is drawn walking up.**
///
/// The defect, in the maintainer's own words as complaint #4: *"The orientation
/// is plain and side-on. Characters should face front and back, so you can
/// actually see them."* Three quarters of the answer was already on disk. The
/// manifest declares `walk`, `idle`, `spawn`, `depart` and `deliver` in all four
/// directions at six frames each — only `working` is side-only, which is the M0
/// sit-row finding and is correct — and the scene asked for two of the four.
///
/// The one line that did it was the travel rule. It was
/// `forHorizontalTravel(_:current:)`, keyed on `dx` alone, and it returned the
/// **current** facing when `dx == 0` on the stated grounds that "a vertical-only
/// move does not spin the character". `RoomLayout` contradicts that premise in
/// its own comments: an arrival is "straight up its own column", a departure is
/// "straight back, up its own column, and out through the back of the room", and
/// "every arrival and every departure is one column, one direction". Both are
/// pure `dy`, so `dx == 0` was not an edge case to be protected — it was every
/// entrance and every exit in the room.
///
/// **Nothing in the suite caught it**, which is why this file exists: the full
/// run stayed green through the fix, so the walk facing had no coverage at all
/// before these tests. A wiring bug that no test can see is one that comes back.
struct TravelFacingTests {

    // MARK: The rule, as arithmetic

    /// The axis convention, pinned. `wallBaseY` is `floorRows * tile` — the back
    /// of the room — and `upstageExit` walks to it, so **increasing `y` is away
    /// from the camera**. If this ever inverts, every entrance in the room walks
    /// in backwards and this is the assertion that says so.
    @Test func verticalTravelAnswersUpAndDownRatherThanKeepingASideView() {
        #expect(Facing.forTravel(dx: 0, dy: 40, current: .right) == .up)
        #expect(Facing.forTravel(dx: 0, dy: -40, current: .right) == .down)
        // The old rule's whole behaviour on this input: keep whatever you had.
        #expect(Facing.forTravel(dx: 0, dy: 40, current: .left) != .left,
                "a vertical walk still inherits a side view")
    }

    /// Horizontal travel is unchanged — the one lateral route in the room is the
    /// delivery corridor, and it must still turn the reporter sideways.
    @Test func horizontalTravelIsUnchanged() {
        #expect(Facing.forTravel(dx: 30, dy: 0, current: .up) == .right)
        #expect(Facing.forTravel(dx: -30, dy: 0, current: .up) == .left)
    }

    /// Standing still keeps the current facing. This is the part of the old
    /// rule that was right, and dropping it would spin a character on any script
    /// step that goes nowhere.
    @Test func standingStillKeepsTheCurrentFacing() {
        for facing in Facing.allCases {
            #expect(Facing.forTravel(dx: 0, dy: 0, current: facing) == facing)
        }
    }

    /// The larger magnitude wins, and a tie is deterministic. The room's routes
    /// are axis-aligned by construction so a true diagonal is unreachable today;
    /// this pins the degradation rather than a case that exists.
    @Test func theDominantAxisDecidesAndTiesAreDeterministic() {
        #expect(Facing.forTravel(dx: 50, dy: 10, current: .up) == .right)
        #expect(Facing.forTravel(dx: 10, dy: -50, current: .up) == .down)
        #expect(Facing.forTravel(dx: 20, dy: 20, current: .right) == .up)
        #expect(Facing.forTravel(dx: 20, dy: 20, current: .left) == .up,
                "a tie depended on what the character was already doing")
    }

    // MARK: The room, measured

    /// **The entrance really is vertical**, read off `RoomLayout` rather than
    /// asserted — this is the premise the whole fix rests on, so it is measured
    /// instead of quoted from a comment.
    @Test func everyEntranceRouteInTheRoomIsAPureVerticalWalk() {
        let layout = RoomLayout()
        for seat in 0..<layout.seatCapacity {
            let route = layout.entranceRoute(forSeat: seat)
            #expect(route.count >= 2)
            for (from, to) in zip(route, route.dropFirst()) {
                #expect(abs(to.x - from.x) < 0.001,
                        "seat \(seat)'s entrance moves sideways by \(to.x - from.x)")
                #expect(to.y > from.y,
                        "seat \(seat)'s entrance does not walk away from the camera")
            }
        }
    }

    /// And so is the exit, for the same reason.
    ///
    /// **Still strictly upstage, and at an away-facing seat that is now seven
    /// pixels rather than ninety-six.** The exit stops at whatever the seat
    /// stands behind its own occupant
    /// [`RoomLayout.upstageClearance(forSeat:metrics:)`], and what stops it is
    /// `awayDeskUpstage` — a quarter tile — so the leg survives, shortened. The
    /// direction is what this test is about; the length is
    /// `RouteFurnitureTests`'.
    @Test func everyExitInTheRoomWalksStraightUpstage() throws {
        let layout = RoomLayout()
        let metrics = SceneFixtures.seatMetrics(try SceneFixtures.manifest(), theme: "office")
        for seat in 0..<layout.seatCapacity {
            let seatPoint = layout.seatPosition(seat)
            let exit = layout.upstageExit(forSeat: seat, metrics: metrics)
            #expect(abs(exit.x - seatPoint.x) < 0.001)
            #expect(exit.y > seatPoint.y)
        }
    }
}

/// The same thing on a real character, which is where it would actually be seen.
@MainActor
struct TravelFacingSceneTests {

    static let agent = AgentRef(project: "/p", session: "s", agent: .subagent("a1"))

    static func scene(_ manifest: Manifest) -> RoomScene {
        let scene = RoomScene(manifest: manifest)
        scene.apply([.spawnCharacter(
            agent: agent, variant: manifest.characters.orderedVariantIDs[0],
            nameplate: NameplateText(lead: "8DE", role: "Explore"), seat: 1,
            station: "", costume: nil)])
        return scene
    }

    /// **A character walking in faces away from the camera.** Before the fix
    /// this was `.right` — `Character.currentFacing`'s initial value — for the
    /// whole of the walk, on every arrival in the room's life.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aCharacterWalkingInIsDrawnWalkingAway() throws {
        let scene = Self.scene(try SceneFixtures.manifest())
        scene.advance(to: 0)
        let character = try #require(scene.character(for: Self.agent))
        #expect(character.facing == .up,
                "walked in facing \(character.facing) while travelling upstage")
    }

    /// And the frames it is drawing are the `up` frames, not the side ones
    /// re-labelled. This is the half that proves the art was reached: a facing
    /// enum with no frames behind it would leave `apply` on its
    /// `textures.isEmpty` guard and the character in its previous pose.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theUpwardWalkDrawsTheUpwardFrames() throws {
        let manifest = try SceneFixtures.manifest()
        let store = TextureStore(manifest: manifest)
        let variant = try #require(manifest.characters.orderedVariantIDs.first)
        for state in [BodyState.walk, .spawn, .depart, .idle] {
            for facing in Facing.allCases {
                #expect(!store.frames(variant: variant, state: state, facing: facing).isEmpty,
                        "\(state)/\(facing) has no frames, so the scene cannot ask for it")
            }
        }
        // And the four directions are genuinely four pictures, not one sheet
        // pointed at four times — the sit row's own defect, which is why
        // `working` is excluded here.
        let up = store.frames(variant: variant, state: .walk, facing: .up)
        let down = store.frames(variant: variant, state: .walk, facing: .down)
        let right = store.frames(variant: variant, state: .walk, facing: .right)
        #expect(up.first !== down.first)
        #expect(up.first !== right.first)
    }
}
