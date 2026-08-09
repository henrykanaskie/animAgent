import Foundation
import Testing
import SpriteRoomCore
import SpriteRoomScene

/// **Is the art on disk?** Asked once, here, and nowhere else.
///
/// `assets/` is gitignored: it holds three purchased LimeZu packs whose licence
/// permits use but not redistribution. Only `assets/manifest.json` is tracked,
/// because it is the contract the scene builds against and it holds filenames
/// and numbers rather than artwork. So a fresh clone — and every CI job — holds
/// the contract and none of the art it names.
///
/// The tests that read pixels are doing exactly their job when they fail in
/// that state, but the consequence is that `swift test` cannot pass from the
/// committed state, and "the suite is green" becomes a claim only the author's
/// machine can check. Those tests are therefore gated on `isAvailable`, in the
/// same way `NotchPanelTests.hasWindowServer` gates the tests that need a GUI
/// session.
///
/// **This asks whether the manifest's declared art *resolves*, not whether an
/// `assets/` directory exists.** A half-populated `assets/` — an interrupted
/// copy, a partial `git-lfs` fetch, a pack unzipped to the wrong level — is the
/// case that would otherwise produce a scattering of confusing individual
/// failures instead of one clear "the art is not here".
///
/// A missing *manifest* is deliberately **not** covered. `assets/manifest.json`
/// is tracked, so its absence is a real defect in the checkout and the tests
/// that load it should stay red and say so.
///
/// `ArtAvailabilityTests` below always runs and reports which mode the suite
/// ran in, so a green run on a machine with no art cannot be mistaken for a run
/// that verified the art.
///
/// **Override.** Set `SPRITE_ROOM_REQUIRE_ART=1` on a machine that is supposed
/// to have the art — a release build, a packaging step, the machine cutting M5 —
/// and missing art becomes a hard failure in `ArtAvailabilityTests` instead of a
/// skip. The gate itself still reports the truth about the disk, so the failure
/// is one legible error naming the missing files rather than N art tests
/// failing on their own assertions.
enum SceneArt {

    /// What a walk of every path the manifest declares found.
    struct Survey: Sendable {
        /// Every distinct manifest-relative path declared.
        ///
        /// The set rather than just its size, so a test can ask *which* paths
        /// the walk found. The count alone cannot distinguish a walk that
        /// covers the manifest from one that covers most of it — which is
        /// exactly what happened to the animation frames: `role.file` is frame
        /// 0 and is always present, so a survey that collected only `file`
        /// declared a plausible number and left frames 1..N out of the set. Art
        /// could then be missing with `SPRITE_ROOM_REQUIRE_ART=1` green.
        var paths: Set<String> = []
        /// Distinct manifest-relative paths declared.
        var declaredPaths: Int { paths.count }
        /// Those that are not on disk, sorted.
        var missingPaths: [String] = []
        /// Set when the manifest itself could not be loaded, which is a
        /// different failure and not this gate's business.
        var manifestError: String?

        var isAvailable: Bool {
            manifestError == nil && declaredPaths > 0 && missingPaths.isEmpty
        }
    }

