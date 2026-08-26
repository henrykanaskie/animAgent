import Foundation

/// **Whether a desk object's screen is on.** [ADR-006 §12]
///
/// It says one thing and it is the turn: the screen is `lit` while the agent
/// holds a turn and `dark` when it does not. It is not the open-call set: a
/// call is 23 ms at the median and a screen that blinked with one would be the
/// strobe with a bigger sprite, and it is not a mood.
///
/// **Two of the four kinds have a screen**; see `WorkKind.hasScreen`, which is
/// where the abstention is argued. Passing `.dark` to a kind that draws paper
/// returns the same bitmap as `.lit`, because turning paper off is fiction.
/// [I1]
public enum DeskScreen: Sendable, Hashable {
    case lit
    case dark
}

/// The fourth desk-top object ADR-006 §1 names and could not declare: a desk
/// monitor with a lit screen, for `running` (`Bash`, `BashOutput`, `KillShell`).
///
/// # Why this file exists rather than a fourth `manifest.json` entry
///
/// `DeskTopObjectTests.theRejectedMonitorSinglesExceedTheBoundAndTheDeclaredThreeDoNot`
/// proves it over the pixels: every single in the pack's desk-monitor band
/// (130–134) measures 30–32 px wide against the 28 px SS2c bound, so no pack
/// single can be bound to this role. `running` is bound to `Bash`, and `Bash`
/// is the most common tool in `fixtures/` (37 calls against `Read`'s 19: see
/// `docs/ADR-006-the-desk-says-the-work.md` §3b), so the missing kind is the
/// one most agents would need, and its absence draws the same bare desk as
/// abstention, which inverts the feature the other three kinds exist for.
///
/// **Authoring is precedented and is not an I1 violation.** `HeldObjectArt`'s
/// own doc comment says it and this file relies on the same sentence: "I1
/// forbids the room asserting *data* the hooks did not give us; it says
/// nothing about who drew the pixels." Three things in this room are authored
/// rather than sourced: four of seven badges, every nameplate, the `×N` chip,
/// and `HeldObjectArt` is a fourth. This is a fifth, following its shape
/// exactly: a design grid in the pack's own inks,
/// doubled onto whole pixels, checked by a test that measures rather than
/// trusts.
///
/// # Who reads it
///
/// `RoomScene.deskObjectArt` does, for `running`. **That sentence used to read
/// "nothing yet reads it"**, which was true only for the few hours between this
/// file being written and the binding landing; it is recorded here because a
/// stale "not wired up yet" is the kind of comment that makes a reader go
/// looking for a bug that does not exist.
///
/// This file still declares and measures the art and nothing else: no
/// `WorkKind` case, no chooser, no classifier. ADR-006 §5a keeps that in
/// `SceneDirector`.
///
/// **No manifest entry, on purpose.** This object has no source PNG to point at
///: it is drawn by the scene, exactly like `DeskWorkArt`, `HeldObjectArt`,
/// `SceneBitmaps.nameplate` and the four authored badges, none of which carry a
/// manifest entry either. A manifest key with no file behind it would be the
/// thing M5c already refused for the placeholder badges: a declaration that
/// outruns what is actually on disk.
///
/// `laptop`, `papers` and `pad` are still declared in the manifest and are now
/// read by nothing: see `WorkKind.propRole` for why they are left there.
enum DeskMonitorArt {

    // MARK: - Palette: the pack's own inks, not new colours

    /// Sampled from `assets/processed/room/32x32/singles/`, not chosen: this is
    /// the dark structural ink common to `desk` (single 34), `laptop` (135),
    /// `papers` (153) and `pad` (179) alike: `(154, 154, 170)` appears in the
    /// top colour table of all four processed files. It is the room pack's own
    /// "outline/casing" step after `scripts/process-assets.py`'s desaturation
    /// and value-compression pass, which is why it is safe to reuse rather than
    /// a new invention: it already cleared I7 once, four times over, before
    /// this file existed.
    ///
    /// Value **0.667**, inside the room's measured `[0.55, 0.92]` band
    /// (`04-ART-DIRECTION.md`, "The palette rule is now a build step").
    ///
    /// **Re-sampled at ADR-015**, which put every theme and the room itself on
    /// the pack's own saturation. It was `(154, 154, 170)` at saturation 0.094.
    /// This is the **same source pixel**: identical value 0.667 and identical
    /// hue 240 deg, at the saturation the pack drew it with, 0.276. The 25%
    /// saturation ceiling this comment used to cite no longer applies to any
    /// room art; the value band it also cites is unchanged and still does.
    static let outline = Bitmap.RGBA(123, 123, 170)

