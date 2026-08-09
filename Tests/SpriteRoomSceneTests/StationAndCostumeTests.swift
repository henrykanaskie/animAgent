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

    /// **The headline, and it now runs against the manifest that ships.**
    ///
    /// It used to run the other way up. The control was "with no stations
    /// declared the two seats are pixel-identical", asserted against
    /// `assets/manifest.json` itself, with the claim demonstrated only on a
    /// hand-built fixture — a test that pins an empty spec and reads as
    /// coverage, which is exactly the shape that let the station spend three
    /// months resolved, stored and drawn by nothing. Inverted, not deleted, the
    /// way `CostumeContractTests` was.
    ///
    /// Two claims, and the second is what makes the first mean anything:
    ///
    /// - `Explore` and `general-purpose` — the two `agent_type`s that actually
    ///   occur in `fixtures/`, 23 and 165 times — draw **different** pixels at
    ///   their seats.
    /// - two `general-purpose` agents draw **identical** pixels at theirs, which
    ///   is §4's rule ("same desk means same kind of worker") and is also the
    ///   proof that this comparator can still report equality. A rasteriser that
    ///   reported a difference everywhere would pass the first claim on its own.
    @Test(.enabled(if: SceneArt.isAvailable))
    func twoAgentsOfDifferentTypeDrawDifferentPixelsAtTheirSeats() throws {
        let shipped = try SceneFixtures.manifest()
        let themeID = try #require(shipped.themes.orderedIDs.first)

        func seats(_ manifest: Manifest, _ types: [String])
        throws -> (patches: [Bitmap], stations: [String?]) {
            let scene = RoomScene(manifest: manifest, themeID: themeID)
            scene.setViewport(CGSize(width: 720, height: 400))
            var director = SceneDirector(manifest: manifest, themeID: themeID)
            let cast = Self.cast(types.count + 1)
            var deltas: [WorldDelta] = [
                .agentAppeared(agent: cast[0], agentType: nil, lifecycle: .active),
            ]
            for (index, type) in types.enumerated() {
                deltas.append(.agentAppeared(
                    agent: cast[index + 1], agentType: type, lifecycle: .spawning))
            }
            scene.apply(director.apply(deltas))
            var patches: [Bitmap] = []
            for index in types.indices {
                let seat = try #require(director.seats[cast[index + 1]])
                patches.append(SeatRaster.render(scene, seat: seat, manifest: manifest))
            }
            return (patches, types.indices.map { director.station(cast[$0 + 1]) })
        }

        let types = ["Explore", "general-purpose", "general-purpose"]
        let drawn = try seats(shipped, types)
        #expect(drawn.patches[0].opaqueCount > 0, "nothing at all was drawn at a seat")

        #expect(drawn.stations[0] != drawn.stations[1], Comment(rawValue:
            "`Explore` and `general-purpose` both resolved to \(drawn.stations[0] ?? "-")"
            + " in the shipped manifest, so this compares two copies of one station"))
        #expect(SeatRaster.differences(drawn.patches[0], drawn.patches[1]) > 0, Comment(
            rawValue: "`Explore` (\(drawn.stations[0] ?? "-")) and `general-purpose`"
            + " (\(drawn.stations[1] ?? "-")) drew the same \(drawn.patches[0].width)×"
            + "\(drawn.patches[0].height) patch of room at their seats. The station"
            + " resolved and reached nothing. [ADR-002 §4]"))

        // §4: identical agents get identical desks, deliberately.
        #expect(drawn.stations[1] == drawn.stations[2])
        #expect(SeatRaster.differences(drawn.patches[1], drawn.patches[2]) == 0,
                "two agents of one agent_type were given different stations")
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

// MARK: - Station contract

/// What a manifest carrying stations has to satisfy. Runs on a fresh clone —
/// every assertion but the last asks what the manifest *declares*, never what is
/// on disk.
struct StationContractTests {