    /// Computed once per test run. ~1500 `stat` calls; cheaper than one of the
    /// replays that depends on it.
    static let survey: Survey = {
        var survey = Survey()
        let manifest: Manifest
        do {
            manifest = try Manifest.load(root: SceneFixtures.repositoryRoot)
        } catch {
            survey.manifestError = "\(error)"
            return survey
        }

        var declared: Set<String> = []
        for id in manifest.characters.orderedVariantIDs {
            guard let variant = manifest.characters.variant(id) else { continue }
            for (_, animation) in variant.states {
                for (_, paths) in animation.frames { declared.formUnion(paths) }
            }
        }
        // The wardrobe. Empty in the shipped manifest; walked anyway, because
        // the survey that under-counts is the one that goes green with art
        // missing, and `role.file` already taught this lesson once.
        for id in manifest.characters.costumes.orderedIDs {
            guard let costume = manifest.characters.costumes.costume(id) else { continue }
            declared.formUnion(costume.declaredPaths)
        }
        for (_, art) in manifest.badges.map { declared.insert(art.file) }
        for (_, art) in manifest.badges.states { declared.insert(art.file) }
        declared.formUnion(manifest.room.builderTiles)
        declared.formUnion(manifest.room.propFiles)
        for (_, role) in manifest.room.propRoles { declared.formUnion(role.declaredPaths) }
        // Every theme's art too, since ADR-002 the scene draws it. A checkout
        // holding the Office room and none of the theme sets is exactly the
        // half-populated `assets/` this survey exists to report as one clear
        // "the art is not here" rather than as a scattering of failures.
        for id in manifest.themes.orderedIDs {
            guard let theme = manifest.themes.theme(id) else { continue }
            declared.formUnion(theme.room.builderTiles)
            declared.formUnion(theme.room.propFiles)
            for (_, role) in theme.room.propRoles { declared.formUnion(role.declaredPaths) }
            for path in [theme.room.declaredFloor, theme.room.declaredWall] {
                if let path { declared.insert(path) }
            }
            for (_, station) in theme.room.stations {
                for role in [station.desk, station.chair] { declared.formUnion(role.declaredPaths) }
                if let prop = station.prop { declared.formUnion(prop.declaredPaths) }
            }
        }

        survey.paths = declared
        survey.missingPaths = declared
            .filter { !FileManager.default.fileExists(atPath: manifest.url($0).path) }
            .sorted()
        return survey
    }()

    /// The gate. Safe to evaluate as a test trait: `nonisolated`, no throwing,
    /// no actor hops.
    static var isAvailable: Bool { survey.isAvailable }

    /// `SPRITE_ROOM_REQUIRE_ART=1` turns absent art from a skip into a failure.
    static var isRequired: Bool {
        let raw = ProcessInfo.processInfo.environment["SPRITE_ROOM_REQUIRE_ART"]?
            .trimmingCharacters(in: .whitespaces).lowercased()
        return ["1", "true", "yes"].contains(raw ?? "")
    }

