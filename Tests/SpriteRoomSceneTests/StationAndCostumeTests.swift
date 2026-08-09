import Foundation
import SpriteKit
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// **The test the last three months of this feature lacked.**
///
/// `docs/ADR-002-themed-rooms.md` §4 and §8 items 4 and 6 were half implemented
/// for the whole of M6: `ThemeSelector.station(agentID:agentType:in:)` resolved a
/// station per agent, `SceneDirector` stored it in the presentation record, and
/// **`Manifest.Station` had no caller outside `ThemeSelector` and its tests.**
/// The id never left the director. The room drew `props.roles.desk` and
/// `props.roles.chair` at every seat, once, at build time.
///
/// It was found by rendering, not by reading: a manifest carrying six visually
/// wild stations in all six themes — a chalkboard, a drum kit, a softbox, a flip
/// chart, a two-screen post — rendered **byte-identical** to a manifest with no
/// stations at all. Six pairs, zero differing bytes, over a fixture with three
/// agents of two `agent_type`s at 720×400.
///
/// Every assertion the suite had at the time passed. That is the interesting
/// part, and it is what these tests are shaped against:
///
/// - `theDirectorStoresAStationForEveryCharacter` passed — the id was stored.
/// - `typedSubagentsOfOneKindShareAStation` passed — the hash worked.
/// - `theStationIsNeverRewrittenAfterSpawn` passed — vacuously, since nothing
///   could rewrite what nothing read.
/// - `changingTheThemeRedressesTheRoomAndMovesNoCharacter` passed — themes did
///   redress the room; stations were not what redressed it.
///
/// So the missing assertion is not about ids, or hashes, or nodes, or counts.
/// **It is about pixels at a seat**, and it is stated the way the maintainer
/// states the complaint: *can you tell one agent from another by looking at the
/// room?*
///
/// > **Two agents of different `agent_type` in one room must produce different
/// > pixels at their seats.**
///
/// `RoomScene.furnitureForTesting(seat:)` reports what is actually on screen at
/// a seat — path, placement, anchor, depth — and `SeatRaster` composites it. The
/// comparison is between two seats drawn by the same compositor, so no
/// convention error in the compositor can turn different art into an equal
/// result: an offset bug moves both seats identically. It can only ever fail to
/// find a difference that is there, never invent one, which is the right
/// direction for a hand-rolled rasteriser to be wrong in.
@MainActor
struct StationSceneTests {

    static func cast(_ count: Int) -> [AgentRef] {
        (0..<count).map { index in
            AgentRef(
                project: "/p", session: "s",
                agent: index == 0 ? .mainThread : .subagent(String(format: "a%016x", index)))
        }
    }

    /// **The headline.** Two subagents whose `agent_type` differs, in one room,
    /// in a theme that binds stations: the pixels at their two seats differ.
    ///
    /// And the control, in the same test and against the *shipped* manifest,
    /// because a difference means nothing without knowing what the same looks
    /// like: with no stations declared, the two seats are **pixel-identical**,
    /// which is the room this change was asked to fix and the state every
    /// existing assertion was happy with.
    @Test(.enabled(if: SceneArt.isAvailable))
    func twoAgentsOfDifferentTypeDrawDifferentPixelsAtTheirSeats() throws {
        let shipped = try SceneFixtures.manifest()
        let themeID = try #require(shipped.themes.orderedIDs.first)

        func seats(_ manifest: Manifest) throws -> (a: Bitmap, b: Bitmap, stations: [String?]) {
            let scene = RoomScene(manifest: manifest, themeID: themeID)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest, themeID: themeID)
            let cast = Self.cast(3)
            scene.apply(director.apply([
                .agentAppeared(agent: cast[0], agentType: nil, lifecycle: .active),
                .agentAppeared(agent: cast[1], agentType: "Explore", lifecycle: .spawning),
                .agentAppeared(agent: cast[2], agentType: "security-reviewer",
                               lifecycle: .spawning),
            ]))
            let seatA = try #require(director.seats[cast[1]])
            let seatB = try #require(director.seats[cast[2]])
            return (SeatRaster.render(scene, seat: seatA, manifest: manifest),
                    SeatRaster.render(scene, seat: seatB, manifest: manifest),
                    [director.station(cast[1]), director.station(cast[2])])
        }

