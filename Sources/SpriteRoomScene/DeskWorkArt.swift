import Foundation

/// The three desk-top objects this app draws itself: `authoring`'s laptop,
/// `research`'s paper stack and `coordinating`'s pad.
///
/// `running`'s monitor is next door in `DeskMonitorArt`, which came first and
/// carries the account of the palette these four share. This file follows its
/// construction exactly — a design grid at half resolution, doubled on the way
/// out, in the room pack's own inks.
///
/// # Why these replace art the pack already ships
///
/// The manifest declares `laptop` (single 135), `papers` (153) and `pad` (179)
/// and all three are real depictions of the right objects. They were rendered at
/// the panel's true size and looked at, which is the check that had never been
/// done: **all three are drawn in isometric projection**, at 24–26 px of content
/// on a 32 px canvas, in the pack's palest inks. A maintainer running the room
/// live reported seeing no objects at all, then — once the held layer was added
/// — "just a teal rectangle". The pack's laptop is legible at 4x and mush at the
/// 1x and 2x this panel actually runs at, because a diagonal wedge loses its
/// diagonal first.
///
/// So these are **front-facing** rather than isometric, and they spend the whole
/// placement budget rather than a quarter of it.
///
/// # What is not available, stated plainly
///
/// **Contrast is not a lever here and no amount of authoring will make it one.**
/// I7 gives the room a value band of `[0.55, 0.92]` and 25% saturation, and it
/// exists so that nothing outside the characters owns the darkest pixel on
/// screen — that is the one axis the whole art direction protects. A desk object
/// with a dark outline would read instantly and would be the room breaking its
/// own rule to shout. `HeldObjectArt` is allowed `(58, 58, 80)` precisely
/// because it is drawn *on* a character and is measured against the cast's floor
/// instead; furniture is not.
///
/// What is left is **silhouette and size**, and that is what these designs
/// spend:
///
/// | kind | profile | the feature no sibling has |
/// |---|---|---|
/// | `authoring` | narrow screen over a wider base | it steps *outward* at the hinge |
/// | `research` | a stepped stack, wide and short | no vertical structure at all |
/// | `coordinating` | tall, narrow, constant width | a clip bar across the top |
/// | `running` | screen, stalk, flared foot | a two-column waist |
///
/// Four different outlines, told apart with the colour thrown away — which is
/// the test `theFourProfilesAreTellableApartAsSilhouettesAlone` performs rather
/// than the picture in this comment.
enum DeskWorkArt {

    // MARK: - Palette

    /// The room's structural ink, shared with `DeskMonitorArt` — `(154, 154,
    /// 170)`, saturation 0.094, value 0.667. See that file for where it was
    /// sampled from and why it is safe to reuse.
    static let outline = DeskMonitorArt.outline
    /// The lit-screen / paper-white ink, `(182, 198, 222)`, value 0.871. The
    /// brightest thing any of these objects may draw, and still under the room's
    /// 0.92 ceiling.
    static let face = DeskMonitorArt.screen
    /// The second neutral, `(159, 159, 175)`, for the features that would
    /// otherwise leave a flat field: a keyboard, a ruled line, a clip.
    static let detail = DeskMonitorArt.statusDot
    /// The unlit screen, `(141, 141, 141)`, value 0.553 — the darkest 8-bit
    /// neutral inside the room's band. `DeskMonitorArt.screenOff` carries the
    /// derivation and the four separations it was chosen on. **Only the laptop
    /// ever draws it**; see `bitmap(_:screen:)`.
    static let faceOff = DeskMonitorArt.screenOff

    // MARK: - The design grids

    /// **The placement bound is 28 px of content**, which is 14 design columns
    /// doubled. `RoomScene.deskObjectNearEdgeX` and the desk's own width are what
    /// set it; exceeding it puts an object into the neighbouring station's lane,
    /// which is the bug ADR-002 §7 already fixed once for theme desks.
    ///
    /// Every grid below is 13 columns or fewer, so every object clears the bound
    /// with a column to spare, and each is checked against it by
    /// `theArtFitsThePlacementBudget` rather than by this comment.
    static let maximumDesignWidth = 14