    /// The number of tests carrying the gate, counted from the test sources
    /// rather than maintained by hand, so the notice below cannot drift into
    /// naming a number that stopped being true.
    ///
    /// Counts the trait annotation, which means it is only correct while every
    /// gate is written per-test. Both scene suites are *mixed* — `ManifestTests`
    /// has two tests that need no art at all and `RoomSceneTests` has fifteen —
    /// so there is no suite-level gate to miss. If a wholly art-dependent suite
    /// is ever added and gated at `@Suite`, teach this to count its tests too.
    static let gatedTestCount: Int = {
        // Assembled from two pieces so that this line does not count itself.
        let trait = ".enabled(if: SceneArt" + ".isAvailable)"
        let directory = SceneFixtures.repositoryRoot
            .appending(path: "Tests").appending(path: "SpriteRoomSceneTests")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var total = 0
        for name in names where name.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: directory.appending(path: name),
                                         encoding: .utf8) else { continue }
            total += text.components(separatedBy: trait).count - 1
        }
        return total
    }()

    /// What is expected to be gated, so a test that quietly gains or loses the
    /// trait is reported rather than absorbed. Update deliberately, in the same
    /// change that moves a test across the line.
    /// 20 as of M5b: `ManifestTests.everyBadgeFileIsExactlyTheDeclaredCanvas`
    /// opens the badge PNGs, so it has to be gated like the rest.
    /// 24 as of M6c: the report round trip added four tests that play real
    /// animations — the beat itself, the whole cast leaving in one frame, a
    /// leaver caught in the aisle, and the delivery station held across the
    /// return leg. Each of them reads `Character.state`, which is `nil` without
    /// frames on disk.
    /// 31 with ADR-002's themed rooms: seven tests that need theme art. Three
    /// check the theme contract — every theme binds every role the scene draws,
    /// every theme resolves a floor and a wall of its own declared tile size,
    /// and every named pose state exists with `right` and `left`. Four check
    /// what reaches the screen — no prop node rebuilt across any fixture replay,
    /// a theme change that redresses the room and moves no character, the
    /// declared floor being the one drawn, and the measurement behind why the
    /// declaration exists at all (the flat-tile search accepts 2 of 141).
    /// 35 with the `sleep` badge: two tests open the badge PNGs — that the
    /// dormant glyph loads and is neither a tool badge nor `attention`, and that
    /// a `Character` swaps to it and gives the slot up to `attention`.
    /// 39 with the animated prop: four tests that need the frames on disk — the
    /// room plays them while an unanimated theme stays still, the animated
    /// prop's node is never rebuilt across a fixture replay, the animation is
    /// identical with and without a delta stream, and no `SpriteIntent` can move
    /// a prop texture.
    /// 40 with the seated-pose guard: `characters.poses.working` may only name
    /// a pose whose every frame keeps its feet off the canvas's floor row, and
    /// that is a claim about pixels, so it opens the character PNGs.
    /// 49 when the station finally reached the room: nine tests that need the
    /// art because they are about the picture rather than about the ids. Five
    /// are `StationSceneTests` — two agents of different `agent_type` differing
    /// in pixels at their seats, a station changing the seat it is drawn at, a
    /// seat whose station names nothing keeping the theme's own furniture, a
    /// station going up at spawn and coming down at retirement, and the fixture
    /// sweep down the branch that actually draws one. Three are `CostumeTests`
    /// — a manifest with no wardrobe dressing nobody, a costume drawn on every
    /// state the body plays, and a layer whose frame count disagrees not being
    /// drawn. One is `CostumeContractTests`, which opens every frame a declared
    /// costume names.
    /// 50 when the stations became real art: `StationContractTests
    /// .everyDeclaredStationFrameIsOnDisk` opens every file the eleven declared
    /// stations name, in every theme. The other five station contract checks are
    /// **not** gated and must not become so — they ask what the manifest
    /// declares, which is the half of this feature a fresh clone can still
    /// check.
    /// 58 with the held-object layer: eight tests in `HeldObjectTests` that
    /// need the seated frames on disk. Seven are `HeldObjectSceneTests`, which
    /// build a real `Character` — a `Character` with no art never enters a body
    /// state at all, so every rule about what is in its hands would pass
    /// vacuously without the pack. The eighth is
    /// `HeldObjectArtTests.theSeatedHandBoxIsWhereTheArtSaysItIs`, which
    /// re-derives the hand anchor from the shipped PNGs and is the measurement
    /// the whole layer stands on. `HeldObjectPolicyTests` and the other four
    /// `HeldObjectArtTests` are deliberately **not** gated: the badge-to-object
    /// mapping and the authored bitmaps are this repository's own, so a fresh
    /// clone can and should still check them.
    /// 59 with the two-row seat lattice: `RoomSceneTests
    /// .decorationIsSpreadAcrossTheRoomAndStandsAtTwoDepths` asks where the
    /// room's decorative props were *placed*, and a prop with no art on disk is
    /// never placed at all — so without the pack it would assert an empty list
    /// and pass having checked nothing. The other new composition tests
    /// (`theSeatsAlternateDepthAlongXWithoutMovingAnyColumn` and the two new
    /// blocks in `theAisleIsGuaranteedClearAtTheStationsAndNotBetweenThem`) are
    /// deliberately **not** gated: they are arithmetic over `RoomLayout`, which
    /// a fresh clone can and should still check.
    /// 65 with the ambient motion channel: six tests that need the seated frames
    /// on disk. Five are `AmbientMotionSceneTests`, which build real
    /// `Character`s — a `Character` with no art never enters a body state at
    /// all, so every rule about *how* it moves would pass vacuously without the
    /// pack. The sixth is
    /// `AmbientMotionArtTests.theSeatedLoopHoldsExactlyTwoPositions`, which
    /// re-derives from the shipped PNGs the measurement the whole channel stands
    /// on: the seated loop holds two positions, not three.
    /// `AmbientMotionPolicyTests` is deliberately **not** gated — the phrase
    /// table and the question-mark rule are this repository's own, so a fresh
    /// clone can and should still check them.
    ///
    /// 66 with `RoomSceneTests.anIdleCharacterPutsOneTextureOnScreenForever`.
    /// The logic half of that claim — `AmbientMotionTests.anIdleBodyHoldsOneFrame`
    /// — is ungated and always runs; the gated one is the same claim read off the
    /// texture the node is actually wearing, which needs the pack. The defect it
    /// pins was found in pixels, so one assertion of it lives near the pixels.
    /// `SleepBadgeTests.theDormancyTabIsNotABubble` is **not** gated for the
    /// reason it exists: the tab is drawn rather than loaded, so it is there on a
    /// checkout with no art.
    ///
    /// 69 when the badge moved beside the head: three of `BadgeSlotTests`'s five
    /// need the pack. Two build a real `Character` and read where the slot
    /// landed, which is `nil`-bodied without frames on disk; the third derives
    /// the cast's widest silhouette from the shipped PNGs, because the manifest
    /// records one head-top number per variant and the slot has to clear every
    /// frame of every state. The other two are arithmetic —
    /// `theSlotTopIsOnePixelAboveTheHighestHeadInTheCast` reads the manifest and
    /// `theSlotAndTheCountChipStayOutOfTheNeighbouringColumn` reads `RoomLayout`
    /// — so a fresh clone still checks the number this change exists to produce.
    static let expectedGatedTestCount = 69

    /// The notice, as a pure function of what was surveyed, so the two branches
    /// this machine cannot reach can still be rendered and asserted on.
    ///
    /// It was inline in `theSuiteSaysOutLoudWhetherItCheckedTheArt` until now,
    /// which meant the text that exists to make a green run unambiguous was
    /// itself unpinned: on a machine with art, the ABSENT and NO MANIFEST
    /// branches were never evaluated by anything. Mirrors
    /// `PanelFixtures.notice(survey:gated:required:)` idiom for idiom, because
    /// the two gates are meant to read the same way.
    ///
    /// Rendering a branch is not the same as proving the skip it describes —
    /// see `theAbsentNoticeSaysTheRunVerifiedNothing`, which is a text test and
    /// says so.
    static func notice(survey: Survey, gated: Int, required: Bool) -> String {
        let rule = String(repeating: "=", count: 78)
        var lines = [rule]

        if let error = survey.manifestError {
            lines.append("SPRITE ROOM ART: NO MANIFEST — \(error)")
            lines.append("  assets/manifest.json is TRACKED, so this is a broken checkout, not")
            lines.append("  the expected missing-art state. Expect further failures below.")
        } else if survey.isAvailable {
            lines.append(
                "SPRITE ROOM ART: PRESENT — all \(survey.declaredPaths) declared asset paths"
                + " resolve on disk.")
            lines.append("  \(gated) art-dependent tests RAN. The art was verified.")
        } else {
            lines.append(
                "SPRITE ROOM ART: ABSENT — \(survey.missingPaths.count) of"
                + " \(survey.declaredPaths) declared asset paths are missing.")
            lines.append(
                "  \(gated) art-dependent tests were SKIPPED."
                + " THIS RUN VERIFIED NOTHING ABOUT THE ART.")
            lines.append("  Expected on a fresh clone: assets/ is gitignored (purchased LimeZu")
            lines.append("  packs, not redistributable); only assets/manifest.json is tracked.")
            if let first = survey.missingPaths.first { lines.append("  First missing: \(first)") }
            // The notice has to know which mode it is in, exactly as
            // `PanelFixtures.notice(survey:gated:required:)` does — the two
            // gates mirror each other idiom for idiom. Printing "set this to
            // make it a failure" directly above the failure that variable has
            // just caused is the kind of line that teaches people to stop
            // reading the notice, and the notice is the whole mechanism by
            // which a green run is unambiguous.
            if required {
                lines.append("  SPRITE_ROOM_REQUIRE_ART is SET, so this is a FAILURE below.")
            } else {
                lines.append(
                    "  Set SPRITE_ROOM_REQUIRE_ART=1 to make this a failure instead of a skip.")
            }
        }
        lines.append(rule)
        return lines.joined(separator: "\n")
    }

    /// Why a `SPRITE_ROOM_REQUIRE_ART=1` run failed, as a pure function, or
    /// `nil` when it has no reason to.
    ///
    /// **The two unavailable states report separately, and that is the fix.**
    /// They shared one message until now, so a broken `assets/manifest.json`
    /// failed with "0 of 0 paths missing" — both counts are zero precisely
    /// because nothing parsed to declare a path to look for. `manifest.json` is
    /// tracked while the rest of `assets/` is gitignored, so the two states need
    /// opposite instructions: buy and place the art, versus repair a checkout.
    /// A reader given the missing-art sentence goes hunting for absent files
    /// when the file that is wrong is the one in the repository.
    static func requirementFailure(survey: Survey, required: Bool) -> String? {
        guard required, !survey.isAvailable else { return nil }
        if let error = survey.manifestError {
            return "SPRITE_ROOM_REQUIRE_ART is set and assets/manifest.json could not be"
                + " read, so no path was ever declared to look for: \(error)"
        }
        return "SPRITE_ROOM_REQUIRE_ART is set but the art is not on disk:"
            + " \(survey.missingPaths.count) of \(survey.declaredPaths) paths missing,"
            + " first \(survey.missingPaths.first ?? "unknown")"
    }
}

