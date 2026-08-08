import Foundation
import SpriteKit

/// Loads and caches every texture the room needs, addressed only through the
/// manifest.
///
/// No filename and no frame index is written down here. Ask for
/// `frames(variant:state:facing:)` and the paths come from
/// `assets/manifest.json`; swap the manifest and the same code draws different
/// art.
@MainActor
public final class TextureStore {

    public let manifest: Manifest
    /// Which theme's bindings this store resolves. `nil` is the room this app
    /// has always drawn. [ADR-002 §8 item 5]
    public let themeID: String?
    /// The resolved bindings — `manifest.room` or `manifest.themes.sets[id]`.
    /// Every room-facing lookup goes through here rather than through
    /// `manifest.room`, which is what makes the theme a *selection* rather than
    /// a branch at each call site.
    public let room: Manifest.Room
    private var cache: [String: SKTexture] = [:]
    private var accents: [String: Bitmap.RGBA] = [:]
    private var roomTiles: RoomTiles?

    /// Which builder tiles the room is built from.
    ///
    /// **Declared, with measurement as the fallback.** The manifest records the
    /// Room Builder sheet as a flat list of 141 sliced tiles with no semantics,
    /// and the original answer was to measure rather than to read a filename:
    /// among tiles that are fully opaque and a single flat colour, the darker is
    /// the floor and the lighter is the wall. Picking `tile_r00_c08` because it
    /// sounds like a floor would be exactly the filename dependency the manifest
    /// exists to prevent, and that reasoning still stands.
    ///
    /// What did not stand is the *cost*: of those 141 tiles the filter accepts
    /// exactly **2**, because a floor that carries a pattern is by construction
    /// neither single-coloured nor a candidate. So the room was two flat colour
    /// fields, and since `004b587` draws at `1x` at every population, those two
    /// fields are most of the panel. A themeable floor cannot be found by
    /// searching for the flattest thing in the set.
    ///
    /// So `builder.floor` and `builder.wall` are now read when the manifest
    /// declares them — which is a *measurement recorded at import time* rather
    /// than a filename written down in `Sources/`, so nothing about the rule
    /// this heuristic protects has been given up. The heuristic remains, and is
    /// still exercised: `room` itself declares neither, so the default room
    /// resolves exactly as it always has.
    /// [04-ART-DIRECTION, "Two facts about the room that this work uncovered"]
    public struct RoomTiles: Sendable {
        public let floor: String
        public let wall: String
        /// `true` when both came from `builder.floor`/`builder.wall`. Diagnostic
        /// only — a test asserts a theme is read rather than searched, and this
        /// is how it can tell the two apart without reading pixels.
        public let isDeclared: Bool
    }

    public init(manifest: Manifest, themeID: String? = nil) {
        self.manifest = manifest
        self.themeID = themeID
        self.room = manifest.room(theme: themeID)
    }

    // MARK: Textures

    public func texture(path: String) -> SKTexture? {
        if let cached = cache[path] { return cached }
        guard let bitmap = try? PixelImage.bitmap(contentsOf: manifest.url(path)),
              let texture = PixelImage.texture(from: bitmap) else { return nil }
        cache[path] = texture
        return texture
    }

    public func texture(bitmap: Bitmap, key: String) -> SKTexture? {
        if let cached = cache[key] { return cached }
        guard let texture = PixelImage.texture(from: bitmap) else { return nil }
        cache[key] = texture
        return texture
    }

    /// Animation frames for one state of one variant.
    ///
    /// `working` is drawn `right` and `left` only, so a request for it facing
    /// up or down falls back to the nearest side view rather than returning
    /// nothing — a seated character facing the camera is art that was never
    /// drawn. [04-ART-DIRECTION]
    public func frames(variant: String, state: BodyState, facing: Facing) -> [SKTexture] {
        guard let animation = manifest.characters.variant(variant)?.animation(state) else {
            return []
        }
        let resolved: Facing
        if animation.frames(facing: facing) != nil {
            resolved = facing
        } else if animation.frames(facing: facing.seated) != nil {
            resolved = facing.seated
        } else if let any = Facing.allCases.first(where: { animation.frames(facing: $0) != nil }) {
            resolved = any
        } else {
            return []
        }
        return (animation.frames(facing: resolved) ?? []).compactMap { texture(path: $0) }
    }

    public func frameRate(variant: String, state: BodyState) -> Double {
        manifest.characters.variant(variant)?.animation(state)?.fps ?? manifest.characters.frameRate
    }

    public func loops(variant: String, state: BodyState) -> Bool {
        manifest.characters.variant(variant)?.animation(state)?.loops ?? state.loopsByDefault
    }

    public func headTop(variant: String) -> Int {
        manifest.characters.variant(variant)?.headTopPx ?? 0
    }

    public func badgeTexture(_ badge: ToolBadge) -> SKTexture? {
        guard let art = manifest.badges.art(badge) else { return nil }
        return texture(path: art.file)
    }

    /// The `Notification` badge, from `badges.states.attention`. There is one
    /// glyph for every `notification_type`: the attention badge asserts "this
    /// session wants you", which is what all of them mean, and drawing a
    /// different icon per type would need art nobody has drawn. [I1]
    public func attentionTexture() -> SKTexture? {
        guard let art = manifest.badges.attention else { return nil }
        return texture(path: art.file)
    }

