#!/usr/bin/env python3
"""Look at the character generator: catalogue its outfits, check its coverage,
and measure what a costume actually buys.

Why this exists
---------------
`docs/04-ART-DIRECTION.md` said for six milestones that the character generator
was a Windows-only tool and the cast had to be exported under a VM. That is a
claim about a *third-party convenience* named in `THIRD-PARTY TOOLS.txt`, not
about the files: `CHARACTER_GENERATOR.txt` says to stack the layers in any
editor that supports them, and `Character_Generator/{Bodies,Eyes,Outfits,
Hairstyles,Accessories}/32x32/` are ordinary PNGs on the premade sheet's own
geometry. Compositing them is `pnglite` and an alpha blend.

That makes casting a *design* problem again, and this repo's rule for a design
problem is that you render it and look at it — the rule that caught the `sleep`
row, the second sit row and the `Books` folder. 132 outfits and 200 hairstyles
is too many to look at one at a time, so this is that pass, committed and
re-runnable.

It is a **review tool**. It writes to whatever `--out` you give it and never
touches `assets/`. The art itself is cut by `scripts/process-assets.py`, whose
`COSTUMES` table this script reads rather than duplicating.

Usage
-----
    cast-sheet.py --out DIR --coverage     # which pose rows the layers cover
    cast-sheet.py --out DIR --outfits      # all 33 outfits, front and seated
    cast-sheet.py --out DIR --outfits --all-colours   # all 132 files
    cast-sheet.py --out DIR --costumes     # every costume at 1x and 4x, seated
    cast-sheet.py --out DIR --room         # six roles in the real 720x400 panel
    cast-sheet.py --out DIR --measure      # silhouette, value and the I7 table
    cast-sheet.py --out DIR --select       # re-derive the assignable pool

Python 3 stdlib only.
"""

import argparse
import glob
import importlib.util
import itertools
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(REPO, "assets/moderninteriors-win/2_Characters",
                   "Character_Generator")
PREMADES = os.path.join(GEN, "0_Premade_Characters")
MANIFEST = os.path.join(REPO, "assets/manifest.json")

FW, FH = 32, 64
COLS, ROWS = 56, 20
DIRS = ("right", "up", "left", "down")

# The pose the room actually draws. Every seated character in this product is
# `sit_a`, block 0 (right), and nothing else is on screen while an agent works,
# so this is the frame every number below is measured on unless it says
# otherwise.
SEATED = (4, 0)
# M0 measured the premade cast's silhouette on the front-facing idle frame.
# Kept so the costume numbers can be compared with the 7.3% in FINDINGS-M0.md
# on the same pose rather than only on a friendlier one.
IDLE_FRONT = (1, 18)

# `scripts/lint-palette.py`'s own threshold, quoted here so the two cannot
# drift: every character must carry a colour above this saturation.
CHAR_MIN_SAT = 0.55

BG = (28, 28, 34, 255)
GRID = (58, 58, 70, 255)
INK = (235, 235, 245, 255)
WARN = (240, 170, 90, 255)

# 3x5 bitmap font. Same construction as scripts/contact-sheet.py's digits,
# extended to letters because a costume has a name and an index does not.
FONT = {
    "0": ("###", "# #", "# #", "# #", "###"), "1": (" # ", "## ", " # ", " # ", "###"),
    "2": ("###", "  #", "###", "#  ", "###"), "3": ("###", "  #", "###", "  #", "###"),
    "4": ("# #", "# #", "###", "  #", "  #"), "5": ("###", "#  ", "###", "  #", "###"),
    "6": ("###", "#  ", "###", "# #", "###"), "7": ("###", "  #", "  #", "  #", "  #"),
    "8": ("###", "# #", "###", "# #", "###"), "9": ("###", "# #", "###", "  #", "###"),
    "A": (" # ", "# #", "###", "# #", "# #"), "B": ("## ", "# #", "## ", "# #", "## "),
    "C": (" ##", "#  ", "#  ", "#  ", " ##"), "D": ("## ", "# #", "# #", "# #", "## "),
    "E": ("###", "#  ", "## ", "#  ", "###"), "F": ("###", "#  ", "## ", "#  ", "#  "),
    "G": (" ##", "#  ", "# #", "# #", " ##"), "H": ("# #", "# #", "###", "# #", "# #"),
    "I": ("###", " # ", " # ", " # ", "###"), "J": ("  #", "  #", "  #", "# #", " # "),
    "K": ("# #", "# #", "## ", "# #", "# #"), "L": ("#  ", "#  ", "#  ", "#  ", "###"),
    "M": ("# #", "###", "###", "# #", "# #"), "N": ("# #", "## ", "###", " ##", "# #"),
    "O": (" # ", "# #", "# #", "# #", " # "), "P": ("## ", "# #", "## ", "#  ", "#  "),
    "Q": (" # ", "# #", "# #", " # ", "  #"), "R": ("## ", "# #", "## ", "# #", "# #"),
    "S": (" ##", "#  ", " # ", "  #", "## "), "T": ("###", " # ", " # ", " # ", " # "),
    "U": ("# #", "# #", "# #", "# #", " ##"), "V": ("# #", "# #", "# #", " # ", " # "),
    "W": ("# #", "# #", "###", "###", "# #"), "X": ("# #", "# #", " # ", "# #", "# #"),
    "Y": ("# #", "# #", " # ", " # ", " # "), "Z": ("###", "  #", " # ", "#  ", "###"),
    "-": ("   ", "   ", "###", "   ", "   "), " ": ("   ",) * 5,
    ".": ("   ", "   ", "   ", "   ", "#  "), ":": ("   ", " # ", "   ", " # ", "   "),
    "%": ("# #", "  #", " # ", "#  ", "# #"), "+": ("   ", " # ", "###", " # ", "   "),
    "/": ("  #", "  #", " # ", "#  ", "#  "), "_": ("   ", "   ", "   ", "   ", "###"),
}


