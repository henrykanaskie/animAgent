#!/usr/bin/env python3
"""Draw the art no pack supplies: four authored tool badges, and one fallback.

Renamed at M5c from `generate-placeholders.py`, because four of the six badges
it draws stopped being placeholders. **No further art packs will be bought.**
M5b proved exhaustively that no pack we own contains a magnifier, a terminal, a
globe or a plug — every 32px cell of three UI sheets rendered and inspected (337
distinct masks on Style 1, 283 on Style 2, 28 straddling components), plus a
filename sweep of all 52726 PNGs in the three packs returning exactly one hit, a
Christmas snow globe. That investigation is finished. Its conclusion is not
"keep searching", it is "draw them", and this is where they are drawn.

So these four are **authored final art**, not scaffolding:

  * `magnifier`, `terminal`, `globe`, `plug` — `provenance: "authored"` in the
    manifest, with the search that led here recorded beside it so nobody repeats
    it or goes shopping.

Authoring them is not an I1 violation. I1 forbids the room asserting *data* the
hooks did not give us — a character walking when nothing said it walked, a badge
invented for a tool we did not recognise. It says nothing about who drew the
pixels. `PixelFont.standard` is the precedent: written here rather than sourced,
licence-clean by construction, and M5 judged it good enough to close the blocker
outright.

What still ships as a genuine placeholder:

  * `document` and `checklist` are drawn here too, but only as the fallback
    behind the pack art that scripts/process-assets.py composites. The manifest
    prefers the real cut whenever it exists.
  * A character variant set, drawn only under --characters. Not in the manifest;
    it exists so a missing pack degrades to something that renders.

**How the badges are drawn, and why it looks like that.** A badge is the pack's
own empty speech bubble — the same 692-pixel component `question_mark` is cut
from — with a glyph composited into it by the same arithmetic
scripts/process-assets.py uses for the pack's own icons. The glyphs are drawn on
the pack's grid and in the pack's palette, both measured rather than guessed:

  * The Modern UI icons on the 32x sheet are a 2x scale-up of a 16px design, so
    every feature in them is a 2x2 block. Drawing at 1px line weight next to
    them reads as a different hand immediately. Every glyph here is therefore
    authored on a half-resolution grid and doubled. See DESIGN.
  * Their ink is exactly four colours, recovered by differencing `document` and
    `checklist` against the empty bubble: saturation 0.252-0.345, value
    0.420-0.694. PALETTE is those four values. Matching a palette claims no
    provenance — the manifest says who drew the shape.

Python 3 stdlib only. Idempotent — same inputs, byte-identical outputs.
"""

import argparse
import colorsys
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Two output roots, because the two things this script makes are not the same
# kind of thing any more. The badges are final art and go under authored/; the
# fallback cast is scaffolding and stays under placeholder/. A path is the first
# thing a reviewer reads in the manifest, so it should not contradict the
# provenance field two lines below it.
AUTHORED = os.path.join(REPO, "assets", "authored")
PLACEHOLDER = os.path.join(REPO, "assets", "placeholder")

# Matches the canvas that scripts/process-assets.py cuts the real badges onto,
# so swapping a real icon in at M5 needs no layout change anywhere.
BADGE_CANVAS = (24, 34)

# The pack's empty speech bubble, written out by scripts/process-assets.py from
# UI_32x32.png (164,16,24,34) — the same 692-pixel component the question_mark
# badge is cut from, with no glyph in it. Read rather than re-measured, so that
# rectangle is written down in exactly one place.
BUBBLE = os.path.join(REPO, "assets", "processed", "badges", "32x32",
                      "_bubble_frame.png")

# Where a glyph may go inside that frame, in frame-local coordinates. Same
# constant scripts/process-assets.py composites the pack icons with, so an
# authored glyph sits exactly where a pack one does.
BUBBLE_INTERIOR = (2, 2, 20, 24)

# The badges drawn here. Names are exactly the badge names in the
# docs/03-EVENT-MODEL.md table — that table is the contract and this file does
# not get to rename anything in it.
BADGES = ("document", "magnifier", "terminal", "globe", "checklist", "plug")

# The four with no source art in any pack we own, and no pack coming. These are
# authored final art. The other two are the fallback behind pack art.
AUTHORED_BADGES = ("magnifier", "terminal", "globe", "plug")