/// Always runs, in both modes, and never fails for the absence of art.
///
/// A gate alone would only relocate the dishonesty: a suite that goes green on
/// a machine with no art has reported success having verified nothing about it.
/// This prints which of the two runs actually happened.
struct ArtAvailabilityTests {

    @Test func theSuiteSaysOutLoudWhetherItCheckedTheArt() {
        let survey = SceneArt.survey
        let gated = SceneArt.gatedTestCount
        print(SceneArt.notice(survey: survey, gated: gated, required: SceneArt.isRequired))

        // Never a failure for absent art — that is the whole point. These two
        // are about the gate's own integrity.
        let drift = "\(gated) tests carry the art gate but"
            + " \(SceneArt.expectedGatedTestCount) were expected; update"
            + " SceneArt.expectedGatedTestCount in the same change"
        #expect(gated == SceneArt.expectedGatedTestCount, Comment(rawValue: drift))
        #expect(survey.declaredPaths > 0, "the manifest declared no asset paths at all")

        // `Issue.record` rather than `#expect(survey.isAvailable)`: the latter
        // renders the whole survey into the failure, which on a machine with no
        // art means all 1052 missing paths in one unreadable line.
        //
        // **The two unavailable states are reported separately.** They used to
        // share one message, so a broken `assets/manifest.json` — which is
        // tracked, and so is a corrupt checkout rather than the expected
        // missing-art state — failed with "0 of 0 paths missing": both counts
        // are zero precisely because nothing could be parsed to declare a path.
        // That sentence sends a reader looking for absent files when the file
        // that is wrong is the one in the repository.
        if let why = SceneArt.requirementFailure(survey: survey, required: SceneArt.isRequired) {
            Issue.record(Comment(rawValue: why))
        }
    }

