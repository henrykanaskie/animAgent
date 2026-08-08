import Foundation

/// What a nameplate says, split into the two things it has to say.
///
/// **The split exists because the two halves are not equally informative.**
/// Three `general-purpose` subagents share every glyph of their type and differ
/// only in the discriminator, so the discriminator is the whole of the
/// identity and the type is context. A single line spends its first eight
/// glyphs on the shared part and its last three — smallest, after an ellipsis —
/// on the part that differs, which is the worst possible ordering. Carrying the
/// two separately lets the plate draw the discriminator large and lead with it.
///
/// This is a value type rather than a formatted string so the *geometry* lives
/// in `SceneBitmaps` and the *policy* lives in `SceneDirector`; neither has to
/// parse the other's output. The old `TYPE:XXX` string needed a separator glyph
/// purely to tell a reader where the type stopped, and that separator is now
/// free — the rows do it.
public struct NameplateText: Sendable, Hashable {
    /// The line that differs, drawn large. The `agent_id` discriminator for a
    /// subagent; the name for the main agent, which has no `agent_id` and so
    /// has nothing to discriminate against. [CLAUDE.md, Identity model]
    ///
    /// **Empty is meaningful**: it says there is nothing that differs, and the
    /// plate then draws the role alone on one row. That is the honest picture
    /// for a subagent whose `agent_id` yielded no usable characters — inventing
    /// a headline for it would be the same mistake as guessing a badge for an
    /// unmapped tool. [I1]
    public var lead: String
    /// `agent_type`, drawn small beneath the lead. `nil` when there is nothing
    /// to add — the main agent, or a subagent whose id yielded no discriminator
    /// and whose type is therefore already the lead.
    public var role: String?

    public init(lead: String, role: String? = nil) {
        self.lead = lead
        self.role = role
    }

    /// Stable, collision-free key for the texture cache.
    var textureKey: String { lead + "\u{1}" + (role ?? "") }
}

/// Everything the scene draws itself rather than loading — the nameplate and
/// the placeholder furniture. Pure bitmap arithmetic, no graphics framework, so
/// each of these is inspectable in a test.
public enum SceneBitmaps {

    /// Glyphs the lead line gets, at `nameplateLeadScale`.
    ///
    /// Five rather than three so the fallback fits: the lead is normally the
    /// three-character discriminator, but for the main agent it is a name, and
    /// `MAIN` is four. Five doubled glyphs is 58 px, inside the role line's own
    /// budget, so the lead never decides the plate's width.
    public static let nameplateLeadGlyphLimit = 5

    /// Glyphs the role line gets, at 1×.
    ///
    /// Ten at 5+1 px is 59 px of text plus 6 px of plate = **65 px**, against
    /// 96 px of seat pitch and 80 px of delivery-slot pitch — a 31 px gap
    /// between neighbouring plates where the single-line 12-glyph plate left
    /// 19 px and read as nearly touching at the wide default.
    ///
    /// Ten is *fewer* glyphs than the old plate carried in total, and the type
    /// still gets more of them than it did: the old split gave the type 8 of
    /// 12, so `general-purpose` truncated at `GENERAL…`; it now truncates at
    /// `GENERAL-P…` while the discriminator is no longer competing for the same
    /// row. The ellipsis stays because it is the honest fallback — see
    /// `SceneDirector.nameplate(for:)` for why no abbreviation scheme replaced
    /// it.
    public static let nameplateRoleGlyphLimit = 10

    /// Integer magnification of the lead line. [I6]
    public static let nameplateLeadScale = 2

    /// 1 px border + 2 px of air on each side.
    private static let platePadX = 3
    /// Air above and below each row of glyphs. One pixel, not two, because
    /// height is the axis under pressure: the plate has to stay shorter than
    /// the tile between the aisle and the seat row. See
    /// `maximumNameplateHeight`.
    private static let platePadY = 1
    /// Extra air under the role line so the bottom border does not sit against
    /// the descender-less glyphs.
    private static let plateFootY = 2

    public static let nameplateInk = Bitmap.RGBA(238, 238, 244)
    /// **Fully opaque.** It was `alpha 235` — 8% of whatever is behind it came
    /// through, which was invisible against today's near-empty grey floor and
    /// will not be against a furnished themed room. A plate that borrows its
    /// contrast from the background does not survive a change of background.
    public static let nameplatePlate = Bitmap.RGBA(26, 24, 32, 255)
    /// Ink for the lead line when it sits on the accent rather than the plate.
    public static let nameplateLeadInkDark = Bitmap.RGBA(20, 18, 26, 255)

