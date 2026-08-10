import Foundation
import Testing
@testable import SpriteRoomScene

/// ADR-006 SS1, SS2c, SS2d — the desk-top object *declarations* only.
///
/// This step draws nothing and binds nothing: no `SceneDirector` code reads
/// `room.props.roles.laptop`, `.papers` or `.pad`, exactly as `DeskSurfaceTests`
/// pins that nothing read `surface_y` at its own step. What exists after it is
/// three more entries in `room.props.roles`, in the same `{file, content_box}`
/// shape `desk`/`chair`/`board`/`plant` already have, plus the deliberate
/// *absence* of a fourth — `running`'s desk monitor has no candidate single that
/// fits the SS2c width bound, so none is declared. [I1: wrong is worse than
/// missing]
///
/// Every test here either reads the manifest as data (no art required) or
/// re-derives a number from `RoomLayout`/`SeatedHead` against the real pixels
/// (gated on `SceneArt.isAvailable`, same as the rest of this suite) — nothing
/// is transcribed from ADR-006's own tables and trusted, because the brief this
/// task ran against was explicit that a previous inventory in this exact band
/// (85-101, "workbenches") was wrong when checked against the pixels.
struct DeskTopObjectTests {

    /// Work kind -> declared role name, ADR-006 SS1's table minus `running`.
    static let declaredKinds: [String: String] = [
        "authoring": "laptop",
        "research": "papers",
        "coordinating": "pad",
    ]

    // MARK: The declarations themselves — no art needed

