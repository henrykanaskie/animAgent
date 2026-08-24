import Foundation

/// What a working character has **in its hands**.
///
/// # Why this exists, and why the document that forbade it was half wrong
///
/// `docs/04-ART-DIRECTION.md` carried "Nothing is held" from M0 to M6g on two
/// premises. M6g refuted one of them and kept the other:
///
/// - *The pack has no held art.* **False.** `Character_Generator/Books/` and
///   `/Smartphones/` are overlay layers on the premade sheet's own geometry.
///   Measured here again rather than taken on trust: `Book_32x32_01.png` is
///   1792x1312 with ink on exactly one 32-px row, row 15, and compositing it
///   onto the premade at `dy = 0` puts **0 of its 2656 pixels on transparency
///   and changes only 104**: it is a recolour of a book the premade already
///   draws. `Smartphone_32x32_1.png` is 768x384 with ink on exactly one 32-px
///   row, row 9, and its best fit is `dy = +128`: **0 on transparency, 24
///   changed**. In the pack's own row table those land on **row 7 (`phone_b`,
///   a front-facing standing figure holding an open book at chest height)** and
///   **row 6 (`phone_a`, the same figure holding a phone)**. That is the
///   semantic answer to "what are rows 15 and 9": they are the two rows in
///   which the artist already drew a held object, and the generator folders
///   only repaint it.
/// - *An arbitrary prop cannot be placed against this art, because there is no
///   per-frame hand anchor.* **True of the download, and it does not follow.**
///   The two held rows are front-facing standing poses and this room draws a
///   side-view seated character and nothing else, so route 1: composite the
///   layer, which pins the body to the row the layer was drawn for: buys a
///   held book at the price of the pose, the chair and the desk. It was cut and
///   looked at at M6g and again here.
///
/// # The measurement that made route 2 possible
///
/// There is no per-frame hand anchor in the files, but there is **one anchor to
/// measure**, because on the pose this room draws the hands do not move:
///
/// | | seated hand box, in the 32x64 canvas, y down |
/// |---|---|
/// | every cast variant (06, 07, 09, 10, 17, 19) | `x 14...17`, `y 52...55` |
/// | every frame of `sit` (0, 1, 2) | the same box |
/// | facing `right` **and** facing `left` | the same box |
///
/// Found by taking each variant's own skin colour from its cheek and locating
/// that colour below the shoulder line. Eighteen right-facing frames and nine
/// left-facing ones agree to the pixel, which is why the anchor below is one
/// constant and not a table: the `sit` loop moves the head and the torso and
/// leaves the hands alone, and the left frames are the right frames mirrored
/// about a canvas whose centre the hand box straddles symmetrically.
///
/// So this is **not** an eyeballed offset dressed up as data, which is the
/// charge `04-ART-DIRECTION.md` correctly lays against the unplaced monitors and
/// against a second badge slot. It is a measurement, it is reproducible from the
/// shipped frames, and `HeldObjectArtTests` re-derives it from the PNGs rather
/// than trusting this comment.
///
/// # What it cannot do, stated before anyone hopes otherwise
///
/// **A held object on this pose cannot change the silhouette.** The seated body
/// is a chibi: the head spans `x 2...29, y 20...45` and the whole torso below it
/// is about 20x16 px. The hands sit in the middle of that torso, so an object in
/// them is a colour block *inside* an existing outline: the same channel a
/// costume buys (`04-ART-DIRECTION.md`, "Costumes"), at about half the area, and
/// not the silhouette channel that document says carries identity at `1x`. The
/// honest claim for this layer is "you can see they are holding something, and
/// at `3x` you can see roughly what"; it is not "you can name the tool from
/// across the room". The badge above the head is still the layer that carries
/// tool identity.
public enum HeldObject: String, Sendable, Hashable, CaseIterable {
    /// A sheet of paper. `Edit`, `Write`, `NotebookEdit`.
    case page
    /// An open book. `Read`, `Glob`, `Grep`, `ToolSearch`.
    case book
    /// A handheld console with a lit screen. `Bash`, `BashOutput`, `KillShell`.
    case console
    /// A globe. `WebSearch`, `WebFetch`.
    case globe
    /// A clipboard. `TodoWrite`, `Agent`, `SendMessage`.
    case clipboard
    /// A two-pin plug on a lead. `mcp__*`.
    case plug

    /// The object for a badge class, or `nil` when the class has none.
    ///
    /// **`questionMark` has none, and that is the whole of I1 on this layer.**
    /// An unrecognised tool gets the question-mark badge because guessing a
    /// glyph for it would be a claim the data did not make; putting a *thing* in
    /// the character's hands for it would be the same claim with a bigger
    /// surface. So an unmapped tool leaves the hands empty, exactly as it leaves
    /// the badge unguessed. [I1]
    public init?(badge: ToolBadge) {
        switch badge {
        case .document: self = .page
        case .magnifier: self = .book
        case .terminal: self = .console
        case .globe: self = .globe
        case .checklist: self = .clipboard
        case .plug: self = .plug
        case .questionMark: return nil
        }
    }

