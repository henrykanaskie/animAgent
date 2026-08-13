import Foundation

/// What a nameplate says: three candidate lines, of which the plate draws
/// exactly one.
///
/// **The plate is one row — see `SceneBitmaps.nameplate`.** The maintainer, at
/// the running app: *"the nameplates are still wrong, they take up too much
/// space, should just have the summary of what they are doing in one or 2
/// words. and that's it."* So this type is no longer a stack of rows to be laid
/// out; it is the input to a **ladder**, and `headline` is the whole of the
/// layout decision.
///
/// It stays a value type rather than a formatted string so the *geometry* lives
/// in `SceneBitmaps` and the *policy* lives in `SceneDirector`; neither has to
/// parse the other's output.
///
/// **What went with the rows.** The plate used to carry the `agent_type` on a
/// second row and the `agent_id` discriminator on a third. Both are gone from
/// the room — the discriminator is no longer even produced (see
/// `SceneDirector.nameplate(for:)`), and the type is drawn only when there is
/// no task to outrank it. The cost is recorded where it bites:
/// `SceneDirectorTests.twoNearlyIdenticalDispatchesNowShareAPlateEntirely`.
public struct NameplateText: Sendable, Hashable {
    /// The name for an agent that has nothing more specific — the main agent,
    /// whose absence of an `agent_id` *is* its identity [CLAUDE.md, Identity
    /// model], and the overflow plate, which belongs to nobody.
    ///
    /// It is the bottom rung of `headline`'s ladder and is drawn only when the
    /// two rungs above it are empty. Empty is legal and means the plate has
    /// nothing to say at all; nothing is invented to fill it. [I1]
    public var lead: String
    /// `agent_type` — the headline for a subagent we never saw a dispatch for.
    /// `nil` or empty when there is none: the main agent, whose `lead` is then
    /// the only thing to draw.
    public var role: String?

    /// **What this agent was dispatched to do, already shortened.** One or two
    /// words off the `Agent` call's own `tool_input.description` — never a
    /// paraphrase, and never present unless a real dispatch carried one. [I1]
    ///
    /// **It arrives after the plate is already on screen** and it is the reason
    /// `SpriteIntent.setNameplate` exists: `agentTasked` rides one event behind
    /// the `SubagentStart` that created the character. The plate does not change
    /// shape when it lands — one row before, one row after — so the update is a
    /// single substitution on a line that keeps its size and its position.
    ///
    /// The shortening itself is `SceneDirector.taskLine(_:)`. This field holds
    /// its output, not the raw description: the raw string is unbounded and the
    /// texture cache is keyed on what is drawn.
    public var task: String?

    public init(lead: String, role: String? = nil, task: String? = nil) {
        self.lead = lead
        self.role = role
        self.task = task
    }

    /// **The plate's one line: the most specific true thing it knows about this
    /// character.** The task if a dispatch gave it one, else the `agent_type`,
    /// else `lead`.
    ///
    /// **One ladder, and now it is also the whole layout.** Its bottom rung is
    /// the rule the main agent has always taken — no `agent_type` at all, so
    /// `lead` is the only name it has — and its top rung is the maintainer's
    /// instruction that the task is what they want to read. Nothing is
    /// synthesised at any rung: an agent with no task shows its type, which is a
    /// true statement about it, and never a placeholder shaped like a task. [I1]
    ///
    /// The rungs below the one taken are not drawn *anywhere*. That is the
    /// point of the change and it is a real loss, stated at
    /// `SceneBitmaps.nameplate`.
    public var headline: String {
        if let task, !task.isEmpty { return task }
        return role.flatMap { $0.isEmpty ? nil : $0 } ?? lead
    }

    /// Stable, collision-free key for the texture cache.
    var textureKey: String { lead + "\u{1}" + (role ?? "") + "\u{1}" + (task ?? "") }
}

/// Everything the scene draws itself rather than loading — the nameplate and
/// the placeholder furniture. Pure bitmap arithmetic, no graphics framework, so
/// each of these is inspectable in a test.
public enum SceneBitmaps {