# ---------------------------------------------------------------------------
# The generator's layers
# ---------------------------------------------------------------------------

_sheets = {}


def sheet(path):
    if path not in _sheets:
        _sheets[path] = pnglite.load(path)
    return _sheets[path]


def frame(path, row, col):
    """Cut one 32x64 frame out of any generator layer sheet.

    Indexing is by the *sheet's own* width, which matters: Outfits, Hairstyles
    and Eyes are 1792 wide, Bodies and four of the Accessories are 1854. Both
    are 56 columns of 32 px starting at x=0 — the extra 62 px is trailing pad —
    so a frame address is the same in both and registration needs no offset.
    """
    w, h, px = sheet(path)
    buf = pnglite.new(FW, FH)
    for y in range(FH):
        sy = row * FH + y
        if sy >= h:
            break
        si = (sy * w + col * FW) * 4
        buf[y * FW * 4:(y + 1) * FW * 4] = px[si:si + FW * 4]
    return buf


def over(dst, src):
    for i in range(0, len(dst), 4):
        a = src[i + 3]
        if a == 0:
            continue
        if a == 255:
            dst[i:i + 4] = src[i:i + 4]
            continue
        da = dst[i + 3]
        oa = a + da * (255 - a) // 255
        if oa:
            for c in range(3):
                dst[i + c] = (src[i + c] * a
                              + dst[i + c] * da * (255 - a) // 255) // oa
        dst[i + 3] = oa
    return dst


def layer_paths(spec, size="32x32"):
    """The source PNGs behind one COSTUMES entry, back to front."""
    imp = import_process_assets()
    out = []
    for kind, pick in spec["layers"]:
        folder, tmpl = imp.COSTUME_LAYER_SRC[kind]
        name = tmpl % (pick[0], size, pick[1]) if isinstance(pick, tuple) \
            else tmpl % (size, pick)
        out.append(os.path.join(GEN, folder, size, name))
    return out


def premade(who="06"):
    return os.path.join(PREMADES, "32x32", "Premade_Character_32x32_%s.png" % who)


def dressed(spec, pose=SEATED, who="06"):
    """One premade wearing one costume — the picture the scene composes.

    Composited here rather than layered because a still image cannot have
    z-order, and this is what `Character` draws: the body sprite with the
    costume's layer nodes over it, on the body's own frame index. The scene is
    the thing that keeps them in phase; this is the thing that shows what the
    result looks like.
    """
    row, col = pose
    buf = frame(premade(who), row, col)
    for p in layer_paths(spec):
        over(buf, frame(p, row, col))
    return buf


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

def mask(px):
    """Flatten to solid black. The rule is `04-ART-DIRECTION.md`'s: if two
    variants match here they are one character in different colours."""
    return bytes(1 if px[i + 3] >= 128 else 0 for i in range(0, len(px), 4))


def silhouette_distance(a, b):
    """Percent of the combined outline that differs.

    `diff / union`, which is the arithmetic `scripts/generate-art.py` already
    runs on the fallback cast and the arithmetic behind FINDINGS-M0.md's 7.3%.
    Reproduced rather than re-invented so the numbers can be put side by side.
    """
    diff = sum(1 for p, q in zip(a, b) if p != q)
    union = sum(1 for p, q in zip(a, b) if p or q)
    return 100.0 * diff / union if union else 0.0


def hsv(r, g, b):
    r, g, b = r / 255.0, g / 255.0, b / 255.0
    mx, mn = max(r, g, b), min(r, g, b)
    s = 0.0 if mx == 0 else (mx - mn) / mx
    if mx == mn:
        h = 0.0
    elif mx == r:
        h = (60 * (g - b) / (mx - mn)) % 360
    elif mx == g:
        h = 60 * (b - r) / (mx - mn) + 120
    else:
        h = 60 * (r - g) / (mx - mn) + 240
    return h, s, mx


def palette(px):
    """(max saturation, darkest value, opaque pixel count) — the two numbers I7
    is about, on one frame."""
    ms, dv, n = 0.0, 1.0, 0
    for i in range(0, len(px), 4):
        if px[i + 3] < 128:
            continue
        n += 1
        _h, s, v = hsv(px[i], px[i + 1], px[i + 2])
        ms = max(ms, s)
        dv = min(dv, v)
    return ms, dv, n


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

def text(buf, w, h, x0, y0, s, scale=1, colour=INK):
    for i, ch in enumerate(str(s).upper()):
        g = FONT.get(ch, FONT[" "])
        for r, rowbits in enumerate(g):
            for c, p in enumerate(rowbits):
                if p == "#":
                    pnglite.fill_rect(buf, w, h, x0 + (i * 4 + c) * scale,
                                      y0 + r * scale, scale, scale, colour)


def upscale(px, n, w=FW, h=FH):
    if n == 1:
        return w, h, px
    out = pnglite.new(w * n, h * n)
    for y in range(h):
        for x in range(w):
            p = px[(y * w + x) * 4:(y * w + x) * 4 + 4]
            for dy in range(n):
                ro = ((y * n + dy) * w * n + x * n) * 4
                for dx in range(n):
                    out[ro + dx * 4:ro + dx * 4 + 4] = p
    return w * n, h * n, out


def blit(dst, dw, dh, x0, y0, sw, sh, src):
    for y in range(sh):
        ty = y0 + y
        if ty < 0 or ty >= dh:
            continue
        for x in range(sw):
            tx = x0 + x
            if tx < 0 or tx >= dw:
                continue
            si = (y * sw + x) * 4
            a = src[si + 3]
            if a == 0:
                continue
            di = (ty * dw + tx) * 4
            if a == 255:
                dst[di:di + 4] = src[si:si + 4]
            else:
                for c in range(3):
                    dst[di + c] = (src[si + c] * a + dst[di + c] * (255 - a)) // 255
                dst[di + 3] = 255


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

def mode_coverage(out, quiet=False):
    """Which pose rows and direction blocks each generator layer carries ink on.

    This is the check M6g's `Books` finding says to run *before* designing
    anything on top of a layer: the folder name is not the coverage, the alpha
    channel is. Reported per layer family, per row this project cuts, per
    direction, per frame.
    """
    imp = import_process_assets()
    report = {}
    for family, pattern in (("Bodies", "Body_*"), ("Eyes", "Eyes_*"),
                            ("Outfits", "Outfit_*"), ("Hairstyles", "Hairstyle_*"),
                            ("Accessories", "Accessory_*")):
        files = sorted(glob.glob(os.path.join(GEN, family, "32x32", pattern + ".png")))
        geoms, gaps, rowless = {}, [], []
        for f in files:
            w, h, _bd, _ct, _il = pnglite.read_header(f)
            geoms[(w, h)] = geoms.get((w, h), 0) + 1
            if w // FW < COLS or h < ROWS * FH:
                continue
            for state, (row, per_dir, dirs) in imp.CHAR_EXPORT.items():
                for d in dirs:
                    block = DIRS.index(d)
                    for k in range(per_dir):
                        px = frame(f, row, block * per_dir + k)
                        if not any(px[i] for i in range(3, len(px), 4)):
                            gaps.append((os.path.basename(f), state, d, k))
            # A whole row with no ink anywhere is worth naming separately: it is
            # what `sleep` looks like on an outfit sheet — row 3 is a head on a
            # pillow and has no body to dress — and it is not a defect.
            for row in range(ROWS):
                if not any(any(frame(f, row, c)[i]
                               for i in range(3, FW * FH * 4, 4))
                           for c in range(0, COLS, 4)):
                    rowless.append((os.path.basename(f), row))
            _sheets.clear()
        report[family] = {"files": len(files),
                          "geometries": {"%dx%d" % k: v for k, v in geoms.items()},
                          "gaps_in_cut_rows": gaps,
                          "rows_with_no_ink": sorted(set(r for _f, r in rowless))}
        if not quiet:
            print("%-12s %3d files  %s" % (family, len(files),
                                           ", ".join("%dx%d x%d" % (k[0], k[1], v)
                                                     for k, v in sorted(geoms.items()))))
            if gaps:
                for g in gaps[:12]:
                    print("    GAP  %s %s/%s frame %d" % g)
                if len(gaps) > 12:
                    print("    ... and %d more" % (len(gaps) - 12))
            else:
                print("    every cut pose row, every direction, every frame: ink present")
            if rowless:
                print("    rows with no ink anywhere (not cut, not a defect): %s"
                      % ", ".join(str(r) for r in sorted(set(r for _f, r in rowless))))
    with open(os.path.join(out, "coverage.json"), "w") as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write("\n")
    return report


def mode_outfits(out, all_colours=False, roles_only=False, scale=6, per_page=12):
    """Contact sheets of the outfit layers, front-facing and seated.

    Drawn **on a premade**, because that is what the scene does — a costume is
    an overlay on the cast, not a character of its own, and an outfit judged on
    a bare bald body is judged in a situation that never occurs. Front-facing
    because that is where a garment is identifiable; seated because that is the
    only pose this room draws while an agent works, and an outfit that reads as
    a role standing and as a smudge sitting is not a role here. The 1x copy on
    the right of each cell is the acceptance test.
    """
    pat = "*.png" if all_colours else "*_01.png"
    files = sorted(glob.glob(os.path.join(GEN, "Outfits/32x32", pat)))
    if roles_only:
        files = [f for f in files
                 if os.path.basename(f).split("_")[1] in ROLE_FAMILIES]
    cw = FW * scale * 2 + 24 + FW + 8
    ch = FH * scale + 22
    cols = 3
    written = []
    for page in range((len(files) + per_page - 1) // per_page):
        part = files[page * per_page:(page + 1) * per_page]
        rows = (len(part) + cols - 1) // cols
        w, h = cols * cw, rows * ch
        buf = bytearray(bytes(BG) * (w * h))
        for i, f in enumerate(part):
            name = os.path.basename(f).replace("Outfit_", "").replace("_32x32", "") \
                                      .replace(".png", "")
            x0, y0 = (i % cols) * cw, (i // cols) * ch
            pnglite.fill_rect(buf, w, h, x0, y0, cw - 2, 1, GRID)
            text(buf, w, h, x0 + 5, y0 + 4, name, 3)
            for j, pose in enumerate((IDLE_FRONT, SEATED)):
                px = frame(premade(), *pose)
                over(px, frame(f, *pose))
                sw, sh, sp = upscale(px, scale)
                blit(buf, w, h, x0 + 5 + j * (FW * scale + 6), y0 + 22, sw, sh, sp)
                if j == 1:
                    blit(buf, w, h, x0 + 16 + 2 * FW * scale,
                         y0 + 22 + FH * scale - FH, FW, FH, px)
        p = os.path.join(out, "outfits_%s_p%d.png"
                         % ("roles" if roles_only else "all", page))
        pnglite.save(p, w, h, buf)
        written.append(p)
    return written


# The outfit families that carry role vocabulary, found by rendering all 33 and
# looking at them. `--outfits --roles-only` draws just these, which is the sheet
# worth keeping; the other twenty designs are a different shirt.
ROLE_FAMILIES = ("06", "08", "09", "12", "15", "16", "18", "19", "22", "26",
                 "28", "30", "33")


def mode_costumes(out, costumes, order, scale=6):
    """Every costume on a seated premade at 4x and at 1x, with its numbers.

    1x is the gate: `04-ART-DIRECTION.md` says design at 2x and accept at 1x.
    The label carries the costume's title and whether it asserts anything —
    orange for the pool, white for a role — so the sheet is reviewable without
    this file open beside it.
    """
    cw = FW * scale + FW + 28
    ch = FH * scale + 64
    cols = 6
    rows = (len(order) + cols - 1) // cols
    w, h = cols * cw, rows * ch
    buf = bytearray(bytes(BG) * (w * h))
    for i, name in enumerate(order):
        spec = costumes[name]
        px = dressed(spec)
        bare = frame(premade(), *SEATED)
        changed = sum(1 for k in range(0, len(px), 4) if px[k:k + 4] != bare[k:k + 4])
        ms, dv, n = palette(px)
        x0, y0 = (i % cols) * cw, (i // cols) * ch
        pnglite.fill_rect(buf, w, h, x0, y0, cw - 2, 1, GRID)
        text(buf, w, h, x0 + 5, y0 + 5, name, 3,
             INK if spec.get("asserts") else WARN)
        sw, sh, sp = upscale(px, scale)
        blit(buf, w, h, x0 + 5, y0 + 22, sw, sh, sp)
        blit(buf, w, h, x0 + 14 + FW * scale, y0 + 22 + FH * scale - FH, FW, FH, px)
        text(buf, w, h, x0 + 5, y0 + 28 + FH * scale, "CHG %d PX" % changed, 2)
        text(buf, w, h, x0 + 5, y0 + 40 + FH * scale, "SILH %d" % n, 2)
        text(buf, w, h, x0 + 5, y0 + 52 + FH * scale,
             "SAT %d DK %d" % (round(ms * 100), round(dv * 100)), 2)
    p = os.path.join(out, "costumes_%dx.png" % scale)
    pnglite.save(p, w, h, buf)
    return p


def import_process_assets():
    spec = importlib.util.spec_from_file_location(
        "process_assets", os.path.join(REPO, "scripts", "process-assets.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def import_preview_theme():
    spec = importlib.util.spec_from_file_location(
        "preview_theme", os.path.join(REPO, "scripts", "preview-theme.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def mode_room(out, costumes, order, theme="office", panel=(720, 400), who=None):
    """The costumes seated in the real panel, in the tool the scene is tied to.

    `preview-theme.py --verify` holds that tool against `RoomScene` at zero
    differing pixels in all six themes, so this is not a third opinion about the
    room — it is the room, with dressed characters in the seats. The bodies are
    the shipped cast in manifest order, so what varies between seats is the
    costume and only the costume.

    The question this picture has to answer is the maintainer's: can you tell a
    tester from a developer by looking?
    """
    pt = import_preview_theme()
    with open(MANIFEST) as f:
        m = json.load(f)
    sets = m.get("themes", {}).get("sets")
    if not sets or theme not in sets:
        raise SystemExit("no theme %r in the manifest" % theme)
    variants = sorted(m["characters"]["variants"])
    who = who or variants
    scratch = os.path.join(out, "_seated")
    os.makedirs(scratch, exist_ok=True)
    seated = {}
    for i, name in enumerate(order):
        px = dressed(costumes[name], SEATED, who[i % len(who)])
        p = os.path.join(scratch, "%s.png" % name)
        pnglite.save(p, FW, FH, px)
        seated[name] = os.path.relpath(p, REPO)
    dst = os.path.join(out, "room_%s.png" % theme)
    pt.render(sets[theme], theme, len(order), dst, seated, list(order), panel=panel)

    # The same picture with the occupied band cut out and blown up. The 1x copy
    # is the acceptance test and stays the artefact of record; this is a *crop*
    # of that accepted picture, not a second render of it, so a reviewer can see
    # why it does or does not read without being shown a different image.
    w, h, px = pnglite.load(dst)
    empty = os.path.join(out, "_empty_%s.png" % theme)
    pt.render(sets[theme], theme, 0, empty, seated, list(order), panel=panel)
    _ew, _eh, epx = pnglite.load(empty)
    rows = [y for y in range(h)
            if any(px[(y * w + x) * 4:(y * w + x) * 4 + 4]
                   != epx[(y * w + x) * 4:(y * w + x) * 4 + 4] for x in range(w))]
    cols = [x for x in range(w)
            if any(px[(y * w + x) * 4:(y * w + x) * 4 + 4]
                   != epx[(y * w + x) * 4:(y * w + x) * 4 + 4] for y in range(h))]
    if rows and cols:
        pad = 12
        y0, y1 = max(0, rows[0] - pad), min(h - 1, rows[-1] + pad)
        x0, x1 = max(0, cols[0] - pad), min(w - 1, cols[-1] + pad)
        cw2, ch2 = x1 - x0 + 1, y1 - y0 + 1
        crop = pnglite.new(cw2, ch2)
        for y in range(ch2):
            si = ((y0 + y) * w + x0) * 4
            crop[y * cw2 * 4:(y + 1) * cw2 * 4] = px[si:si + cw2 * 4]
        zw, zh, zoom = upscale(crop, 4, cw2, ch2)
        pnglite.save(os.path.join(out, "room_%s_4x.png" % theme), zw, zh, zoom)
    os.remove(empty)
    return dst


def mode_measure(out, costumes, order, quiet=False):
    """The numbers a costume set lives or dies by, against the shipped cast.

    **Silhouette**, by M0's own arithmetic, on the pose the room draws *and* on
    the front-facing idle frame M0 used — because a set that only looks
    separable on the friendlier pose has not been measured, it has been framed.
    The comparison is between *dressed* characters, since that is what is on
    screen, and the premade row is the same six bodies undressed.

    **Value**, because that is the channel an outfit actually has: the mean
    value of the block it changes, and how far apart those blocks are.

    **I7**, per costume: peak saturation and darkest value against the cast's
    0.314 and against the room's mean. A costume is drawn on the character,
    which owns the darkest and most saturated pixels in the room, so this is
    where the invariant is tightest.
    """
    imp = import_process_assets()
    result = {"poses": {}, "palette": {}, "value": {}}
    cast = imp.CHAR_CAST
    for label, pose in (("sit_right_f0", SEATED), ("idle_down_f0", IDLE_FRONT)):
        # Every costume on ONE body, so the difference measured is the costume's
        # and not the body's.
        masks = {n: mask(dressed(costumes[n], pose)) for n in order}
        pre = {}
        for c in cast:
            p = premade(c)
            if os.path.exists(p):
                pre[c] = mask(frame(p, *pose))

        def matrix(ms):
            names = sorted(ms)
            return sorted((silhouette_distance(ms[a], ms[b]), a, b)
                          for a, b in itertools.combinations(names, 2))

        rec = [n for n in order if costumes[n].get("asserts") is not None]
        neu = [n for n in order if costumes[n].get("asserts") is None]
        entry = {
            "all": matrix(masks)[0] if len(masks) > 1 else None,
            "recognised": matrix({n: masks[n] for n in rec})[0] if len(rec) > 1 else None,
            "assignable": matrix({n: masks[n] for n in neu})[0] if len(neu) > 1 else None,
            "premades_undressed": matrix(pre)[0] if len(pre) > 1 else None,
            "worst_pairs": matrix(masks)[:5],
            "best_pairs": matrix(masks)[-3:],
        }
        result["poses"][label] = entry
        if not quiet:
            print("== silhouette, %s (diff/union, M0's arithmetic)" % label)
            for k in ("premades_undressed", "recognised", "assignable", "all"):
                v = entry[k]
                if v:
                    print("   %-19s min %5.2f%%  (%s vs %s)" % ((k,) + v))
            print("   %-19s max %5.2f%%  (%s vs %s)"
                  % (("costumes",) + entry["best_pairs"][-1]))

    # --- value, the channel an outfit actually has -------------------------
    bare = frame(premade(), *SEATED)
    if not quiet:
        print("\n== value, seated frame, on premade %s" % imp.CHAR_CAST[0])
        print("   %-10s %-6s %-7s %-7s %s" % ("costume", "chg", "meanV", "silh+", "title"))
    vals = []
    for n in order:
        px = dressed(costumes[n], SEATED)
        idx = [k for k in range(0, len(px), 4) if px[k:k + 4] != bare[k:k + 4]]
        vs = [hsv(px[k], px[k + 1], px[k + 2])[2] for k in idx]
        mean_v = sum(vs) / len(vs) if vs else 0.0
        add = sum(mask(px)) - sum(mask(bare))
        result["value"][n] = {"changed_px": len(idx), "mean_value": round(mean_v, 3),
                              "silhouette_added_px": add}
        vals.append((mean_v, n))
        if not quiet:
            print("   %-10s %-6d %-7.3f %-7d %s"
                  % (n, len(idx), mean_v, add, costumes[n].get("title", "")))
    vals.sort()
    gaps = [(round(b[0] - a[0], 3), a[1], b[1]) for a, b in zip(vals, vals[1:])]
    result["value_gaps"] = gaps
    if not quiet and gaps:
        tight = min(gaps)
        print("   value span %.3f to %.3f; closest pair %s/%s at %.3f apart"
              % (vals[0][0], vals[-1][0], tight[1], tight[2], tight[0]))

    # --- and the number that actually predicts the picture ------------------
    #
    # **HSV value is the project's metric and it is the wrong one for this
    # question.** `V = max(R,G,B)`, so a saturated red and a white shirt score
    # 0.895 and 0.891 and look nothing alike, while two greys 0.05 apart look
    # identical. What a user is doing at 1x is telling two ~100 px blocks of
    # flat colour apart, so the honest measure is the distance between those
    # blocks' mean colours. Both are reported: `V` because the rest of this
    # repo speaks it, and this because it is what the room shows.
    means = {}
    for n in order:
        px = dressed(costumes[n], SEATED)
        idx = [k for k in range(0, len(px), 4) if px[k:k + 4] != bare[k:k + 4]]
        if not idx:
            continue
        means[n] = tuple(sum(px[k + c] for k in idx) / len(idx) for c in range(3))
    pairs = sorted((round(sum((means[a][c] - means[b][c]) ** 2
                              for c in range(3)) ** 0.5, 1), a, b)
                   for a, b in itertools.combinations(sorted(means), 2))
    result["block_colour"] = {n: [round(v, 1) for v in means[n]] for n in means}
    result["block_distance"] = pairs
    if not quiet and pairs:
        print("\n== changed-block mean colour, RGB distance (0-441)")
        print("   closest:  " + ", ".join("%s/%s %.0f" % (a, b, d)
                                          for d, a, b in pairs[:4]))
        print("   furthest: " + ", ".join("%s/%s %.0f" % (a, b, d)
                                          for d, a, b in pairs[-2:]))
        rec = [p for p in pairs if costumes[p[1]].get("asserts") is not None
               and costumes[p[2]].get("asserts") is not None]
        if rec:
            print("   closest two roles: %s/%s at %.0f" % (rec[0][1], rec[0][2], rec[0][0]))

    # --- I7 ---------------------------------------------------------------
    with open(MANIFEST) as f:
        m = json.load(f)
    rooms = {}
    for tname, tset in sorted(m.get("themes", {}).get("sets", {}).items()):
        pal = tset.get("palette") or {}
        if pal:
            rooms[tname] = pal
    bs, bv, bn = palette(bare)
    # The floor is the cast's own darkest pixel as measured, not the rounded
    # 0.314 the documents print. `80/255` compared against `0.314` is a
    # false alarm every time, which is the kind of check that gets ignored.
    floor = min(palette(frame(premade(c), *SEATED))[1] for c in imp.CHAR_CAST)
    if not quiet:
        print("\n== I7, seated frame. undressed premade %s: max sat %.3f, "
              "darkest %.3f, %d px" % (imp.CHAR_CAST[0], bs, bv, bn))
        print("   cast floor across all six variants: %.4f" % floor)
        print("   %-10s %-7s %-7s %-8s %-7s %s"
              % ("costume", "maxsat", "darkest", "worstsat", "asserts", "layer darkest"))
    worst_sat = None
    for n in order:
        px = dressed(costumes[n], SEATED)
        ms, dv, _cnt = palette(px)
        # **Every cast variant, not just one.** A costume covers whatever the
        # body was carrying underneath it, so "this character still owns the
        # saturation" is a claim about a costume *on a wearer*, and the wearer
        # is whichever variant the seat happened to get.
        per_variant = {c: palette(dressed(costumes[n], SEATED, c))[:2]
                       for c in imp.CHAR_CAST}
        low_sat = min(v[0] for v in per_variant.values())
        low_val = min(v[1] for v in per_variant.values())
        own = [palette(frame(p, *SEATED))[1] for p in layer_paths(costumes[n])]
        result["palette"][n] = {
            "max_saturation": round(ms, 3), "darkest_value": round(dv, 3),
            "worst_saturation_over_cast": round(low_sat, 3),
            "worst_darkest_over_cast": round(low_val, 4),
            "layer_darkest": [round(v, 3) for v in own]}
        if worst_sat is None or low_sat < worst_sat[0]:
            worst_sat = (low_sat, n)
        if not quiet:
            flag = "" if low_val >= floor else "   << BELOW THE CAST FLOOR"
            if low_sat <= CHAR_MIN_SAT:
                flag += "   << under CHAR_MIN_SAT %.2f" % CHAR_MIN_SAT
            print("   %-10s %-7.3f %-7.3f %-8.3f %-7s %s%s"
                  % (n, ms, dv, low_sat, "yes" if costumes[n].get("asserts") else "no",
                     ", ".join("%.3f" % v for v in own), flag))
    result["worst_saturation"] = {"costume": worst_sat[1], "value": round(worst_sat[0], 3)}
    result["cast_floor"] = round(floor, 4)
    result["undressed"] = {"max_saturation": round(bs, 3),
                           "darkest_value": round(bv, 3), "silhouette_px": bn}
    result["room"] = rooms
    with open(os.path.join(out, "measure.json"), "w") as f:
        json.dump(result, f, indent=1, sort_keys=True, default=list)
        f.write("\n")
    return result


def mode_select(costumes, order, quiet=False):
    """Re-derive the assignable pool's colourways from the value axis.

    **Value, not hue, and not silhouette.** Hue is already the nameplate
    accent's channel — six hues 60 degrees apart, assigned at M5 — and spending
    it twice buys nothing. Silhouette is not on offer: an outfit adds 0-16 px of
    outline to a seated body, so a pool chosen for outline would be six
    identically-shaped people. What is left is the value of the block the outfit
    changes, and the honest pool is the widest evenly-spread set of plain-shirt
    colourways that clears the cast's 0.314 floor.

    Prints what it found; does not write the table. A pinned number somebody can
    disagree with is worth more than one recomputed on every import.
    """
    imp = import_process_assets()
    bare = frame(premade(), *SEATED)
    role_values = []
    for n in order:
        if costumes[n].get("asserts") is None:
            continue
        px = dressed(costumes[n], SEATED)
        idx = [k for k in range(0, len(px), 4) if px[k:k + 4] != bare[k:k + 4]]
        vs = [hsv(px[k], px[k + 1], px[k + 2])[2] for k in idx]
        role_values.append(sum(vs) / len(vs))
    rows = []
    for f in sorted(glob.glob(os.path.join(GEN, "Outfits/32x32", "*.png"))):
        base = os.path.basename(f)
        if base in imp.COSTUME_EXCLUDED:
            continue
        family = base.split("_")[1]
        if family not in NEUTRAL_FAMILIES:
            continue
        px = bytearray(bare)
        over(px, frame(f, *SEATED))
        idx = [k for k in range(0, len(px), 4) if px[k:k + 4] != bare[k:k + 4]]
        if not idx:
            continue
        vs = [hsv(px[k], px[k + 1], px[k + 2])[2] for k in idx]
        # **Saturation is reported, not filtered.** A costume covers whatever
        # the body carried underneath it, so a desaturated garment takes its
        # wearer under `CHAR_MIN_SAT` — and the two garments the value spread
        # exists for, the lightest and the darkest, are exactly the two with no
        # saturation to give. Filtering them out costs half the span (0.447
        # down to 0.223), so the pick is made knowing the trade rather than
        # having it made silently by a `continue`.
        sat = palette(frame(f, *SEATED))[0]
        rows.append((sum(vs) / len(vs), family, base, sat))
        _sheets.pop(f, None)
    rows.sort()
    want = len([n for n in order if costumes[n].get("asserts") is None])
    best = None
    for combo in itertools.combinations(rows, want):
        if len(set(c[1] for c in combo)) < want - 1:
            continue
        vs = [c[0] for c in combo]
        gap = min(b - a for a, b in zip(vs, vs[1:]))
        # Also keep clear of the role costumes, which share the screen with the
        # pool and are the ones a user is being asked to read.
        clear = min(abs(v - r) for v in vs for r in role_values) if role_values else 1.0
        score = (round(min(gap, clear), 4), round(vs[-1] - vs[0], 4))
        if best is None or score > best[0]:
            best = (score, combo)
    if not quiet and best:
        print("assignable pool: %d plain-shirt colourways over the 0.314 floor"
              % len(rows))
        print("   min gap (to each other and to any role) %.3f, span %.3f" % best[0])
        for v, _fam, base, sat in best[1]:
            mark = "" if sat >= CHAR_MIN_SAT else \
                "   << takes its wearer under CHAR_MIN_SAT %.2f" % CHAR_MIN_SAT
            print("   %-28s mean value %.3f  layer saturation %.3f%s"
                  % (base, v, sat, mark))
    return best


# Outfit families with no role vocabulary — plain tees, jumpers and buttoned
# shirts. Everything else in the pack says something: a coat, a hi-vis top, an
# apron, dungarees, a suit, a hood, chef's whites, a towel. Derived by rendering
# all 33 and looking at them; the contact sheets are what this list is arguing
# from and `--outfits` regenerates them.
NEUTRAL_FAMILIES = ("01", "04", "10", "11", "13", "14", "17", "20", "21",
                    "23", "24", "27", "29")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True, help="scratch directory for pictures")
    ap.add_argument("--coverage", action="store_true")
    ap.add_argument("--outfits", action="store_true")
    ap.add_argument("--all-colours", action="store_true",
                    help="--outfits: all 132 files, not one per design")
    ap.add_argument("--roles-only", action="store_true",
                    help="--outfits: only the families that carry role vocabulary")
    ap.add_argument("--costumes", action="store_true")
    ap.add_argument("--scale", type=int, default=4,
                    help="--costumes: zoom for the large copy (default 4; the 1x "
                         "copy beside it is the acceptance test either way)")
    ap.add_argument("--room", action="store_true")
    ap.add_argument("--theme", default="office")
    ap.add_argument("--size", default="720x400")
    ap.add_argument("--measure", action="store_true")
    ap.add_argument("--select", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    if not os.path.isdir(GEN):
        print("error: %s is absent. The packs are gitignored; unpack them under "
              "assets/." % os.path.relpath(GEN, REPO), file=sys.stderr)
        return 2
    os.makedirs(args.out, exist_ok=True)

    imp = import_process_assets()
    costumes = imp.COSTUMES
    # Recognised first, then the pool, so every sheet reads in the order the
    # table is argued in.
    recognised = sorted(set(imp.COSTUME_ROLES.values()))
    order = recognised + [n for n in imp.COSTUME_ASSIGNABLE if n not in recognised]

    did = False
    if args.coverage:
        mode_coverage(args.out, args.quiet)
        did = True
    if args.outfits:
        for p in mode_outfits(args.out, args.all_colours, args.roles_only):
            print(os.path.relpath(p))
        did = True
    if args.costumes:
        print(os.path.relpath(
            mode_costumes(args.out, costumes, order, scale=args.scale)))
        did = True
    if args.room:
        w, h = (int(v) for v in args.size.lower().split("x", 1))
        print(os.path.relpath(
            mode_room(args.out, costumes, recognised, args.theme, (w, h))))
        did = True
    if args.measure:
        mode_measure(args.out, costumes, order, args.quiet)
        did = True
    if args.select:
        mode_select(costumes, order, args.quiet)
        did = True
    if not did:
        ap.error("nothing to do: pick at least one of --coverage --outfits "
                 "--costumes --room --measure --select")
    return 0


if __name__ == "__main__":
    sys.exit(main())