    /// The nameplate: a solid accent band carrying the discriminator at 2×,
    /// and the agent type beneath it at 1× on the dark plate.
    ///
    /// **Three channels, one plate, and only one of them is text.** M0 measured
    /// that this cast is not separable by silhouette (the best six-variant
    /// subset differs by 7.3% of outline) and M2 measured that accent hue *as
    /// sampled from the art* does not separate it either (all six inside a 30°
    /// arc). Both refutations are about the sprites. The plate is not a sprite:
    ///
    /// - the **accent band** is a solid field of a hue that is assigned 60°
    ///   apart and lint-enforced, so unlike the sampled hues it genuinely
    ///   separates — and a band is a signal you can catch peripherally, which a
    ///   one-pixel border is not;
    /// - the **lead** is the only text that differs between same-typed agents,
    ///   drawn at 2× so it is the first thing legible rather than the last;
    /// - the **role** is context, and is allowed to be the small line because
    ///   losing it costs you what an agent *is*, not which one it is.
    ///
    /// The band's ink is picked per accent by contrast rather than fixed, so a
    /// dark accent gets light glyphs and a light one gets dark. Six hues 60°
    /// apart cannot all be light. [criterion 5]
    public static func nameplate(
        _ text: NameplateText, accent: Bitmap.RGBA, font: PixelFont = .standard
    ) -> Bitmap {
        let lead = font.fit(text.lead, limit: nameplateLeadGlyphLimit)
        let role = text.role.flatMap {
            $0.isEmpty ? nil : font.fit($0, limit: nameplateRoleGlyphLimit)
        }
        let leadWidth = lead.isEmpty ? 0 : font.width(of: lead, scale: nameplateLeadScale)
        let roleWidth = role.map { font.width(of: $0) } ?? 0

        let width = max(1, max(leadWidth, roleWidth)) + 2 * platePadX
        // An empty lead keeps a one-pixel stub of band rather than none, so the
        // accent still reads as a rule along the top and every plate in the
        // room shares a construction.
        let band = lead.isEmpty
            ? platePadY
            : font.height(scale: nameplateLeadScale) + 2 * platePadY
        let roleBand = role == nil ? 0 : font.glyphHeight + platePadY + plateFootY
        let height = max(band + roleBand, 3)

        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, nameplatePlate)
        bitmap.fill(x: 0, y: 0, w: width, h: band, accent)
        bitmap.stroke(x: 0, y: 0, w: width, h: height, accent)
        if !lead.isEmpty {
            font.draw(
                lead, into: &bitmap,
                x: (width - leadWidth) / 2, y: platePadY,
                colour: contrastingInk(on: accent), scale: nameplateLeadScale)
        }
        if let role {
            font.draw(
                role, into: &bitmap,
                x: (width - roleWidth) / 2, y: band + platePadY, colour: nameplateInk)
        }
        return bitmap
    }

    /// Tallest plate the font and the limits can produce.
    ///
    /// The camera's content band is derived from this rather than from a
    /// formula repeated at the call site, so a change here cannot quietly
    /// overflow the frame. It is also the number that keeps a seated
    /// character's plate clear of an aisle character's: the two rows are one
    /// tile apart, so a plate taller than a tile would put them in the same
    /// horizontal strip and leave `noTwoNameplatesEverIntersect` depending on
    /// x alone. `RoomSceneTests` asserts that bound.
    public static var maximumNameplateHeight: Int {
        nameplate(NameplateText(lead: "MMMMM", role: "MMMMMMMMMM"), accent: .clear).height
    }

    /// Widest plate the font and the limits can produce.
    public static var maximumNameplateWidth: Int {
        nameplate(NameplateText(lead: "MMMMM", role: "MMMMMMMMMM"), accent: .clear).width
    }

    /// Whichever of the two inks reads better on `background`, by WCAG relative
    /// luminance. A rule rather than a table, so an accent nobody anticipated
    /// still gets a legible plate.
    static func contrastingInk(on background: Bitmap.RGBA) -> Bitmap.RGBA {
        contrast(background, nameplateInk) >= contrast(background, nameplateLeadInkDark)
            ? nameplateInk : nameplateLeadInkDark
    }

    static func contrast(_ a: Bitmap.RGBA, _ b: Bitmap.RGBA) -> Double {
        let first = relativeLuminance(a), second = relativeLuminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    static func relativeLuminance(_ colour: Bitmap.RGBA) -> Double {
        func channel(_ raw: UInt8) -> Double {
            let value = Double(raw) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(colour.r) + 0.7152 * channel(colour.g)
            + 0.0722 * channel(colour.b)
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
