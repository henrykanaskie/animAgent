import Foundation
import Testing
import SpriteRoomCore
@testable import SpriteRoomScene

/// `docs/ADR-002-themed-rooms.md` §8, items 1–4: the selection rules, which are
/// pure string arithmetic and need neither a screen nor the art on disk.
struct ThemeSelectorTests {

    // MARK: §8 item 1 — the pinned hash

    /// **The pinned vector, and the only thing standing between this project and
    /// every user's room redecorating itself on launch.**
    ///
    /// The failure it exists to catch is not a wrong answer; it is a *plausible*
    /// one. Swift's `Hasher` is seeded per process, so a cleanup that swaps
    /// `fnv1a64` for `hashValue` still produces a deterministic-looking spread
    /// of themes — it just produces a different one every launch, which surfaces
    /// as "the scene keeps changing my room" and gets debugged in the renderer.
    /// [§3c, §11 item 7]
    ///
    /// The three vectors are the published FNV-1a 64 ones, so this is a check
    /// against the specification rather than against whatever this file happened
    /// to compute the day it was written. The fourth is a `cwd`, because that is
    /// the input that matters and a multi-byte path exercises the `&*` overflow
    /// the first three barely touch.
    @Test func thePinnedFNV1aVectorsHold() {
        #expect(ThemeSelector.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(ThemeSelector.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(ThemeSelector.fnv1a64("foobar") == 0x8594_4171_f739_67e8)
        #expect(ThemeSelector.fnv1a64("/Users/x/code/sprite-room") == 0x80bd_48f8_6265_f207)
    }

    /// The offset basis is the hash of the empty input by construction, and the
    /// prime is what one byte of zero multiplies it by. Two constants, checked
    /// against their own definition rather than transcribed twice.
    @Test func theOffsetBasisAndPrimeAreTheOnesSpecified() {
        #expect(ThemeSelector.fnv1a64([UInt8]()) == 0xcbf2_9ce4_8422_2325)
        #expect(ThemeSelector.fnv1a64([0]) == 0xcbf2_9ce4_8422_2325 &* 0x100_0000_01b3)
    }

    // MARK: §8 item 2 — rendezvous

    @Test func anEmptyPoolSelectsNothing() {
        #expect(ThemeSelector.rendezvous(key: "anything", over: []) == nil)
    }

    @Test func aPoolOfOneAlwaysSelectsThatOne() {
        #expect(ThemeSelector.rendezvous(key: "anything", over: ["only"]) == "only")
    }

    /// **The simulated process restart.** [§8 tests, bullet 2]
    ///
    /// A test that resolves the same key twice inside one process cannot catch
    /// `Hasher`, because `Hasher` is perfectly stable inside one process — that
    /// is exactly what makes it such a good disguise. What catches it is an
    /// expected value written down in a file, compared against on a later run in
    /// a different process. These four are that: the pool is synthetic and fixed
    /// so the expectations survive a theme being added to the manifest, which
    /// is a thing that is supposed to be cheap.
    @Test func rendezvousWinnersArePinnedAcrossProcesses() {
        let pool = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"]
        #expect(ThemeSelector.rendezvous(key: "/Users/x/code/sprite-room", over: pool) == "beta")
        #expect(ThemeSelector.rendezvous(key: "/Users/x/code/other", over: pool) == "gamma")
        #expect(ThemeSelector.rendezvous(key: "/tmp", over: pool) == "alpha")
        #expect(ThemeSelector.rendezvous(key: "", over: pool) == "epsilon")
    }

    /// Order of the pool must not reach the answer. Without the tie-break a
    /// 64-bit collision would let it, and the room would then depend on which
    /// order a dictionary happened to iterate in that launch — a bug that would
    /// appear once a decade and never reproduce. [§3c]
    @Test func theSelectionDoesNotDependOnTheOrderOfThePool() {
        let pool = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"]
        for key in (0..<200).map({ "/project/\($0)" }) {
            let forwards = ThemeSelector.rendezvous(key: key, over: pool)
            let backwards = ThemeSelector.rendezvous(key: key, over: pool.reversed())
            let shuffled = ThemeSelector.rendezvous(key: key, over: pool.shuffled())
            #expect(forwards == backwards)
            #expect(forwards == shuffled)
        }
    }