        // The control. This is the room as shipped, and it is the bug.
        let plain = try seats(shipped)
        #expect(plain.a.opaqueCount > 0, "the control drew nothing at all at a seat")
        #expect(SeatRaster.differences(plain.a, plain.b) == 0, Comment(rawValue:
            "two agents of different agent_type already differ at their seats in the"
            + " shipped manifest, so this test is no longer measuring what it was written"
            + " to measure"))
        #expect(plain.stations[0] == ThemeSelector.defaultStationID,
                "the shipped themes declare no numbered stations, so both fall to `default`")
        #expect(plain.stations[1] == ThemeSelector.defaultStationID)

        // The claim.
        let stationed = try seats(try ManifestFixtures.stationed(shipped))
        #expect(stationed.stations[0] != stationed.stations[1], Comment(rawValue:
            "`Explore` and `security-reviewer` hashed to the same station"
            + " (\(stationed.stations[0] ?? "-")), so this compares two copies of one desk"))
        let differing = SeatRaster.differences(stationed.a, stationed.b)
        #expect(differing > 0, Comment(rawValue:
            "two agents of different agent_type — \(stationed.stations[0] ?? "-") against"
            + " \(stationed.stations[1] ?? "-") — drew the same \(stationed.a.width)×"
            + "\(stationed.a.height) patch of room at their seats. The station resolved and"
            + " reached nothing. [ADR-002 §4]"))
    }

    /// The other half of the same claim, and it is a different one: the pixels
    /// have to differ **because of the station**, not because two seats happen
    /// to sit under different scenery. Same theme, same seats, same everything —
    /// only the manifest's stations change.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aStationChangesTheSeatItIsDrawnAt() throws {
        let shipped = try SceneFixtures.manifest()
        let themeID = try #require(shipped.themes.orderedIDs.first)
        let agent = Self.cast(2)[1]

        func seat(_ manifest: Manifest) throws -> Bitmap {
            let scene = RoomScene(manifest: manifest, themeID: themeID)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest, themeID: themeID)
            scene.apply(director.apply([
                .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning),
            ]))
            return SeatRaster.render(
                scene, seat: try #require(director.seats[agent]), manifest: manifest)
        }

        let before = try seat(shipped)
        let after = try seat(try ManifestFixtures.stationed(shipped))
        #expect(SeatRaster.differences(before, after) > 0,
                "declaring a station changed nothing at the seat that agent sits at")
    }

    /// **A seat whose station names nothing keeps the theme's `props.roles`**,
    /// and that is what makes this change degrade to yesterday's picture rather
    /// than to an empty room. Three shapes of "names nothing", all of which
    /// happen: a theme with no stations at all (every theme shipped), a station
    /// id the theme does not bind, and the main thread in a theme that binds
    /// only numbered stations.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aSeatWhoseStationNamesNothingKeepsTheThemesOwnFurniture() throws {
        let shipped = try SceneFixtures.manifest()
        let themeID = try #require(shipped.themes.orderedIDs.first)
        let theme = try #require(shipped.themes.theme(themeID))
        let desk = try #require(theme.room.prop(RoomScene.surfaceRole)).file
        let chair = try #require(theme.room.prop(RoomScene.seatRole)).file

        // Numbered stations only: `main` and `default` are unbound, so the main
        // thread and an untyped subagent both fall back to the theme's roles.
        let partial = try ManifestFixtures.stationed(shipped, bindMainAndDefault: false)
        let scene = RoomScene(manifest: partial, themeID: themeID)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: partial, themeID: themeID)
        let cast = Self.cast(3)
        scene.apply(director.apply([
            .agentAppeared(agent: cast[0], agentType: nil, lifecycle: .active),
            .agentAppeared(agent: cast[1], agentType: "", lifecycle: .spawning),
            .agentAppeared(agent: cast[2], agentType: "Explore", lifecycle: .spawning),
        ]))

        for agent in [cast[0], cast[1]] {
            let seat = try #require(director.seats[agent])
            let paths = Set(scene.furnitureForTesting(seat: seat).map(\.path))
            #expect(paths.contains(desk), "seat \(seat) lost the theme's desk")
            #expect(paths.contains(chair), "seat \(seat) lost the theme's chair")
        }
        // And the typed one did take a station, or the fallback proved nothing.
        let stationed = try #require(director.seats[cast[2]])
        let paths = Set(scene.furnitureForTesting(seat: stationed).map(\.path))
        #expect(!paths.contains(desk), "the typed subagent kept the theme-wide desk")
    }

    /// A station is put up when its agent arrives and taken down when its node
    /// is retired, and the empty desk comes back. Anything else and a departed
    /// `security-reviewer` leaves its bench behind for whoever sits there next.
    ///
    /// **The room's own prop nodes are not touched by any of it**, which is what
    /// keeps §6 rule 1 — "zero prop-node rebuilds across an entire fixture
    /// replay" — true through every arrival and departure: the theme-wide pair is
    /// hidden, never destroyed.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aStationGoesUpAtSpawnAndComesDownWhenItsAgentIsRetired() throws {
        let manifest = try ManifestFixtures.stationed(try SceneFixtures.manifest())
        let themeID = try #require(manifest.themes.orderedIDs.first)
        let scene = RoomScene(manifest: manifest, themeID: themeID)
        scene.setViewport(CGSize(width: 720, height: 400))
        var director = SceneDirector(manifest: manifest, themeID: themeID)
        let agent = Self.cast(2)[1]
        let props = Set(scene.propNodesForTesting.map(ObjectIdentifier.init))

        scene.apply(director.apply([
            .agentAppeared(agent: agent, agentType: "Explore", lifecycle: .spawning),
        ]))
        let seat = try #require(director.seats[agent])
        let seated = SeatRaster.render(scene, seat: seat, manifest: manifest)

        scene.apply(director.apply([.agentDeparted(agent: agent)]))
        // The exit is a walk; the station stands until the walker is retired.
        var time = 0.0
        while time < 20 {
            time += 1.0 / 60.0
            scene.advance(to: time)
        }
        #expect(scene.charactersOnScreen.isEmpty, "the leaver never finished walking out")

        let empty = SeatRaster.render(scene, seat: seat, manifest: manifest)
        #expect(SeatRaster.differences(seated, empty) > 0,
                "the station was still standing after its agent was retired")
        #expect(Set(scene.propNodesForTesting.map(ObjectIdentifier.init)) == props,
                "a room prop node was rebuilt by an arrival or a departure")
        #expect(scene.roomBuildCount == 1)

        // And the empty desk is back: what a seat with nobody at it looks like
        // is the theme's own furniture, exactly as before anyone arrived.
        let theme = try #require(manifest.themes.theme(themeID))
        let themeDesk = try #require(theme.room.prop(RoomScene.surfaceRole)).file
        let paths = Set(scene.furnitureForTesting(seat: seat).map(\.path))
        #expect(paths.contains(themeDesk), "the seat did not get its empty desk back")
    }

    /// Every fixture, end to end, against a manifest that *does* bind stations:
    /// no prop node is rebuilt, the room is built once, and nothing is left
    /// standing at a seat after the cast has gone.
    ///
    /// The existing sweep runs against the shipped manifest, where no theme
    /// declares a station — so it exercises the branch that draws nothing. This
    /// is the same sweep down the branch that draws something.
    @Test(.enabled(if: SceneArt.isAvailable))
    func noStationSurvivesAnyFixtureReplay() async throws {
        let manifest = try ManifestFixtures.stationed(try SceneFixtures.manifest())
        let themeID = try #require(manifest.themes.orderedIDs.first)
        let names = try FileManager.default
            .contentsOfDirectory(atPath: SceneFixtures.repositoryRoot.appending(path: "fixtures").path)
            .filter { $0.hasSuffix(".jsonl") }
            .map { String($0.dropLast(6)) }
            .sorted()
        #expect(names.count > 10, "the fixture sweep found almost nothing")

        var everDrewAStation = false
        for name in names {
            let scene = RoomScene(manifest: manifest, themeID: themeID)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest, themeID: themeID)
            let props = Set(scene.propNodesForTesting.map(ObjectIdentifier.init))
            let empty = (0..<scene.layout.seatCapacity).map {
                scene.furnitureForTesting(seat: $0)
            }

            var time = 0.0
            for batch in try await SceneFixtures.batchedDeltas(name) {
                scene.apply(director.apply(batch))
                time += 1.0 / 60.0
                scene.advance(to: time)
                if (0..<scene.layout.seatCapacity).contains(where: {
                    scene.furnitureForTesting(seat: $0) != empty[$0]
                }) { everDrewAStation = true }
            }
            // Let every exit walk finish.
            for _ in 0..<1800 {
                time += 1.0 / 60.0
                scene.advance(to: time)
            }

            #expect(Set(scene.propNodesForTesting.map(ObjectIdentifier.init)) == props,
                    "\(name): the prop nodes were rebuilt")
            #expect(scene.roomBuildCount == 1, "\(name): the room was built more than once")
            if scene.charactersOnScreen.isEmpty {
                for seat in 0..<scene.layout.seatCapacity {
                    #expect(scene.furnitureForTesting(seat: seat) == empty[seat], Comment(
                        rawValue: "\(name): seat \(seat) is not back to its empty desk"))
                }
            }
        }
        #expect(everDrewAStation,
                "no fixture ever put a station on screen, so this swept nothing")
    }
}

