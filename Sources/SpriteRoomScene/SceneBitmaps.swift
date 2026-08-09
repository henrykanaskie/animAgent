import Foundation

/// What a nameplate says, split into the two things it has to say.
///
/// **The split exists because the two halves are not equally informative**, and
/// which half is which was got backwards twice. A single line spent its first
/// eight glyphs on the type and its last three, after an ellipsis, on the
/// discriminator. Splitting the rows fixed the ordering and then over-corrected:
/// the discriminator got the accent band at 2× and the type got the small row,
/// so the loudest element in the room said `430` — the last three hex characters
/// of an `agent_id`, which tells a person nothing — and the useful half read
/// `GENERAL-P…` underneath at half the size.
///
/// **The type is what identifies an agent to a person; the discriminator is a
/// tiebreaker between two agents of the same type.** So the type is the
/// headline and the discriminator is the tag beneath it. See
/// `SceneBitmaps.nameplate` for the geometry, which is where the decision lives
/// — not here.
///
/// This is a value type rather than a formatted string so the *geometry* lives
/// in `SceneBitmaps` and the *policy* lives in `SceneDirector`; neither has to
/// parse the other's output. The old `TYPE:XXX` string needed a separator glyph
/// purely to tell a reader where the type stopped, and that separator is free —
/// the rows do it.
///
/// **The two stored names are historical and are now a size too small for what
/// they hold.** `lead` was named for the line that led, and it no longer leads.
/// Renaming it is a rename of `SceneDirector.nameplate(for:)`'s three call sites
/// as well, which is another change's file; `headline` and `tag` below state the
/// mapping once so nothing else has to remember it, and the fields should take
/// those names the next time this struct is opened.
public struct NameplateText: Sendable, Hashable {
    /// The `agent_id` discriminator for a subagent; the name for the main agent,
    /// which has no `agent_id` and so has nothing to discriminate against.
    /// [CLAUDE.md, Identity model]
    ///
    /// **Empty is meaningful**: it says there is nothing that differs, and the
    /// plate then draws the type alone on one row. That is the honest picture
    /// for a subagent whose `agent_id` yielded no usable characters — inventing
    /// a tag for it would be the same mistake as guessing a badge for an
    /// unmapped tool. [I1]
    public var lead: String
    /// `agent_type` — the headline. `nil` or empty when there is none: the main
    /// agent, whose `lead` is then the only thing to draw.
    public var role: String?

    public init(lead: String, role: String? = nil) {
        self.lead = lead
        self.role = role
    }

    /// **The line on the accent band: the `agent_type`, or `lead` when there is
    /// no type.** The fallback is not a second policy — it is the same rule read on
    /// the main agent, which has no `agent_type` at all and whose `lead` is
    /// therefore the only name it has. Nothing is synthesised either way. [I1]
    public var headline: String {
        role.flatMap { $0.isEmpty ? nil : $0 } ?? lead
    }

    /// **The line under the band: the discriminator, and only when something
    /// else is above it.** When the headline already *is* `lead` there is nothing left
    /// to tag, and a plate that repeated its own headline underneath itself
    /// would spend a row saying nothing.
    public var tag: String? {
        guard headline != lead, !lead.isEmpty else { return nil }
        return lead
    }

    /// Stable, collision-free key for the texture cache.
    var textureKey: String { lead + "\u{1}" + (role ?? "") }
}

/// Everything the scene draws itself rather than loading — the nameplate and
/// the placeholder furniture. Pure bitmap arithmetic, no graphics framework, so
/// each of these is inspectable in a test.
public enum SceneBitmaps {