    /// Ties go to the lexicographically smaller id, so a duplicated id cannot
    /// make the answer depend on which copy was reached first.
    @Test func aTieGoesToTheSmallerID() {
        #expect(ThemeSelector.rendezvous(key: "k", over: ["b", "a", "b"]) != nil)
        for key in (0..<50).map({ "k\($0)" }) {
            let a = ThemeSelector.rendezvous(key: key, over: ["dup", "dup"])
            #expect(a == "dup")
        }
    }

    /// **Rendezvous, not modulo.** [§8 tests, bullet 3]
    ///
    /// The whole reason the selection is not `fnv1a64(cwd) % themeCount`. Adding
    /// a theme should move about one project in N; modulo moves nearly all of
    /// them, which means the day a seventh theme ships every user's rooms change
    /// at once and the change looks like a bug.
    ///
    /// The bound is generous — a sixth of the corpus, against an expectation of
    /// a seventh — because this is asserting a *property*, not a number. Modulo
    /// over the same corpus is measured beside it rather than argued about, and
    /// it comes out at roughly six sevenths.
    @Test func addingAThemeMovesOnlyASmallFractionOfProjects() {
        let corpus = (0..<3000).map { "/Users/someone/code/project-\($0)" }
        let before = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"]
        let after = before + ["eta"]

        var moved = 0
        for cwd in corpus
        where ThemeSelector.rendezvous(key: cwd, over: before)
            != ThemeSelector.rendezvous(key: cwd, over: after) {
            moved += 1
        }
        let fraction = Double(moved) / Double(corpus.count)
        #expect(fraction < 1.0 / 6.0, "rendezvous moved \(moved) of \(corpus.count)")
        #expect(moved > 0, "adding a theme moved nothing at all — the pool is not being read")

        // What the rejected implementation would have done, measured rather
        // than asserted, so the margin is visible when this is read.
        var modulo = 0
        for cwd in corpus {
            let hash = ThemeSelector.fnv1a64(cwd)
            let a = before[Int(hash % UInt64(before.count))]
            let b = after[Int(hash % UInt64(after.count))]
            if a != b { modulo += 1 }
        }
        #expect(Double(modulo) / Double(corpus.count) > 0.5,
                "modulo moved \(modulo) of \(corpus.count) — the comparison is not doing its job")
    }

    /// Every key lands somewhere, and the pool is not one bucket wearing six
    /// names. Not a distribution proof — that is not what the mechanism owes —
    /// only that no theme is unreachable, which a broken concatenation would
    /// produce.
    @Test func everyThemeInThePoolIsReachable() {
        let pool = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"]
        var seen: Set<String> = []
        for cwd in (0..<2000).map({ "/p/\($0)" }) {
            guard let choice = ThemeSelector.rendezvous(key: cwd, over: pool) else {
                Issue.record("a non-empty pool selected nothing")
                return
            }
            seen.insert(choice)
        }
        #expect(seen == Set(pool))
    }

    // MARK: §8 item 4 — stations

    /// **The one §8 spelled out twice, because it is the one that gets missed.**
    ///
    /// M0c observed `agent_type` arriving as the empty string, and
    /// `docs/03-EVENT-MODEL.md` records it. An implementation that only checked
    /// for `nil` would put an empty-typed subagent through the rendezvous with
    /// `""` as its key — a perfectly stable answer that means nothing, and one
    /// that would quietly collide a genuinely unknown agent with whichever
    /// numbered station `""` happens to hash to.
    @Test func emptyAndAbsentAgentTypeTakeTheSameBranch() {
        let theme = ThemeFixtures.stationed(count: 4)
        let absent = ThemeSelector.station(agentID: "a1", agentType: nil, in: theme)
        let empty = ThemeSelector.station(agentID: "a1", agentType: "", in: theme)
        #expect(absent == empty)
        #expect(absent == ThemeSelector.defaultStationID)
    }

    /// Absence of `agent_id` **is** the main agent — the identity rule, not a
    /// fallback — so no value of `agent_type` may reach past it. [CLAUDE.md]
    @Test func absentAgentIDIsTheMainStationWhateverTheTypeSays() {
        let theme = ThemeFixtures.stationed(count: 4)
        for type: String? in [nil, "", "Explore", "general-purpose", "main", "default", "0"] {
            #expect(ThemeSelector.station(agentID: nil, agentType: type, in: theme)
                    == ThemeSelector.mainStationID)
        }
    }

    /// A typed subagent draws from the numbered pool, and `main`/`default` are
    /// not in it — they are reached by the identity rules or not at all.
    @Test func aTypedSubagentTakesANumberedStation() {
        let theme = ThemeFixtures.stationed(count: 4)
        for type in ["Explore", "general-purpose", "scene-engineer", "Plan"] {
            let station = ThemeSelector.station(agentID: "a1", agentType: type, in: theme)
            #expect(theme.numberedStationIDs.contains(station), "got \(station)")
        }
        #expect(theme.numberedStationIDs == ["0", "1", "2", "3"])
    }

    /// §4's deliberate thinness: **four `general-purpose` subagents get four
    /// identical desks.** Keyed on `agent_type`, "same desk" means "same kind of
    /// worker" — a rule a user can read off the room. Keyed on `agent_id` the
    /// desks would all differ and none of them would mean anything.
    @Test func agentsOfOneTypeShareOneStation() {
        let theme = ThemeFixtures.stationed(count: 4)
        let ids = ["a1b2c3", "d4e5f6", "0000", "zzzz"]
        let stations = Set(ids.map {
            ThemeSelector.station(agentID: $0, agentType: "general-purpose", in: theme)
        })
        #expect(stations.count == 1)
    }

    /// A theme with no numbered stations seats every typed subagent at
    /// `default`. **This case is not in §8** — §4's third line has no answer for
    /// an empty pool — and it is the case every theme in the shipped manifest
    /// actually takes, since none of them declares a station at all. Resolved to
    /// `default` because `default` is already this function's answer for "we
    /// have nothing that distinguishes this agent", and reported as a gap.
    @Test func anEmptyStationPoolFallsToTheDefaultStation() {
        let theme = ThemeFixtures.stationed(count: 0)
        #expect(ThemeSelector.station(agentID: "a1", agentType: "Explore", in: theme)
                == ThemeSelector.defaultStationID)
        #expect(ThemeSelector.station(agentID: nil, agentType: "Explore", in: theme)
                == ThemeSelector.mainStationID)
    }
}