    /// `.` transparent, `o` outline, `a` face, `b` detail.
    ///
    /// **The laptop: a screen that steps outward onto a keyboard.** Nine design
    /// columns of screen over thirteen of base, with the hinge row wider than
    /// the screen and narrower than the front edge. The step is the whole
    /// silhouette — a monitor narrows below its screen and this widens, so the
    /// two are opposite profiles rather than variations on one.
    static let laptop: [String] = [
        "..ooooooooo..",
        "..oaaaaaaao..",
        "..oaaaaaaao..",
        "..oaaaaaaao..",
        "..oaaaaaaao..",
        "..ooooooooo..",
        ".ooooooooooo.",
        "obbbbbbbbbbbo",
        "ooooooooooooo",
    ]

    /// **The paper stack: three sheets, each wider than the one above.** Seven
    /// rows against the laptop's nine and the pad's ten, so it is the short one
    /// as well as the flat one; the stepped left and right edges are what say
    /// "several sheets" rather than "one slab", which is the reading the pack's
    /// own single (a low flat slab at an angle) could not survive at 1x.
    static let papers: [String] = [
        "..ooooooooo..",
        "..oaaaaaaao..",
        ".ooooooooooo.",
        ".oaaaaaaaaao.",
        "ooooooooooooo",
        "oaaaaaaaaaaao",
        "ooooooooooooo",
    ]

    /// **The pad: tall, narrow and the same width all the way down**, with a
    /// clip across the top and two ruled lines. Constant width is the feature —
    /// the monitor has a waist, the laptop has a step, and this has neither, so
    /// a flattened outline still separates all three.
    static let pad: [String] = [
        "..ooooo..",
        ".ooooooo.",
        "ooooooooo",
        "oaaaaaaao",
        "oabbbbbao",
        "oaaaaaaao",
        "oabbbbbao",
        "oaaaaaaao",
        "oaaaaaaao",
        "ooooooooo",
    ]

    /// The design for a kind, or `nil` for `running`, which `DeskMonitorArt`
    /// owns. Total over the other three by construction — a fifth kind would
    /// fail to compile here rather than silently drawing nothing.
    static func design(_ kind: WorkKind) -> [String]? {
        switch kind {
        case .authoring: return laptop
        case .research: return papers
        case .coordinating: return pad
        case .running: return nil
        }
    }

    /// The design, doubled — `HeldObjectArt.bitmap`'s construction, which is the
    /// pack's own: every 32x file in Modern Office is a pixel-doubled copy of its
    /// 16x sibling, so a feature drawn at 1 px line weight would read as a
    /// different hand immediately.
    ///
    /// # `screen: .dark` reaches exactly one of these three, and that is I1
    ///
    /// **The laptop is the only kind here with a screen** — `WorkKind.hasScreen`
    /// is where that is decided and argued. `research` draws a paper stack and
    /// `coordinating` draws a pad, and **a sheet of paper cannot be switched
    /// off**: dimming one would be the room inventing a state the object does
    /// not have, in order to repeat something the character's own dim already
    /// says truthfully. So both return the same bitmap in either state,
    /// deliberately, and a reader who expected four dark objects should read
    /// this paragraph rather than file a bug. [I1]
    ///
    /// On the laptop the substitution is `a` alone. `b` is the **keyboard** row
    /// under the hinge — a physical object, which stays exactly as bright when
    /// the display does not — unlike `DeskMonitorArt`'s own `b`, which is two
    /// icon dots *on the glass* and goes dark with it. The two files disagree on
    /// purpose and each says why.
    static func bitmap(_ kind: WorkKind, screen state: DeskScreen = .lit) -> Bitmap? {
        guard let design = design(kind), let width = design.first?.count else { return nil }
        let dark = state == .dark && kind.hasScreen
        var bitmap = Bitmap(width: width * 2, height: design.count * 2)
        for (row, line) in design.enumerated() {
            for (column, character) in line.enumerated() {
                let colour: Bitmap.RGBA
                switch character {
                case "o": colour = outline
                case "a": colour = dark ? faceOff : face
                case "b": colour = detail
                default: continue
                }
                bitmap.fill(x: column * 2, y: row * 2, w: 2, h: 2, colour)
            }
        }
        return bitmap
    }
}
