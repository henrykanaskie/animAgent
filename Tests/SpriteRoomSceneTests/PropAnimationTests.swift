import Foundation
import SpriteKit
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// `docs/ADR-002-themed-rooms.md` §14b — the rule that replaced the flat ban on
/// animated props:
///
/// > A prop may idle on its own loop and **may never take input from the delta
/// > stream.**
///
/// Half of this suite checks that the prop idles. The other half checks that it
/// cannot be told anything, which is the half that matters — a clock that swings
/// is scenery, and a clock that swings faster when an agent is busy is scenery
/// asserting something the data did not say. [I1]
@MainActor
struct PropAnimationTests {

    /// The first theme whose `board` — or any role — carries an `animation`.
    ///
    /// Found by asking the manifest rather than by naming a theme, both because
    /// no theme name may appear in a source file the scene ships and because
    /// this suite should keep working when the animated prop moves.
    static func animatedTheme(_ manifest: Manifest) -> (id: String, role: String)? {
        for id in manifest.themes.orderedIDs {
            guard let theme = manifest.themes.theme(id) else { continue }
            for role in theme.room.propRoles.keys.sorted()
            where theme.room.prop(role)?.animation?.isPlayable == true {
                return (id, role)
            }
        }
        return nil
    }

    static func scene(_ manifest: Manifest, themeID: String?) -> RoomScene {
        let scene = RoomScene(manifest: manifest, themeID: themeID)
        scene.setViewport(CGSize(width: 720, height: 400))
        return scene
    }

    static func propTextures(_ scene: RoomScene) -> [ObjectIdentifier?] {
        scene.propNodesForTesting.map { $0.texture.map(ObjectIdentifier.init) }
    }

    // MARK: The manifest half

    /// The manifest declares an animation and it is the shape §14b describes:
    /// `file` is frame 0, there is more than one frame, the rate is real, and
    /// `loop` is `true` — which §14b says is its only value.
    ///
    /// Runs on a fresh clone; the manifest is tracked.
    @Test func theManifestDeclaresOneIdleAnimationInTheShapeTheADRSpecifies() throws {
        let manifest = try SceneFixtures.manifest()
        let found = try #require(Self.animatedTheme(manifest),
                                 "no theme carries an animated prop, so this suite checks nothing")
        let role = try #require(manifest.themes.theme(found.id)?.room.prop(found.role))
        let animation = try #require(role.animation)

