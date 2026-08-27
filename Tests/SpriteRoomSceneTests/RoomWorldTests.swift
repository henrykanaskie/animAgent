import Foundation
import SpriteKit
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The room is separable from the view, and that is the whole of the change
/// this file exists to protect.**
///
/// `RoomScene` used to be both, which is why there could only ever be one room:
/// the camera, the viewport and the integer scale lived in the same object as
/// the props, the characters and the seat map. M9 Phase 4 needs several rooms at
/// once, one per project, so the two were separated.
///
/// The extraction itself is proved by `scripts/lint-palette.py`'s scene
/// agreement, which compares the rendered room to an independent transcription
/// pixel for pixel, per theme, with an empty defect register: a refactor that
/// moved one prop would fail it, and none of the six moved.
///
/// What that check cannot notice is the two halves quietly growing back
/// together, which is what these assert. **None of them needs a view, a camera
/// or an `SKScene`**, and that is the point: if any of them stops compiling
/// because a `RoomWorld` now wants a scene, the separation has been lost and
/// Phase 4 is blocked again.
@MainActor
@Suite struct RoomWorldTests {

    /// **A room builds with no scene at all.**
    ///
    /// The plainest statement of the property. Before the extraction this line
    /// could not be written: constructing the room meant constructing an
    /// `SKScene`, and an `SKScene` is a thing there is one of per view.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aRoomBuildsWithoutAScene() throws {
        let manifest = try SceneFixtures.manifest()
        let world = RoomWorld(manifest: manifest)
        #expect(world.root.parent == nil, "a freshly built room belongs to nobody")
        #expect(!world.root.children.isEmpty, "the room built nothing")
        #expect(world.population == 0)
        #expect(world.roomBuildCount == 1, "the room built itself more than once")
    }

    /// **Two rooms coexist, on two themes, with independent node trees.**
    ///
    /// This is Phase 4's enabling property stated as an assertion. The two are
    /// dressed differently and neither shares a node with the other, which is
    /// what makes "one room per project" a layout problem rather than an
    /// architectural one.
    @Test(.enabled(if: SceneArt.isAvailable))
    func twoRoomsCoexistWithoutSharingANode() throws {
        let manifest = try SceneFixtures.manifest()
        let ids = manifest.themes.orderedIDs
        try #require(ids.count >= 2, "two themes are needed to tell two rooms apart")

        let a = RoomWorld(manifest: manifest, themeID: ids[0])
        let b = RoomWorld(manifest: manifest, themeID: ids[1])

        #expect(a.root !== b.root)
        #expect(a.store.themeID != b.store.themeID)

        func nodes(_ world: RoomWorld) -> Set<ObjectIdentifier> {
            var found: Set<ObjectIdentifier> = []
            func walk(_ node: SKNode) {
                found.insert(ObjectIdentifier(node))
                for child in node.children { walk(child) }
            }
            walk(world.root)
            return found
        }
        let shared = nodes(a).intersection(nodes(b))
        #expect(shared.isEmpty, Comment(rawValue:
            "\(shared.count) node(s) are in both rooms, so the two are not"
            + " independent and a second project would redraw the first"))

        // Dressed differently, which is what makes them two *rooms* rather than
        // two copies. Compared on the art each draws, not on the theme id,
        // because the id is what was asked for and this is what was drawn.
        #expect(Set(a.propArtForTesting) != Set(b.propArtForTesting), Comment(rawValue:
            "\(ids[0]) and \(ids[1]) drew the same props, so this proves nothing"
            + " about two rooms being distinguishable"))
    }

    /// **A room can be driven with no view attached**: intents in, characters
    /// out, the clock advanced by hand.
    ///
    /// The offscreen harness has always driven the scene this way; what is new
    /// is that the thing being driven is not a scene. A `RoomWorld` that needed
    /// `update(_:)` from a view's render loop could not be one of several.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aRoomCanBeDrivenWithNoViewAttached() throws {
        let manifest = try SceneFixtures.manifest()
        let world = RoomWorld(manifest: manifest)
        var director = SceneDirector(manifest: manifest)
        let agent = AgentRef(project: "/p", session: "s", agent: .mainThread)

        world.apply(director.apply(
            [.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)], at: Date()))
        #expect(world.population == 1, "the room drew nobody")
        world.advance(to: 1.0)
        #expect(world.character(for: agent) != nil)
        #expect(world.root.parent == nil, "driving the room attached it to something")
    }

    /// **`.setScale` never reaches the room.** [I6]
    ///
    /// The scale is the view's, and `RoomScene.apply` takes that intent out of
    /// the batch before forwarding. `RoomWorld`'s own `.setScale` arm is
    /// therefore unreachable, and this is the assertion that it stays that way:
    /// a room that acted on a scale would be a room that had opinions about a
    /// camera it does not own, which is exactly what made one room the limit.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theRoomIgnoresTheScaleBecauseTheSceneOwnsIt() throws {
        let manifest = try SceneFixtures.manifest()
        let world = RoomWorld(manifest: manifest)
        let before = world.root.children.count
        world.apply([.setScale(1), .setScale(3)])
        #expect(world.root.children.count == before,
                "a scale intent changed the room's node tree")

        // And the scene does act on it, so the intent is handled once rather
        // than nowhere. Both halves in one test on purpose: "the room ignores
        // it" is only worth asserting alongside "and something else does not".
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        scene.apply([.setScale(1)])
        #expect(scene.currentScale == 1, "the scene ignored the scale too")
    }
}