// MARK: - The wardrobe

/// `characters.costumes`: what an agent wears, and the two tiers that keep it
/// honest.
///
/// The maintainer's ask is specific — *the software developers should have a
/// computer, then the tester or verifier should have a lab coat* — and it is
/// asking for a costume that **says something**. That is allowed exactly as far
/// as `agent_type` licenses it, and no further:
///
/// - `roles` is keyed on the exact `agent_type` the user typed. A
///   `test-engineer` in a lab coat is the room repeating a name the user chose.
/// - the hash draws only from `assignable`, whose members must assert nothing,
///   because arbitrary user text licenses no claim about the work. It is
///   `question_mark`'s answer, worn. [I1]
@MainActor
struct CostumeTests {

    static func cast(_ count: Int) -> [AgentRef] { StationSceneTests.cast(count) }

    @Test func theMainThreadAndTheUntypedWearTheCastsOwnClothes() throws {
        let wardrobe = try ManifestFixtures.wardrobe(try SceneFixtures.manifest())
        for type: String? in [nil, "", "Explore", "test-engineer"] {
            #expect(ThemeSelector.costume(agentID: nil, agentType: type, in: wardrobe) == nil,
                    "the main thread was dressed; absence of agent_id is the identity rule")
        }
        for type: String? in [nil, ""] {
            #expect(ThemeSelector.costume(agentID: "a1", agentType: type, in: wardrobe) == nil,
                    "an agent whose type we were not told was dressed as something")
        }
    }

    /// Tier 1: a recognised name is translated, and the translation may assert.
    @Test func arecognisedAgentTypeWearsWhatTheManifestSaysItWears() throws {
        let wardrobe = try ManifestFixtures.wardrobe(try SceneFixtures.manifest())
        let named = try #require(wardrobe.roles.first)
        #expect(ThemeSelector.costume(agentID: "a1", agentType: named.key, in: wardrobe)
                == named.value)
        // And it is reached by *exact* text, with no folding — the same rule
        // `theme(for:stored:manifest:)` follows for `cwd`. A folded match would
        // be this app inventing a normalisation of the user's own string.
        #expect(ThemeSelector.costume(
            agentID: "a1", agentType: named.key.uppercased(), in: wardrobe) != named.value
            || named.key == named.key.uppercased())
    }

    /// **Tier 2 is where I1 lives.** An `agent_type` nobody anticipated is
    /// arbitrary text; the costume it draws may say only *this is a different
    /// agent from that one*. So the hash's range is the neutral pool, and no
    /// asserting costume is reachable from it at any input.
    @Test func nothingAnUnrecognisedTypeCanWearMakesAClaim() throws {
        let manifest = try SceneFixtures.manifest()
        let wardrobe = try ManifestFixtures.wardrobe(manifest)
        let poolIsNeutral = wardrobe.assignableIDs
            .allSatisfy { wardrobe.costume($0)?.asserts == false }
        #expect(poolIsNeutral, "an asserting costume is in the pool the hash draws from")
        let someCostumeAsserts = wardrobe.sets.values.contains { $0.asserts }
        #expect(someCostumeAsserts,
                "no costume in the fixture asserts, so the separation is vacuous")

        var reached: Set<String> = []
        for index in 0..<4000 {
            let type = "an-agent-name-\(index)"
            guard wardrobe.roles[type] == nil else { continue }
            guard let id = ThemeSelector.costume(
                agentID: "a1", agentType: type, in: wardrobe) else {
                Issue.record("a non-empty pool dressed nobody")
                return
            }
            reached.insert(id)
            #expect(wardrobe.costume(id)?.asserts == false, Comment(rawValue:
                "the hash put the unrecognised type \(type) in \(id), which asserts"))
        }
        #expect(reached == Set(wardrobe.assignableIDs),
                "the pool is not fully reachable: \(reached.sorted())")
    }

    /// §4's rule, worn instead of sat at: two agents of one type dress alike,
    /// because they are the same kind of worker and dressing them differently
    /// would spend the channel's meaning on variety.
    @Test func agentsOfOneTypeWearOneCostume() throws {
        let wardrobe = try ManifestFixtures.wardrobe(try SceneFixtures.manifest())
        let worn = Set(["a1b2c3", "d4e5f6", "0000", "zzzz"].map {
            ThemeSelector.costume(agentID: $0, agentType: "general-purpose", in: wardrobe)
        })
        #expect(worn.count == 1)
    }

    /// **The whole thing degrades to today.** A manifest that declares no
    /// wardrobe dresses nobody, builds no layer node, and draws the character
    /// this app has always drawn.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aManifestWithNoWardrobeDressesNobody() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.characters.costumes.isEmpty)
        var director = SceneDirector(manifest: manifest)
        let cast = Self.cast(3)
        let intents = director.apply([
            .agentAppeared(agent: cast[0], agentType: nil, lifecycle: .active),
            .agentAppeared(agent: cast[1], agentType: "Explore", lifecycle: .spawning),
            .agentAppeared(agent: cast[2], agentType: "test-engineer", lifecycle: .spawning),
        ])
        for intent in intents {
            guard case let .spawnCharacter(_, _, _, _, _, costume) = intent else { continue }
            #expect(costume == nil)
        }
        let store = TextureStore(manifest: manifest)
        let character = Character(
            variant: manifest.characters.orderedVariantIDs[0],
            nameplate: NameplateText(lead: "main"), store: store)
        #expect(character.costumeNodesForTesting.isEmpty)
        #expect(character.agentCostume == nil)
    }

    /// The costume reaches the character, and it reaches every state the body
    /// plays — a coat that vanishes when its wearer stands up is not clothing.
    ///
    /// The layers here are another cast variant's own frames used as an overlay.
    /// That is not what a costume will look like; it is the right *geometry*,
    /// which is what this test is about, and it is real art on disk rather than
    /// a stub that could hide a loading failure. The generator's outfit sheets
    /// are the premade sheets' exact dimensions, so the shape is the same.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aCostumeIsDrawnOnEveryStateTheBodyPlaysAndStaysInPhaseWithIt() throws {
        let manifest = try ManifestFixtures.dressed(try SceneFixtures.manifest())
        let store = TextureStore(manifest: manifest)
        let costumeID = try #require(manifest.characters.costumes.orderedIDs.first)
        let character = Character(
            variant: manifest.characters.orderedVariantIDs[0],
            nameplate: NameplateText(lead: "001", role: "Explore"),
            store: store, costume: costumeID)
        let layers = character.costumeNodesForTesting
        #expect(layers.count == manifest.characters.costumes.costume(costumeID)?.layers.count)
        #expect(!layers.isEmpty, "the costume built no layer node")

        for state in BodyState.allCases {
            character.apply(state: state, facing: .right, startingAt: 0)
            guard character.state == state else { continue }
            for (index, node) in layers.enumerated() {
                #expect(!node.isHidden, "layer \(index) is not drawn for \(state.rawValue)")
                #expect(node.texture != nil)
                // Geometry is the body's, because the art is the body's.
                #expect(node.size == CGSize(
                    width: manifest.characters.canvas.width,
                    height: manifest.characters.canvas.height))
                #expect(node.anchorPoint == CGPoint(
                    x: manifest.characters.anchor.x, y: manifest.characters.anchor.y))
                // Over the body, and far under the badge and the plate, so a
                // costume can never cover an identity.
                #expect(node.zPosition > 0)
                #expect(node.zPosition < Character.Layer.badge)
            }
        }

        // In phase: the layer's texture changes on exactly the frames the body's
        // does, over a full loop of the seated pose.
        character.apply(state: .working, facing: .right, startingAt: 0)
        var seen: Set<ObjectIdentifier> = []
        var frames = 0
        for step in 0..<24 {
            character.advance(to: Double(step) / 8.0)
            if let texture = layers[0].texture {
                seen.insert(ObjectIdentifier(texture))
                frames += 1
            }
        }
        #expect(frames == 24)
        #expect(seen.count > 1, "the costume layer never changed frame — it is a still image")
    }

    /// A costume whose layer does not match the body's frame count is **not
    /// drawn** for that state. The honest answer is an undressed layer, not a
    /// coat playing at a different speed from the person in it.
    @Test(.enabled(if: SceneArt.isAvailable))
    func aLayerThatDoesNotMatchTheBodysFrameCountIsNotDrawn() throws {
        let manifest = try ManifestFixtures.dressed(
            try SceneFixtures.manifest(), truncateWorkingTo: 1)
        let store = TextureStore(manifest: manifest)
        let costumeID = try #require(manifest.characters.costumes.orderedIDs.first)
        let character = Character(
            variant: manifest.characters.orderedVariantIDs[0],
            nameplate: NameplateText(lead: "001", role: "Explore"),
            store: store, costume: costumeID)

        character.apply(state: .working, facing: .right, startingAt: 0)
        let hiddenWhileWorking = character.costumeNodesForTesting.allSatisfy(\.isHidden)
        #expect(hiddenWhileWorking, "a mismatched layer was drawn anyway")
        character.apply(state: .idle, facing: .right, startingAt: 0)
        let drawnWhileIdle = character.costumeNodesForTesting.allSatisfy { !$0.isHidden }
        #expect(drawnWhileIdle, "the intact states stopped being drawn too")
    }

    /// §6 rule 2 for the wardrobe: what an agent wears is decided at spawn and
    /// never rewritten, including when `agentAppeared` arrives again carrying an
    /// `agent_type` we did not have the first time. Changing a character's
    /// clothes under the user's eye changes who it is.
    @Test func theCostumeIsNeverRewrittenAfterSpawn() throws {
        let manifest = try SceneFixtures.manifest()
        var director = SceneDirector(
            layout: RoomLayout(), variantIDs: manifest.characters.orderedVariantIDs,
            costumes: try ManifestFixtures.wardrobe(manifest))
        let agent = Self.cast(2)[1]

        _ = director.apply([.agentAppeared(agent: agent, agentType: nil, lifecycle: .spawning)])
        #expect(director.costume(agent) == nil)
        _ = director.apply([
            .agentAppeared(agent: agent, agentType: "test-engineer", lifecycle: .active),
        ])
        #expect(director.costume(agent) == nil, "the costume changed after spawn")
    }
}