    /// Glyphs the plate's one line gets — the task, or the `agent_type` when
    /// there is no task.
    ///
    /// **Ten, and the causality behind the number has been turned round.** It
    /// was eleven, chosen as *the largest number the 96 px seat pitch allows*:
    /// a glyph is 5 px plus 1 px of tracking, so eleven was 65 px of text plus
    /// 6 px of plate = 71 px, and twelve would have been 77 px against a pitch
    /// the plate was not allowed to argue with.
    ///
    /// The pitch is no longer the given. The plate is **the widest thing any
    /// character owns** — a body is 32 px, a desk 32–40 — so it is the plate
    /// that sets the pitch and not the other way round, and the pitch is
    /// quantised to whole 32 px tiles. That makes **64 the only target worth
    /// hitting**: a plate of 65 and a plate of 95 both buy the same three-tile
    /// pitch, so the entire range 65…95 is width spent for nothing.
    ///
    /// Ten glyphs at `platePadX` 2 is `59 + 4 =` **63 px**, which clears 64 with
    /// a pixel to spare. Eleven at the same padding is 69 and clears nothing.
    ///
    /// **Losing the rows freed height, not width, and this is where that is
    /// recorded.** The obvious move once the type and the discriminator left the
    /// plate was to spend their width on the line that remains — more glyphs is
    /// fewer collisions. It was measured and it is refused, for two reasons that
    /// do not depend on each other:
    ///
    /// - **The 65…95 dead band is unchanged.** It is a property of the 32 px
    ///   tile, not of how many rows the plate has, so eleven or twelve glyphs
    ///   still buys nothing and still puts the plate the wrong side of 64.
    /// - **It would not fix the collision it is for.** `Touch file s1` needs
    ///   *thirteen* glyphs to reach the `S1` — at eleven and twelve it clips to
    ///   `TOUCH FILE…` and still collides with `Touch file s2`. Thirteen is
    ///   81 px, which `RoomLayout.minimumSeatSpacingTiles` prices at a **four**
    ///   tile pitch, a 128 px seat spacing, and three seat columns then span
    ///   more than the 360 px a `2x` frame gives — so the one width that would
    ///   fix it is the one that costs `2x`. [`RoomCamera.defaultComfortablePopulation`]
    ///
    /// The ellipsis stays because it is the honest fallback — see
    /// `SceneDirector.taskLine(_:)` for why no abbreviation scheme replaced it.
    public static let nameplateGlyphLimit = 10

    /// 1 px border + 1 px of air on each side.
    ///
    /// **The second pixel of air was the cheapest 2 px in the room and it is
    /// gone.** It bought nothing legibility owns: the glyphs still never touch
    /// the border, which is the property that matters at `1x` — ink against a
    /// frame merges into it. What it cost was width, and width is what decides
    /// the seat pitch.
    private static let platePadX = 2
    /// Air above and below the line, inside the accent band.
    ///
    /// Two rather than one, and the extra pixel is the only thing in this file
    /// that is a matter of taste rather than arithmetic. A band cut tight to a
    /// 5×7 face reads as a strip of colour with letters jammed in it; one more
    /// pixel each way makes it a field with a word standing in it, which is what
    /// the plate is supposed to be. It is the whole of the plate's height budget
    /// now that there is nothing under the band: 7 + 4 = 11 px.
    /// [see `maximumNameplateHeight`]
    private static let plateHeadY = 2

    public static let nameplateInk = Bitmap.RGBA(238, 238, 244)
    /// The dark field the room's own lettering sits on: the overflow plate, the
    /// dormancy tab, the `×N` chip and the pilot lamp. **A character's nameplate
    /// no longer draws it at all** — the plate is one accent band edge to edge
    /// now, and this colour went out with the rows underneath it.
    ///
    /// **Fully opaque.** It was `alpha 235` — 8% of whatever is behind it came
    /// through, which was invisible against today's near-empty grey floor and
    /// will not be against a furnished themed room. A plate that borrows its
    /// contrast from the background does not survive a change of background.
    public static let nameplatePlate = Bitmap.RGBA(26, 24, 32, 255)
    /// Ink for the line when the accent it sits on is light.
    public static let nameplateBandInkDark = Bitmap.RGBA(20, 18, 26, 255)