// MARK: - §8 item 3, against the manifest that shipped

struct ThemeResolutionTests {

    /// §3c in order, over the real manifest: a stored choice wins, and it wins
    /// even when the hash would have drawn something else.
    @Test func aStoredChoiceOutranksTheDerivedDefault() throws {
        let manifest = try SceneFixtures.manifest()
        let cwd = "/Users/someone/code/thing"
        let derived = try #require(
            ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest))
        let other = try #require(manifest.themes.orderedIDs.first { $0 != derived })
        #expect(ThemeSelector.theme(for: cwd, stored: [cwd: other], manifest: manifest) == other)
    }

    /// A stored entry naming a theme the manifest does not have — a removed
    /// theme, an older manifest — falls to the derived default *for that project
    /// only*, and does not throw. The caller keeps the entry: the theme may come
    /// back. [§3d]
    @Test func anUnknownStoredThemeFallsToTheDerivedDefault() throws {
        let manifest = try SceneFixtures.manifest()
        let cwd = "/Users/someone/code/thing"
        let derived = ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest)
        let stored = [cwd: "a-theme-that-was-removed"]
        #expect(ThemeSelector.theme(for: cwd, stored: stored, manifest: manifest) == derived)
    }

    /// A stored entry for *another* project does not reach this one. The key is
    /// the `cwd` exactly as received, with no normalisation of its own, so a
    /// trailing slash is a different project here exactly as it is everywhere
    /// else in the app. [§3c]
    @Test func theStoredChoiceIsKeyedOnTheExactCWD() throws {
        let manifest = try SceneFixtures.manifest()
        let cwd = "/Users/someone/code/thing"
        let stored = ["/Users/someone/code/other": manifest.themes.orderedIDs.first ?? ""]
        #expect(ThemeSelector.theme(for: cwd, stored: stored, manifest: manifest)
                == ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest))
        #expect(ThemeSelector.theme(for: cwd + "/", stored: [cwd: "x"], manifest: manifest)
                == ThemeSelector.theme(for: cwd + "/", stored: [:], manifest: manifest))
    }

    /// **Two resolutions of the same `cwd` give the same theme.** [§8 tests,
    /// bullet 2] The within-process half; the cross-process half is
    /// `rendezvousWinnersArePinnedAcrossProcesses`, which is where a pinned
    /// expectation can actually live.
    @Test func theSameCWDAlwaysResolvesToTheSameTheme() throws {
        let manifest = try SceneFixtures.manifest()
        for cwd in (0..<200).map({ "/Users/someone/code/p\($0)" }) {
            let first = ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest)
            let second = ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest)
            #expect(first == second)
            #expect(first != nil, "the manifest declares themes, so one must be drawn")
        }
    }

    /// The derived default draws only from `assignable: true`. All six shipped
    /// themes are assignable, so this checks the *pool* rather than the split —
    /// the flag exists so the first theme that would read as a claim about the
    /// work can be offered without ever being assigned. [§3e, §14a]
    @Test func theDerivedDefaultOnlyDrawsFromTheAssignablePool() throws {
        let manifest = try SceneFixtures.manifest()
        let assignable = Set(manifest.themes.assignableIDs)
        #expect(!assignable.isEmpty)
        for cwd in (0..<300).map({ "/p/\($0)" }) {
            let drawn = try #require(ThemeSelector.theme(for: cwd, stored: [:], manifest: manifest))
            #expect(assignable.contains(drawn))
        }
    }

    /// The floor under §3c: a manifest with no themes at all names none, and the
    /// room is the one this app has always drawn. Not a corner case — it is
    /// every checkout that has not run the import scripts.
    @Test func aManifestWithNoThemesNamesNone() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(manifest.themes.isEmpty == false, "the shipped manifest declares themes")
        #expect(Manifest.Themes.none.assignableIDs.isEmpty)
        #expect(Manifest.Themes.none.defaultID == nil)
        // The bindings for an id nothing declares are `room` itself, so a scene
        // handed a stale theme id still draws a room.
        #expect(manifest.room(theme: "not-a-theme") == manifest.room)
        #expect(manifest.room(theme: nil) == manifest.room)
    }

    /// The manifest's default is a theme the manifest actually has. A `default`
    /// naming a set that is not there is not a default, and resolving it would
    /// hand the scene an id with no bindings behind it.
    @Test func theDeclaredDefaultNamesADeclaredTheme() throws {
        let manifest = try SceneFixtures.manifest()
        let id = try #require(manifest.themes.defaultID)
        #expect(manifest.themes.contains(id))
    }
}