    /// The pack's own **lit-screen** ink: sampled from
    /// `Modern_Office_Singles_32x32_135.png` (the declared `laptop` single)
    /// where it is the brightest, most saturated pixel in the file. It is the
    /// same colour a desk-monitor single (130–134) uses for its own screen,
    /// confirmed by direct pixel sampling of both files rather than assumed
    /// from the family resemblance.
    ///
    /// **This is the "lit screen" budget the brief names.** The `laptop`
    /// declaration's own screen measures saturation 0.183 against the room's
    /// **Re-sampled at ADR-015.** It was `(182, 198, 222)` at saturation 0.180,
    /// chosen when the room ran on a 25% saturation ceiling. This is the same
    /// source pixel at the pack's own saturation: identical value **0.871**,
    /// identical hue **216 deg**, saturation **0.703**.
    ///
    /// A lit screen is the one place this object is allowed to be the
    /// brightest thing it draws, and it still sits under the room's 0.92 value
    /// ceiling. It is no longer under the cast on the saturation axis, and that
    /// is ADR-015's whole point rather than an oversight: the maintainer asked
    /// for full saturation, I7's saturation half is spent, and its value half,
    /// the one that carries legibility at 32 px, is untouched.
    static let screen = Bitmap.RGBA(66, 129, 222)

    /// A second, slightly darker ink for the two status dots on the screen,
    /// also present in `desk`, `laptop`, `papers` and `pad`'s own colours.
    /// Value **0.686**, hue **240 deg**.
    ///
    /// Its only job is to keep the screen from being one flat rectangle of
    /// `screen`, the way `laptop`'s own single is described in the manifest as
    /// showing "two faint icon dots".
    ///
    /// **Re-sampled at ADR-015** from `(159, 159, 175)`, saturation 0.091: the
    /// same source pixel at the pack's saturation, 0.257, with the value and
    /// hue unmoved.
    static let statusDot = Bitmap.RGBA(130, 130, 175)

    /// **The screen with nothing on it**: `(141, 141, 141)`, saturation
    /// **0.000**, value **0.553**.
    ///
    /// # It is derived rather than sampled, and the reason is measured
    ///
    /// `screen` above was *sampled*, because a lit screen already existed in the
    /// pack. A dark one does not: scanning every opaque pixel of
    /// `assets/processed/room/32x32/`: builder tiles, builder-full and all 339
    /// singles: the whole processed room palette bottoms out at value **0.659**
    /// (`(168, 150, 154)`), because `scripts/process-assets.py` value-compresses
    /// the pack *into* I7's band and the pack's own art never reaches the
    /// bottom of it. There is no pack ink below 0.659 to sample, and 0.659 is
    /// eight hundredths *brighter* than this object's own casing, so sampling
    /// the darkest thing available would draw a screen lighter than the box
    /// around it.
    ///
    /// So it is derived the way `SceneBitmaps.placeholderDesk`'s inks are, and
    /// the derivation is the mirror of `screen`'s own sentence:
    ///
    /// > A lit screen is the one place this object may be the **brightest**
    /// > thing it draws and it still does not reach the room's ceiling. A dark
    /// > screen is the one place it may be the **darkest**, and it sits exactly
    /// > on the room's floor rather than through it.
    ///
    /// I7's room band is `[0.55, 0.92]` (`04-ART-DIRECTION.md`, "The palette
    /// rule is now a build step"). `140/255 = 0.549` is below the floor;
    /// `141/255 = 0.553` is the darkest 8-bit neutral at or above it. Grey
    /// rather than tinted, because an off screen is the absence of emission and
    /// a hue would be a claim about what is not being displayed.
    ///
    /// # What it separates from, measured
    ///
    /// | against | value | Δ |
    /// |---|---:|---:|
    /// | `screen` / `face`, the lit ink | 0.871 | **0.318** |
    /// | `outline`, this object's own casing | 0.667 | 0.114 |
    /// | the room's darkest opaque ink | 0.659 | 0.106 |
    /// | the cast's darkest pixel, dimmed or not | 0.304–0.314 | 0.239 |
    ///
    /// The first number is the one that has to survive `1x`, and it is larger
    /// than the room's entire measured spread from its darkest ink to its mean
    /// (0.659 → 0.785 = 0.126) and larger than the lit screen's own step away
    /// from the casing it sits in (0.204). The second says the dark screen still
    /// reads as a *recess in* the casing rather than dissolving into it: a flat
    /// slab would have been the cheaper answer and a worse picture. The last
    /// says the room still does not own the darkest pixel on screen, which is
    /// the only thing the band's floor exists to protect. [I7]
    static let screenOff = Bitmap.RGBA(141, 141, 141)

