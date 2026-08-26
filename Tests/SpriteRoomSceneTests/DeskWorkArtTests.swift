import Foundation
import Testing
@testable import SpriteRoomScene

/// The three authored desk objects: their palette, their grid, their budget and
/// (the one that matters) whether they are actually tellable apart.
///
/// None of this needs the pack on disk. It is bitmap arithmetic over art this
/// repository draws itself, which is exactly the layer `scripts/lint-palette.py`
/// cannot see: that lint reads `assets/manifest.json`, and these bitmaps are
/// built by the scene. A layer no lint can see is a layer whose I7 numbers are
/// whatever somebody last typed, so they are measured here instead.
struct DeskWorkArtTests {

    /// The room's band, from `04-ART-DIRECTION.md`, "The palette rule is now a
    /// build step". Furniture lives inside this so that nothing outside the
    /// characters owns the darkest pixel on screen. [I7]
    static let valueFloor = 0.55
    static let valueCeiling = 0.92
    static let saturationCeiling = 0.25

    static func value(_ colour: Bitmap.RGBA) -> Double {
        Double(max(colour.r, max(colour.g, colour.b))) / 255
    }

    static func saturation(_ colour: Bitmap.RGBA) -> Double {
        let high = value(colour)
        guard high > 0 else { return 0 }
        let low = Double(min(colour.r, min(colour.g, colour.b))) / 255
        return (high - low) / high
    }

    /// Kinds this file draws. `running` belongs to `DeskMonitorArt` and has its
    /// own suite.
    static let authored: [WorkKind] = [.authoring, .research, .coordinating]