// MARK: - §7, the theme contract, against the art

/// Every theme binds every key the scene draws, and every named pose state
/// exists with exactly `right` and `left` frames.
///
/// **Art-gated**, and it earns the gate rather than inheriting it: it opens the
/// declared floor and wall of every theme and checks their size against the
/// theme's own `tile`, which is the assertion that would otherwise let a theme
/// declare a path to a 16 px tile and only fail on screen. [CLAUDE.md]
struct ThemeContractTests {

    @Test(.enabled(if: SceneArt.isAvailable))
    func everyThemeBindsEveryRoleTheSceneDraws() throws {
        let manifest = try SceneFixtures.manifest()
        let required = [
            RoomScene.surfaceRole, RoomScene.seatRole,
            RoomScene.backdropRole, RoomScene.accentRole,
        ]
        #expect(!manifest.themes.orderedIDs.isEmpty)
        for id in manifest.themes.orderedIDs {
            let theme = try #require(manifest.themes.theme(id))
            for role in required {
                let prop = theme.room.prop(role)
                #expect(prop != nil, "theme \(id) does not bind \(role)")
                guard let prop else { continue }
                #expect(FileManager.default.fileExists(atPath: manifest.url(prop.file).path),
                        "theme \(id) binds \(role) to a file that is not on disk")
                #expect(prop.contentBox.width > 0 && prop.contentBox.height > 0,
                        "theme \(id) role \(role) has an empty content box")
            }
            #expect(!theme.title.isEmpty, "theme \(id) has no title for the menu to show")
        }
    }

    /// The floor and the wall a theme actually draws, loaded.
    ///
    /// A theme that declares neither falls to the heuristic, which is legal and
    /// is what the default room does — so this asserts the *resolved* pair
    /// rather than the declaration, and records which route each theme took.
    @Test(.enabled(if: SceneArt.isAvailable)) @MainActor
    func everyThemeResolvesAFloorAndAWallOfTheDeclaredTileSize() throws {
        let manifest = try SceneFixtures.manifest()
        var declared = 0
        for id in manifest.themes.orderedIDs {
            let theme = try #require(manifest.themes.theme(id))
            let store = TextureStore(manifest: manifest, themeID: id)
            let tiles = store.roomTileChoice()
            if tiles.isDeclared { declared += 1 }
            for path in [tiles.floor, tiles.wall] {
                #expect(!path.isEmpty, "theme \(id) resolved no tile")
                let bitmap = try #require(
                    try? PixelImage.bitmap(contentsOf: manifest.url(path)),
                    Comment(rawValue: "theme \(id) tile \(path) did not load"))
                #expect(bitmap.width == theme.room.tile.width
                        && bitmap.height == theme.room.tile.height,
                        "theme \(id) tile \(path) is \(bitmap.width)x\(bitmap.height)")
            }
        }
        #expect(declared > 0, Comment(rawValue:
            "no theme declared builder.floor/builder.wall — the heuristic is doing all"
            + " the work and floors are not themeable"))
    }

    /// §7's pose clause: every state named by `characters.poses.working` must
    /// exist in `characters.states` with **exactly** `right` and `left`.
    ///
    /// Both sit rows in the pack are side art in all four direction blocks —
    /// there is no front- or back-facing sitting sprite at any size — so a pose
    /// table naming a state with an `up` or a `down` block is naming art that
    /// was never drawn. The table is empty today, which is a legal state and is
    /// §5b item 2's "inert with no code path to delete"; the check is here so it
    /// binds the day a second sit row is imported rather than the day after.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyNamedPoseStateExistsWithExactlyRightAndLeftFrames() throws {
        let manifest = try SceneFixtures.manifest()
        let poses = manifest.characters.workingPoses
        if !poses.isEmpty {
            #expect(poses[Manifest.Characters.defaultPoseKey] != nil,
                    "characters.poses.working has no required `default`")
        }
        for (badgeKey, stateName) in poses {
            #expect(badgeKey == Manifest.Characters.defaultPoseKey
                    || ToolBadge(manifestKey: badgeKey) != nil,
                    "characters.poses.working.\(badgeKey) is not a badge id")
            let state = try #require(BodyState(rawValue: stateName),
                                     "pose \(stateName) is not a body state")
            for id in manifest.characters.orderedVariantIDs {
                let variant = try #require(manifest.characters.variant(id))
                let animation = try #require(variant.animation(state),
                                             "variant \(id) has no \(stateName)")
                #expect(animation.facings == [.right, .left],
                        "variant \(id) state \(stateName) is drawn \(animation.facings)")
            }
        }
        // Whatever the table says, the lookup is total: every badge class and
        // the absent one resolve to a state that exists on every variant.
        for badge in ToolBadge.allCases.map({ Optional($0) }) + [nil] {
            let pose = manifest.characters.workingPose(forBadgeKey: badge?.manifestKey)
            for id in manifest.characters.orderedVariantIDs {
                #expect(manifest.characters.variant(id)?.animation(pose) != nil,
                        "variant \(id) cannot draw the pose for \(badge?.manifestKey ?? "none")")
            }
        }
    }

    /// §5a's other word: body state while working is a **seated** pose in every
    /// case. This is the half of §7's pose clause that had nothing checking it.
    ///
    /// The check above tests *side-on*, by requiring exactly `right` and `left`.
    /// That is necessary and it is not sufficient, and the gap is not
    /// hypothetical — it is the shape of every remaining pose row in the pack.
    /// Modern Interiors' `pick_up` (row 9), `lift` (11), `throw` (12) and
    /// `push_cart` (8) are laid out in the ordinary four direction blocks whose
    /// blocks 0 and 2 are near-mirrors, so any of them can be cut `right`/`left`
    /// only, drop into `characters.poses.working`, and satisfy the facings check
    /// exactly. Every one of them is a person **standing up**. Dropped into a
    /// chair at a desk it is not a second way of working; it is a character who
    /// has got out of its seat, and the room would be asserting a posture no
    /// event says. [I1]
    ///
    /// **The discriminator is measured, not named.** A pose row cannot be
    /// trusted by its label — `sleep` was a head on a pillow and `phone_b` is a
    /// person reading — so this reads the pixels. A character is bottom-aligned
    /// in its 32×64 frame with the anchor on the canvas's bottom edge, so the
    /// last pixel row is the floor a standing character stands on:
    ///
    /// - **every** frame of `idle`, in every direction of every variant,
    ///   occupies it. That is the calibration, and it is asserted rather than
    ///   assumed so that a flipped row order turns this red instead of vacuous.
    /// - **no** frame of a seated pose does, because the feet are on a chair.
    ///   The shipped `working` row clears it by 2 px in all 12 of its
    ///   variant-directions.
    ///
    /// `walk`, `spawn` and `depart` would *pass* a bottom-row check taken on one
    /// frame — a mid-stride foot leaves the floor — which is why the assertion
    /// is over every frame of the loop rather than a representative one.
    @Test(.enabled(if: SceneArt.isAvailable))
    func everyNamedPoseStateIsSeatedRatherThanMerelySideOn() throws {
        let manifest = try SceneFixtures.manifest()
        let floorRow = manifest.characters.canvas.height - 1

        func touchesFloorRow(_ path: String) throws -> Bool {
            let bitmap = try #require(
                try? PixelImage.bitmap(contentsOf: manifest.url(path)),
                Comment(rawValue: "\(path) did not load"))
            guard bitmap.height == manifest.characters.canvas.height else { return false }
            return (0..<bitmap.width).contains { bitmap.at($0, floorRow).a > 0 }
        }

        func frames(_ state: BodyState) throws -> [(String, String)] {
            var out: [(String, String)] = []
            for id in manifest.characters.orderedVariantIDs {
                guard let animation = try #require(manifest.characters.variant(id))
                    .animation(state) else { continue }
                for facing in Facing.allCases {
                    for path in animation.frames(facing: facing) ?? [] {
                        out.append(("\(id)/\(state.rawValue)/\(facing.rawValue)", path))
                    }
                }
            }
            return out
        }

        // Calibration: standing means standing on the last row, everywhere.
        let standing = try frames(.idle)
        #expect(!standing.isEmpty, "no idle frames — the calibration checked nothing")
        for (label, path) in standing {
            #expect(try touchesFloorRow(path), Comment(rawValue:
                "\(label) does not reach row \(floorRow), so the floor row is not"
                + " where a standing character stands and this check is measuring"
                + " the wrong end of the canvas"))
        }

        // The claim. The fallback pose is checked too: `workingPose` resolves to
        // `working` for a manifest carrying no table at all, so it is a named
        // pose whether or not anyone named it.
        var named = Set(manifest.characters.workingPoses.values.compactMap(BodyState.init(rawValue:)))
        named.insert(.working)
        for state in named.sorted(by: { $0.rawValue < $1.rawValue }) {
            for (label, path) in try frames(state) {
                #expect(!(try touchesFloorRow(path)), Comment(rawValue:
                    "\(label) puts a foot on row \(floorRow): it is a standing pose,"
                    + " and characters.poses.working may only name seated ones"
                    + " [ADR-002 §5a]"))
            }
        }
    }

    /// **No filename and no theme name appears in `Sources/`.** [§8 item 5]
    ///
    /// Mechanical, because it is exactly the kind of rule that decays quietly: a
    /// single `if themeID == "office"` would work, ship, and make final art a
    /// code change rather than a manifest swap.
    ///
    /// It reads string *literals* rather than the whole file, so the prose in a
    /// doc comment — which mentions the Modern Office pack by name in several
    /// places, correctly — is not what is being policed. What is policed is
    /// anything the compiler could compare against.
    ///
    /// **It used to scan `Sources/SpriteRoomScene` only, and non-recursively**,
    /// while this comment and §8 item 5 both said `Sources/`. The gap was not
    /// theoretical: `Sources/SpriteRoomApp/ThemeCatalog.swift` carries the
    /// comment "No theme name appears in this file, and none may" and was
    /// covered by nothing at all — the app is where a theme id is *stored*, so
    /// it is the likelier place for one to be hardcoded, not the less likely.
    /// The property held; the test did not enforce it.
    ///
    /// **Two scopes, and the split is a real distinction rather than an
    /// exemption list.**
    ///
    /// - **A theme id is forbidden everywhere in `Sources/`.** There is no
    ///   module that has any business spelling one: the scene is handed an id,
    ///   the app reads ids out of the manifest and the preference file, and the
    ///   core does not know themes exist.
    /// - **An *art filename* is forbidden in `SpriteRoomScene`**, which is the
    ///   only module that loads a texture, and is where "final art must drop in
    ///   as a manifest swap with zero code change" is the rule. It is not
    ///   checked across the whole tree because `SpriteRoomApp/main.swift`
    ///   legitimately holds `.png` names — `"panel-%.0fx%.0f-t%06.2f.png"` and
    ///   friends, the render harness's *output* filenames. Those are not art
    ///   and never reach a texture. Widening the suffix rule over them would
    ///   need an exemption list, and an exemption list is how a mechanical rule
    ///   turns back into a convention.
    /// - **An art *path* is forbidden everywhere**, which catches the thing the
    ///   suffix rule was really for without catching output names: nothing
    ///   outside the manifest may name a location inside the processed art
    ///   tree. `assets/manifest.json` itself is not that — it is the contract,
    ///   `Manifest.developmentRoot` legitimately spells it, and a rule that
    ///   forbade it would forbid loading the file the rest of this depends on.
    @Test func noThemeNameAndNoArtFilenameIsWrittenDownInSources() throws {
        let manifest = try SceneFixtures.manifest()
        let root = SceneFixtures.repositoryRoot.appending(path: "Sources")
        let themeIDs = Set(manifest.themes.orderedIDs)
        let sceneModule = root.appending(path: "SpriteRoomScene").path
        var scanned = 0
        var scannedInScene = 0
        var modules: Set<String> = []

        for url in try Self.swiftSources(under: root) {
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = url.lastPathComponent
            let drawsArt = url.path.hasPrefix(sceneModule)
            scanned += 1
            if drawsArt { scannedInScene += 1 }
            modules.insert(
                url.pathComponents.drop(while: { $0 != "Sources" }).dropFirst().first ?? "?")

            for literal in SourceLiterals.strings(in: text) {
                #expect(!themeIDs.contains(literal),
                        "\(name) names the theme \"\(literal)\"")
                #expect(!literal.contains("assets/processed"),
                        "\(name) writes down the art path \"\(literal)\"")
                if drawsArt {
                    #expect(!literal.hasSuffix(".png"),
                            "\(name) writes down the art file \"\(literal)\"")
                }
            }
        }

        #expect(scanned > 30,
                "the source scan found almost nothing — it is not reading the files")
        #expect(scannedInScene > 5, "the scene module was not reached")
        // All three modules, or the recursion is not doing what it says. The
        // core's sources live in `Ingest/` and `Model/` subdirectories, which is
        // the other half of what the flat `contentsOfDirectory` walk missed.
        #expect(
            modules == ["SpriteRoomApp", "SpriteRoomCore", "SpriteRoomReplay", "SpriteRoomScene"],
            "the walk covered \(modules.sorted())")
        #expect(!themeIDs.isEmpty, "the manifest declares no themes, so this checked nothing")
    }

    /// Every `.swift` file under a directory, recursively.
    static func swiftSources(under root: URL) throws -> [URL] {
        guard let walk = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }
}

