import Foundation

/// Everything the scene draws itself rather than loading — the nameplate and
/// the placeholder furniture. Pure bitmap arithmetic, no graphics framework, so
/// each of these is inspectable in a test.
public enum SceneBitmaps {

    /// Longest nameplate that still fits inside one seat's spacing. Ten glyphs
    /// at 5+1 px is 59 px of text plus the plate, against 96 px of seat pitch.
    public static let nameplateGlyphLimit = 10

    public static let nameplateInk = Bitmap.RGBA(238, 238, 244)
    public static let nameplatePlate = Bitmap.RGBA(26, 24, 32, 235)

    /// The nameplate: dark plate, light text, one-pixel border in the
    /// character's own accent hue.
    ///
    /// The border is not decoration. M0 measured that this cast is not
    /// separable by silhouette, so identity has to come from the plate: the
    /// name reads first, the accent reads second, and neither depends on being
    /// able to tell two 32×64 bodies apart. [criterion 5]
    public static func nameplate(
        _ text: String, accent: Bitmap.RGBA, font: PixelFont = .standard
    ) -> Bitmap {
        let fitted = font.fit(text, limit: nameplateGlyphLimit)
        let textWidth = font.width(of: fitted)
        let width = textWidth + 6
        let height = font.glyphHeight + 6
        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, nameplatePlate)
        bitmap.stroke(x: 0, y: 0, w: width, h: height, accent)
        font.draw(fitted, into: &bitmap, x: 3, y: 3, colour: nameplateInk)
        return bitmap
    }

    /// The `×N` that rides beside the badge when several calls are open.
    public static func badgeCount(_ count: Int, font: PixelFont = .standard) -> Bitmap {
        let text = "×\(count)"
        let width = font.width(of: text) + 4
        let height = font.glyphHeight + 4
        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, nameplatePlate)
        font.draw(text, into: &bitmap, x: 2, y: 2, colour: nameplateInk)
        return bitmap
    }

    /// A desk, drawn as an obvious placeholder.
    ///
    /// Modern Office ships 339 object singles named by index only, and the
    /// manifest records `room.props.identified = false` — nothing in that set
    /// is *known* to be a desk. Picking one because it looks desk-shaped would
    /// be building against a filename, which is the thing that makes M5's
    /// "manifest swap, zero code change" impossible. So: a flat block at the
    /// right size, in the room's value band, hatched so nobody mistakes it for
    /// final art. [04-ART-DIRECTION, "Placeholders"]
    public static func placeholderDesk(width: Int = 32, height: Int = 26) -> Bitmap {
        // Kept inside the room's value band [0.55, 0.92] so the placeholder
        // cannot own the darkest pixel on screen — that belongs to the
        // characters. [I7]
        let body = Bitmap.RGBA(142, 138, 132)
        let edge = Bitmap.RGBA(120, 117, 112)
        let hatch = Bitmap.RGBA(120, 117, 112)
        var bitmap = Bitmap(width: width, height: height)
        // Top surface and a leg each side — a side-view desk silhouette.
        bitmap.fill(x: 0, y: 0, w: width, h: 5, body)
        bitmap.fill(x: 2, y: 5, w: 5, h: height - 5, body)
        bitmap.fill(x: width - 7, y: 5, w: 5, h: height - 5, body)
        for y in 0..<height {
            for x in 0..<width where (x + y).isMultiple(of: 4) && bitmap.at(x, y).a > 0 {
                bitmap.set(x, y, hatch)
            }
        }
        bitmap.stroke(x: 0, y: 0, w: width, h: 5, edge)
        return bitmap
    }
}