    /// Glyphs the headline gets.
    ///
    /// **Eleven is not a taste; it is the largest number the seat pitch allows.**
    /// A glyph is 5 px plus 1 px of tracking, so eleven is 65 px of text plus
    /// 6 px of plate = **71 px**, against a 96 px seat pitch — a 25 px gap
    /// between neighbouring plates. Twelve would be 77 px and a 19 px gap, which
    /// is exactly the width the maintainer complained read as *nearly touching*.
    ///
    /// The type therefore gets more glyphs than it has ever had: 8 on the M5
    /// single-line plate (`GENERAL…`), 10 on the two-row plate that put the
    /// discriminator first (`GENERAL-P…`), 11 now (`GENERAL-PU…`). The ellipsis
    /// stays because it is the honest fallback — see
    /// `SceneDirector.nameplate(for:)` for why no abbreviation scheme replaced
    /// it.
    public static let nameplateTypeGlyphLimit = 11

    /// Glyphs the tag line gets, at 1×.
    ///
    /// Five rather than three so nothing can be clipped by surprise: the tag is
    /// normally the three-character discriminator, but the same construction
    /// draws the overflow plate's `MORE`, and five glyphs is 29 px — well inside
    /// the headline's own budget, so the tag never decides the plate's width.
    public static let nameplateTagGlyphLimit = 5

    /// 1 px border + 2 px of air on each side.
    private static let platePadX = 3
    /// Air above and below the tag row. One pixel, not two, because height is
    /// the axis under pressure: the plate has to stay shorter than the tile
    /// between the aisle and the seat row. See `maximumNameplateHeight`.
    private static let platePadY = 1
    /// Air above and below the headline, inside the accent band.
    ///
    /// Two rather than one, and the extra pixel is the only thing in this file
    /// that is a matter of taste rather than arithmetic. A band cut tight to a
    /// 5×7 face reads as a strip of colour with letters jammed in it; one more
    /// pixel each way makes it a field with a word standing in it, which is what
    /// the headline row is supposed to be. It costs 2 px of a plate that has 11
    /// px of slack under the tile. [see `maximumNameplateHeight`]
    private static let plateHeadY = 2
    /// Extra air under the tag row so the bottom border does not sit against
    /// the descender-less glyphs.
    private static let plateFootY = 2

    public static let nameplateInk = Bitmap.RGBA(238, 238, 244)
    /// **Fully opaque.** It was `alpha 235` — 8% of whatever is behind it came
    /// through, which was invisible against today's near-empty grey floor and
    /// will not be against a furnished themed room. A plate that borrows its
    /// contrast from the background does not survive a change of background.
    public static let nameplatePlate = Bitmap.RGBA(26, 24, 32, 255)
    /// Ink for the headline when it sits on the accent rather than the plate.
    public static let nameplateBandInkDark = Bitmap.RGBA(20, 18, 26, 255)