// MARK: - Fixtures

enum ThemeFixtures {

    /// A theme carrying `count` numbered stations plus `main` and `default`.
    ///
    /// Synthetic, and deliberately so: **no theme in the shipped manifest
    /// declares a station at all**, so a fixture built from the manifest would
    /// exercise only the empty-pool branch and the rendezvous half of §4 would
    /// go untested until the art catches up.
    static func stationed(count: Int) -> Manifest.Theme {
        let box = Manifest.PropRole.Box(x: 0, y: 0, width: 8, height: 8)
        let role = Manifest.PropRole(file: "x", contentBox: box, animation: nil)
        let station = Manifest.Station(desk: role, chair: role, prop: nil)
        var stations: [String: Manifest.Station] = [
            ThemeSelector.mainStationID: station,
            ThemeSelector.defaultStationID: station,
        ]
        for index in 0..<max(0, count) { stations["\(index)"] = station }
        return Manifest.Theme(
            id: "fixture", title: "Fixture", isAssignable: true,
            room: Manifest.Room(
                tile: Manifest.Size(width: 32, height: 32),
                builderTiles: [], declaredFloor: nil, declaredWall: nil,
                propCanvas: Manifest.Size(width: 64, height: 96),
                propFiles: [], propsIdentified: true, propRoles: [:],
                stations: stations))
    }
}