// MARK: - Contract

/// What a manifest carrying a wardrobe has to satisfy. Runs on a fresh clone —
/// it asks what the manifest *declares*, and the shipped one declares nothing,
/// which is a legal state and is asserted as one rather than skipped past.
struct CostumeContractTests {

    @Test func theShippedManifestDeclaresNoWardrobeAndThatIsLegal() throws {
        let manifest = try SceneFixtures.manifest()
        let costumes = manifest.characters.costumes
        #expect(costumes.isEmpty)
        #expect(costumes.roles.isEmpty)
        #expect(costumes.assignableIDs.isEmpty)
        #expect(ThemeSelector.costume(agentID: "a1", agentType: "Explore", in: costumes) == nil)
    }

    /// **No costume the hash can reach may assert**, over whatever the manifest
    /// actually declares. This is the contract check that binds the day the art
    /// lands rather than the day after — the same reason the seated-pose guard
    /// was written against an empty pose table.
    @Test func noAssertingCostumeIsInThePoolTheHashDrawsFrom() throws {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.characters.costumes.assignableIDs {
            let costume = try #require(manifest.characters.costumes.costume(id))
            #expect(!costume.asserts, Comment(rawValue:
                "costume \(id) (\(costume.title)) asserts and is assignable: a hash would"
                + " be making a claim about an agent_type nobody anticipated [I1]"))
        }
        // Every role entry names a costume that exists — enforced at decode, and
        // asserted here so the enforcement is visible rather than implied.
        for (agentType, id) in manifest.characters.costumes.roles {
            #expect(manifest.characters.costumes.costume(id) != nil,
                    "roles.\(agentType) names the costume \(id), which is not declared")
        }
    }

    /// Every frame a declared costume names must exist on every state its own
    /// layer declares, with the same facings the body carries — the check that
    /// would catch a half-imported outfit sheet.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyDeclaredCostumeFrameIsOnDisk() throws {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.characters.costumes.orderedIDs {
            let costume = try #require(manifest.characters.costumes.costume(id))
            #expect(!costume.layers.isEmpty)
            for path in costume.declaredPaths {
                #expect(FileManager.default.fileExists(atPath: manifest.url(path).path),
                        "costume \(id) names \(path), which is not on disk")
            }
        }
    }
}