    // MARK: - The design grid

    /// The design canvas, **before** the 2x doubling: the same convention
    /// `HeldObjectArt` uses and the one the room pack's own files were built
    /// on: Modern Office ships every single at `16x16` *and* `32x32`, and the
    /// two are pixel-doubled copies of each other (checked by eye against
    /// `Modern_Office_Singles_130.png` and its `32x32` counterpart), so a
    /// design authored at half scale and doubled on the way out is drawn in
    /// the pack's own hand, not a different one.
    static let designWidth = 10
    static let designHeight = 11

    /// The doubled canvas the scene would draw: `20x22`, even in both axes
    /// by construction (any integer doubled is even), so every edge lands on
    /// a whole pixel at 1x, 2x and 3x. [I6]
    static var canvasWidth: Int { designWidth * 2 }
    static var canvasHeight: Int { designHeight * 2 }

    /// `.` transparent, `o` the dark structural ink, `a` the lit screen,
    /// `b` a status dot.
    ///
    /// **The family, and why this reads as a fourth silhouette rather than a
    /// smaller pad.** ADR-006 §1a names the intended shape: "an upright
    /// rectangle on a stalk". Eleven design rows, top to bottom:
    ///
    /// - **rows 0–5, a bordered rectangle**: the screen, `10` design columns
    ///   wide, the widest part of the object;
    /// - **rows 6–8, a two-column stalk**: a deliberate **waist**, four times
    ///   narrower than the screen above it. This is the one feature `pad`
    ///   (single 179, "book or pad standing upright on its spine, on a small
    ///   base") does not have: a book stands directly on its own spine, so its
    ///   silhouette is one near-constant width top to bottom. A stalk this
    ///   narrow, this far from either end, is what a flattened silhouette
    ///   keeps and a pad's outline does not have to lose.
    /// - **rows 9–10, a flared base**: 6 then 8 design columns, narrower than
    ///   the screen and wider than the stalk, so the shape reads
    ///   screen-neck-foot rather than two disconnected rectangles.
    ///
    /// This is also why it is not a smaller `papers` (153, "a low flat slab",
    /// wide and short, no vertical structure at all) and not a `laptop` (135,
    /// a diagonal wedge silhouette: this shape has no diagonal edge anywhere).
    /// `DeskMonitorArtTests.theSilhouetteHasAWaistNoSiblingHas` checks the
    /// waist as a row-width profile rather than trusting the picture in this
    /// comment.
    private static let design: [String] = [
        "oooooooooo",
        "oaaaaaaaao",
        "oaabaabaao",
        "oaaaaaaaao",
        "oaaaaaaaao",
        "oooooooooo",
        "....oo....",
        "....oo....",
        "....oo....",
        "..oooooo..",
        ".oooooooo.",
    ]

    /// The design, doubled onto the `20x22` canvas: `HeldObjectArt.bitmap`'s
    /// own construction, one design grid smaller.
    ///
    /// **`screen: .dark` repaints the glass and nothing else.** `a` and `b` are
    /// both *inside* the bordered rectangle: the field and the two icon dots,
    /// so a dark screen takes both: a monitor that is off does not keep its
    /// status lights. The `o` casing, the stalk and the base are the same pixels
    /// in either state, because a screen going dark is not a monitor changing
    /// shape: the silhouette is the object's identity [ADR-006 §1a] and this
    /// channel may not touch it.
    static func bitmap(screen state: DeskScreen = .lit) -> Bitmap {
        var bitmap = Bitmap(width: canvasWidth, height: canvasHeight)
        for (row, line) in design.enumerated() {
            for (column, character) in line.enumerated() {
                let colour: Bitmap.RGBA
                switch (character, state) {
                case ("o", _): colour = outline
                case ("a", .lit): colour = screen
                case ("b", .lit): colour = statusDot
                case ("a", .dark), ("b", .dark): colour = screenOff
                default: continue
                }
                bitmap.fill(x: column * 2, y: row * 2, w: 2, h: 2, colour)
            }
        }
        return bitmap
    }
}