    @Test func threeOfTheFourWorkKindsHaveADeclaredDeskTopRole() throws {
        let manifest = try SceneFixtures.manifest()
        for (kind, role) in Self.declaredKinds {
            #expect(manifest.room.prop(role) != nil, "no \(role) role for \(kind)")
        }
        // `running` is the honest abstention: every candidate in the pack's
        // desk-scale band is over budget (see the width tests below), so no
        // role named after a monitor/screen exists to be bound later.
        for absent in ["monitor", "screen", "display"] {
            #expect(manifest.room.prop(absent) == nil, Comment(rawValue:
                    "a '\(absent)' role exists; update this test and the honesty note in the "
                    + "manifest's room.props.note together"))
        }
    }

    @Test func theDeclaredSinglesAreExactlyWhatWasMeasured() throws {
        let manifest = try SceneFixtures.manifest()

        let laptop = try #require(manifest.room.prop("laptop"))
        #expect(laptop.file
                == "assets/processed/room/32x32/singles/Modern_Office_Singles_32x32_135.png")
        #expect(laptop.contentBox == .init(x: 4, y: 38, width: 26, height: 40))

        let papers = try #require(manifest.room.prop("papers"))
        #expect(papers.file
                == "assets/processed/room/32x32/singles/Modern_Office_Singles_32x32_153.png")
        #expect(papers.contentBox == .init(x: 8, y: 72, width: 24, height: 22))

        let pad = try #require(manifest.room.prop("pad"))
        #expect(pad.file
                == "assets/processed/room/32x32/singles/Modern_Office_Singles_32x32_179.png")
        #expect(pad.contentBox == .init(x: 8, y: 32, width: 24, height: 42))
    }

    /// None of the three is bound to anything: `everyPropRoleTheSceneDrawsIsOne
    /// TheManifestNames` (`RoomSceneTests`) already proves the scene draws
    /// nothing the manifest does not name, which is the half that matters. This
    /// is the other half — the manifest naming something nobody reads yet is
    /// legal, and the three roles are not among the two the room actually
    /// falls back to (`desk`, `chair`) or draws unconditionally (`board`,
    /// `plant`).
    @Test func theThreeNewRolesAreNotTheFallbackRolesAStationReadsFrom() throws {
        let manifest = try SceneFixtures.manifest()
        for role in ["laptop", "papers", "pad"] {
            #expect(role != "desk" && role != "chair", "would change station fallback behaviour")
        }
        #expect(manifest.room.propRoles.keys.sorted()
                == ["board", "chair", "desk", "laptop", "pad", "papers", "plant"])
    }

    /// A weak but cheap silhouette-distinctness pin: no two of the three share
    /// both dimensions of their content box. The real silhouette check —
    /// distinct outlines at `1x`, from the actual pixels — is
    /// `theDeclaredSinglesInkFootprintsAreDistinctSilhouettesAtOnex` below,
    /// gated on the art. This one runs on a fresh clone and catches the coarse
    /// version of the same mistake (two roles pointing at the same box shape).
    @Test func noTwoDeclaredRolesShareAContentBoxShape() throws {
        let manifest = try SceneFixtures.manifest()
        let boxes = ["laptop", "papers", "pad"].map {
            manifest.room.prop($0)!.contentBox
        }
        for i in 0..<boxes.count {
            for j in (i + 1)..<boxes.count {
                #expect(boxes[i].width != boxes[j].width || boxes[i].height != boxes[j].height)
            }
        }
    }

    // MARK: The SS2c width bound, re-derived rather than hardcoded

    /// **28px, derived from `RoomLayout` and the manifest's own desk, not
    /// asserted from ADR-006's prose.**
    ///
    /// ADR-006 SS2c's placement rule is: an object's near (left) edge stands at
    /// the first scene column strictly outside the seated character's own
    /// canvas — which `SeatedHead.clearance(nearEdgeX:)` treats as unbounded
    /// starting at `nearEdgeX == canvasWidth / 2` (`theSS2cSixteenPxThreshold...`
    /// below proves that arithmetic against the real cast) — and its right edge
    /// stays inside the desk's own footprint, or the object reads as floating
    /// past the desk rather than standing on it. Both edges come from numbers
    /// this file can ask `RoomLayout` and `Manifest` for directly:
    ///
    ///   near edge  = characters.canvas.width / 2                (SeatedHead's own threshold)
    ///   desk right = deskPosition(seat).x - seatPosition(seat).x + desk.contentBox.width / 2
    ///   bound      = desk right - near edge
    ///
    /// If this ever measures something other than 28, ADR-006's own arithmetic
    /// (desk offset 28, desk width 32, next station at +48) has changed and the
    /// three declared roles need re-checking against the new number, which is
    /// exactly why the later tests compute the bound instead of writing `28`.
    static func deskTopWidthBound(manifest: Manifest, layout: RoomLayout) throws -> Double {
        let nearEdgeX = Double(manifest.characters.canvas.width) / 2
        let desk = try #require(manifest.room.prop("desk"))
        let seat = layout.seatPosition(0)
        let deskAnchor = layout.deskPosition(0)
        let deskRightEdge = (deskAnchor.x - seat.x) + Double(desk.contentBox.width) / 2
        return deskRightEdge - nearEdgeX
    }

    @Test func theDeskTopWidthBoundIsTwentyEightPixels() throws {
        let manifest = try SceneFixtures.manifest()
        let bound = try Self.deskTopWidthBound(manifest: manifest, layout: RoomLayout())
        #expect(bound == 28)
    }

    @Test func everyDeclaredDeskTopRoleFitsInsideTheDerivedWidthBound() throws {
        let manifest = try SceneFixtures.manifest()
        let bound = try Self.deskTopWidthBound(manifest: manifest, layout: RoomLayout())
        for role in ["laptop", "papers", "pad"] {
            let prop = try #require(manifest.room.prop(role))
            #expect(Double(prop.contentBox.width) <= bound,
                    "\(role) is \(prop.contentBox.width)px wide, over the \(bound)px SS2c bound")
        }
    }

    // MARK: Re-derived against the real pixels [gated: SceneArt.isAvailable]

    /// The alpha>0 ink bounding box of a bitmap, in the same convention
    /// `content_box` is measured in (top-left origin, y down, inclusive).
    static func inkBoundingBox(_ bitmap: Bitmap) -> (x: Int, y: Int, w: Int, h: Int)? {
        var minX = bitmap.width, minY = bitmap.height, maxX = -1, maxY = -1
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// `SeatedHead.clearance(nearEdgeX:)` claims an object cannot cover a head
    /// pixel at any height once its near edge reaches `canvasWidth / 2` (`16`
    /// for this cast). Proven here against every seated frame the pack ships,
    /// not read off `RoomScene`'s own doc comment: `clearance` is unbounded
    /// (equal to the canvas height) at exactly that edge, and strictly bounded
    /// one pixel inside it — otherwise `16` would not be the real threshold and
    /// `deskTopWidthBound` above would be computing the wrong number.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theSeatedHeadClearanceThresholdMatchesWhatTheWidthBoundAssumes() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let frames = RoomScene.seatedFrames(manifest: manifest, facing: layout.seatedFacing)
        let head = try #require(SeatedHead(frames: frames), "no seated frame loaded")
        let nearEdgeX = Double(manifest.characters.canvas.width) / 2
        #expect(nearEdgeX == 16)
        #expect(head.clearance(nearEdgeX: nearEdgeX) == head.canvasHeight, Comment(rawValue:
                "at the desk-top placement rule's own near edge, ADR-006 SS2c claims nothing "
                + "can cover a head pixel at any height"))
        #expect(head.clearance(nearEdgeX: nearEdgeX - 1) < head.canvasHeight, Comment(rawValue:
                "one pixel inside the near edge the clearance must be bounded, or +16 is not "
                + "really where the claim starts holding"))
    }

    /// The honesty-rule rejection, proven against the pixels rather than left as
    /// prose: every single in the pack's desk monitor family (130-134, none
    /// bound to any manifest role) really does measure wider than the derived
    /// bound, and the three roles this task did declare really do fit inside
    /// it — recomputed from the files on disk, not read back from
    /// `content_box`, so a future edit to the manifest that drifts from the art
    /// is caught here rather than trusted.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theRejectedMonitorSinglesExceedTheBoundAndTheDeclaredThreeDoNot() throws {
        let manifest = try SceneFixtures.manifest()
        let bound = try Self.deskTopWidthBound(manifest: manifest, layout: RoomLayout())
        #expect(bound == 28)

        for index in [130, 131, 132, 133, 134] {
            let url = manifest.url(
                "assets/processed/room/32x32/singles/Modern_Office_Singles_32x32_\(index).png")
            let bitmap = try PixelImage.bitmap(contentsOf: url)
            let box = try #require(Self.inkBoundingBox(bitmap), "single \(index) has no ink")
            #expect(Double(box.w) > bound, Comment(rawValue:
                    "single \(index) (a desk-monitor candidate) measured \(box.w)px wide; "
                    + "expected it to exceed the \(bound)px bound, which is why `running` has "
                    + "no declared desk-top role"))
        }

        for role in ["laptop", "papers", "pad"] {
            let prop = try #require(manifest.room.prop(role))
            let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(prop.file))
            let box = try #require(Self.inkBoundingBox(bitmap), "\(role)'s file has no ink")
            #expect(box.x == prop.contentBox.x, "\(role) content_box.x drifted from the art")
            #expect(box.y == prop.contentBox.y, "\(role) content_box.y drifted from the art")
            #expect(box.w == prop.contentBox.width, "\(role) content_box.w drifted from the art")
            #expect(box.h == prop.contentBox.height, "\(role) content_box.h drifted from the art")
            #expect(Double(box.w) <= bound, "\(role) measured \(box.w)px wide, over the bound")
        }
    }

    /// The real silhouette check, at `1x`: solid-black-filled ink footprints of
    /// the three declared singles, compared pixel for pixel. I7 says silhouette
    /// is what reads at small sizes, so "distinguishable" is checked as
    /// silhouettes actually differing rather than as a content-box shape
    /// mismatch (`noTwoDeclaredRolesShareAContentBoxShape` above, which cannot
    /// tell a wedge from a rectangle of the same bounding box).
    @Test(.enabled(if: SceneArt.isAvailable))
    func theDeclaredSinglesInkFootprintsAreDistinctSilhouettesAtOnex() throws {
        let manifest = try SceneFixtures.manifest()
        var silhouettes: [(role: String, pixels: Set<Int>)] = []
        for role in ["laptop", "papers", "pad"] {
            let prop = try #require(manifest.room.prop(role))
            let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(prop.file))
            var on: Set<Int> = []
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    on.insert(y * bitmap.width + x)
                }
            }
            #expect(!on.isEmpty, "\(role) has no visible pixels")
            silhouettes.append((role, on))
        }
        // The fourth family, extended into the same comparison: `running`'s
        // monitor has no manifest entry (it is authored, `DeskMonitorArt`, not
        // a pack single — see that file for why), but it belongs in exactly
        // this check, because the claim under test is "four kinds, four
        // silhouettes" and only three of them have ever been run through it.
        let monitorBitmap = DeskMonitorArt.bitmap()
        var monitorOn: Set<Int> = []
        for y in 0..<monitorBitmap.height {
            for x in 0..<monitorBitmap.width where monitorBitmap.at(x, y).a > 0 {
                monitorOn.insert(y * monitorBitmap.width + x)
            }
        }
        #expect(!monitorOn.isEmpty, "the authored monitor has no visible pixels")
        silhouettes.append(("monitor", monitorOn))

        for i in 0..<silhouettes.count {
            for j in (i + 1)..<silhouettes.count {
                #expect(silhouettes[i].pixels != silhouettes[j].pixels,
                        "\(silhouettes[i].role) and \(silhouettes[j].role) silhouette identically")
            }
        }
    }
}