        #expect(animation.frames.first == role.file, "`file` is not frame 0")
        #expect(animation.frames.count > 1)
        #expect(animation.fps > 0)
        #expect(animation.loops, "ADR-002 §14b: `loop` is always true and has no other value")
        #expect(Set(animation.frames).count == animation.frames.count, "a frame is repeated")
        // Every path the role needs is one list, so nothing that walks the
        // manifest for art can see frame 0 and miss the rest.
        #expect(Set(role.declaredPaths) == Set(animation.frames))
    }

    // MARK: The arithmetic half — time in, frame out, nothing else

    /// The frame is `floor(elapsed × fps) mod count`, measured from the first
    /// advance. Checked without a scene, because the point is that the only
    /// input is the number.
    @Test func theFrameIsAFunctionOfTheClockAndNothingElse() throws {
        let node = SKSpriteNode()
        let frames = (0..<4).map { _ in SKTexture() }
        let player = try #require(
            PropAnimation(node: node, frames: frames, fps: 5, loops: true))

        // The origin is the first advance, so a host clock handing over system
        // uptime starts on frame 0 exactly as the offscreen harness does.
        player.advance(to: 1_000_000)
        #expect(node.texture === frames[0])
        #expect(player.frameIndex(at: 1_000_000) == 0)

        // Sampled at frame centres rather than on the boundaries: `(k + 0.5)/5`
        // lands unambiguously inside frame `k`, so this checks the mapping
        // rather than double rounding at the exact instant of a swap.
        let origin = 1_000_000.0
        for k in 0..<13 {
            let time = origin + (Double(k) + 0.5) / 5.0
            player.advance(to: time)
            #expect(player.frameIndex(at: time) == k % 4, "frame \(k)")
            #expect(node.texture === frames[k % 4])
        }

        // Going backwards is not a case that happens, and it clamps rather than
        // producing a negative index.
        #expect(player.frameIndex(at: 0) == 0)
    }

    /// One frame, or no rate, is not an animation. The still prop path is what
    /// every other role takes and it is not worth a second mechanism.
    @Test func nothingToPlayIsNotAnAnimation() {
        let node = SKSpriteNode()
        #expect(PropAnimation(node: node, frames: [SKTexture()], fps: 5, loops: true) == nil)
        #expect(PropAnimation(node: node, frames: [], fps: 5, loops: true) == nil)
        #expect(PropAnimation(
            node: node, frames: [SKTexture(), SKTexture()], fps: 0, loops: true) == nil)
    }

    /// A non-looping animation clamps on its last frame. Nothing ships one —
    /// §14b says `loop` is always `true` — but the flag is decoded, so it is
    /// honoured rather than ignored, and a decoded value nothing acts on is
    /// worse than either.
    @Test func aNonLoopingAnimationStopsOnItsLastFrame() throws {
        let node = SKSpriteNode()
        let frames = (0..<3).map { _ in SKTexture() }
        let player = try #require(
            PropAnimation(node: node, frames: frames, fps: 10, loops: false))
        player.advance(to: 0)
        player.advance(to: 100)
        #expect(node.texture === frames[2])
        #expect(player.frameIndex(at: 100) == 2)
    }

    // MARK: The room half — it actually plays

    @Test(.enabled(if: SceneArt.isAvailable))
    func theRoomPlaysTheAnimatedPropAndTheOthersStayStill() throws {
        let manifest = try SceneFixtures.manifest()
        let found = try #require(Self.animatedTheme(manifest))
        let scene = Self.scene(manifest, themeID: found.id)

        #expect(!scene.propAnimationsForTesting.isEmpty,
                "the room placed the animated role and did not animate it")
        // The scene draws `board` at the back row's even seats, so an animated
        // `board` is several nodes on one clock, in phase.
        let animatedNodes = Set(
            scene.propAnimationsForTesting.map { ObjectIdentifier($0.animatedNode) })
        #expect(animatedNodes.count == scene.propAnimationsForTesting.count,
                "two players are driving one node")

        var seen: Set<ObjectIdentifier> = []
        var frames = 0
        for step in 0..<120 {
            scene.advance(to: Double(step) / 60.0)
            let textures = scene.propAnimationsForTesting
                .compactMap { $0.animatedNode.texture.map(ObjectIdentifier.init) }
            #expect(Set(textures).count == 1, "the copies of one animated prop fell out of phase")
            seen.formUnion(textures)
            frames += 1
        }
        #expect(frames == 120)
        // Two seconds at 5 fps is ten frame boundaries over a four-frame loop,
        // so every frame must have been on screen.
        let declared = try #require(
            manifest.themes.theme(found.id)?.room.prop(found.role)?.animation)
        #expect(seen.count == declared.frames.count,
                "\(seen.count) of \(declared.frames.count) frames were ever drawn")

        // A theme with no animated role animates nothing. The default room is
        // that theme, and it is the room this app drew before §14b.
        let still = Self.scene(manifest, themeID: nil)
        #expect(still.propAnimationsForTesting.isEmpty)
        let before = Self.propTextures(still)
        for step in 0..<120 { still.advance(to: Double(step) / 60.0) }
        #expect(Self.propTextures(still) == before)
    }

    /// **§6 rule 1 for an animated prop.** Zero prop-node rebuilds across a
    /// fixture replay is an existing assertion, and the obvious way to implement
    /// an animation is the one that breaks it — rebuild the room, or the node,
    /// every frame. This replays a real capture into the *animated* theme, which
    /// the existing sweep does not cover because it builds the default room.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theAnimatedPropIsNeverRebuiltAcrossAFixtureReplay() async throws {
        let manifest = try SceneFixtures.manifest()
        let found = try #require(Self.animatedTheme(manifest))
        let scene = Self.scene(manifest, themeID: found.id)
        var director = SceneDirector(manifest: manifest, themeID: found.id)

        let before = Set(scene.propNodesForTesting.map(ObjectIdentifier.init))
        let players = Set(scene.propAnimationsForTesting.map { ObjectIdentifier($0.animatedNode) })
        #expect(!before.isEmpty)
        #expect(!players.isEmpty)

        var time = 0.0
        var textures: Set<ObjectIdentifier> = []
        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            scene.apply(director.apply(batch))
            time += 1.0 / 60.0
            scene.advance(to: time)
            textures.formUnion(
                scene.propAnimationsForTesting
                    .compactMap { $0.animatedNode.texture.map(ObjectIdentifier.init) })
        }

        #expect(Set(scene.propNodesForTesting.map(ObjectIdentifier.init)) == before,
                "the prop nodes were rebuilt")
        #expect(Set(scene.propAnimationsForTesting.map { ObjectIdentifier($0.animatedNode) })
                == players, "an animated prop was replaced")
        #expect(scene.roomBuildCount == 1, "the room was built more than once")
        #expect(textures.count > 1, "the prop did not actually animate during the replay")
    }

    // MARK: The rule — it cannot read a delta

    /// **The behavioural proof.** Two rooms in the same theme on the same clock:
    /// one is fed an entire real capture, the other is fed nothing at all. If
    /// the animation could see a delta — directly, or through some state the
    /// scene keeps — the two would diverge on the frame the first delta lands.
    /// They must be equal on every frame, and the equality has to be per frame
    /// rather than at the end, because a loop that fell out of step and back in
    /// would pass an end-state comparison.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theAnimationIsIdenticalWithAndWithoutADeltaStream() async throws {
        let manifest = try SceneFixtures.manifest()
        let found = try #require(Self.animatedTheme(manifest))

        let busy = Self.scene(manifest, themeID: found.id)
        let quiet = Self.scene(manifest, themeID: found.id)
        var director = SceneDirector(manifest: manifest, themeID: found.id)

        // **What was drawn, not what would be drawn.** Reading
        // `frameIndex(at:)` here would compare a pure function against itself
        // and pass however the drawing was actually driven — checked, by making
        // `RoomScene.advance(to:)` pass a delta-dependent clock and watching
        // this test stay green until it read `currentFrame` instead.
        func frames(_ scene: RoomScene) -> [Int?] {
            scene.propAnimationsForTesting.map(\.currentFrame)
        }

        // **At real time**, a fixed 1/60 step with each event delivered as its
        // own `_receivedAt` passes — the same loop the offscreen harness runs.
        // Stepping once per batch instead would advance the clock 20 frames
        // over a 34-second capture, and the animation would barely move.
        let entries = try HookLog.load(contentsOf: SceneFixtures.url("three-subagents"))
        let origin = try #require(entries.first?.receivedAt)
        let end = try #require(entries.last?.receivedAt)
        let model = WorldModel()
        var index = entries.startIndex

        var time = 0.0
        var deltasDelivered = 0
        var comparisons = 0
        var busiestPopulation = 0
        var distinctFrames: Set<[Int?]> = []

        while time <= end.timeIntervalSince(origin) + 5 {
            var pending: [WorldDelta] = []
            let cutoff = origin.addingTimeInterval(time)
            while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                if let event = entries[index].event {
                    pending += await model.ingest(event, at: entries[index].receivedAt)
                }
                index += 1
            }
            if !pending.isEmpty {
                busy.apply(director.apply(pending))
                deltasDelivered += pending.count
            }
            busy.advance(to: time)
            quiet.advance(to: time)
            busiestPopulation = max(busiestPopulation, busy.charactersOnScreen.count)

            let a = frames(busy)
            let b = frames(quiet)
            #expect(a == b, "the animation diverged at t=\(time) after \(deltasDelivered) deltas")
            distinctFrames.insert(a)
            comparisons += 1
            time += 1.0 / 60.0
        }

        #expect(deltasDelivered > 40, "the busy room was barely driven")
        #expect(comparisons > 2000, "the whole fixture was not stepped at 1/60")
        #expect(distinctFrames.count > 1, "the animation never moved, so this compared two stills")
        // And the busy room really was busy — otherwise the two scenes are
        // trivially equal and this proves nothing.
        #expect(busiestPopulation > 2, "only \(busiestPopulation) characters were ever on screen")
    }

    /// **The structural proof, on the other side.** `apply(_ intent:)` is where
    /// every consequence of a delta reaches this scene. One of every
    /// `SpriteIntent` case goes through it, with the clock held still, and no
    /// prop texture may move.
    ///
    /// The clock is deliberately not advanced: this is asking whether an
    /// *intent* can change a prop, not whether time can.
    @Test(.enabled(if: SceneArt.isAvailable))
    func noSpriteIntentCanMoveAPropTexture() throws {
        let manifest = try SceneFixtures.manifest()
        let found = try #require(Self.animatedTheme(manifest))
        let scene = Self.scene(manifest, themeID: found.id)
        scene.advance(to: 0)

        let before = Self.propTextures(scene)
        #expect(!before.isEmpty)

        let agent = AgentRef(project: "/p", session: "s", agent: .subagent("a0000000000000001"))
        let parent = AgentRef(project: "/p", session: "s", agent: .mainThread)
        let intents: [SpriteIntent] = [
            .spawnCharacter(agent: parent, variant: manifest.characters.orderedVariantIDs[0],
                            nameplate: NameplateText(lead: "main"), seat: 0,
                            station: ThemeSelector.mainStationID, costume: nil),
            .spawnCharacter(agent: agent, variant: manifest.characters.orderedVariantIDs[1],
                            nameplate: NameplateText(lead: "001", role: "Explore"), seat: 1,
                            station: ThemeSelector.defaultStationID, costume: nil),
            .setBody(agent: agent, state: .working, facing: .right),
            .setBadge(agent: agent, selection: BadgeSelection.select(openToolNames: ["Bash"])),
            .setBadge(agent: agent, selection: BadgeSelection.select(
                openToolNames: ["Bash"], attention: .permissionPrompt)),
            .setBadge(agent: agent, selection: BadgeSelection.select(
                openToolNames: [String](), isDormant: true)),
            .deliverReport(agent: agent, anchorSeat: 0),
            .setScale(3),
            .setScale(1),
            .exitCharacter(agent: agent, style: .report(anchorSeat: 0)),
            .exitCharacter(agent: parent, style: .walkOff),
        ]
        // Every case of the enum is represented; if one is added this line is
        // where it is noticed.
        #expect(intents.count == 11)

        for intent in intents {
            scene.apply(intent)
            // Reduced to a `Bool` first: passing the two arrays renders 42
            // `ObjectIdentifier`s into one unreadable failure line, and the
            // intent's own name is the part worth reading.
            let unchanged = Self.propTextures(scene) == before
            #expect(unchanged, Comment(rawValue: "a prop texture moved on \(intent)"))
        }
        scene.apply(intents)
        let unchanged = Self.propTextures(scene) == before
        #expect(unchanged, "a prop texture moved when the whole batch was applied")
    }

    /// **The source proof.** `PropAnimation` may not so much as name the delta
    /// vocabulary, and it may not import the module that defines it.
    ///
    /// Mechanical because "does not import `SpriteRoomCore`" is exactly the kind
    /// of thing a later edit adds without noticing, and because the rule it
    /// enforces — §14b — is a rule about what the code *can* do rather than what
    /// it does today.
    ///
    /// **Comments are stripped first**, and that is not a loophole: the reason a
    /// file may not name a type is normally written in a doc comment that names
    /// it, and `PropAnimation`'s says in as many words that `WorldDelta` and
    /// `AgentRef` are not in scope there. What is policed is what the compiler
    /// sees.
    @Test func thePropAnimationSourceCannotReachADelta() throws {
        let url = SceneFixtures.repositoryRoot
            .appending(path: "Sources").appending(path: "SpriteRoomScene")
            .appending(path: "PropAnimation.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let code = SourceLiterals.code(in: text)
        #expect(!code.isEmpty)
        #expect(code.count < text.count, "the comment stripper did nothing")

        // The import is the whole boundary: none of `SpriteRoomCore`'s types is
        // in scope here, so none of them can be reached however hard anybody
        // tries.
        #expect(!code.contains("import SpriteRoomCore"),
                "PropAnimation imports the module that defines the delta stream")
        #expect(code.contains("import SpriteKit"))

        // And nothing from this module's own delta-facing vocabulary either,
        // which the import boundary does not cover.
        for forbidden in ["SpriteIntent", "BadgeSelection", "SceneDirector", "Character",
                          "WorldDelta", "AgentRef", "AgentID", "OpenCall", "AttentionKind",
                          "ToolBadge", "WorldModel", "TextureStore", "RoomScene"] {
            #expect(!code.contains(forbidden),
                    "PropAnimation names \(forbidden); §14b forbids it any delta input")
        }

        // The only mutating entry point takes the clock and nothing else, and
        // there is nothing else to take: `frameIndex(at:)` is the same
        // arithmetic without the side effect.
        #expect(code.contains("func advance(to time: TimeInterval)"))
        #expect(code.contains("func frameIndex(at time: TimeInterval)"))
        #expect(code.components(separatedBy: "func ").count - 1 == 2, Comment(rawValue:
            "PropAnimation has \(code.components(separatedBy: "func ").count - 1) functions;"
            + " a new one is a new way in, so check it takes no delta input"))
        // `init` is the only other way to put anything in, and it is called from
        // exactly one place — see `noSpriteIntentCanMoveAPropTexture` for the
        // other half.
        #expect(code.components(separatedBy: "init").count - 1 == 1)
    }
}