// MARK: - Fixtures

/// Manifests built by editing the real one and reloading it through
/// `Manifest.load(contentsOf:root:)`.
///
/// **Real art, real decoder, real root.** The alternative — a `Manifest` value
/// assembled in Swift — cannot exercise the decoding at all, and a fixture whose
/// paths point at nothing cannot exercise the drawing. These edit
/// `assets/manifest.json` in memory, write it beside the test run, and load it
/// with the repository as the root, so every path in them resolves to the same
/// files the app draws.
enum ManifestFixtures {

    static func load(_ object: [String: Any]) throws -> Manifest {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sprite-room-fixture-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try Manifest.load(contentsOf: url, root: SceneFixtures.repositoryRoot)
    }

    static func raw() throws -> [String: Any] {
        let data = try Data(contentsOf: SceneFixtures.repositoryRoot
            .appending(path: "assets").appending(path: "manifest.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Manifest.LoadError.malformed("fixture base is not an object")
        }
        return object
    }

    /// The shipped manifest with **every theme carrying numbered stations**,
    /// built out of the other themes' own desks, chairs and accents.
    ///
    /// Real files, byte-different from each other, already measured and already
    /// through the import pass — which is what makes a pixel comparison over
    /// them mean something. It is deliberately *not* what the art will be; the
    /// art-director owns that. It is the shape the scene has to be able to draw.
    static func stationed(_ manifest: Manifest, bindMainAndDefault: Bool = true) throws
    -> Manifest {
        var object = try raw()
        guard var themes = object["themes"] as? [String: Any],
              var sets = themes["sets"] as? [String: Any] else {
            throw Manifest.LoadError.malformed("the base manifest declares no themes")
        }
        // One donor per numbered station, taken from the themes themselves so
        // every station is a desk that already exists.
        let donors = manifest.themes.orderedIDs
        var pool: [[String: Any]] = []
        for id in donors {
            guard let theme = sets[id] as? [String: Any],
                  let props = theme["props"] as? [String: Any],
                  let roles = props["roles"] as? [String: Any],
                  let desk = roles[RoomScene.surfaceRole],
                  let chair = roles[RoomScene.seatRole],
                  let accent = roles[RoomScene.accentRole] else { continue }
            pool.append(["desk": desk, "chair": chair, "prop": accent])
        }
        guard pool.count > 1 else {
            throw Manifest.LoadError.malformed("fewer than two themes to build stations from")
        }

        for id in donors {
            guard var theme = sets[id] as? [String: Any],
                  var props = theme["props"] as? [String: Any] else { continue }
            var stations: [String: Any] = [:]
            for (index, station) in pool.enumerated() {
                stations[String(format: "%02d", index + 1)] = station
            }
            if bindMainAndDefault {
                stations[ThemeSelector.mainStationID] = pool[0]
                stations[ThemeSelector.defaultStationID] = pool[pool.count - 1]
            }
            props["stations"] = stations
            theme["props"] = props
            sets[id] = theme
        }
        themes["sets"] = sets
        object["themes"] = themes
        return try load(object)
    }

    /// `characters.costumes`, built out of the cast's own frames.
    ///
    /// The layers are other variants' state maps used as overlays: right
    /// geometry, right frame counts, real files on disk. What a costume will
    /// actually be is an outfit sheet from `Character_Generator/Outfits`, which
    /// is the premade sheets' exact dimensions and therefore exactly this shape.
    ///
    /// - Parameter truncateWorkingTo: drops the first layer's `working` frames
    ///   to this many, to exercise the frame-count guard.
    static func dressed(_ manifest: Manifest, truncateWorkingTo: Int? = nil) throws -> Manifest {
        var object = try raw()
        guard var characters = object["characters"] as? [String: Any],
              let variants = characters["variants"] as? [String: Any] else {
            throw Manifest.LoadError.malformed("the base manifest declares no variants")
        }
        let ids = manifest.characters.orderedVariantIDs
        guard ids.count > 3 else {
            throw Manifest.LoadError.malformed("too few variants to build a wardrobe from")
        }

        func layer(_ variantID: String, truncateWorking: Int? = nil) throws -> [String: Any] {
            guard let variant = variants[variantID] as? [String: Any],
                  var states = variant["states"] as? [String: Any] else {
                throw Manifest.LoadError.malformed("variant \(variantID) has no states")
            }
            if let truncateWorking,
               var working = states[BodyState.working.rawValue] as? [String: Any],
               var frames = working["frames"] as? [String: Any] {
                for (facing, paths) in frames {
                    frames[facing] = Array((paths as? [String] ?? []).prefix(truncateWorking))
                }
                working["frames"] = frames
                states[BodyState.working.rawValue] = working
            }
            return ["states": states]
        }

        characters["costumes"] = [
            "sets": [
                "neutral_a": [
                    "title": "plain overalls",
                    "asserts": false,
                    "layers": [try layer(ids[1], truncateWorking: truncateWorkingTo)],
                ],
                "neutral_b": [
                    "title": "plain jacket",
                    "asserts": false,
                    "layers": [try layer(ids[2], truncateWorking: truncateWorkingTo)],
                ],
                "coat": [
                    "title": "lab coat",
                    "asserts": true,
                    "layers": [try layer(ids[3], truncateWorking: truncateWorkingTo)],
                ],
            ],
            "roles": ["test-engineer": "coat"],
            "assignable": ["neutral_a", "neutral_b"],
        ]
        object["characters"] = characters
        return try load(object)
    }

    static func wardrobe(_ manifest: Manifest) throws -> Manifest.Costumes {
        try dressed(manifest).characters.costumes
    }
}

/// Composites what a `RoomScene` drew at one seat into a bitmap.
///
/// **Only ever used for a difference, never for an absolute claim**, and that is
/// what makes a hand-rolled rasteriser safe here. Two seats go through the same
/// code with the same window, so a wrong offset or a flipped axis moves both
/// identically and cannot turn two different desks into an equal result. It can
/// only under-report, which is the direction this has to be wrong in — the
/// failure it exists to catch is a *false* difference being reported, and it
/// cannot report one.
///
/// The preview tool in `scripts/` learned this the expensive way: it misplaced
/// every prop in every theme for two milestones because it was compared against
/// nothing. This is compared against itself.
@MainActor
enum SeatRaster {

