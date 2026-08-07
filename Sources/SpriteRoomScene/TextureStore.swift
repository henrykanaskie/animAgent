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
    private var cache: [String: SKTexture] = [:]
    private var accents: [String: Bitmap.RGBA] = [:]
    private var roomTiles: RoomTiles?

    /// Which builder tiles the room is built from, chosen by **measuring** the
    /// tiles rather than by reading their filenames.
    ///
    /// The manifest records the Room Builder sheet as a flat list of 141 sliced
    /// tiles with no semantics — the pack does not say which is floor and which
    /// is wall. Picking `tile_r00_c08` because it sounds like a floor would be
    /// exactly the filename dependency the manifest exists to prevent. Instead:
    /// among tiles that are fully opaque and a single flat colour, the darker
    /// is the floor and the lighter is the wall. That is reproducible, and it
    /// stays correct if the slicing changes.
    public struct RoomTiles: Sendable {
        public let floor: String
        public let wall: String
    }

    public init(manifest: Manifest) {
        self.manifest = manifest
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

    // MARK: Room

    public func roomTileChoice() -> RoomTiles {
        if let roomTiles { return roomTiles }
        struct Candidate {
            let path: String
            let value: Double
        }
        var flat: [Candidate] = []
        for path in manifest.room.builderTiles {
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
        let sorted = flat.sorted { $0.value < $1.value }
        let choice = RoomTiles(
            floor: sorted.first?.path ?? manifest.room.builderTiles.first ?? "",
            wall: sorted.last?.path ?? sorted.first?.path
                ?? manifest.room.builderTiles.first ?? "")
        roomTiles = choice
        return choice
    }

    // MARK: Accent

    /// The variant's own accent hue, measured from its art.
    ///
    /// I7 guarantees every selected character carries something above 0.55
    /// saturation and the processed room carries nothing above 0.18, so the
    /// most saturated pixel in a character's first idle frame is its accent by
    /// construction. Sampling it beats hard-coding a palette that would drift
    /// from the art the moment the cast changes.
    ///
    /// **It is a weak channel and should not be relied on.** Measured across
    /// the M0 cast, all six accents land inside a 30° arc of hue — 07 and 17
    /// are hue-identical, and 07/19 and 17/19 differ by 3.5° — because the
    /// generator dresses one body in variations of the same warm palette. The
    /// nameplate *text* is what separates the cast; the border is a second
    /// glance, not a first one. See the M2 report.
    ///
    /// This wants to be `accent_hex` in the manifest, chosen for mutual
    /// separation rather than sampled — an art-director call, not a scene one.
    public func accent(variant: String) -> Bitmap.RGBA {
        if let cached = accents[variant] { return cached }
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