    /// The dormant badge, from `badges.states.sleep`. One glyph, and it says the
    /// one thing the lifecycle knows: this character finished a turn and is
    /// still assigned. There is no body state to go with it and there must not
    /// be one — see `Manifest.Badges.sleepKey`. [I1]
    public func sleepTexture() -> SKTexture? {
        guard let art = manifest.badges.sleep else { return nil }
        return texture(path: art.file)
    }

    // MARK: Room

    public func roomTileChoice() -> RoomTiles {
        if let roomTiles { return roomTiles }

        // The declaration wins outright when it is there. Both keys, or
        // neither: a half-declared builder is a manifest defect, and silently
        // pairing a declared floor with a searched wall would hide it behind a
        // room that looks nearly right.
        if let floor = room.declaredFloor, let wall = room.declaredWall {
            let choice = RoomTiles(floor: floor, wall: wall, isDeclared: true)
            roomTiles = choice
            return choice
        }

        let flat = flatBuilderTiles()
        let choice = RoomTiles(
            floor: flat.first?.path ?? room.builderTiles.first ?? "",
            wall: flat.last?.path ?? flat.first?.path
                ?? room.builderTiles.first ?? "",
            isDeclared: false)
        roomTiles = choice
        return choice
    }

    /// One builder tile the heuristic accepts, and its mean value. Ascending, so
    /// the first is the floor and the last is the wall.
    struct FlatTile {
        let path: String
        let value: Double
    }

    /// The tiles that are fully opaque **and** a single flat colour, which is
    /// the whole of the old selection rule.
    ///
    /// Exposed because the interesting fact about it is *how few there are* —
    /// 2 of the Office room's 141 — and a number that explains a design decision
    /// should be measurable rather than quoted. A patterned floor cannot pass
    /// this filter by construction, which is why no amount of art would have
    /// widened it and why `builder.floor` exists.
    func flatBuilderTiles() -> [FlatTile] {
        struct Candidate {
            let path: String
            let value: Double
        }
        var flat: [Candidate] = []
        for path in room.builderTiles {
            guard let bitmap = try? PixelImage.bitmap(contentsOf: manifest.url(path)) else {
                continue
            }
            var colours: Set<UInt32> = []
            var opaque = 0
            var valueSum = 0.0
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    let pixel = bitmap.at(x, y)
                    guard pixel.a > 200 else { continue }
                    opaque += 1
                    colours.insert(
                        UInt32(pixel.r) << 16 | UInt32(pixel.g) << 8 | UInt32(pixel.b))
                    valueSum += Double(max(pixel.r, max(pixel.g, pixel.b))) / 255.0
                }
            }
            let total = bitmap.width * bitmap.height
            guard total > 0, opaque == total, colours.count == 1 else { continue }
            flat.append(Candidate(path: path, value: valueSum / Double(opaque)))
        }
        return flat
            .sorted { $0.value < $1.value }
            .map { FlatTile(path: $0.path, value: $0.value) }
    }

    /// The seated pose for a badge class, from `characters.poses.working`.
    /// Total; see `Manifest.Characters.workingPose(forBadgeKey:)`. [§8 item 7]
    public func workingPose(forBadgeKey key: String?) -> BodyState {
        manifest.characters.workingPose(forBadgeKey: key)
    }

    // MARK: Accent

    /// The variant's accent, from `accent_hex` in the manifest.
    ///
    /// **Assigned, not sampled, and that is the point.** The obvious
    /// implementation — take the most saturated pixel of the sprite — is what
    /// this used to do, and M2 measured the result: all six selected premades'
    /// accents land inside a 30° arc, 07 and 17 are hue-identical, and 07/19
    /// differ by 3.5°, because the generator dresses one body in variations of
    /// one warm palette. A second identity channel that does not separate is
    /// worse than none, because it looks like one.
    ///
    /// So the manifest carries six hues 60° apart and this reads them. The
    /// accent is drawn as the nameplate border — a colour the *scene* puts on
    /// screen — so assigning it is not a claim about any pixel in the sprite,
    /// and `scripts/lint-palette.py` checks the separation rather than
    /// asserting it.
    ///
    /// Sampling survives only as the fallback for a manifest that predates the
    /// field, so a room built against an older manifest still draws.
    public func accent(variant: String) -> Bitmap.RGBA {
        if let cached = accents[variant] { return cached }
        if let assigned = manifest.characters.variant(variant)?.accentHex {
            accents[variant] = assigned
            return assigned
        }
        var best = Bitmap.RGBA(220, 220, 230)
        var bestSaturation = -1.0
        if let path = manifest.characters.variant(variant)?
            .animation(.idle)?.frames(facing: .down)?.first,
           let bitmap = try? PixelImage.bitmap(contentsOf: manifest.url(path)) {
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    let pixel = bitmap.at(x, y)
                    guard pixel.a > 200 else { continue }
                    let high = Double(max(pixel.r, max(pixel.g, pixel.b))) / 255
                    let low = Double(min(pixel.r, min(pixel.g, pixel.b))) / 255
                    guard high > 0 else { continue }
                    let saturation = (high - low) / high
                    if saturation > bestSaturation {
                        bestSaturation = saturation
                        best = pixel
                    }
                }
            }
        }
        accents[variant] = best
        return best
    }
}
