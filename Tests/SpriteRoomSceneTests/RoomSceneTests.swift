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

    @Test(.enabled(if: SceneArt.isAvailable))
    func aLoopingStateCyclesAndNeverRunsOffTheEnd() throws {
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
        #expect(textures.count == 6, "idle should cycle its six frames")
    }

    // MARK: Choreography

    @Test(.enabled(if: SceneArt.isAvailable))
    func aSpawningCharacterWalksInFromTheEdgeAndSettles() throws {
        let store = try Self.store()
        let character = Character(variant: "06", nameplate: NameplateText(lead: "main"), store: store)
        character.advance(to: 0)
        character.setResting(.idle, facing: .right)
        character.enter(
            from: ScenePoint(x: -32, y: 32),
            approach: ScenePoint(x: 400, y: 32),
            seat: ScenePoint(x: 400, y: 64))
        character.advance(to: 0)
        #expect(character.state == .spawn)
        #expect(character.position.x == -32)

        character.advance(to: 2)
        #expect(character.position.x > -32 && character.position.x < 400)

        character.advance(to: 10)
        #expect(character.position.x == 400)
        #expect(character.position.y == 64, "the walk-in ends at the desk, not the aisle")
        #expect(character.state == .idle, "the walk-in must hand back to the data's state")
    }

    /// The one dramatisation the event model licenses: walk, deliver, depart.
    /// All three states have to actually play, in that order.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theReportWalkPlaysWalkThenDeliverThenDepart() throws {
        let store = try Self.store()
        let character = Character(variant: "07", nameplate: NameplateText(lead: "6E7", role: "Explore"), store: store)
        character.advance(to: 0)
        character.position = CGPoint(x: 496, y: 64)
        var finished = false
        character.reportAndDepart(
            via: ScenePoint(x: 496, y: 32),
            to: ScenePoint(x: 376, y: 32),
            facing: .right,
            thenExitAt: ScenePoint(x: -32, y: 32)) { finished = true }

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
            via: ScenePoint(x: 400, y: 32),
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
        character.enter(
            from: ScenePoint(x: -32, y: 32),
            approach: ScenePoint(x: 200, y: 32),
            seat: ScenePoint(x: 200, y: 64))
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

    @Test func theDeliveryPointIsInTheAisleBesideTheAnchorAndFacesIt() {
        let layout = RoomLayout()
        #expect(layout.deliveryPosition.x < layout.seatPosition(0).x)
        #expect(layout.deliveryFacing == .right)
        // In the aisle, not on the desk row: otherwise the reporter walks
        // through whoever is sitting between it and the anchor.
        #expect(layout.deliveryPosition.y == layout.aisleY)
        #expect(layout.aisleY < layout.baselineY)
        for seat in 0..<layout.seatCapacity {
            #expect(layout.seatPosition(seat).y != layout.deliveryPosition.y)
        }
    }

    @Test func everySeatedCharacterFacesADirectionThePackDrew() {
        let layout = RoomLayout()
        #expect(layout.seatedFacing.isSideView)
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
    @Test func noCharacterOnScreenChangesBadgeMoreOftenThanItsCallSet() async throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 960, height: 540))
        var director = SceneDirector(manifest: manifest)

        var callChanges: [AgentRef: Int] = [:]
        var badgeChanges: [AgentRef: Int] = [:]
        var lastBadge: [AgentRef: BadgeSelection] = [:]
        var time = 0.0

        for batch in try await SceneFixtures.batchedDeltas("three-subagents") {
            for delta in batch {
                switch delta {
                case let .callOpened(agent, _),
                     let .callClosed(agent, _, _, _),
                     let .callAbandoned(agent, _, _, _):
                    callChanges[agent, default: 0] += 1
                default: break
                }
            }
            scene.apply(director.apply(batch))
            time += 1.0 / 60.0
            scene.advance(to: time)

            for (agent, _) in callChanges {
                guard let character = scene.character(for: agent) else { continue }
                if lastBadge[agent] != character.badgeSelection {
                    lastBadge[agent] = character.badgeSelection
                    badgeChanges[agent, default: 0] += 1
                }
            }
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
    @Test func aDeskOutranksTheSeatedBodyButNotTheNameplate() {
        let layout = RoomLayout()
        let seated = Character.Layer.rowDepth(layout.baselineY)
        let desk = Character.Layer.rowDepth(layout.deskPosition(0).y) + 0.5
        let aisle = Character.Layer.rowDepth(layout.aisleY)
        #expect(desk > seated, "the desk's near edge must cross the body it belongs to")
        #expect(aisle > desk, "a character walking past is always in front of the furniture")
        #expect(seated + Character.Layer.nameplate > aisle, "no body may hide a nameplate")
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

        for id in manifest.characters.orderedVariantIDs {
            let variant = manifest.characters.variant(id)!
            let badgeTop = layout.baselineY
                + Double(manifest.characters.canvas.height - variant.headTopPx + 1)
                + Double(manifest.badges.canvas.height)
            #expect(badgeTop <= band.top, "variant \(id) badge pokes out of the frame")
        }
        // The **tallest** plate, not a sample one: the plate grew a second row
        // at the wide default, and a band derived from `MAIN` alone would have
        // cropped every subagent's type line.
        let plateHeight = Double(SceneBitmaps.maximumNameplateHeight)
        // The lowest plate belongs to a character standing in the aisle.
        #expect(layout.aisleY - 2 - plateHeight >= band.bottom)
        #expect(band.top - band.bottom < layout.height,
                "framing the nominal room box is what left the middle-third composition")
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
    /// What changed is the preference on top of it. The maintainer looked at
    /// the shipped panel and asked for the room to be bigger from the start.
    /// So the camera no longer pulls in on a small population, and one agent is
    /// drawn at the floor with the room around it. The ladder is untouched and
    /// still integer [I6]; `RoomCameraTests` proves the closer rungs still work
    /// when a camera is told to prefer them.
    @Test func oneAgentIsDrawnWideInsideThePanel() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest)
        let ref = AgentRef(project: "/p", session: "s", agent: .mainThread)
        scene.apply(director.apply([
            .agentAppeared(agent: ref, agentType: nil, lifecycle: .active)]))
        #expect(scene.currentScale == 1)
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

    /// Once there is slack, the frame is biased upwards — the band's bottom is
    /// reserved for a character in the aisle, and most of the time nobody is
    /// there.
    @Test func spareVerticalRoomGoesToTheWallRatherThanTheForeground() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let band = scene.contentBand
        let tight = scene.cameraY(band: band, sceneHeight: band.top - band.bottom)
        let loose = scene.cameraY(band: band, sceneHeight: 400)
        #expect(loose > tight)
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

    /// Foreground decoration must sit entirely below the content band. Inside
    /// it, it would be on screen at `3x` — the zoom where a character is
    /// biggest and the frame is tightest — which is the one place I7 says a
    /// background detail must not be.
    @Test(.enabled(if: SceneArt.isAvailable))
    func foregroundDecorationIsEntirelyOutsideTheContentBand() throws {
        let manifest = try SceneFixtures.manifest()
        let scene = RoomScene(manifest: manifest)
        let band = scene.contentBand
        let ahead = scene.propNodesForTesting.filter { $0.position.y < band.bottom }
        #expect(!ahead.isEmpty, "no foreground decoration was placed")
        for node in ahead {
            // The node's top edge, from its own anchor.
            let top = node.position.y + (1 - node.anchorPoint.y) * node.size.height
            let box = try #require(manifest.room.prop("plant")).contentBox
            let inkTop = node.position.y + Double(box.height)
            #expect(inkTop < band.bottom, "foreground prop reaches into the frame at 3x")
            #expect(top >= inkTop)
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
}

// MARK: - Test hooks

extension Character {
    /// The texture currently on the body. Read-only, for tests that need to
    /// prove an animation did or did not advance.
    var currentTextureForTesting: SKTexture? {
        (children.first as? SKSpriteNode)?.texture
    }
}
