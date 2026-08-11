import Foundation

/// The fourth desk-top object ADR-006 §1 names and could not declare: a desk
/// monitor with a lit screen, for `running` (`Bash`, `BashOutput`, `KillShell`).
///
/// # Why this file exists rather than a fourth `manifest.json` entry
///
/// `DeskTopObjectTests.theRejectedMonitorSinglesExceedTheBoundAndTheDeclaredThreeDoNot`
/// proves it over the pixels: every single in the pack's desk-monitor band
/// (130–134) measures 30–32 px wide against the 28 px SS2c bound, so no pack
/// single can be bound to this role. `running` is bound to `Bash`, and `Bash`
/// is the most common tool in `fixtures/` (37 calls against `Read`'s 19 — see
/// `docs/ADR-006-the-desk-says-the-work.md` §3b), so the missing kind is the
/// one most agents would need, and its absence draws the same bare desk as
/// abstention, which inverts the feature the other three kinds exist for.
///
/// **Authoring is precedented and is not an I1 violation.** `HeldObjectArt`'s
/// own doc comment says it and this file relies on the same sentence: "I1
/// forbids the room asserting *data* the hooks did not give us; it says
/// nothing about who drew the pixels." Four things in this room are already
/// authored rather than sourced — four of seven badges, every nameplate, the
/// `×N` chip, the dormancy tab — and `HeldObjectArt` is a fifth. This is a
/// sixth, following its shape exactly: a design grid in the pack's own inks,
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
/// This file still declares and measures the art and nothing else — no
/// `WorkKind` case, no chooser, no classifier. ADR-006 §5a keeps that in
/// `SceneDirector`.
///
/// **No manifest entry, on purpose.** This object has no source PNG to point at
/// — it is drawn by the scene, exactly like `DeskWorkArt`, `HeldObjectArt`,
/// `SceneBitmaps.nameplate` and the four authored badges, none of which carry a
/// manifest entry either. A manifest key with no file behind it would be the
/// thing M5c already refused for the placeholder badges: a declaration that
/// outruns what is actually on disk.
///
/// `laptop`, `papers` and `pad` are still declared in the manifest and are now
/// read by nothing — see `WorkKind.propRole` for why they are left there.
enum DeskMonitorArt {

    // MARK: - Palette — the pack's own inks, not new colours

    /// Sampled from `assets/processed/room/32x32/singles/`, not chosen: this is
    /// the dark structural ink common to `desk` (single 34), `laptop` (135),
    /// `papers` (153) and `pad` (179) alike — `(154, 154, 170)` appears in the
    /// top colour table of all four processed files. It is the room pack's own
    /// "outline/casing" step after `scripts/process-assets.py`'s desaturation
    /// and value-compression pass, which is why it is safe to reuse rather than
    /// a new invention: it already cleared I7 once, four times over, before
    /// this file existed.
    ///
    /// Saturation **0.094**, value **0.667** — both well inside the room's
    /// measured band, `[0.55, 0.92]` value and 25% saturation
    /// (`04-ART-DIRECTION.md`, "The palette rule is now a build step").
    static let outline = Bitmap.RGBA(154, 154, 170)

    /// The pack's own **lit-screen** ink — sampled from
    /// `Modern_Office_Singles_32x32_135.png` (the declared `laptop` single)
    /// where it is the brightest, most saturated pixel in the file. It is the
    /// same colour a desk-monitor single (130–134) uses for its own screen,
    /// confirmed by direct pixel sampling of both files rather than assumed
    /// from the family resemblance.
    ///
    /// **This is the "lit screen" budget the brief names.** The `laptop`
    /// declaration's own screen measures saturation 0.183 against the room's
    /// 0.25 ceiling; this colour measures **0.180** — the same pixel, to
    /// within a rounding step, because it is the same file. Value **0.871**,
    /// under the room's 0.92 ceiling. A lit screen is the one place this
    /// object is allowed to be the brightest, most saturated thing it draws,
    /// and it still does not reach the room's own ceiling, let alone a
    /// character's.
    static let screen = Bitmap.RGBA(182, 198, 222)

    /// A second, slightly darker neutral for the two status dots on the
    /// screen — `(159, 159, 175)`, also present in `desk`, `laptop`, `papers`
    /// and `pad`'s own top colours. Saturation **0.091**, value **0.686**.
    /// Its only job is to keep the screen from being one flat rectangle of
    /// `screen`, the way `laptop`'s own single is described in the manifest as
    /// showing "two faint icon dots".
    static let statusDot = Bitmap.RGBA(159, 159, 175)

    // MARK: - The design grid

    /// The design canvas, **before** the 2x doubling — the same convention
    /// `HeldObjectArt` uses and the one the room pack's own files were built
    /// on: Modern Office ships every single at `16x16` *and* `32x32`, and the
    /// two are pixel-doubled copies of each other (checked by eye against
    /// `Modern_Office_Singles_130.png` and its `32x32` counterpart), so a
    /// design authored at half scale and doubled on the way out is drawn in
    /// the pack's own hand, not a different one.
    static let designWidth = 10
    static let designHeight = 11

    /// The doubled canvas the scene would draw — `20x22`, even in both axes
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
    /// - **rows 0–5, a bordered rectangle** — the screen, `10` design columns
    ///   wide, the widest part of the object;
    /// - **rows 6–8, a two-column stalk** — a deliberate **waist**, four times
    ///   narrower than the screen above it. This is the one feature `pad`
    ///   (single 179, "book or pad standing upright on its spine, on a small
    ///   base") does not have: a book stands directly on its own spine, so its
    ///   silhouette is one near-constant width top to bottom. A stalk this
    ///   narrow, this far from either end, is what a flattened silhouette
    ///   keeps and a pad's outline does not have to lose.
    /// - **rows 9–10, a flared base** — 6 then 8 design columns, narrower than
    ///   the screen and wider than the stalk, so the shape reads
    ///   screen-neck-foot rather than two disconnected rectangles.
    ///
    /// This is also why it is not a smaller `papers` (153, "a low flat slab" —
    /// wide and short, no vertical structure at all) and not a `laptop` (135,
    /// a diagonal wedge silhouette — this shape has no diagonal edge anywhere).
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

    /// The design, doubled onto the `20x22` canvas — `HeldObjectArt.bitmap`'s
    /// own construction, one design grid smaller.
    static func bitmap() -> Bitmap {
        var bitmap = Bitmap(width: canvasWidth, height: canvasHeight)
        for (row, line) in design.enumerated() {
            for (column, character) in line.enumerated() {
                let colour: Bitmap.RGBA
                switch character {
                case "o": colour = outline
                case "a": colour = screen
                case "b": colour = statusDot
                default: continue
                }
                bitmap.fill(x: column * 2, y: row * 2, w: 2, h: 2, colour)
            }
        }
        return bitmap
    }
}