# The pack's own icon palette, recovered by differencing `document` and
# `checklist` against the empty bubble: those two glyphs are exactly these four
# colours and no others. Saturation 0.252-0.345, value 0.420-0.694.
#
# Used verbatim rather than approximated. A palette is a set of numbers, not
# artwork — matching it is what "stylistically of a piece" means, and the
# manifest is where provenance is claimed. An earlier draft of these glyphs used
# a deliberately off-hue slate ramp so a reviewer could spot which four were
# ours; that was the right instinct while they were placeholders and the wrong
# one for final art, whose whole job is not to announce itself.
DARK = (0x6B, 0x50, 0x52, 255)    # s 0.252 v 0.420 — outlines and main strokes
MID = (0x91, 0x66, 0x62, 255)     # s 0.324 v 0.569 — secondary strokes
HALF = (0x9C, 0x78, 0x6B, 255)    # s 0.314 v 0.612 — fills
LIGHT = (0xB1, 0x8A, 0x74, 255)   # s 0.345 v 0.694 — highlights

# Measured off the pack's bubble: interior RGB(235,225,246) at value 0.965 and
# the darkest border step RGB(53,53,86) at value 0.337. Used only to draw the
# fallback bubble below, for a checkout with no pack on disk.
PAPER = (235, 225, 246, 255)
BORDER = (53, 53, 86, 255)

CHAR_CANVAS = (32, 64)


def _pack_bubble():
    """The pack's empty speech bubble, or None if the pack is not on disk.

    Read from assets/processed/, which scripts/process-assets.py writes from the
    Modern Interiors UI sheet. Reading it is what makes a placeholder badge the
    *same* bubble as a real one rather than a lookalike — same border weight,
    same interior colour, same silhouette, same tail on the same anchor.
    """
    if not os.path.exists(BUBBLE):
        return None
    w, h, px = pnglite.load(BUBBLE)
    if (w, h) != BADGE_CANVAS:
        return None
    return px