/// **The fourth desk-top object: `running`'s monitor, authored rather than
/// sourced.** `DeskMonitorArt` — see that file for the full derivation. These
/// tests check the three things `HeldObjectArtTests` checks of its own
/// authored objects, plus the two ADR-006 SS2c/height obligations this task's
/// brief named specifically: the width bound (already exercised above for the
/// three sourced roles) and the head-clearance argument, re-derived at both
/// desk-surface heights the shipped themes use rather than assumed to transfer
/// from the three roles that never checked it either.
struct DeskMonitorArtTests {

    // MARK: Room ceiling, not the character floor [I7]
    //
    // This object stands on the desk, in the room, not in a character's hands
    // — unlike `HeldObjectArt`, which is checked against the *cast's* darkest
    // value because it is drawn on a character. The applicable numbers are
    // `04-ART-DIRECTION.md`'s room band: saturation under 25%, value inside
    // `[0.55, 0.92]`. `scripts/lint-palette.py` cannot see this object because
    // it reads `assets/manifest.json` and this object has no entry there (see
    // `DeskMonitorArt`'s doc comment for why) — so this is the test that closes
    // that gap, the same way `HeldObjectArtTests` closes it for the held layer.

    static func value(_ colour: Bitmap.RGBA) -> Double {
        Double(max(colour.r, max(colour.g, colour.b))) / 255
    }

