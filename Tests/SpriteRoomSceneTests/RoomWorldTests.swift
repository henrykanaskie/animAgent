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