    /// The nameplate: **one accent band carrying one line — what this agent was
    /// dispatched to do**, in a word or two, and nothing else.
    ///
    /// The line is a ladder, not three layouts: task, else `agent_type`, else
    /// `lead`. See `NameplateText.headline`.
    ///
    /// # Why one row
    ///
    /// The maintainer, looking at the running app: *"the nameplates are still
    /// wrong, they take up too much space, should just have the summary of what
    /// they are doing in one or 2 words. and that's it."* The plate was three
    /// rows for a tasked agent — task on the band, `agent_type` under it, the
    /// `agent_id` discriminator under that, 63 × 29 px hanging under a 32 px
    /// character. It is 63 × 11 now.
    ///
    /// # What that costs, stated rather than discovered later
    ///
    /// **The discriminator was doing real work and it is gone.**
    /// `fixtures/concurrent-permission-gates.jsonl` dispatches `Touch file s1`
    /// and `Touch file s2`; both shorten to `TOUCH FIL…`, so those two
    /// characters now carry **byte-identical plates** and nothing but their
    /// seats tells them apart. That is a genuine regression in S4 and it is the
    /// price of the instruction, not an oversight — it is pinned by
    /// `SceneDirectorTests.twoNearlyIdenticalDispatchesNowShareAPlateEntirely`
    /// so it stays a known property. The same goes for two untasked subagents of
    /// one type: `GENERAL-P…` twice.
    ///
    /// Nothing was made *false* by this. Every plate still says something the
    /// data said [I1]; the plate simply says less, which is what was asked for.
    ///
    /// **The `agent_type` is no longer stated anywhere in the room** when a task
    /// outranks it. The accent hue is assigned per character rather than per
    /// type, so nothing else carries it.
    ///
    /// # What is unchanged
    ///
    /// - **The accent band is still an identity channel.** M0 measured that this
    ///   cast is not separable by silhouette (7.3% of outline at the best
    ///   six-variant subset) and M2 that hue *sampled from the art* does not
    ///   separate it either (all six inside a 30° arc). The band is not a
    ///   sprite: its hues are assigned 60° apart and lint-enforced, and a solid
    ///   field is catchable peripherally where a one-pixel border is not. The
    ///   plate is now band edge to edge, so that channel got *louder* as the
    ///   plate got smaller.
    /// - **No magnification, in either axis.** Horizontally the plate has 59 px
    ///   of interior, which is five glyphs at 2× — `GENE…`, `SECU…` — not an
    ///   identification. Vertically a 1×-wide, 2×-tall line was implemented and
    ///   rendered at `1x` and is *less* legible, not more: a 5×14 cell keeps 1 px
    ///   vertical strokes against 2 px horizontal ones, so `MAIN` reads as
    ///   `MFIN`. The face is designed on a square grid and survives scaling only
    ///   on both axes at once.
    ///
    /// The band's ink is picked per accent by contrast rather than fixed, so a
    /// dark accent gets light glyphs and a light one gets dark. Six hues 60°
    /// apart cannot all be light. [criterion 5]
    public static func nameplate(
        _ text: NameplateText, accent: Bitmap.RGBA, font: PixelFont = .standard
    ) -> Bitmap {
        let line = font.fit(text.headline, limit: nameplateGlyphLimit)
        let lineWidth = line.isEmpty ? 0 : font.width(of: line)

        let width = max(1, lineWidth) + 2 * platePadX
        // A plate with nothing to say keeps a 3 px stub — two borders and a
        // pixel of accent — rather than vanishing or drawing a blank row. It is
        // unreachable from `SceneDirector.nameplate(for:)`, where every rung of
        // the ladder is non-empty by construction, and is kept because the
        // geometry should not depend on that being true elsewhere.
        let height = line.isEmpty ? 3 : font.glyphHeight + 2 * plateHeadY

        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, accent)
        bitmap.stroke(x: 0, y: 0, w: width, h: height, accent)
        if !line.isEmpty {
            font.draw(
                line, into: &bitmap,
                x: (width - lineWidth) / 2, y: plateHeadY,
                colour: contrastingInk(on: accent))
        }
        return bitmap
    }

    /// The worst case the font and the limit can produce: a full-width line.
    /// `M` because it is the widest glyph in the table and every glyph is the
    /// same width anyway, so this is the bound rather than a sample.
    ///
    /// It is one row because every plate is one row — the bound and the ordinary
    /// case are the same shape now, which is what makes `maximumNameplateHeight`
    /// a constant of the font rather than of who happens to be on screen.
    private static var largestPossiblePlate: Bitmap {
        nameplate(
            NameplateText(lead: String(repeating: "M", count: nameplateGlyphLimit)),
            accent: .clear)
    }

    /// Tallest plate the font and the limits can produce — **11 px**, where the
    /// three-row plate was 29.
    ///
    /// The camera's content band is derived from this rather than from a
    /// formula repeated at the call site, so a change here cannot quietly
    /// overflow the frame; losing two rows took the band from **178 px to
    /// 160 px** on the shipped layout. It is also the number that keeps a
    /// seated character's plate clear of an aisle character's: the two rows are
    /// one tile apart, so a plate taller than a tile would put them in the same
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

    /// The word that follows the count on the overflow plate.
    ///
    /// "MORE" rather than a noun because the plate stands in a room full of
    /// characters and the only true statement it can make is that there are
    /// this many more of them than are drawn.
    ///
    /// It used to be a second row under the count. The plate is one row now, so
    /// the two are one line — `+3 MORE` — which keeps both facts rather than
    /// dropping the word that makes the number a sentence.
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
    /// construction, same font, same single row, so it reads as the room's own
    /// lettering rather than as chrome bolted on; but every character's plate
    /// carries a saturated accent band assigned 60° apart, and this one carries
    /// the plate colour itself. So it cannot be mistaken for somebody's
    /// identity — there is nobody it belongs to.
    ///
    /// **The count leads the line.** It is the half that differs; `MORE` is the
    /// context that makes it a sentence. Both used to have a row each and the
    /// plate has one row now, so they share it. `+12 MORE` is eight glyphs
    /// against the line's ten, so nothing is at risk of clipping until the room
    /// is hiding a thousand agents.
    ///
    /// The whole line goes in `lead`, the ladder's bottom rung: this plate has
    /// no task and no `agent_type` because it belongs to no agent.
    public static func overflowPlate(_ count: Int, font: PixelFont = .standard) -> Bitmap {
        nameplate(
            NameplateText(lead: "+\(max(0, count)) \(overflowLabel)"),
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
    /// The room renders at `2x` up to three agents and at `1x` from four
    /// [`RoomCamera.defaultComfortablePopulation`], so **`1x` is the scale a busy
    /// room is drawn at** — which is exactly when the badge layer most needs
    /// reading. (This paragraph said `1x` *always*, on a
    /// `comfortablePopulation` that has not been empty since `44e82f0`.) At `1x`
    /// the badge slot's *presence* is the loudest thing on screen: a bright
    /// ~24x28 blob over an ~11 px head. Until this existed the dormant `Z` was
    /// drawn in that slot from the pack's own speech bubble, and measured against
    /// the six tool bubbles it was:
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
    // MARK: The floor plan's own ink [ADR-007]

    /// **A vertical floor-plan line**: 2 px dark, 10 px light, 2 px dark, with
    /// the same 2 px dark closing each end.
    ///
    /// The section is measured, not chosen — `docs/06-SET-BUILDING.md` §2, down
    /// x=16 of the pack's own `tile_r01_c01` — and the two colours are the
    /// **manifest's**, taken off the cap tile this surface is drawn with. So
    /// nothing about a partition's appearance lives in `Sources/`: the shape is
    /// the pack's measurement and the ink is the theme's.
    ///
    /// It is authored rather than tiled from the pack because the pack's own
    /// plain runs, T-junctions and jambs are 12–14 px stripes on otherwise empty
    /// tiles, and `scripts/process-assets.py` drops every tile under 60% opaque
    /// — correctly, since laying one as floor would show the void behind the
    /// room. Twenty of the sheet's 161 tiles fall under that cut and they are
    /// exactly the pieces a plan is drawn with. `scripts/compose-scene.py`
    /// reached the same conclusion and draws its runs the same way.
    public static func planLine(
        height: Int, edge: Bitmap.RGBA, fill: Bitmap.RGBA
    ) -> Bitmap {
        let width = RoomPlan.partitionPx
        let height = max(4, height)
        var bitmap = Bitmap(width: width, height: height)
        bitmap.fill(x: 0, y: 0, w: width, h: height, edge)
        bitmap.fill(x: 2, y: 2, w: width - 4, h: height - 4, fill)
        return bitmap
    }

    /// **A doorway jamb**: the 2 px dark edge a gap cut through a 64 px wall band
    /// would otherwise leave raw.
    public static func planJamb(height: Int, colour: Bitmap.RGBA) -> Bitmap {
        var bitmap = Bitmap(width: 2, height: max(1, height))
        bitmap.fillAll(colour)
        return bitmap
    }

    /// **The contact shadow a wall band casts onto its own floor**, four rows
    /// deep, y-down from the band's foot.
    ///
    /// The pack's artists paint one in; without it a 64 px band of wall sits on
    /// the floor with a hard seam and reads as a poster rather than as a wall.
    /// Four rows at 70/46/26/12 alpha, transcribed from
    /// `scripts/compose-scene.py`'s `draw_plan` step 3, which measured them.
    ///
    /// **It is not a prop and it does not move.** It is drawn once at build
    /// time, from the plan alone, and nothing in the delta stream can reach it —
    /// so I7's motion budget has nothing to price here. [ADR-002 §6 rule 1]
    public static func wallContactShadow(width: Int = 32) -> Bitmap {
        let alphas: [UInt8] = [70, 46, 26, 12]
        var bitmap = Bitmap(width: max(1, width), height: alphas.count)
        for (row, alpha) in alphas.enumerated() {
            bitmap.fill(x: 0, y: row, w: bitmap.width, h: 1, Bitmap.RGBA(24, 24, 34, alpha))
        }
        return bitmap
    }

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