    /// The nameplate: a solid accent band carrying the **agent type**, and the
    /// `agent_id` discriminator beneath it on the dark plate.
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
    /// - the **headline** is the `agent_type`, which is what an agent is *called*
    ///   — `Explore`, `security-reviewer`, a name the user wrote themselves — and
    ///   is therefore the only thing on the plate a person can act on;
    /// - the **tag** is the discriminator, which is the tiebreaker between two
    ///   agents of one type and nothing else. It is real data and it stays, at a
    ///   size that matches what it is worth.
    ///
    /// **The hierarchy used to be the other way up and that was the defect.**
    /// The band — the loudest element in the room — read `430`, the last three
    /// hex characters of an `agent_id`, at 2× on a saturated field, while
    /// `GENERAL-P…` sat under it at half the size. A user reading the room got
    /// the tiebreaker first and the answer second. What changed is only the
    /// *assignment*: the band, the two rows and the construction are what they
    /// were.
    ///
    /// **The hierarchy is carried by position and field, not by size, and that
    /// is forced.** The type is arbitrary user text — `general-purpose`,
    /// `claude-code-guide` — and the plate has 66 px of interior before it
    /// starts eating the gap between two seats. 66 px at 2× is five glyphs:
    /// `GENE…`, `SECU…`, `CLAU…`, which is not an identification and collapses
    /// `claude-code-guide` onto every other `claude-code-*`. So there is no
    /// horizontal magnification available to the line that most needs it.
    ///
    /// **Vertical-only magnification was tried and is rejected on the
    /// evidence.** A 1×-wide, 2×-tall headline fits eleven glyphs and doubles
    /// the ink, and it was implemented and rendered into a seven-agent room at
    /// `1x` — the only scale the app uses. It is *less* legible, not more: a
    /// 5×14 cell keeps 1 px vertical strokes against 2 px horizontal ones and
    /// keeps 1 px of tracking beside a 14 px glyph, so words turn into a picket
    /// fence and `MAIN` reads as `MFIN`. Stretching one axis of a face designed
    /// on a square grid is not the same operation as doubling both, and the
    /// frames are the argument. The headline is therefore drawn at 1×, exactly
    /// as the tag is, and what separates them is that one sits on the accent
    /// band and one does not.
    ///
    /// The band's ink is picked per accent by contrast rather than fixed, so a
    /// dark accent gets light glyphs and a light one gets dark. Six hues 60°
    /// apart cannot all be light. [criterion 5]
    public static func nameplate(
        _ text: NameplateText, accent: Bitmap.RGBA, font: PixelFont = .standard
    ) -> Bitmap {
        let headline = font.fit(text.headline, limit: nameplateTypeGlyphLimit)
        let tag = text.tag.map { font.fit($0, limit: nameplateTagGlyphLimit) }
        let headlineWidth = headline.isEmpty ? 0 : font.width(of: headline)
        let tagWidth = tag.map { font.width(of: $0) } ?? 0

        let width = max(1, max(headlineWidth, tagWidth)) + 2 * platePadX
        // An empty headline keeps a one-pixel stub of band rather than none, so
        // the accent still reads as a rule along the top and every plate in the
        // room shares a construction.
        let band = headline.isEmpty ? platePadY : font.glyphHeight + 2 * plateHeadY
        let tagBand = tag == nil ? 0 : font.glyphHeight + platePadY + plateFootY
        let height = max(band + tagBand, 3)

        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, nameplatePlate)
        bitmap.fill(x: 0, y: 0, w: width, h: band, accent)
        bitmap.stroke(x: 0, y: 0, w: width, h: height, accent)
        if !headline.isEmpty {
            font.draw(
                headline, into: &bitmap,
                x: (width - headlineWidth) / 2, y: plateHeadY,
                colour: contrastingInk(on: accent))
        }
        if let tag {
            font.draw(
                tag, into: &bitmap,
                x: (width - tagWidth) / 2, y: band + platePadY, colour: nameplateInk)
        }
        return bitmap
    }

    /// The worst case the font and the limits can produce, in both axes at once:
    /// a full-width headline over a full-width tag. `M` because it is the widest
    /// glyph in the table and every glyph is the same width anyway, so this is
    /// the bound rather than a sample.
    private static var largestPossiblePlate: Bitmap {
        nameplate(
            NameplateText(
                lead: String(repeating: "M", count: nameplateTagGlyphLimit),
                role: String(repeating: "M", count: nameplateTypeGlyphLimit)),
            accent: .clear)
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
    public static var maximumNameplateHeight: Int { largestPossiblePlate.height }

    /// Widest plate the font and the limits can produce.
    public static var maximumNameplateWidth: Int { largestPossiblePlate.width }

    /// Whichever of the two inks reads better on `background`, by WCAG relative
    /// luminance. A rule rather than a table, so an accent nobody anticipated
    /// still gets a legible plate.
    static func contrastingInk(on background: Bitmap.RGBA) -> Bitmap.RGBA {
        contrast(background, nameplateInk) >= contrast(background, nameplateBandInkDark)
            ? nameplateInk : nameplateBandInkDark
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

    /// The word under the count on the overflow plate.
    ///
    /// Small, on the tag line, for the reason the nameplate's tag line is small:
    /// the number is the thing that differs and the word is context. That is the
    /// same rule the character plate follows and it lands the other way round
    /// here, which is the test that the rule is a rule: on a character plate the
    /// type is what a person can act on, and on this plate there is no type —
    /// only a count.
    /// "MORE" rather than a noun because the plate stands in a room full of
    /// characters and the only true statement it can make is that there are
    /// this many more of them than are drawn.
    public static let overflowLabel = "MORE"

    /// **The plate that says how many agents the room has no seat for.**
    ///
    /// The room has seven seats and cannot honestly have more — see
    /// `RoomLayout.seatCapacity` for why neither raising the count nor reusing
    /// the back row survives its own arithmetic. What it can do is show the
    /// seats it has and say out loud that there are `count` more, which asserts
    /// nothing false [I1] and keeps the count answerable: seven characters plus
    /// "+1" is still eight. The alternative — seating the eighth agent on top of
    /// the first — is the room stating a population that is wrong, and quietly
    /// dropping it is the same lie with nothing on screen to catch it.
    ///
    /// **It is a nameplate with no accent, and that is deliberate.** Same
    /// construction, same font, same two rows, so it reads as the room's own
    /// lettering rather than as chrome bolted on; but every character's plate
    /// carries a saturated accent band assigned 60° apart, and this one carries
    /// the plate colour itself. So it cannot be mistaken for somebody's
    /// identity — there is nobody it belongs to.
    ///
    /// The count goes in `role` and the word in `lead`, which reads backwards
    /// until you remember that neither field is a position: `role` is the field
    /// the plate draws as its **headline**, and on this plate the count is the
    /// headline. See `NameplateText.headline` — the fields' names are older than
    /// the layout and are noted there as due a rename.
    public static func overflowPlate(_ count: Int, font: PixelFont = .standard) -> Bitmap {
        nameplate(
            NameplateText(lead: overflowLabel, role: "+\(max(0, count))"),
            accent: nameplatePlate, font: font)
    }

    /// The letter the dormancy tab carries. The pack's `sleep` glyph is a `Z`
    /// and this says the same thing in the room's own lettering — the assertion
    /// is not being changed, only its volume. [I1]
    public static let dormancyLabel = "Z"

    /// **The tab that says a character finished a turn — deliberately not a
    /// bubble.**
    ///
    /// # The defect this exists for
    ///
    /// The room renders at `1x` always (`RoomCamera.comfortablePopulation` is
    /// empty), and at `1x` the badge slot's *presence* is the loudest thing on
    /// screen: a bright ~24x28 blob over an ~11 px head. Until this existed the
    /// dormant `Z` was drawn in that slot from the pack's own speech bubble, and
    /// measured against the six tool bubbles it was:
    ///
    /// - **the same shape** — silhouette IoU 0.792, and the sleep silhouette is a
    ///   strict **subset** of every tool bubble (548 px of 692, 100% contained);
    /// - **the same value** — median 210 against a floor of 154;
    /// - **the same size in the room** — 548 badge-slot pixels against a working
    ///   badge's 678, i.e. **84%**, measured off a real 1x frame.
    ///
    /// So six glyphs meant *this agent is working* and a seventh, in the same
    /// slot at 84% of the size, meant *this agent has finished*. A fresh-eyes
    /// evaluation given a real frame read six bubbles as "six busy, one idle";
    /// the truth was that all six were `Z`, **zero agents were working**, and the
    /// one character with no badge was the only live one. The badge was marking
    /// the dead and its absence was marking the living.
    ///
    /// # What this draws instead, and why this shape
    ///
    /// The `×N` chip's construction, one glyph wide: the plate colour, the room's
    /// own font, 1 px of air. **9x11 px — 15-19% of a working badge's slot
    /// footprint**, against `dim`'s 72% (the same bubble at `alpha 0.3`, tested
    /// and rejected). Extent is what "there is a bubble over that head" is read
    /// from at a glance; value is what it is read from once you have already
    /// looked. Dimming fixes the second and leaves the first, which is why the
    /// tab is small rather than faint.
    ///
    /// It also lands in a **different family**. Every white bubble in this room
    /// is pack art about a tool call; every dark plate is the room's own
    /// lettering about identity. A dormancy tab is a statement about the
    /// character, not about a call, so it belongs to the lettering. Nobody has to
    /// resolve 9 px of `Z` for that to work — telling a dark tab from a white
    /// bubble is a value-and-size judgement, which is what survives `1x`. [I7]
    ///
    /// **It occupies the one badge anchor, not a new one.** The manifest carries
    /// exactly one, and this project has twice refused a second position as "an
    /// eyeballed offset dressed as data". A smaller picture in the same
    /// bottom-centre anchor is not a second anchor.
    ///
    /// **What it gives up.** The pack's `sleep` art is no longer drawn — it stays
    /// declared in `badges.states.sleep`, and `TextureStore.sleepTexture()` stays
    /// with it, because the fact it illustrates is unchanged and the manifest is
    /// where that is recorded. Losing it costs a `Z` nobody could read at `1x`
    /// and buys the distinction the room exists to make.
    public static func dormancyTab(font: PixelFont = .standard) -> Bitmap {
        let width = font.width(of: dormancyLabel) + 4
        let height = font.glyphHeight + 4
        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, nameplatePlate)
        font.draw(dormancyLabel, into: &bitmap, x: 2, y: 2, colour: nameplateInk)
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

    /// The pilot lamp's plate, 9 px square.
    ///
    /// Sized against the room's own lettering rather than picked: the dormancy
    /// tab is 9×11 and is the smallest thing this room draws that a person is
    /// expected to notice, so the lamp is that, square. Anything smaller would
    /// be asserting a legibility nothing in this room has ever demonstrated at
    /// `1x`.
    public static let pilotLampSize = 9

    /// **The room's pilot lamp: is this app still receiving?**
    ///
    /// See `LivenessLamp` for what it means and what drives it. This is only
    /// the picture, and there are exactly three of them, separated by
    /// **extent** rather than by hue or value:
    ///
    /// | phase | core | says |
    /// |---|---|---|
    /// | `lit` | 5×5 | a hook posted to this app landed within the last `hold` |
    /// | `wink` | 3×3 | …and one landed within the last 125 ms — this is the pulse |
    /// | `dark` | none | nothing has landed for `hold`; the listener is not answering |
    ///
    /// **Extent, because extent is what survives `1x`.** That is the dormancy
    /// tab's finding re-used rather than re-derived: "extent is what *there is
    /// something there* is read from at a glance; value is what it is read from
    /// once you have already looked". A lamp that pulsed by changing brightness
    /// would be asking a viewer to resolve two greys in a 9 px square on a
    /// 720×400 panel, which nothing in this project has ever shown a person can
    /// do.
    ///
    /// **The wink contracts rather than extinguishes, and that is the whole
    /// reason there are three pictures instead of two.** If the pulse were an
    /// off-frame, then "no ink in the lamp" would mean *either* the pulse *or*
    /// a dead listener, and a glance landing inside a 125 ms wink would read as
    /// "broken" — the exact confusion this feature exists to remove, moved from
    /// the room into the indicator. With a contraction the rule is total and
    /// has no exceptions to remember:
    ///
    /// > **Any ink inside the lamp means a request landed within the last
    /// > `hold`. No ink means none did.**
    ///
    /// **It introduces no colour the room does not already draw.** [I7] The
    /// plate and the ink are the nameplate's own two values, so the lamp cannot
    /// own a more saturated pixel than the room already permits, cannot own a
    /// darker one than every nameplate already does, and needs no new entry in
    /// any palette argument. It is chrome about the app, drawn in the room's
    /// lettering family, which is the same family the overflow plate is in and
    /// for the same reason: it is a caption on the picture, not a thing in it.
    public static func pilotLamp(core: Int) -> Bitmap {
        let size = pilotLampSize
        var bitmap = Bitmap(width: size, height: size)
        bitmap.fill(x: 0, y: 0, w: size, h: size, nameplatePlate)
        let width = max(0, min(core, size - 2))
        if width > 0 {
            let origin = (size - width) / 2
            bitmap.fill(x: origin, y: origin, w: width, h: width, nameplateInk)
        }
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
