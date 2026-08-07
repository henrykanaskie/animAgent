#!/usr/bin/env python3
"""Generate placeholder art for everything we could not source from a pack.

docs/04-ART-DIRECTION.md: "ship M1 and M2 with flat-colour blocks at the correct
dimensions and the correct palette split. The scene builds against the manifest,
so real art is a manifest swap with no code change."

As of M0 the character and room layers are fully sourced from the purchased
packs, so this script's job has narrowed to what is genuinely absent:

  * Six of the seven tool badges. The tool->badge table in
    docs/03-EVENT-MODEL.md names document, magnifier, terminal, globe,
    checklist and plug. None of them exist in any pack on disk — Modern
    Interiors' 4_User_Interface_Elements is an emote set (hearts, "?", "!",
    music, moons), not an application icon set. The standalone LimeZu "Modern
    User Interface" pack that docs/04 assumes would supply them has not been
    purchased. Until it is, these six are drawn here.

  * A character variant, drawn only when --characters is passed. Not used by
    the manifest today; kept because the moment a pack goes missing or a
    seventh agent needs a body, the fallback has to already work.

These are placeholders and they look like placeholders on purpose. A badge that
could be mistaken for final art will survive to M5.

Python 3 stdlib only. Idempotent — same inputs, byte-identical outputs.
"""

import argparse
import colorsys
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "placeholder")

# Matches the canvas that scripts/process-assets.py cuts the real badges onto,
# so swapping a real icon in at M5 needs no layout change anywhere.
BADGE_CANVAS = (24, 34)

# Badges still missing, with the glyph each one draws. Names are exactly the
# badge names in the docs/03-EVENT-MODEL.md table — that table is the contract
# and this file does not get to rename anything in it.
MISSING_BADGES = ("document", "magnifier", "terminal", "globe", "checklist", "plug")

# Placeholder ink. Deliberately high saturation: a badge sits above the room, so
# I7's room ceiling does not bind it, and a washed-out placeholder is one nobody
# notices is still a placeholder.
INK = (32, 30, 46, 255)
PAPER = (232, 231, 240, 255)
ACCENT = {
    "document": (78, 154, 241, 255),
    "magnifier": (90, 200, 160, 255),
    "terminal": (120, 226, 120, 255),
    "globe": (96, 172, 246, 255),
    "checklist": (246, 190, 72, 255),
    "plug": (232, 118, 96, 255),
}

CHAR_CANVAS = (32, 64)


def _bubble(w, h):
    """The speech-bubble frame the real badges use, so the placeholders read as
    the same family and the swap at M5 does not change the silhouette."""
    buf = pnglite.new(w, h)
    body_h = h - 6
    pnglite.fill_rect(buf, w, h, 1, 0, w - 2, body_h, INK)
    pnglite.fill_rect(buf, w, h, 0, 1, w, body_h - 2, INK)
    pnglite.fill_rect(buf, w, h, 3, 2, w - 6, body_h - 4, PAPER)
    pnglite.fill_rect(buf, w, h, 2, 3, w - 4, body_h - 6, PAPER)
    # tail, bottom-centre — this is the anchor edge
    for i in range(6):
        pnglite.fill_rect(buf, w, h, w // 2 - 3 + i // 2, body_h - 2 + i, 6 - i, 1, INK)
        if 6 - i > 2:
            pnglite.fill_rect(buf, w, h, w // 2 - 2 + i // 2, body_h - 2 + i, 4 - i, 1, PAPER)
    return buf


def _glyph(buf, w, h, name):
    """Draw a crude but unambiguous mark inside the bubble.

    Every glyph is legible as a distinct blob at 1x. That is the only bar a
    placeholder has to clear; detail here would be wasted and, worse, would make
    the placeholder look finished.
    """
    c = ACCENT[name]
    cx, cy = w // 2, (h - 6) // 2

    if name == "document":
        pnglite.fill_rect(buf, w, h, cx - 5, cy - 8, 10, 15, c)
        for k in range(4):
            pnglite.fill_rect(buf, w, h, cx - 3, cy - 5 + k * 3, 6, 1, INK)
    elif name == "magnifier":
        ox, oy = cx - 2, cy - 3
        for dy in range(-6, 7):
            for dx in range(-6, 7):
                d = dx * dx + dy * dy
                if d <= 16:
                    pnglite.fill_rect(buf, w, h, ox + dx, oy + dy, 1, 1, PAPER)
                if 16 < d <= 30:
                    pnglite.fill_rect(buf, w, h, ox + dx, oy + dy, 1, 1, c)
        for k in range(6):
            pnglite.fill_rect(buf, w, h, ox + 4 + k, oy + 4 + k, 3, 3, c)
    elif name == "terminal":
        pnglite.fill_rect(buf, w, h, cx - 7, cy - 6, 14, 12, INK)
        pnglite.fill_rect(buf, w, h, cx - 6, cy - 5, 12, 10, (16, 20, 18, 255))
        pnglite.fill_rect(buf, w, h, cx - 4, cy - 2, 2, 2, c)
        pnglite.fill_rect(buf, w, h, cx - 2, cy, 2, 2, c)
        pnglite.fill_rect(buf, w, h, cx, cy + 2, 4, 1, c)
    elif name == "globe":
        for dy in range(-7, 8):
            for dx in range(-7, 8):
                if dx * dx + dy * dy <= 46:
                    pnglite.fill_rect(buf, w, h, cx + dx, cy + dy, 1, 1, c)
        pnglite.fill_rect(buf, w, h, cx - 7, cy, 15, 1, PAPER)
        pnglite.fill_rect(buf, w, h, cx - 7, cy - 4, 15, 1, PAPER)
        pnglite.fill_rect(buf, w, h, cx - 7, cy + 4, 15, 1, PAPER)
        pnglite.fill_rect(buf, w, h, cx - 1, cy - 7, 2, 15, PAPER)
    elif name == "checklist":
        for k in range(3):
            y = cy - 6 + k * 5
            pnglite.fill_rect(buf, w, h, cx - 7, y, 4, 4, INK)
            pnglite.fill_rect(buf, w, h, cx - 6, y + 1, 2, 2, c)
            pnglite.fill_rect(buf, w, h, cx - 1, y + 1, 8, 2, INK)
    elif name == "plug":
        pnglite.fill_rect(buf, w, h, cx - 4, cy - 7, 3, 5, INK)
        pnglite.fill_rect(buf, w, h, cx + 1, cy - 7, 3, 5, INK)
        pnglite.fill_rect(buf, w, h, cx - 6, cy - 2, 12, 6, c)
        pnglite.fill_rect(buf, w, h, cx - 2, cy + 4, 4, 5, INK)


def make_badges(scale, quiet):
    w, h = BADGE_CANVAS[0] * scale, BADGE_CANVAS[1] * scale
    size = "%dx%d" % (32 * scale, 32 * scale)
    d = os.path.join(OUT, "badges", size)
    os.makedirs(d, exist_ok=True)
    made = []
    for name in MISSING_BADGES:
        base = _bubble(BADGE_CANVAS[0], BADGE_CANVAS[1])
        _glyph(base, BADGE_CANVAS[0], BADGE_CANVAS[1], name)
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
        print("  badges/%s: %d placeholders (%s)" % (size, len(made), ", ".join(MISSING_BADGES)))
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
    d = os.path.join(OUT, "characters", "32x32")
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
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    os.makedirs(OUT, exist_ok=True)
    if not args.quiet:
        print("placeholders -> %s" % os.path.relpath(OUT, REPO))
    make_badges(args.scale, args.quiet)
    if args.characters:
        make_characters(args.quiet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