    /// **The gate must walk every path the manifest declares, not most of
    /// them.** This is the assertion that was missing when `props.roles` grew an
    /// `animation` object.
    ///
    /// `role.file` is always frame 0 and is always present, so a survey that
    /// collected only `file` produced a plausible declared-path count, an
    /// `isAvailable` that said yes, and a `SPRITE_ROOM_REQUIRE_ART=1` run that
    /// passed — with frames 1..N of an animated prop free to be absent from
    /// disk. The failure mode of a gate that under-counts is not a red test; it
    /// is a green one, which is why the coverage has to be asserted rather than
    /// inferred from the count.
    ///
    /// Runs on a fresh clone: the manifest is tracked, and this asks what the
    /// survey *declared*, never what is on disk.
    @Test func theArtGateWalksEveryAnimationFrameTheManifestDeclares() throws {
        let manifest = try SceneFixtures.manifest()
        let declared = SceneArt.survey.paths
        var animatedRoles = 0
        var frames = 0

        var rooms = [manifest.room]
        rooms += manifest.themes.orderedIDs.compactMap { manifest.themes.theme($0)?.room }

        for room in rooms {
            for (name, role) in room.propRoles {
                // The membership is reduced to a `Bool` before it reaches
                // `#expect`, for the reason this file already records about
                // `survey.isAvailable`: passing the set renders all ~1500 of
                // its elements into a single unreadable failure line.
                var found = declared.contains(role.file)
                #expect(found, Comment(rawValue: "the survey missed \(name)'s frame 0"))
                guard let animation = role.animation else { continue }
                animatedRoles += 1
                frames += animation.frames.count
                for path in animation.frames {
                    found = declared.contains(path)
                    #expect(found, Comment(rawValue:
                        "the survey declared \(declared.count) paths and \(path) is not one of"
                        + " them — an animated role's frames are art like any other"))
                }
                // `file` is frame 0 by construction, which is why an
                // animation-blind reader draws something correct and why
                // nothing noticed the gap.
                #expect(animation.frames.first == role.file,
                        "\(name).file is not frame 0, so a `file`-only reader draws a mid-swing")
            }
        }

        #expect(animatedRoles > 0, Comment(rawValue:
            "no role in any theme carries an `animation`, so this test checked nothing"))
        #expect(frames > animatedRoles, "every animation is one frame long")
    }
}

