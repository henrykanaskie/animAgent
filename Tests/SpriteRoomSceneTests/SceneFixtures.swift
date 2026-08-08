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
        /// Distinct manifest-relative paths declared.
        var declaredPaths: Int = 0
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
        for (_, art) in manifest.badges.map { declared.insert(art.file) }
        for (_, art) in manifest.badges.states { declared.insert(art.file) }
        declared.formUnion(manifest.room.builderTiles)
        declared.formUnion(manifest.room.propFiles)
        for (_, role) in manifest.room.propRoles { declared.insert(role.file) }

        survey.declaredPaths = declared.count
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
    static let expectedGatedTestCount = 24
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
            lines.append("  Set SPRITE_ROOM_REQUIRE_ART=1 to make this a failure instead of a skip.")
        }
        lines.append(rule)
        print(lines.joined(separator: "\n"))

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
        if SceneArt.isRequired && !survey.isAvailable {
            let why = "SPRITE_ROOM_REQUIRE_ART is set but the art is not on disk:"
                + " \(survey.missingPaths.count) of \(survey.declaredPaths) paths missing,"
                + " first \(survey.missingPaths.first ?? survey.manifestError ?? "unknown")"
            Issue.record(Comment(rawValue: why))
        }
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
            if !pending.isEmpty {
                scene.apply(director.apply(pending))
                pending.removeAll(keepingCapacity: true)
            }
            scene.advance(to: time)
            onFrame(time)
            time += step
        }
        return director
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