    /// Stable key for the texture cache.
    var textureKey: String { "held:" + rawValue }
}

// MARK: - The art

/// The pixels, authored here.
///
/// **Authoring is precedented and is not an I1 violation.** I1 forbids the room
/// asserting *data* the hooks did not give us; it says nothing about who drew
/// the pixels. `PixelFont.standard`, `SceneBitmaps.nameplate` and the four
/// badges `scripts/generate-art.py` draws are all authored, and M5c wrote the
/// rule down: no further art packs will be bought, so the answer to "no pack
/// draws this" is to draw it properly rather than to leave a placeholder up
/// forever.
///
/// Three constraints, all of them measured off the pack rather than chosen:
///
/// - **The pack's grid.** Every feature in the 32x set is a 2x2 block, because
///   the 32x art is a 2x scale-up of a 16-px design: dump any seated frame and
///   the rows come in identical pairs. So every design below is an ASCII grid at
///   half resolution and is doubled on the way out, which is the same
///   construction `generate-art.py` uses for the badges. It also forces the
///   simple silhouette that survives `1x`.
/// - **The pack's palette.** `outline`, `shade` and `soft` are the three
///   structural inks every held object in `Character_Generator/Books/` and
///   `/Smartphones/` is built from (all eleven files share them exactly) and
///   `paper` is the page white from the same set. Nothing here is a new colour
///   in the sense that matters: they are the numbers the artist used for the
///   only held objects this pack contains.
/// - **The pack's floor.** `outline` is `(58, 58, 80)`, value **0.314**, which
///   is the cast's own darkest pixel to three decimals. Nothing here goes below
///   it, so a held object can never be the darkest thing on screen: the one
///   axis I7 actually protects. `HeldObjectArtTests` measures this rather than
///   trusting it, because `scripts/lint-palette.py` reads the *manifest* and
///   this layer is drawn by the scene, exactly like the nameplate and the `×N`,
///   so the lint does not and cannot see it.
enum HeldObjectArt {

    // MARK: Palette: measured off Books/ and Smartphones/, which are the only
    // held objects the pack draws. All eleven files carry these three inks.

    /// `(58, 58, 80)`: saturation 0.275, value **0.314**. The cast's floor.
    /// Nothing in this file may be darker.
    static let outline = Bitmap.RGBA(58, 58, 80)
    /// `(70, 70, 94)`: value 0.369. Interior shadow.
    static let shade = Bitmap.RGBA(70, 70, 94)
    /// `(86, 89, 114)`: value 0.447. The soft edge step.
    static let soft = Bitmap.RGBA(86, 89, 114)
    /// `(255, 255, 255)`: the page white the pack's book is printed on.
    static let paper = Bitmap.RGBA(255, 255, 255)
    /// `(235, 228, 242)`: the page's shaded side.
    static let paperShade = Bitmap.RGBA(235, 228, 242)

    /// `(66, 128, 221)`: `Book_32x32_01`'s cover.
    static let blue = Bitmap.RGBA(66, 128, 221)
    /// `(49, 90, 130)`: `Book_32x32_05`'s dark cover step.
    static let blueDark = Bitmap.RGBA(49, 90, 130)
    /// `(242, 178, 43)`: the gold the pack stamps its books with.
    static let gold = Bitmap.RGBA(242, 178, 43)
    /// `(150, 114, 80)`: `Book_32x32_04`'s board.
    static let board = Bitmap.RGBA(150, 114, 80)
    /// `(109, 187, 201)`: `Smartphone_32x32_1`'s lit screen.
    static let screen = Bitmap.RGBA(109, 187, 201)
    /// `(198, 189, 213)`: `Smartphone_32x32_4`'s pale casing.
    static let casing = Bitmap.RGBA(198, 189, 213)
    /// `(240, 78, 36)`: `Smartphone_32x32_5`'s casing. The only warm hue in the
    /// set, given to the one class whose meaning is open-ended.
    static let orange = Bitmap.RGBA(240, 78, 36)
    /// `(192, 42, 25)`: the same phone's dark step.
    static let orangeDark = Bitmap.RGBA(192, 42, 25)