/// Fixtures over mocks, same as the core tests: every scene test that needs
/// event data drives a real captured payload through the real `WorldModel`.
enum SceneFixtures {

    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SpriteRoomSceneTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static func url(_ name: String) -> URL {
        repositoryRoot.appending(path: "fixtures").appending(path: "\(name).jsonl")
    }

    static func manifest() throws -> Manifest {
        try Manifest.load(root: repositoryRoot)
    }

    /// The delta stream, batched the way the scene actually receives it: one
    /// batch per frame of fixture time, not one per event. Same-frame
    /// coalescing is a real behaviour and the tests have to exercise it.
    static func batchedDeltas(
        _ name: String, frameInterval: TimeInterval = 1.0 / 60.0
    ) async throws -> [[WorldDelta]] {
        let entries = try HookLog.load(contentsOf: url(name))
        let model = WorldModel()
        var batches: [[WorldDelta]] = []
        var current: [WorldDelta] = []
        var frameEnd: Date?

        for entry in entries {
            guard let event = entry.event else { continue }
            if let end = frameEnd, entry.receivedAt > end {
                if !current.isEmpty { batches.append(current) }
                current = []
                frameEnd = entry.receivedAt.addingTimeInterval(frameInterval)
            } else if frameEnd == nil {
                frameEnd = entry.receivedAt.addingTimeInterval(frameInterval)
            }
            current += await model.ingest(event, at: entry.receivedAt)
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    /// `batchedDeltas`, with the instant each batch belongs to.
    ///
    /// ADR-003 made the director a function of deltas *and time*, so a test that
    /// asks anything about the badge over a fixture needs the fixture's own
    /// clock rather than a made-up one. The batches are identical to
    /// `batchedDeltas`'; only the instant is added.
    static func timedBatchedDeltas(
        _ name: String, frameInterval: TimeInterval = 1.0 / 60.0
    ) async throws -> [(at: Date, deltas: [WorldDelta])] {
        let entries = try HookLog.load(contentsOf: url(name))
        let model = WorldModel()
        var batches: [(at: Date, deltas: [WorldDelta])] = []
        var current: [WorldDelta] = []
        var frameEnd: Date?
        var frameStart: Date?

        for entry in entries {
            guard let event = entry.event else { continue }
            if let end = frameEnd, entry.receivedAt > end {
                if !current.isEmpty, let start = frameStart {
                    batches.append((at: start, deltas: current))
                }
                current = []
                frameStart = entry.receivedAt
                frameEnd = entry.receivedAt.addingTimeInterval(frameInterval)
            } else if frameEnd == nil {
                frameStart = entry.receivedAt
                frameEnd = entry.receivedAt.addingTimeInterval(frameInterval)
            }
            current += await model.ingest(event, at: entry.receivedAt)
        }
        if !current.isEmpty, let start = frameStart {
            batches.append((at: start, deltas: current))
        }
        return batches
    }

    /// Replays a fixture **at its own pace** against a scene, stepping the
    /// scene clock a frame at a time and delivering each event as its
    /// `_receivedAt` passes.
    ///
    /// This is the same loop the offscreen render harness runs, and it is the
    /// only honest way to test anything phrased as "at real time": compressing
    /// the event stream against a slower animation clock manufactures
    /// coincidences — two characters in one spot — that could not happen in a
    /// real replay, and then fails on them.
    ///
    /// `tail` keeps stepping after the last event so exit walks finish.
    @MainActor
    static func replayInFixtureTime(
        _ name: String,
        into scene: RoomScene,
        director: SceneDirector,
        step: TimeInterval = 1.0 / 60.0,
        tail: TimeInterval = 10,
        onFrame: (TimeInterval) -> Void
    ) async throws -> SceneDirector {
        var director = director
        let entries = try HookLog.load(contentsOf: url(name))
        guard let origin = entries.first?.receivedAt,
              let end = entries.last?.receivedAt else { return director }
        let duration = end.timeIntervalSince(origin) + tail

        var index = entries.startIndex
        var pending: [WorldDelta] = []
        var time = 0.0

        while time <= duration {
            let cutoff = origin.addingTimeInterval(time)
            while index < entries.endIndex, entries[index].receivedAt <= cutoff {
                if let event = entries[index].event {
                    pending += await scene.modelForReplay.ingest(event, at: entries[index].receivedAt)
                }
                index += 1
            }
            // Unguarded, exactly as `SceneBinding.apply` and the offscreen
            // renderer are: the director is a function of deltas *and time* as
            // of ADR-003, and a closing beat ends on a frame that carries
            // nothing. `cutoff` is the fixture instant, so a beat lasts 500 ms
            // of fixture time here rather than 500 ms of however long the test
            // machine took.
            scene.apply(director.apply(pending, at: cutoff))
            pending.removeAll(keepingCapacity: true)
            scene.advance(to: time)
            onFrame(time)
            time += step
        }
        return director
    }
}

extension SceneDirector {

    /// A **frozen** instant, for the tests that predate ADR-003's closing beat.
    ///
    /// `apply` takes a clock now. Most tests in this suite are about seats,
    /// variants, stations, costumes, nameplates or props and have nothing to say
    /// about time; giving each of them a hand-rolled clock would be noise, and
    /// giving them `Date()` would make them flaky — a beat armed inside a test
    /// that happens to take longer than 500 ms would expire, and one inside a
    /// faster test would not.
    ///
    /// So the shim below freezes time instead. It is deliberately **not** a way
    /// to switch the beat off: a beat armed under a frozen clock is armed, and
    /// stays up, so any test whose expectations ADR-003 actually changed fails
    /// loudly rather than quietly keeping its old answer. Tests that are *about*
    /// the beat — and every test that measures badge changes over a fixture —
    /// call `apply(_:at:)` with a real, advancing instant.
    static let frozenTestInstant = Date(timeIntervalSinceReferenceDate: 0)

    @discardableResult
    mutating func apply(_ deltas: [WorldDelta]) -> [SpriteIntent] {
        apply(deltas, at: Self.frozenTestInstant)
    }
}

/// One `WorldModel` per scene, for the replay helper above. The scene never
/// reaches into it — the model is driven by the test and only deltas cross.
@MainActor
private var replayModels: [ObjectIdentifier: WorldModel] = [:]

@MainActor
extension RoomScene {
    var modelForReplay: WorldModel {
        let key = ObjectIdentifier(self)
        if let existing = replayModels[key] { return existing }
        let model = WorldModel()
        replayModels[key] = model
        return model
    }
}