    /// The window round a seat: wide enough for the desk on the right, the
    /// optional adjacent prop on the left, and the whole of a standing prop's
    /// height.
    static let width = 160
    static let height = 160

    static func render(_ scene: RoomScene, seat: Int, manifest: Manifest) -> Bitmap {
        var bitmap = Bitmap(width: width, height: height)
        let origin = scene.layout.seatPosition(seat)
        let left = origin.x - Double(width) / 2
        let top = origin.y + Double(height) - 32

        for piece in scene.furnitureForTesting(seat: seat) {
            guard let source = try? PixelImage.bitmap(contentsOf: manifest.url(piece.path))
            else { continue }
            // Bottom-left of the sprite in scene coordinates, from its anchor.
            let spriteLeft = piece.x - piece.anchorX * piece.width
            let spriteTop = piece.y - piece.anchorY * piece.height + piece.height
            let offsetX = Int((spriteLeft - left).rounded())
            let offsetY = Int((top - spriteTop).rounded())
            for y in 0..<source.height {
                let row = offsetY + y
                guard row >= 0, row < height else { continue }
                for x in 0..<source.width {
                    let column = offsetX + x
                    guard column >= 0, column < width else { continue }
                    let pixel = source.at(x, y)
                    guard pixel.a > 0 else { continue }
                    bitmap.set(column, row, pixel)
                }
            }
        }
        return bitmap
    }

    static func differences(_ a: Bitmap, _ b: Bitmap) -> Int {
        guard a.width == b.width, a.height == b.height else { return a.width * a.height }
        var count = 0
        for y in 0..<a.height {
            for x in 0..<a.width where a.at(x, y) != b.at(x, y) { count += 1 }
        }
        return count
    }
}

extension Bitmap {
    /// How much of this patch is not transparent. A control that drew nothing
    /// would compare equal to another control that drew nothing, so the tests
    /// that rely on "these two are the same" check there was something there.
    var opaqueCount: Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where at(x, y).a > 0 { count += 1 }
        }
        return count
    }
}