    /// The shipped manifest declares stations, and every part of the resolution
    /// reaches them.
    ///
    /// This asserted the **opposite** until the art landed: "the shipped
    /// manifest declares no stations and that is a legal state". It was true,
    /// and it read as coverage of a feature that was drawing nothing. Inverted
    /// rather than deleted, exactly as the wardrobe's was, and it now fails in
    /// both directions — an empty station table fails here, and a table the
    /// resolver cannot reach fails on the last lines.
    @Test func theShippedManifestDeclaresStationsTheResolverCanReach() throws {
        let manifest = try SceneFixtures.manifest()
        let themeID = try #require(manifest.themes.orderedIDs.first)
        let theme = try #require(manifest.themes.theme(themeID))

        #expect(!theme.orderedStationIDs.isEmpty, "the shipped manifest declares no stations")
        #expect(!theme.stationRoles.isEmpty, "no agent_type resolves to a named station")
        #expect(!theme.assignableStationIDs.isEmpty, "the hash has no pool to draw from")
        #expect(theme.station(ThemeSelector.mainStationID) != nil, "`main` is unbound")
        #expect(theme.station(ThemeSelector.defaultStationID) != nil, "`default` is unbound")

        // The identity rules come first and are not overridable by a type.
        #expect(ThemeSelector.station(agentID: nil, agentType: "Explore", in: theme)
                == ThemeSelector.mainStationID)
        for type: String? in [nil, ""] {
            #expect(ThemeSelector.station(agentID: "a1", agentType: type, in: theme)
                    == ThemeSelector.defaultStationID)
        }

        // Tier 1: an exact name is translated.
        let recognised = try #require(theme.stationRoles.keys.sorted().first)
        #expect(ThemeSelector.station(agentID: "a1", agentType: recognised, in: theme)
                == theme.stationRoles[recognised])
        // Tier 2: a name nobody anticipated still resolves, and to the pool.
        let unknown = ThemeSelector.station(
            agentID: "a2", agentType: "an-agent-type-nobody-anticipated", in: theme)
        #expect(theme.assignableStationIDs.contains(unknown), Comment(rawValue:
            "an unrecognised agent_type landed on \(unknown), which is not in the pool"))
    }

    /// **The agent types the asserting tier is keyed on are ones a real session
    /// produces**, checked against `fixtures/` rather than against a list
    /// somebody typed.
    ///
    /// This is the test the wardrobe does not have and should. `characters
    /// .costumes.roles` is keyed almost entirely on **this repository's own
    /// invented subagent names** — `test-engineer`, `scene-engineer`,
    /// `art-director` — none of which any user outside this repo will ever run,
    /// so its expressive half is addressed to an audience of one. The captured
    /// sessions contain exactly three `agent_type` values: `general-purpose`,
    /// `Explore`, and the empty string. The first two must be translated here or
    /// the whole asserting tier is decoration.
    ///
    /// The empty string is deliberately **not** required to be in `roles`: it
    /// takes the `default` branch before `roles` is consulted, because an agent
    /// we cannot name may not be given a meaning. [I1]
    @Test func everyAgentTypeTheFixturesContainIsTranslatedOrDeliberatelyNot() throws {
        let manifest = try SceneFixtures.manifest()
        let themeID = try #require(manifest.themes.orderedIDs.first)
        let theme = try #require(manifest.themes.theme(themeID))
        let observed = try Self.agentTypesInFixtures()
        #expect(observed.contains(""), "the fixture sweep found no empty agent_type at all")
        #expect(observed.count >= 3, "the fixture sweep found \(observed.count) agent types")

        for type in observed.sorted() where !type.isEmpty {
            #expect(theme.stationRoles[type] != nil, Comment(rawValue:
                "`\(type)` occurs in fixtures/ and the station roles table does not name it,"
                + " so the commonest agent in a real room gets a station that asserts"
                + " nothing. [ADR-002 §14c]"))
        }
    }

    /// **The wardrobe's asserting tier, held to the same standard as the
    /// station's** — this is the test the comment above says the wardrobe does
    /// not have.
    ///
    /// It did not have it, and the consequence was exactly what that comment
    /// predicted: `roles` named `Explore` and `general-purpose` but spent its
    /// four *expressive* costumes — lab coat, hi-vis, dungarees, apron — on
    /// `test-engineer`, `build-verifier`, `scene-engineer`, `ingest-engineer`,
    /// `ui-engineer` and `art-director`, every one of them a name invented for
    /// this repository's own dev team. A real session produced a plain shirt
    /// every time.
    ///
    /// Keyed off `fixtures/` at run time rather than a typed list, so a fourth
    /// `agent_type` appearing in a future capture turns this red instead of
    /// quietly getting a costume that says nothing.
    @Test func everyAgentTypeTheFixturesContainIsDressedOrDeliberatelyNot() throws {
        let manifest = try SceneFixtures.manifest()
        let costumes = manifest.characters.costumes
        let observed = try Self.agentTypesInFixtures()
        #expect(observed.contains(""), "the fixture sweep found no empty agent_type at all")
        #expect(observed.count >= 3, "the fixture sweep found \(observed.count) agent types")

        for type in observed.sorted() where !type.isEmpty {
            #expect(costumes.roles[type] != nil, Comment(rawValue:
                "`\(type)` occurs in fixtures/ and the costume roles table does not name it,"
                + " so the commonest agent in a real room is dressed by a hash"))
        }

        // The empty string takes the default branch before `roles` is consulted:
        // an agent we cannot name may not be given a meaning. [I1]
        #expect(costumes.roles[""] == nil,
                "the empty agent_type is in roles, so an unnameable agent is being dressed")
    }

    /// The maintainer's own words: a tester or a verifier should be the one in
    /// the lab coat. Pinned because it is a product decision, not an accident of
    /// which key happened to be typed first.
    @Test func theCostumesThatAssertAreReachableByNamesPeopleActuallyUse() throws {
        let costumes = try SceneFixtures.manifest().characters.costumes

        for name in ["test-engineer", "tester", "verifier"] {
            let id = try #require(costumes.roles[name], "no costume for `\(name)`")
            #expect(costumes.costume(id)?.title == "lab coat", Comment(rawValue:
                "`\(name)` wears \(id), not the lab coat"))
        }

        // Every costume that makes a claim must be reachable by *some* name, or
        // the art is unreachable decoration.
        for id in costumes.orderedIDs where costumes.costume(id)?.asserts == true {
            #expect(costumes.roles.values.contains(id), Comment(rawValue:
                "costume \(id) asserts something and no agent_type maps to it, so nothing"
                + " in any room can ever wear it"))
        }
    }

    /// **No station the hash can reach may assert.** The contract check that
    /// binds over whatever the manifest declares, not over what it declares
    /// today.
    @Test func noAssertingStationIsInThePoolTheHashDrawsFrom() throws {
        let manifest = try SceneFixtures.manifest()
        let themeID = try #require(manifest.themes.orderedIDs.first)
        let theme = try #require(manifest.themes.theme(themeID))
        for id in theme.assignableStationIDs {
            let station = try #require(theme.station(id))
            #expect(!station.asserts, Comment(rawValue:
                "station \(id) (\(station.title)) asserts and is assignable: a hash would be"
                + " making a claim about an agent_type nobody anticipated [I1]"))
        }
        #expect(theme.stationRoles.values.contains { theme.station($0)?.asserts == true },
                "no station in roles asserts, so the separation is vacuous")

        // And nothing the hash can reach at any input escapes the pool.
        var reached: Set<String> = []
        for index in 0..<4000 {
            let type = "an-agent-name-\(index)"
            guard theme.stationRoles[type] == nil else { continue }
            let id = ThemeSelector.station(agentID: "a1", agentType: type, in: theme)
            reached.insert(id)
            #expect(theme.station(id)?.asserts == false, Comment(rawValue:
                "the hash put the unrecognised type \(type) at \(id), which asserts"))
        }
        #expect(reached == Set(theme.assignableStationIDs),
                "the pool is not fully reachable: \(reached.sorted())")
    }

    /// Every theme binds the same stations, because the block is declared once
    /// under `room` and inherited. A theme that lost them would seat its agents
    /// at identical desks while the others did not — a difference the user would
    /// read as a bug in the theme. [§14c]
    @Test func everyThemeBindsTheSameStations() throws {
        let manifest = try SceneFixtures.manifest()
        let expected = manifest.room.orderedStationIDs
        #expect(!expected.isEmpty)
        for id in manifest.themes.orderedIDs {
            let theme = try #require(manifest.themes.theme(id))
            #expect(theme.orderedStationIDs == expected, "theme \(id) binds \(theme.orderedStationIDs)")
            #expect(theme.assignableStationIDs == manifest.room.assignableStationIDs)
            #expect(theme.stationRoles == manifest.room.stationRoles)
            // And the desk and chair under a station are that theme's own, so a
            // station never drags one room's furniture into another.
            for stationID in expected {
                let station = try #require(theme.station(stationID))
                #expect(station.desk.file == theme.room.prop(RoomScene.surfaceRole)?.file,
                        "theme \(id) station \(stationID) does not use the theme's own desk")
                #expect(station.chair.file == theme.room.prop(RoomScene.seatRole)?.file)
            }
        }
    }

    /// Every theme the room can be dressed in, the manifest's own default
    /// included — `manifest.room` *is* the resolved default theme [§14a] and a
    /// check that skips it skips the room most users see.
    static func everyTheme(_ manifest: Manifest) throws -> [(String, Manifest.Room)] {
        var themes: [(String, Manifest.Room)] = [("room", manifest.room)]
        for id in manifest.themes.orderedIDs {
            themes.append((id, try #require(manifest.themes.theme(id)).room))
        }
        return themes
    }

    /// **The station has to fit the seat it is drawn at**, and both numbers come
    /// out of `RoomLayout` rather than out of taste. Measured from the declared
    /// content boxes, so it runs without any art on disk.
    ///
    /// - A prop stands one tile to the character's left on a 96px seat pitch,
    ///   between the neighbour's desk (which ends at `x−52`) and the character's
    ///   own body. Over 32px wide and it collides with one or the other. A
    ///   120px-wide prop was tried at M6c and could not be drawn at any canvas
    ///   size; the canvas was never what was in the way.
    /// - A station desk is drawn **in front of** the body, so anything taller
    ///   than the shortest variant's head-above-feet hides a face.
    @Test func everyStationFitsTheSeatItIsDrawnAt() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let pitch = layout.seatPosition(1).x - layout.seatPosition(0).x
        #expect(pitch == 96, "the seat pitch moved; these limits are derived from it")

        // The gap a prop has to live in, from the layout itself.
        let propCentre = layout.stationPropPosition(0).x - layout.seatPosition(0).x
        let deskCentre = layout.deskPosition(0).x - layout.seatPosition(0).x
        let maximumPropWidth = 2 * (propCentre - (deskCentre - pitch))
        #expect(maximumPropWidth >= 32)

        let heads = manifest.characters.orderedVariantIDs
            .compactMap { manifest.characters.variant($0)?.headTopPx }
            .map { manifest.characters.canvas.height - $0 }
        let shortestHead = try #require(heads.min())
        #expect(shortestHead == 44, "the shortest head moved; the desk limit is derived from it")

        // **It used to check only what a station DECLARES, and that is why the
        // room drew over every face in `library` for a milestone.** A station
        // that does not override the desk inherits the theme's, and the theme's
        // is drawn by `buildRoom` at every seat whether anybody is sitting there
        // or not — so the limits have to bind what the room *draws*, not what
        // the station *says*. Two themes bound a desk that failed both:
        // `library`'s was 56×70 and `mission_control`'s 44×36.
        //
        // **Both were re-cut at `1c0eeb3` and the sentence above is history.**
        // `library` is now **32×44** and `mission_control` **40×36**, so every
        // desk the room draws is inside both limits and the height branch below
        // is never taken by shipped art. The check stays because it binds what a
        // theme *could* bind, and it is the reason the numbers here are quoted
        // in the past tense — a prose dimension is not a backticked identifier,
        // so `DocumentedSymbolTests` cannot see it go stale and this comment had
        // to be corrected by hand.
        //
        // The height limit is now enforced by the scene instead of asserted
        // against art nobody may edit here: `RoomScene.surfaceDepthBias` puts a
        // desk taller than the shortest head **behind** the body rather than in
        // front of it, so it cannot reach a face whatever a theme binds. That is
        // what this checks, over every desk any theme can put at a seat, and it
        // fails against a scene that resolves the depth by a constant.
        var deskCount = 0
        for (id, room) in try Self.everyTheme(manifest) {
            var desks: [(String, Manifest.PropRole)] = []
            if let inherited = room.prop(RoomScene.surfaceRole) {
                desks.append(("props.roles", inherited))
            }
            for stationID in room.orderedStationIDs {
                desks.append((stationID, try #require(room.station(stationID)).desk))
            }
            for (label, desk) in desks {
                deskCount += 1
                let bias = RoomScene.surfaceDepthBias(
                    deskHeight: desk.contentBox.height, headClearance: shortestHead)
                if bias > 0 {
                    #expect(desk.contentBox.height <= shortestHead, Comment(rawValue:
                        "\(id)/\(label): a \(desk.contentBox.height)px desk is drawn in front"
                        + " of a head that starts \(shortestHead)px up"))
                } else {
                    #expect(bias < RoomScene.seatDepthBias, Comment(rawValue:
                        "\(id)/\(label): the desk goes behind the body but not behind the"
                        + " chair, so a seat's three pieces no longer sort in one order"))
                }
            }
        }
        #expect(deskCount >= 12, "only \(deskCount) desks were examined")

        // **The width limit is not enforceable from here and is bounded
        // instead.** A desk is centred on `deskPosition`, so its right edge
        // reaches `28 + w/2` from its seat while the next seat's station prop
        // lane starts at `+48` — which makes the overhang exactly `w/2 − 20`,
        // and therefore a statement about the desk's width alone.
        //
        // **The bound is 0, and it used to be 8.** 8 was the 56px `library`
        // desk's overhang, and once `1c0eeb3` re-cut that desk to 32 the bound
        // carried 8px of slack over every desk the room draws: the widest is
        // `mission_control`'s 40, which lands at **exactly 0**, and every other
        // theme's 32 lands at −4. A limit with slack over the worst shipped case
        // absorbs the first regression instead of reporting it — art could go
        // back to overhanging by 8 and nothing would say so. Tightened to the
        // measurement, so the next widening fails here.
        //
        // Zero is the right number rather than a coincidence: it is where a
        // desk's right edge meets the lane the neighbour's station prop stands
        // in, so `> 0` is a desk standing *on* the neighbour and `≤ 0` is not.
        // A theme that wants a wider desk is choosing different art in
        // `assets/manifest.json`, which is where the fix belongs.
        // The next seat's prop lane at the 32px limit asserted just above.
        let propLaneLeft = layout.stationPropPosition(1).x
            - Double(manifest.characters.canvas.width) / 2
        for (id, room) in try Self.everyTheme(manifest) {
            guard let desk = room.prop(RoomScene.surfaceRole) else { continue }
            let overhang = layout.deskPosition(0).x
                + Double(desk.contentBox.width) / 2 - propLaneLeft
            #expect(overhang <= 0, Comment(rawValue:
                "\(id): a \(desk.contentBox.width)px desk overhangs the next seat's prop"
                + " lane by \(overhang)px"))
        }

        for id in manifest.themes.orderedIDs {
            let theme = try #require(manifest.themes.theme(id))
            let inheritedDesk = theme.room.prop(RoomScene.surfaceRole)?.file
            for stationID in theme.orderedStationIDs {
                let station = try #require(theme.station(stationID))
                if station.desk.file != inheritedDesk {
                    #expect(station.desk.contentBox.width <= 32, Comment(rawValue:
                        "\(id)/\(stationID): the desk is \(station.desk.contentBox.width)px"
                        + " wide and overlaps the next seat"))
                }
                guard let prop = station.prop else { continue }
                #expect(Double(prop.contentBox.width) <= maximumPropWidth, Comment(rawValue:
                    "\(id)/\(stationID): the prop is \(prop.contentBox.width)px wide against"
                    + " \(Int(maximumPropWidth))px of clear floor beside the seat"))
                // And it stands beside the body, never on it: the prop's box and
                // the 32px character canvas may not share a column.
                let propRight = layout.stationPropPosition(0).x
                    + Double(prop.contentBox.width) / 2
                #expect(propRight <= layout.seatPosition(0).x
                        - Double(manifest.characters.canvas.width) / 2, Comment(rawValue:
                    "\(id)/\(stationID): the prop reaches \(propRight - layout.seatPosition(0).x)"
                    + "px from the seat centre and stands on the character"))
            }
        }
    }

    /// Every frame a declared station names is on disk — the check that would
    /// catch a station pointing at art nobody imported.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyDeclaredStationFrameIsOnDisk() throws {
        let manifest = try SceneFixtures.manifest()
        for id in manifest.themes.orderedIDs {
            let theme = try #require(manifest.themes.theme(id))
            for stationID in theme.orderedStationIDs {
                for path in try #require(theme.station(stationID)).declaredPaths {
                    #expect(FileManager.default.fileExists(atPath: manifest.url(path).path),
                            "\(id)/\(stationID) names \(path), which is not on disk")
                }
            }
        }
    }

    /// Every `agent_type` value any captured session carried.
    ///
    /// Read out of `fixtures/` rather than written down, because a list written
    /// down is a list that stops being true. `fixtures/` is tracked in git, so
    /// this runs on a fresh clone with no art.
    static func agentTypesInFixtures() throws -> Set<String> {
        let directory = SceneFixtures.repositoryRoot.appending(path: "fixtures")
        var found: Set<String> = []
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where name.hasSuffix(".jsonl") {
            let text = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else { continue }
                collectAgentTypes(object, into: &found)
            }
        }
        return found
    }

    private static func collectAgentTypes(_ node: Any, into found: inout Set<String>) {
        if let object = node as? [String: Any] {
            for (key, value) in object {
                if key == "agent_type", let type = value as? String { found.insert(type) }
                collectAgentTypes(value, into: &found)
            }
        } else if let array = node as? [Any] {
            for value in array { collectAgentTypes(value, into: &found) }
        }
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
        // The shipped manifest now carries a wardrobe, so the fallback needs a
        // manifest that genuinely lacks one. Read off the shipped file this
        // test was asserting the *absence of the feature*, which stops being a
        // fallback check the moment the feature exists.
        let manifest = try ManifestFixtures.undressed(try SceneFixtures.manifest())
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
/// it asks what the manifest *declares*, never what is on disk.
struct CostumeContractTests {

    /// The shipped manifest declares a wardrobe, and every part of the
    /// resolution reaches it.
    ///
    /// This asserted the **opposite** until the wardrobe landed: "the shipped
    /// manifest declares nothing, which is a legal state and is asserted as one
    /// rather than skipped past". That was the right assertion to write while
    /// the art did not exist, and it is exactly the shape that let the station
    /// spend three months resolved, stored and drawn by nothing — a test
    /// pinning an empty spec reads as coverage and is the absence of it.
    ///
    /// So it is inverted rather than deleted, and it now fails in **both**
    /// directions: an empty wardrobe fails here, and a wardrobe the resolver
    /// cannot reach fails on the last line.
    @Test func theShippedManifestDeclaresAWardrobeTheResolverCanReach() throws {
        let manifest = try SceneFixtures.manifest()
        let costumes = manifest.characters.costumes

        #expect(!costumes.isEmpty, "the shipped manifest declares no wardrobe")
        #expect(!costumes.roles.isEmpty)
        #expect(!costumes.assignableIDs.isEmpty)

        // A recognised type wears what its name says; the main thread wears
        // nothing, because it has no `agent_id` and therefore no type.
        let recognised = try #require(costumes.roles.keys.sorted().first)
        #expect(ThemeSelector.costume(
            agentID: "a1", agentType: recognised, in: costumes) == costumes.roles[recognised])
        #expect(ThemeSelector.costume(agentID: nil, agentType: nil, in: costumes) == nil)

        // An unrecognised type still resolves — to the neutral pool, never to
        // nothing, or the hash half of the two tiers is unreachable.
        let unknown = ThemeSelector.costume(
            agentID: "a2", agentType: "a-type-nobody-anticipated", in: costumes)
        #expect(unknown != nil)
        #expect(costumes.assignableIDs.contains(try #require(unknown)))
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
    /// The shipped manifest with its **wardrobe removed**, decoded for real.
    ///
    /// Exists because the degradation test used to read the shipped manifest
    /// directly and assert it declared nothing — which was true until the
    /// wardrobe landed, and then the test was asserting the absence of the
    /// feature rather than the presence of the fallback. A manifest that
    /// predates costumes is still a real thing to load, so it is built by
    /// stripping the key and decoding, not by hand.
    static func undressed(_ manifest: Manifest) throws -> Manifest {
        var object = try raw()
        var characters = object["characters"] as? [String: Any] ?? [:]
        characters.removeValue(forKey: "costumes")
        object["characters"] = characters
        return try load(object)
    }

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