    static func saturation(_ colour: Bitmap.RGBA) -> Double {
        let high = value(colour)
        guard high > 0 else { return 0 }
        let low = Double(min(colour.r, min(colour.g, colour.b))) / 255
        return (high - low) / high
    }

    @Test func everyPixelClearsTheRoomSaturationCeilingAndSitsInsideTheValueBand() {
        let bitmap = DeskMonitorArt.bitmap()
        var darkest = 1.0, brightest = 0.0, sawInk = false
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                sawInk = true
                let pixel = bitmap.at(x, y)
                let sat = Self.saturation(pixel)
                let val = Self.value(pixel)
                #expect(sat <= 0.25, "(\(x),\(y)) saturation \(sat) exceeds the room's 25% ceiling")
                #expect(val >= 0.55, "(\(x),\(y)) value \(val) is under the room's 0.55 floor")
                #expect(val <= 0.92, "(\(x),\(y)) value \(val) is over the room's 0.92 ceiling")
                darkest = min(darkest, val)
                brightest = max(brightest, val)
            }
        }
        #expect(sawInk, "the monitor has no opaque pixels")
        // The screen is the loudest thing this object draws and it still does
        // not reach the room's own ceiling — see `DeskMonitorArt.screen`'s doc
        // comment for the 0.183-precedent this measures against.
        #expect(brightest > darkest, "no value range at all — reads as a flat swatch")
    }

    /// Pinned as exact bytes, not described, so a future edit cannot drift the
    /// "sampled from the pack" claim without this test noticing.
    @Test func thePaletteIsExactlyThreeColoursAndTheyAreTheOnesDocumented() {
        #expect(DeskMonitorArt.outline == Bitmap.RGBA(154, 154, 170))
        #expect(DeskMonitorArt.screen == Bitmap.RGBA(182, 198, 222))
        #expect(DeskMonitorArt.statusDot == Bitmap.RGBA(159, 159, 175))

        let allowed: Set<[UInt8]> = [
            DeskMonitorArt.outline, DeskMonitorArt.screen, DeskMonitorArt.statusDot,
        ].reduce(into: Set<[UInt8]>()) { $0.insert([$1.r, $1.g, $1.b]) }
        let bitmap = DeskMonitorArt.bitmap()
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                let pixel = bitmap.at(x, y)
                #expect(allowed.contains([pixel.r, pixel.g, pixel.b]),
                        "off-palette colour at (\(x), \(y))")
            }
        }
    }

    /// **The claim that these are the pack's own inks, checked against the
    /// pixels rather than taken from the doc comment.** All three colours were
    /// sampled from `laptop`/`papers`/`pad`/`desk`'s own processed singles;
    /// this opens those files and confirms each of the three bytes is really
    /// there. Gated because it needs the pack on disk — the palette test above
    /// does not, and is deliberately not gated, because the claim "these three
    /// bytes and no others" is this repository's own and checkable on a fresh
    /// clone.
    @Test(.enabled(if: SceneArt.isAvailable))
    func thePaletteIsReallySampledFromTheShippedPackFiles() throws {
        let manifest = try SceneFixtures.manifest()
        var found: Set<[UInt8]> = []
        for role in ["desk", "laptop", "papers", "pad"] {
            let prop = try #require(manifest.room.prop(role))
            let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(prop.file))
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    let pixel = bitmap.at(x, y)
                    found.insert([pixel.r, pixel.g, pixel.b])
                }
            }
        }
        for colour in [DeskMonitorArt.outline, DeskMonitorArt.screen, DeskMonitorArt.statusDot] {
            #expect(found.contains([colour.r, colour.g, colour.b]),
                    "\(colour) does not appear in desk/laptop/papers/pad's own processed pixels")
        }
    }

    // MARK: The pack's grid [same construction as HeldObjectArt]

    @Test func theDesignIsDoubledOntoWholeTwoByTwoBlocks() {
        let bitmap = DeskMonitorArt.bitmap()
        #expect(bitmap.width == DeskMonitorArt.canvasWidth)
        #expect(bitmap.height == DeskMonitorArt.canvasHeight)
        #expect(bitmap.width.isMultiple(of: 2) && bitmap.height.isMultiple(of: 2))
        for y in stride(from: 0, to: bitmap.height, by: 2) {
            for x in stride(from: 0, to: bitmap.width, by: 2) {
                let corner = bitmap.at(x, y)
                #expect(bitmap.at(x + 1, y) == corner)
                #expect(bitmap.at(x, y + 1) == corner)
                #expect(bitmap.at(x + 1, y + 1) == corner)
            }
        }
    }

    // MARK: SS2c — the width bound, re-derived exactly as the sourced three are

    @Test func theMonitorFitsInsideTheDerivedWidthBound() throws {
        let manifest = try SceneFixtures.manifest()
        let bound = try DeskTopObjectTests.deskTopWidthBound(manifest: manifest, layout: RoomLayout())
        #expect(bound == 28)
        let box = try #require(DeskTopObjectTests.inkBoundingBox(DeskMonitorArt.bitmap()))
        #expect(Double(box.w) <= bound,
                "the monitor is \(box.w)px wide, over the \(bound)px SS2c bound")
        // "Comfortably under it" — the brief's own instruction — checked as a
        // real margin rather than a near miss: 20px against a 28px bound, six
        // whole pixels of slack, more than `laptop`'s own 26px declaration
        // leaves.
        #expect(box.w <= 26, "not comfortably under the bound: \(box.w)px")
        #expect(box.w == DeskMonitorArt.canvasWidth, "ink does not fill the declared canvas width")
    }

    // MARK: The waist — the structural claim, not just "the pixels differ"

    /// Per-row ink-column count for a bitmap: `profile[y]` is how many opaque
    /// columns row `y` has. The shape signature a silhouette comparison should
    /// actually be reading, rather than a raw pixel-set inequality that would
    /// be true of any two differently-sized images regardless of their shape.
    static func rowWidths(_ bitmap: Bitmap) -> [Int] {
        (0..<bitmap.height).map { y in
            (0..<bitmap.width).filter { bitmap.at($0, y).a > 0 }.count
        }
    }

    /// **A waist, defined so that a tapered edge does not count as one.** A
    /// silhouette that only narrows monotonically towards its own top or
    /// bottom row — a wedge's corner, a slab's angled edge — is not "an
    /// upright rectangle on a stalk"; it is one shape with a pointed end. What
    /// "waist" has to mean is an **interior** row that is markedly narrower
    /// than the widest row *on both sides of it* — two separate shoulders with
    /// a valley between them, which a single monotonic taper cannot produce
    /// because one of its two flanks is always the boundary itself.
    ///
    /// `left_max`/`right_max` at row `i` are the widest rows strictly before
    /// and strictly after it; a waist row is under half of *both*. First
    /// verified in Python against real profiles read off the shipped pixels
    /// before this was written in Swift — `laptop`'s own profile is a single
    /// unimodal hump (ramps to 26, ramps back down to 2, no interior dip with
    /// two shoulders), `papers` the same shape shorter, and `pad` is flat at
    /// 24 with one monotonic taper at a single end (24 → 8) — so this
    /// predicate is `false` for all three real siblings and `true` for the
    /// monitor's own screen(20)–stalk(4)–base(16) profile.
    static func hasInteriorWaist(_ widths: [Int]) -> Bool {
        guard widths.count > 2 else { return false }
        for i in 1..<(widths.count - 1) {
            let leftMax = widths[0..<i].max() ?? 0
            let rightMax = widths[(i + 1)...].max() ?? 0
            if Double(widths[i]) < Double(leftMax) * 0.5 && Double(widths[i]) < Double(rightMax) * 0.5 {
                return true
            }
        }
        return false
    }

    /// **The monitor's own profile has an interior waist**, checked as
    /// arithmetic on the authored bitmap rather than by looking at the ASCII
    /// grid and trusting it. This is what "an upright rectangle on a stalk"
    /// cashes out to as a number.
    @Test func theMonitorsOwnRowProfileHasAnInteriorWaist() {
        let widths = Self.rowWidths(DeskMonitorArt.bitmap()).filter { $0 > 0 }
        #expect(Self.hasInteriorWaist(widths), "no interior row is pinched on both sides: \(widths)")
    }

    /// **None of the three sourced siblings has this feature**, measured off
    /// their real pixels rather than assumed from "they are singles, not
    /// stalked shapes". A silhouette family claim should survive being checked
    /// against the thing it is being contrasted with — and a naive
    /// narrowest-over-widest ratio does not survive it: `laptop`'s wedge
    /// corner tapers to a single pixel (ratio 0.077, `papers`'s angled edge to
    /// 0.18), both *tighter* than the monitor's own 0.2, despite neither
    /// having a waist in the sense that matters. `hasInteriorWaist` is the
    /// predicate that actually separates them.
    @Test(.enabled(if: SceneArt.isAvailable))
    func noSourcedSiblingsRowProfileHasAnInteriorWaist() throws {
        let manifest = try SceneFixtures.manifest()
        #expect(Self.hasInteriorWaist(Self.rowWidths(DeskMonitorArt.bitmap()).filter { $0 > 0 }))

        for role in ["laptop", "papers", "pad"] {
            let prop = try #require(manifest.room.prop(role))
            let bitmap = try PixelImage.bitmap(contentsOf: manifest.url(prop.file))
            let widths = Self.rowWidths(bitmap).filter { $0 > 0 }
            #expect(!Self.hasInteriorWaist(widths),
                    "\(role) has an interior waist too, the same as the monitor: \(widths)")
        }
    }

    // MARK: Height — does not reach the head at either desk-surface convention

    /// **The near edge does not move when the surface height does.**
    /// `RoomLayout.deskSurfacePosition(seat:surfaceHeightAboveFloor:)` only
    /// changes `y`; `x` is `deskPosition(_:).x` in both the 24px-surface case
    /// (five themes) and the 36px-surface case (`library`, `mission_control` —
    /// 84be10f). So whatever `SeatedHead.clearance` proves at this near edge
    /// holds for both conventions identically, and this checks that arithmetic
    /// directly rather than assuming it from the formula's shape.
    @Test func theSurfaceHeightNeverMovesTheMonitorsNearEdgeX() {
        let layout = RoomLayout()
        let anchorX = layout.deskPosition(0).x
        for surfaceHeight in [24.0, 36.0] {
            let surface = layout.deskSurfacePosition(seat: 0, surfaceHeightAboveFloor: surfaceHeight)
            #expect(surface.x == anchorX,
                    "surface height \(surfaceHeight) moved the near-edge x")
        }
    }

    /// **The head-clearance argument, at the monitor's own near edge, proven
    /// against the real cast — the check the brief asked for by name.**
    /// `theDeskTopWidthBoundIsTwentyEightPixels` fixes the near edge at
    /// `canvasWidth / 2` (16px); this confirms `SeatedHead.clearance` there is
    /// unbounded — `== canvasHeight` — which is ADR-006 §2c's own reading of
    /// what "cannot cover a head pixel at any height whatsoever" means. Because
    /// the near edge does not move with the surface height (the test above),
    /// this one proof covers both the 24px and the 36px case: there is no
    /// height, including whatever `DeskMonitorArt.canvasHeight` happens to be,
    /// at which the monitor could cover a head pixel standing at this edge.
    @Test(.enabled(if: SceneArt.isAvailable))
    func theMonitorCannotCoverAHeadPixelAtEitherDeskSurfaceHeight() throws {
        let manifest = try SceneFixtures.manifest()
        let layout = RoomLayout()
        let frames = RoomScene.seatedFrames(manifest: manifest, facing: layout.seatedFacing)
        let head = try #require(SeatedHead(frames: frames), "no seated frame loaded")
        let nearEdgeX = Double(manifest.characters.canvas.width) / 2
        #expect(nearEdgeX == 16)
        #expect(head.clearance(nearEdgeX: nearEdgeX) == head.canvasHeight, Comment(rawValue:
                "the monitor's near edge is not past the threshold at which no height covers a "
                + "head pixel, so DeskMonitorArt.canvasHeight (\(DeskMonitorArt.canvasHeight)) "
                + "would need checking against an actual, finite clearance"))
    }
}