/// **Several rooms in one scene: one per project.** [M9 Phase 4]
///
/// `docs/01-PRD.md` listed "Multiple projects on screen simultaneously" under
/// *Explicit non-goals: v1*, "Do not build them". ADR-016 is the reversal and
/// these are what it is checked by.
///
/// The property that matters most is the boring one: **a single-project run is
/// unchanged**. Slot 0 sits at the origin and nothing about it moves, which is
/// what keeps `lint-palette.py`'s pixel comparison meaning what it meant. If
/// that ever stops being true, every claim this project makes about its own art
/// stops being checkable at the same moment.
@MainActor
@Suite struct MultiRoomTests {

    static func scene() throws -> RoomScene {
        let scene = RoomScene(manifest: try SceneFixtures.manifest())
        scene.setViewport(CGSize(width: 720, height: 800))
        return scene
    }

    /// **One project is exactly what it was.** The guarantee the pixel gate
    /// rests on, asserted rather than assumed.
    @Test(.enabled(if: SceneArt.isAvailable))
    func oneProjectPutsItsRoomAtTheOriginAndBuildsNoOther() throws {
        let scene = try Self.scene()
        scene.room(for: "/a", themeID: nil)
        #expect(scene.rooms.count == 1, "a single project built \(scene.rooms.count) rooms")
        #expect(scene.rooms[0].world.root.position == .zero,
                "slot 0 moved, so the single-project picture is not what it was")
        #expect(scene.slot(of: "/a") == 0)
    }

    /// **The room `init` built is claimed by the first project, not discarded.**
    ///
    /// Building a second and throwing the first away would redraw the whole room
    /// on the first delta of every run, which is a rebuild nobody asked for and
    /// `roomBuildCount` is how it would be noticed.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theFirstProjectAdoptsTheRoomThatAlreadyExists() throws {
        let scene = try Self.scene()
        let before = ObjectIdentifier(scene.rooms[0].world)
        let claimed = scene.room(for: "/a", themeID: nil)
        #expect(ObjectIdentifier(claimed) == before, "the first project got a new room")
        #expect(claimed.roomBuildCount == 1, "the room was built twice")
    }

    /// **A second project gets its own room, one pitch upstage.**
    @Test(.enabled(if: SceneArt.isAvailable))
    func aSecondProjectStandsOnePitchUpstageInItsOwnRoom() throws {
        let scene = try Self.scene()
        let ids = try #require(Array(scene.store.manifest.themes.orderedIDs.prefix(2)).count == 2
                               ? Array(scene.store.manifest.themes.orderedIDs.prefix(2)) : nil)
        let a = scene.room(for: "/a", themeID: ids[0])
        let b = scene.room(for: "/b", themeID: ids[1])

        #expect(a !== b, "two projects share one room")
        #expect(scene.slot(of: "/a") == 0 && scene.slot(of: "/b") == 1)
        #expect(a.root.position.y == 0)
        #expect(b.root.position.y == CGFloat(scene.roomPitch), Comment(rawValue:
            "room 1 stands at y=\(b.root.position.y) against a pitch of \(scene.roomPitch)"))
        #expect(a.root.parent === scene && b.root.parent === scene,
                "a room was built but never added to the scene")
    }

    /// **The pitch is exactly the plan's own depth**, so the floor of the room
    /// above starts where the back wall of the room below ends.
    ///
    /// Both neighbouring values were rendered before this one was chosen: the
    /// nominal box (288) buried the lower room's back wall, and the painted
    /// overscan height (672) left a band of void. This pins the measurement so
    /// the next person does not have to re-render to find that out.
    @Test(.enabled(if: SceneArt.isAvailable))
    func thePitchIsThePlansOwnDepth() throws {
        let scene = try Self.scene()
        let plan = scene.store.room.plan
        let lowest = try #require(plan.spaces.map(\.y).min())
        let highest = try #require(plan.spaces.map { $0.y + $0.h }.max())
        #expect(scene.roomPitch == Double((highest - lowest) * scene.layout.tile))
        #expect(scene.roomPitch > scene.layout.height, Comment(rawValue:
            "a pitch of \(scene.roomPitch) is inside the room's own nominal box"
            + " (\(scene.layout.height)), so the room above covers the wall below"))
    }

    /// **An intent addressed to one project lands in that project's room and
    /// nowhere else.** [I1]
    ///
    /// The routing assertion. Without it a fan-out could put every project's
    /// characters in the first room and look, from a distance, like it worked.
    @Test(.enabled(if: SceneArt.isAvailable))
    func anIntentGoesToItsOwnProjectsRoom() throws {
        let scene = try Self.scene()
        let manifest = scene.store.manifest
        scene.room(for: "/a", themeID: nil)
        scene.room(for: "/b", themeID: nil)

        var directorB = SceneDirector(manifest: manifest)
        let b = AgentRef(project: "/b", session: "s", agent: .mainThread)
        let intents = directorB.apply(
            [.agentAppeared(agent: b, agentType: nil, lifecycle: .active)], at: Date())
        scene.apply(intents, to: "/b")

        #expect(scene.rooms[0].world.population == 0, "project B was drawn in project A's room")
        #expect(scene.rooms[1].world.population == 1, "project B was not drawn in its own room")
        #expect(scene.rooms[1].world.character(for: b) != nil)
    }

    /// **A stack taller than the frame shows fewer rooms rather than half of
    /// each.** [I1]
    ///
    /// The regression this prevents is specific: the camera centres on the union
    /// of what is drawn, so two rooms in a 400 px panel would frame the top of
    /// one and the floor of the other and show **neither one's characters**.
    /// That is worse than the single room it replaced, for exactly the user the
    /// feature is for.
    ///
    /// So the surplus is counted and not drawn, which is the answer this room
    /// already gives for the eighth agent. It also makes the panel's height a
    /// pure taste knob: 400 px is one room, 800 is two, and nothing else has to
    /// change to spend it.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aStackTallerThanTheFrameIsCountedRatherThanCropped() throws {
        let manifest = try SceneFixtures.manifest()

        let short = RoomScene(manifest: manifest)
        short.setViewport(CGSize(width: 720, height: 400))
        short.room(for: "/a", themeID: nil)
        short.room(for: "/b", themeID: nil)
        #expect(short.roomsThatFit == 1, Comment(rawValue:
            "a 400 px frame showed \(short.roomsThatFit) rooms; the pitch alone is"
            + " \(short.roomPitch)"))
        #expect(short.roomsNotShown == 1)
        #expect(short.rooms[1].world.root.isHidden, "the surplus room was drawn anyway")
        #expect(!short.rooms[0].world.root.isHidden, "the first room was hidden")

        let tall = RoomScene(manifest: manifest)
        tall.setViewport(CGSize(width: 720, height: 800))
        tall.room(for: "/a", themeID: nil)
        tall.room(for: "/b", themeID: nil)
        #expect(tall.roomsThatFit == 2, Comment(rawValue:
            "an 800 px frame showed \(tall.roomsThatFit) rooms, so raising the"
            + " panel height buys nothing and the knob does not work"))
        #expect(tall.roomsNotShown == 0)
        #expect(!tall.rooms[1].world.root.isHidden)
    }

    /// **Each project's main agent gets seat 0 of its own room.**
    ///
    /// This is the defect `TwoProjectDirectorTests` measured on the shipped
    /// director: sharing one director, the second project's main agent silently
    /// took seat 1, a subagent's chair. A director per project is the fix and
    /// this is the assertion that it stays fixed.
    @Test(.enabled(if: SceneArt.isAvailable))
    func eachProjectsMainAgentSitsInSeatZeroOfItsOwnRoom() throws {
        let scene = try Self.scene()
        let manifest = scene.store.manifest
        for project in ["/a", "/b"] {
            scene.room(for: project, themeID: nil)
            var director = SceneDirector(manifest: manifest)
            let agent = AgentRef(project: project, session: "s", agent: .mainThread)
            scene.apply(
                director.apply(
                    [.agentAppeared(agent: agent, agentType: nil, lifecycle: .active)],
                    at: Date()),
                to: project)
            let slot = try #require(scene.slot(of: project))
            #expect(scene.rooms[slot].world.seatOfForTesting(agent) == 0, Comment(rawValue:
                "\(project)'s main agent took seat"
                + " \(String(describing: scene.rooms[slot].world.seatOfForTesting(agent)))"
                + " rather than seat 0 of its own room"))
        }
    }
}