    /// **Every pixel is inside the room's band.** This is the assertion that
    /// stops the next person "fixing" legibility by reaching for a dark outline,
    /// which would read instantly and would be the room breaking the one rule
    /// the whole art direction protects.
    @Test func everyPixelStaysInsideTheRoomsPaletteBand() {
        for kind in Self.authored {
            let bitmap = DeskWorkArt.bitmap(kind)
            #expect(bitmap != nil, "\(kind.rawValue) draws nothing")
            guard let bitmap else { continue }
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    let pixel = bitmap.at(x, y)
                    let v = Self.value(pixel)
                    let s = Self.saturation(pixel)
                    #expect(v >= Self.valueFloor && v <= Self.valueCeiling,
                            "\(kind.rawValue) at (\(x), \(y)) has value \(v)")
                    // **The saturation ceiling is retired [ADR-015]**: the
                    // maintainer asked that nothing be desaturated, so the room
                    // now runs at the pack's own saturation and authored art
                    // sampled from it follows. The value band above is the half
                    // of I7 that was NOT spent, and it is still asserted per
                    // pixel here, which is the point of keeping this test.
                    _ = s
                }
            }
        }
    }

    /// Only the three inks `DeskMonitorArt` already cleared, so a fourth object
    /// cannot quietly introduce a hue nobody sampled off the pack.
    @Test func theArtUsesOnlyTheThreeSampledInks() {
        let allowed: Set<[UInt8]> = [DeskWorkArt.outline, DeskWorkArt.face, DeskWorkArt.detail]
            .reduce(into: Set<[UInt8]>()) { $0.insert([$1.r, $1.g, $1.b]) }
        for kind in Self.authored {
            guard let bitmap = DeskWorkArt.bitmap(kind) else { continue }
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width where bitmap.at(x, y).a > 0 {
                    let pixel = bitmap.at(x, y)
                    #expect(allowed.contains([pixel.r, pixel.g, pixel.b]),
                            "\(kind.rawValue) uses an off-palette colour at (\(x), \(y))")
                }
            }
        }
    }

    /// **The pack's grid.** Modern Office ships every single at 16x and 32x as
    /// pixel-doubled copies, so a feature at 1 px line weight reads as a
    /// different hand. Asserts the doubling happened rather than trusting the
    /// design tables were transcribed onto it.
    @Test func everyFeatureIsATwoByTwoBlock() {
        for kind in Self.authored {
            guard let bitmap = DeskWorkArt.bitmap(kind) else { continue }
            #expect(bitmap.width.isMultiple(of: 2))
            #expect(bitmap.height.isMultiple(of: 2))
            for y in stride(from: 0, to: bitmap.height, by: 2) {
                for x in stride(from: 0, to: bitmap.width, by: 2) {
                    let corner = bitmap.at(x, y)
                    for (dx, dy) in [(1, 0), (0, 1), (1, 1)] {
                        let other = bitmap.at(x + dx, y + dy)
                        #expect(corner.r == other.r && corner.g == other.g
                                && corner.b == other.b && corner.a == other.a,
                                "\(kind.rawValue) breaks its 2x2 block at (\(x), \(y))")
                    }
                }
            }
        }
    }

    /// **The placement budget.** 28 px of content is what the desk's own width
    /// and `RoomScene.deskObjectNearEdgeX` leave; over it, an object reaches into
    /// the neighbouring station's lane, which is a bug ADR-002 §7 already had to
    /// fix once for theme desks.
    @Test func theArtFitsThePlacementBudget() {
        for kind in Self.authored {
            guard let bitmap = DeskWorkArt.bitmap(kind) else { continue }
            #expect(bitmap.width <= 28, "\(kind.rawValue) is \(bitmap.width) px wide")
            // And the design it came from is inside the stated column bound.
            let columns = DeskWorkArt.design(kind)?.first?.count ?? 0
            #expect(columns <= DeskWorkArt.maximumDesignWidth)
        }
    }

    /// Every design is rectangular. A ragged grid silently shifts every row
    /// under the short one and is invisible in the source.
    @Test func everyDesignGridIsRectangular() {
        for kind in Self.authored {
            guard let design = DeskWorkArt.design(kind), let width = design.first?.count
            else { continue }
            for (row, line) in design.enumerated() {
                #expect(line.count == width,
                        "\(kind.rawValue) row \(row) is \(line.count), not \(width)")
            }
        }
    }

    /// **The one that matters: all four read as different shapes with the colour
    /// thrown away.**
    ///
    /// Contrast is not available to this layer (I7 keeps the room pale on
    /// purpose), so silhouette is the entire legibility budget. Each object is
    /// flattened to its per-row ink width and the four profiles are compared.
    /// Equal profiles would mean two kinds that are distinguishable only by a
    /// detail pixel, which is what the pack's own three singles amounted to at
    /// 1x and the reason they were replaced.
    @Test func theFourProfilesAreTellableApartAsSilhouettesAlone() {
        func profile(_ bitmap: Bitmap) -> [Int] {
            (0..<bitmap.height).map { y in
                (0..<bitmap.width).filter { bitmap.at($0, y).a > 0 }.count
            }
        }

        var profiles: [WorkKind: [Int]] = [:]
        for kind in Self.authored {
            guard let bitmap = DeskWorkArt.bitmap(kind) else { continue }
            profiles[kind] = profile(bitmap)
        }
        profiles[.running] = profile(DeskMonitorArt.bitmap())

        #expect(profiles.count == WorkKind.allCases.count)
        for (a, b) in [(WorkKind.authoring, WorkKind.research),
                       (.authoring, .coordinating), (.authoring, .running),
                       (.research, .coordinating), (.research, .running),
                       (.coordinating, .running)] {
            #expect(profiles[a] != profiles[b],
                    "\(a.rawValue) and \(b.rawValue) have identical silhouettes")
        }

        // And the named features, each checked as a fact about the profile
        // rather than as a claim in a comment.
        let laptop = profiles[.authoring]!
        #expect(laptop.last! > laptop.first!,
                "the laptop should step outward at the hinge, not inward")

        let monitor = profiles[.running]!
        #expect(monitor.min()! * 4 <= monitor.max()!,
                "the monitor's waist is what separates it from the pad")

        let pad = profiles[.coordinating]!
        let padBody = pad.dropFirst(4)
        #expect(Set(padBody).count == 1, "the pad should be one constant width below its clip")

        let papers = profiles[.research]!
        #expect(papers.count < laptop.count && papers.count < pad.count,
                "the paper stack should be the short one")
    }

    /// `running` is not this file's, and asking for it returns nothing rather
    /// than a wrong picture. `RoomScene.deskObjectArt` relies on exactly this to
    /// choose between the two authored sources.
    @Test func runningBelongsToTheMonitorFile() {
        #expect(DeskWorkArt.bitmap(.running) == nil)
        #expect(DeskWorkArt.design(.running) == nil)
    }

    /// Every kind is authored now, so no kind names a manifest role. The seam is
    /// kept deliberately (see `WorkKind.propRole`), and this pins the shipped
    /// state so that a role reappearing is a decision rather than an accident.
    @Test func noKindNamesAManifestRoleAnyMore() {
        for kind in WorkKind.allCases {
            #expect(kind.propRole == nil, "\(kind.rawValue) still names a pack role")
        }
    }
}