    /// The design grid's canvas, **before** the 2x doubling. Every object is cut
    /// to the same box so one anchor serves all six: a per-object anchor would
    /// be six numbers where the measurement only supports one.
    ///
    /// **6x5 was arrived at by looking, and the first attempt was 6x6.** At 6x6
    /// with a one-cell border all round, the border is 2 px of the pack's
    /// darkest ink on every edge of a 12x12 block, and the seated torso it lands
    /// on is about 20x16 px with its own outline in the same colour: rendered
    /// and looked at, the object merged with the body and read as a dark patch
    /// rather than as a thing being held. Dropping a row and letting the fill
    /// reach the border is what made it read.
    static let designWidth = 6
    static let designHeight = 5
    /// The doubled canvas the scene draws. `12x10`, even in both axes, so the
    /// node's edges land on whole pixels at every integer scale. [I6]
    static var canvasWidth: Int { designWidth * 2 }
    static var canvasHeight: Int { designHeight * 2 }

    /// `.` transparent, `o` outline, `s` shade, `t` soft, `w` paper,
    /// `p` paper shade, `a` accent, `b` accent dark, `g` gold.
    ///
    /// Five rows of six, read top-down, y-down like `Bitmap`.
    ///
    /// **These separate by hue and value, not by silhouette, and that is a
    /// concession the pose forces rather than a shortcut.** Five of the six are
    /// a rounded rectangle, because at 12x10 held against a 20x16 torso there is
    /// no room for an outline that says "book" rather than "board". What there
    /// is room for is one bright field each: white, split white, cyan, blue,
    /// gold-over-white, orange. Rendered on three cast variants at `3x` they are
    /// told apart instantly; at `1x` they read as *something being held*, in six
    /// different colours, and the badge above the head is still what names the
    /// tool.
    private static func design(_ object: HeldObject) -> [String] {
        switch object {
        // A sheet held in both hands with a line of writing across it. The
        // brightest object in the set on purpose: `document` was open for 0.75 s
        // of a measured 224 s run [ADR-003], so it needs the loudest value step
        // it can honestly have, and white against a shirt is that.
        case .page:
            return [
                "oooooo",
                "owwwwo",
                "owsswo",
                "owwwwo",
                "oooooo",
            ]
        // An open book: two pages either side of a dark spine. Same white as the
        // page, split down the middle, which is the one difference that
        // survives being 12 px wide.
        case .book:
            return [
                "oooooo",
                "owwsww",
                "owwsww",
                "owwsww",
                "oooooo",
            ]
        // A handheld console, screen towards the character's face. The screen is
        // the pack's own *lit* `Smartphone_1` cyan at value 0.788, so it reads as
        // on rather than as a dark rectangle: a dark screen here would be a
        // black block on a dark torso, which is the shape of the mistake M6b
        // made with `mission_control`'s monitors.
        case .console:
            return [
                "oooooo",
                "oaaaao",
                "oagaao",
                "oaaaao",
                "oooooo",
            ]
        // A globe: the only object in the set with its corners cut, shaded from
        // the top-left, which is what makes it read as round rather than as a
        // sixth rectangle.
        case .globe:
            return [
                ".oooo.",
                "oaaabo",
                "oaabbo",
                "oabbbo",
                ".oooo.",
            ]
        // A clipboard: a gold clip bar over a white page with one ruled line.
        // The bar is what separates it from `page` at a glance.
        case .clipboard:
            return [
                "oooooo",
                "oggggo",
                "owwwwo",
                "owsswo",
                "oooooo",
            ]
        // A plug: two prongs under a body, in the set's only warm hue. Smallest
        // and least explicit of the six on purpose: `mcp__*` is the one class
        // whose contents we cannot know, so it gets a connector and not a
        // depiction of any particular work. [I1]
        case .plug:
            return [
                "..oo..",
                ".oaao.",
                "oaaaao",
                ".oaao.",
                ".o..o.",
            ]
        }
    }

    /// Per-object accent, so `a`/`b` mean something different in each design.
    private static func accents(_ object: HeldObject) -> (a: Bitmap.RGBA, b: Bitmap.RGBA) {
        switch object {
        case .page, .book: return (paper, paperShade)
        case .console: return (screen, casing)
        case .globe: return (blue, blueDark)
        case .clipboard: return (board, gold)
        case .plug: return (orange, orangeDark)
        }
    }

    /// The design, doubled onto the 12x12 canvas.
    static func bitmap(_ object: HeldObject) -> Bitmap {
        let accent = accents(object)
        var bitmap = Bitmap(width: canvasWidth, height: canvasHeight)
        for (row, line) in design(object).enumerated() {
            for (column, character) in line.enumerated() {
                let colour: Bitmap.RGBA
                switch character {
                case "o": colour = outline
                case "s": colour = shade
                case "t": colour = soft
                case "w": colour = paper
                case "p": colour = paperShade
                case "a": colour = accent.a
                case "b": colour = accent.b
                case "g": colour = gold
                default: continue
                }
                // The 2x2 block. This is the whole of "the pack's grid".
                bitmap.fill(x: column * 2, y: row * 2, w: 2, h: 2, colour)
            }
        }
        return bitmap
    }
}