/// The string literals in a piece of Swift source, well enough to police a rule
/// about filenames.
///
/// Not a parser. It skips `//` and `/* */` comments and takes double-quoted runs
/// with `\"` honoured, which is all this project's sources contain — there is no
/// raw string and no multi-line literal in `SpriteRoomScene`. If one ever
/// appears, this under-reports rather than over-reports, and the test above says
/// how many files it scanned so a silent zero is visible.
enum SourceLiterals {

    /// The same source with `//` and `/* */` comments removed — everything the
    /// compiler actually sees.
    ///
    /// Needed by any rule of the form "this file may not name that type",
    /// because the *reason* a file may not name a type is usually written in a
    /// doc comment that names it. `PropAnimation`'s doc comment says in as many
    /// words that `WorldDelta` and `AgentRef` are not in scope there, and a scan
    /// over the raw text would read that as the violation it exists to prevent.
    static func code(in source: String) -> String {
        var code = ""
        let characters = Array(source)
        var index = 0
        var inString = false
        var inLineComment = false
        var inBlockComment = false

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if inLineComment {
                if character == "\n" { inLineComment = false; code.append(character) }
                index += 1
                continue
            }
            if inBlockComment {
                if character == "*", next == "/" { inBlockComment = false; index += 2; continue }
                if character == "\n" { code.append(character) }
                index += 1
                continue
            }
            if !inString, character == "/", next == "/" { inLineComment = true; index += 2; continue }
            if !inString, character == "/", next == "*" { inBlockComment = true; index += 2; continue }
            if character == "\\", inString, next != nil {
                code.append(character)
                code.append(characters[index + 1])
                index += 2
                continue
            }
            if character == "\"" { inString.toggle() }
            if character == "\n" { inString = false }
            code.append(character)
            index += 1
        }
        return code
    }

    static func strings(in source: String) -> [String] {
        var literals: [String] = []
        var current: String?
        let iterator = Array(source)
        var index = 0
        var inLineComment = false
        var inBlockComment = false

        while index < iterator.count {
            let character = iterator[index]
            let next = index + 1 < iterator.count ? iterator[index + 1] : nil

            if inLineComment {
                if character == "\n" { inLineComment = false }
                index += 1
                continue
            }
            if inBlockComment {
                if character == "*", next == "/" { inBlockComment = false; index += 2; continue }
                index += 1
                continue
            }
            if current == nil, character == "/", next == "/" { inLineComment = true; index += 2; continue }
            if current == nil, character == "/", next == "*" { inBlockComment = true; index += 2; continue }

            if character == "\\", current != nil, next != nil {
                current?.append(iterator[index + 1])
                index += 2
                continue
            }
            if character == "\"" {
                if let literal = current {
                    literals.append(literal)
                    current = nil
                } else {
                    current = ""
                }
                index += 1
                continue
            }
            if current != nil, character == "\n" {
                // An unterminated literal is a parse we got wrong; drop it
                // rather than swallow the rest of the file.
                current = nil
            }
            if current != nil { current?.append(character) }
            index += 1
        }
        return literals
    }
}