def _fallback_bubble(w, h):
    """Hand-drawn approximation, used only when the pack is absent.

    This is what every placeholder used to draw, and it is kept for exactly one
    case: a checkout with no assets/ at all, where there is no pack bubble to
    read and something still has to render. Its border weight is a guess; the
    pack's is not. Retoned at M5c to the pack's measured border and interior
    colours so the guess is at least in the right band.
    """
    buf = pnglite.new(w, h)
    body_h = h - 6
    pnglite.fill_rect(buf, w, h, 1, 0, w - 2, body_h, BORDER)
    pnglite.fill_rect(buf, w, h, 0, 1, w, body_h - 2, BORDER)
    pnglite.fill_rect(buf, w, h, 3, 2, w - 6, body_h - 4, PAPER)
    pnglite.fill_rect(buf, w, h, 2, 3, w - 4, body_h - 6, PAPER)
    # tail, bottom-centre — this is the anchor edge
    for i in range(6):
        pnglite.fill_rect(buf, w, h, w // 2 - 3 + i // 2, body_h - 2 + i, 6 - i, 1, BORDER)
        if 6 - i > 2:
            pnglite.fill_rect(buf, w, h, w // 2 - 2 + i // 2, body_h - 2 + i, 4 - i, 1, PAPER)
    return buf


# --- glyphs ----------------------------------------------------------------
#
# Authored on the pack's own grid. The Modern UI icons on the 32x sheet are a 2x
# scale-up of a 16px design — dump `document` or `checklist` pixel by pixel and
# every feature in them is a 2x2 block — so a glyph drawn here at 1px line weight
# reads as a different hand at any size. Each design below is therefore a
# half-resolution grid, doubled on the way out. One design pixel is two screen
# pixels, exactly like the pack's.
#
# That constraint is the good kind. The bubble interior is 20x24, so a design is
# at most 10x12 cells, which forces the simple silhouette that survives 1x —
# docs/04-ART-DIRECTION.md's "if a sprite stops reading when scaled down, the fix
# is a simpler silhouette, never more outline detail".
#
# Shapes are chosen for *mutual* separation, measured as pairwise IoU of the ink
# inside the bubble rather than eyeballed. Two structural decisions come straight
# out of those numbers:
#
#   * `terminal` is wide and `plug` is narrow-and-tall. As two centred blobs of
#     one footprint they were the closest pair in the whole set at 0.57; they are
#     now 0.16.
#   * `magnifier` and `globe` are both circles, so they are deliberately
#     different circles: a small ring set up-and-left with a handle, against a
#     large ring centred with two latitude bands across it.
#
# Three designs were thrown out on legibility before these stuck, all failing the
# same way — detail this grid cannot carry. Recorded so they are not retried:
# a `terminal` whose prompt was one cell thick read as a *picture frame with a
# squiggle* (fixed by fattening the ">" to two cells per stroke and pulling it a
# cell clear of the border, which is what stops it merging with the corner); a
# `globe` with a full vertical meridian read as a *crosshair* (fixed by cutting
# the meridian back to pole hints); a `plug` with a filled body and a stem read
# as a *goblet* (fixed by hollowing the body).
#
#   D outline / main stroke   M secondary stroke   H fill   L highlight
#   .  transparent — the bubble's own interior shows through
#
# H and L are unused by the designs below and kept deliberately: they are two of
# the pack's four icon colours, and a glyph that needs a fill or a highlight
# should reach for the pack's value rather than invent one.

DESIGN = {
    "magnifier": (
        ".DDD...",
        "D...D..",
        "D...D..",
        "D...D..",
        ".DDD...",
        "....DD.",
        ".....DD",
    ),
    "terminal": (
        "DDDDDDDDD",
        "D.DD....D",
        "D..DD...D",
        "D.DD.MM.D",
        "D.......D",
        "DDDDDDDDD",
    ),
    "globe": (
        "..DDD..",
        ".D.M.D.",
        "DMMMMMD",
        "D.....D",
        "DMMMMMD",
        ".D.M.D.",
        "..DDD..",
    ),
    "plug": (
        ".D.D.",
        ".D.D.",
        "DDDDD",
        "D...D",
        "D...D",
        ".DDD.",
        "..D..",
        "..D..",
    ),
    # Fallbacks only — the manifest prefers the pack's own cut of these two
    # whenever assets/processed/ has it.
    "document": (
        "DDDDD",
        "D...D",
        "DMMMD",
        "D...D",
        "DMMMD",
        "D...D",
        "DDDDD",
    ),
    "checklist": (
        "DD.MMMM",
        "DD.....",
        ".......",
        "DD.MMMM",
        "DD.....",
        ".......",
        "DD.MMMM",
        "DD.....",
    ),
}

PEN = {"D": DARK, "M": MID, "H": HALF, "L": LIGHT}

# One design cell is this many screen pixels. Measured off the pack, not chosen:
# see the module docstring.
DESIGN_SCALE = 2


def _glyph(name):
    """Expand a design grid to screen pixels. Nothing else draws a glyph."""
    rows = DESIGN[name]
    w = max(len(r) for r in rows) * DESIGN_SCALE
    h = len(rows) * DESIGN_SCALE
    g = pnglite.new(w, h)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            pnglite.fill_rect(g, w, h, x * DESIGN_SCALE, y * DESIGN_SCALE,
                              DESIGN_SCALE, DESIGN_SCALE, PEN[ch])
    return g, w, h


def _compose(bubble, name):
    """Bubble plus glyph, centred in the interior by bounding box.

    Deliberately the same arithmetic as Importer.badge_composites in
    scripts/process-assets.py: find the glyph's bounding box, centre that box in
    BUBBLE_INTERIOR, blit skipping transparent pixels. An authored badge is the
    same construction as a pack one, differing only in where the glyph came
    from — which is the fact the manifest records.
    """
    cw, _ch = BADGE_CANVAS
    buf = bytearray(bubble)
    g, gw, gh = _glyph(name)
    xs = [(x, y) for y in range(gh) for x in range(gw) if g[(y * gw + x) * 4 + 3]]
    bx = min(p[0] for p in xs)
    by = min(p[1] for p in xs)
    bw = max(p[0] for p in xs) - bx + 1
    bh = max(p[1] for p in xs) - by + 1
    ix, iy, iw, ih = BUBBLE_INTERIOR
    if bw > iw or bh > ih:
        raise SystemExit("glyph %s is %dx%d, larger than the %dx%d bubble "
                         "interior" % (name, bw, bh, iw, ih))
    gx, gy = ix + (iw - bw) // 2, iy + (ih - bh) // 2
    for y in range(bh):
        for x in range(bw):
            si = ((by + y) * gw + bx + x) * 4
            if g[si + 3] == 0:
                continue
            di = ((gy + y) * cw + gx + x) * 4
            buf[di : di + 4] = g[si : si + 4]
    return buf, (bw, bh)


def make_badges(scale, quiet):
    w, h = BADGE_CANVAS[0] * scale, BADGE_CANVAS[1] * scale
    size = "%dx%d" % (32 * scale, 32 * scale)
    d = os.path.join(AUTHORED, "badges", size)
    os.makedirs(d, exist_ok=True)
    bubble = _pack_bubble()
    if bubble is None:
        bubble = _fallback_bubble(*BADGE_CANVAS)
    made = []
    boxes = {}
    for name in BADGES:
        base, boxes[name] = _compose(bubble, name)
        if scale == 1:
            buf = base
        else:
            buf = pnglite.new(w, h)
            for y in range(h):
                for x in range(w):
                    si = ((y // scale) * BADGE_CANVAS[0] + x // scale) * 4
                    di = (y * w + x) * 4
                    buf[di : di + 4] = base[si : si + 4]
        p = os.path.join(d, "%s.png" % name)
        pnglite.save(p, w, h, buf)
        made.append(p)
    if not quiet:
        fallback = [n for n in BADGES if n not in AUTHORED_BADGES]
        print("  badges/%s: %d drawn — %d authored final art (%s), %d fallback "
              "behind pack art (%s)"
              % (size, len(made), len(AUTHORED_BADGES), ", ".join(AUTHORED_BADGES),
                 len(fallback), ", ".join(fallback)))
        print("    bubble: %s"
              % ("the pack's own empty frame, %s"
                 % os.path.relpath(BUBBLE, REPO) if _pack_bubble() is not None
                 else "FALLBACK hand-drawn frame — the pack is not on disk"))
        print("    glyph boxes (screen px, %dx design cells): " % DESIGN_SCALE
              + ", ".join("%s %dx%d" % (n, boxes[n][0], boxes[n][1])
                          for n in BADGES))
    return made


# --- character fallback ----------------------------------------------------

# Each variant is defined by its OUTLINE, not its hue. docs/04-ART-DIRECTION.md:
# "Choose outfits and hairstyles that differ in outline, not only in colour.
# Verify by flattening two variants to solid black." The head shape, shoulder
# width and headgear below are what survive that flattening; the accent hue is
# only there to satisfy I7's above-55%-saturation rule.
CHAR_VARIANTS = {
    #  name:       (head_w, head_h, shoulder_w, crest, accent_hue)
    "block_a": (14, 12, 16, "none", 0.02),
    "block_b": (10, 14, 12, "tall", 0.33),
    "block_c": (16, 10, 20, "brim", 0.58),
    "block_d": (12, 12, 14, "tail", 0.78),
}


def _char_frame(spec, bob):
    w, h = CHAR_CANVAS
    hw, hh, sw, crest, hue = spec
    buf = pnglite.new(w, h)
    r, g, b = colorsys.hsv_to_rgb(hue, 0.85, 0.82)
    accent = (int(r * 255), int(g * 255), int(b * 255), 255)
    dark = (26, 24, 34, 255)  # owns the darkest value on screen [I7]

    feet = h - 2 + bob
    body_h = 18
    body_y = feet - body_h
    head_y = body_y - hh

    pnglite.fill_rect(buf, w, h, (w - sw) // 2, body_y, sw, body_h, accent)
    pnglite.fill_rect(buf, w, h, (w - sw) // 2, body_y, sw, 2, dark)
    pnglite.fill_rect(buf, w, h, (w - hw) // 2, head_y, hw, hh, dark)
    pnglite.fill_rect(buf, w, h, (w - hw) // 2 + 2, head_y + 2, hw - 4, hh - 5, accent)
    if crest == "tall":
        pnglite.fill_rect(buf, w, h, w // 2 - 2, head_y - 6, 4, 6, dark)
    elif crest == "brim":
        pnglite.fill_rect(buf, w, h, (w - hw) // 2 - 4, head_y + 1, hw + 8, 2, dark)
    elif crest == "tail":
        pnglite.fill_rect(buf, w, h, (w + hw) // 2 - 1, head_y + 2, 4, hh + 4, dark)
    pnglite.fill_rect(buf, w, h, w // 2 - 5, feet - 2, 4, 2, dark)
    pnglite.fill_rect(buf, w, h, w // 2 + 1, feet - 2, 4, 2, dark)
    return buf


def make_characters(quiet):
    """Draw the fallback cast and run the flatten-to-black check on it.

    The check is the point. docs/04-ART-DIRECTION.md and the art-director role
    both say a variant set that fails it is "the same character in different
    colours", so generating without verifying would miss the only property
    these placeholders need to have.
    """
    w, h = CHAR_CANVAS
    d = os.path.join(PLACEHOLDER, "characters", "32x32")
    os.makedirs(d, exist_ok=True)
    made = {}
    for name, spec in CHAR_VARIANTS.items():
        for i, bob in enumerate((0, -1)):
            buf = _char_frame(spec, bob)
            p = os.path.join(d, "%s_idle_%02d.png" % (name, i))
            pnglite.save(p, w, h, buf)
            if i == 0:
                made[name] = [1 if buf[k * 4 + 3] > 127 else 0 for k in range(w * h)]
    worst = None
    names = sorted(made)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = made[names[i]], made[names[j]]
            diff = sum(1 for p, q in zip(a, b) if p != q)
            union = sum(1 for p, q in zip(a, b) if p or q)
            pct = 100.0 * diff / union
            if worst is None or pct < worst[0]:
                worst = (pct, names[i], names[j])
    if not quiet:
        print("  characters/32x32: %d variants x 2 frames" % len(CHAR_VARIANTS))
        print("    silhouette check (flattened to black, least distinct pair): "
              "%s vs %s differ by %.1f%% of their combined outline"
              % (worst[1], worst[2], worst[0]))
    return worst


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--characters", action="store_true",
                    help="also draw the fallback character variants (not used by the manifest)")
    ap.add_argument("--scale", type=int, default=1, choices=(1, 2),
                    help="1 => the 32x set (default), 2 => the 48x/64px set")
    ap.add_argument("--allow-fallback-bubble", action="store_true",
                    help="draw the badges in a hand-drawn lookalike when the pack "
                         "is absent; the result is not shippable art")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    # The pack's empty bubble is the whole premise of these four badges: they are
    # "drawn in the pack's own bubble and colours", which is what
    # `provenance: "authored"` claims and what M6 gated. Without it this script
    # silently substitutes the hand-drawn fallback — heavier border, different
    # weight — and exits 0, so a newcomer following the README order before
    # unpacking gets four badges that do not match the two real ones and nothing
    # says so. `assets/` is gitignored, so `git status` stays clean too.
    #
    # This is `build-manifest.py`'s lesson applied here: a script that writes
    # into `assets/` must refuse rather than produce something plausible.
    # `--allow-fallback-bubble` is the way to ask for it on purpose, which is
    # what the fallback exists for — a checkout with no packs at all, where the
    # point is to see *something* rather than to ship it.
    if _pack_bubble() is None and not args.allow_fallback_bubble:
        print("error: the pack's speech bubble is not on disk, so the four "
              "authored badges cannot be drawn in it.", file=sys.stderr)
        print("       Expected: %s" % os.path.relpath(BUBBLE, REPO),
              file=sys.stderr)
        print("       Run scripts/process-assets.py first — it writes that file "
              "out of Modern Interiors.", file=sys.stderr)
        print("       Pass --allow-fallback-bubble to draw them in a hand-drawn "
              "lookalike instead; the result is NOT what provenance 'authored' "
              "claims and must not be shipped.", file=sys.stderr)
        return 2

    os.makedirs(AUTHORED, exist_ok=True)
    if not args.quiet:
        print("authored art -> %s" % os.path.relpath(AUTHORED, REPO))
        if args.allow_fallback_bubble and _pack_bubble() is None:
            print("  WARNING: hand-drawn fallback bubble; these badges do not "
                  "match the pack's and must not be shipped")
    make_badges(args.scale, args.quiet)
    if args.characters:
        os.makedirs(PLACEHOLDER, exist_ok=True)
        if not args.quiet:
            print("placeholders -> %s" % os.path.relpath(PLACEHOLDER, REPO))
        make_characters(args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
