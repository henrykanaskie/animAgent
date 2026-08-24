#!/usr/bin/env python3
"""Render a directory of index-named sprite singles onto a labelled contact sheet.

Why this exists
---------------
LimeZu names its singles by index only. `00_Modern_Office_Singles.ase` holds one
unnamed layer and 339 unnamed frames (no slices, no tags) and the 24 theme
sorter sets in Modern Interiors are the same. There is nothing to look up and no
auto-slicer here, so the only way to find out what single 171 *is* is to render
it and look at it.

M5 did this once by hand for the 339 Office singles and identified four roles.
This script is that pass, committed and re-runnable, so the next person who
needs a prop does not repeat the work from zero. It is a *tool*, not part of the
import pipeline: it writes to a scratch directory and never touches `assets/`.

Usage
-----
    contact-sheet.py --set 13                 # one theme set, all pages
    contact-sheet.py --set 13 --page 0        # one page
    contact-sheet.py --office                 # the Modern Office singles
    contact-sheet.py --list                   # what sets exist
    contact-sheet.py --sheet PATH --tile 32   # label a uniform tile sheet r-c

The `--sheet` mode is the same idea applied to the Room Builder sheets, which
are uniform grids rather than singles: it writes the row-column address into
every cell so a floor or wall can be picked by address and re-checked later.
That is how the per-theme floor and wall picks in scripts/process-assets.py
were chosen.

Output goes to --out (default: the scratch themes dir). Each cell carries its
single's index in a 3x5 bitmap font, so a finding can be written down as an
index and re-checked by anyone.

Python 3 stdlib only.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THEME_ROOT = os.path.join(
    REPO,
    "assets/moderninteriors-win/1_Interiors/32x32",
    "Theme_Sorter_Shadowless_Singles_32x32",
)
OFFICE_ROOT = os.path.join(
    REPO, "assets/Modern_Office_Revamped_v1.2/4_Modern_Office_singles/32x32"
)

# 3x5 digit font. Enough to label a cell; nothing here is shipped art.
DIGITS = {
    "0": ("###", "# #", "# #", "# #", "###"),
    "1": (" # ", "## ", " # ", " # ", "###"),
    "2": ("###", "  #", "###", "#  ", "###"),
    "3": ("###", "  #", "###", "  #", "###"),
    "4": ("# #", "# #", "###", "  #", "  #"),
    "5": ("###", "#  ", "###", "  #", "###"),
    "6": ("###", "#  ", "###", "# #", "###"),
    "7": ("###", "  #", "  #", "  #", "  #"),
    "8": ("###", "# #", "###", "# #", "###"),
    "9": ("###", "# #", "###", "  #", "###"),
    "-": ("   ", "   ", "###", "   ", "   "),
}

BG = (28, 28, 34, 255)
GRID = (58, 58, 70, 255)
INK = (235, 235, 245, 255)
FLOOR = (48, 48, 58, 255)


def index_of(name):
    m = re.search(r"_(\d+)\.png$", name)
    return int(m.group(1)) if m else -1


def listdir_sorted(d):
    fs = [f for f in os.listdir(d) if f.lower().endswith(".png")]
    return sorted(fs, key=index_of)


def blit(dst, dw, dh, src, sw, sh, x0, y0):
    """Alpha-over `src` onto `dst` at (x0, y0), clipped."""
    for y in range(sh):
        dy = y0 + y
        if dy < 0 or dy >= dh:
            continue
        for x in range(sw):
            dx = x0 + x
            if dx < 0 or dx >= dw:
                continue
            si = (y * sw + x) * 4
            a = src[si + 3]
            if a == 0:
                continue
            di = (dy * dw + dx) * 4
            if a == 255:
                dst[di : di + 4] = src[si : si + 4]
            else:
                for c in range(3):
                    dst[di + c] = (src[si + c] * a + dst[di + c] * (255 - a)) // 255
                dst[di + 3] = 255


def draw_text(buf, w, h, x0, y0, text, scale=1, colour=INK):
    cx = x0
    for ch in text:
        rows = DIGITS.get(ch)
        if rows is None:
            cx += 4 * scale
            continue
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    pnglite.fill_rect(
                        buf, w, h, cx + rx * scale, y0 + ry * scale, scale, scale, colour
                    )
        cx += 4 * scale


def scale_up(src, sw, sh, k):
    if k == 1:
        return src, sw, sh
    dw, dh = sw * k, sh * k
    dst = bytearray(dw * dh * 4)
    for y in range(sh):
        for x in range(sw):
            si = (y * sw + x) * 4
            px = src[si : si + 4]
            for yy in range(k):
                base = ((y * k + yy) * dw + x * k) * 4
                for xx in range(k):
                    dst[base + xx * 4 : base + xx * 4 + 4] = px
    return dst, dw, dh


def sheet(files, root, out_path, cols, scale, page_label, start_index):
    """Render one page. Cells are sized to the largest sprite on the page so
    nothing is cropped; a cropped contact sheet is how you mis-identify a prop."""
    imgs = []
    for f in files:
        w, h, px = pnglite.load(os.path.join(root, f))
        imgs.append((index_of(f), w, h, px))

    cw = max(i[1] for i in imgs) * scale + 8
    ch = max(i[2] for i in imgs) * scale + 8 + 8  # + label strip
    rows = (len(imgs) + cols - 1) // cols
    W, H = cols * cw, rows * ch + 12

    buf = bytearray(bytes(BG) * (W * H))
    draw_text(buf, W, H, 4, 3, page_label, 1)

    for n, (idx, w, h, px) in enumerate(imgs):
        r, c = divmod(n, cols)
        x0, y0 = c * cw, r * ch + 12
        # alternating cell wash so cell boundaries are visible
        if (r + c) % 2 == 0:
            pnglite.fill_rect(buf, W, H, x0, y0, cw - 1, ch - 1, FLOOR)
        pnglite.fill_rect(buf, W, H, x0, y0, cw - 1, 1, GRID)
        pnglite.fill_rect(buf, W, H, x0, y0, 1, ch - 1, GRID)

        sp, sw, sh = scale_up(px, w, h, scale)
        # bottom-align inside the cell: these singles are not bottom-aligned in
        # their own canvas, and bottom-aligning the *canvas* keeps the eye on a
        # common baseline while reading the sheet.
        blit(buf, W, H, sp, sw, sh, x0 + (cw - sw) // 2, y0 + 8 + (ch - 8 - sh))
        draw_text(buf, W, H, x0 + 3, y0 + 2, str(idx), 1)

    pnglite.save(out_path, W, H, buf)
    return W, H, len(imgs)


def pick_sheet(picks, out_path, scale, cols):
    """Render an explicit list of (set, index) picks large, for verification.

    The standing rule is that nothing enters the manifest until it has been
    located in the download and looked at. Reading a 96-cell contact sheet is
    how a *candidate* is found; this is how it is confirmed, at a size where a
    server rack cannot be mistaken for a bookshelf. Every prop role in
    scripts/process-assets.py was confirmed through this mode.
    """
    imgs = []
    for setno, idx in picks:
        if setno == "office":
            root, stem = OFFICE_ROOT, "Modern_Office_Singles_32x32"
        else:
            d = next(x for x in theme_dirs() if x.split("_")[0] == str(setno))
            root = os.path.join(THEME_ROOT, d)
            stem = d.replace("_Singles_Shadowless_32x32", "_Singles_Shadowless_32x32")
            stem = next(f for f in os.listdir(root)
                        if f.endswith("_%d.png" % idx))[: -len("_%d.png" % idx)]
        path = os.path.join(root, "%s_%d.png" % (stem, idx))
        w, h, px = pnglite.load(path)
        imgs.append((setno, idx, w, h, px))

    cw = max(i[2] for i in imgs) * scale + 10
    ch = max(i[3] for i in imgs) * scale + 10 + 8
    rows = (len(imgs) + cols - 1) // cols
    W, H = cols * cw, rows * ch
    buf = bytearray(bytes(BG) * (W * H))

    for n, (setno, idx, w, h, px) in enumerate(imgs):
        r, c = divmod(n, cols)
        x0, y0 = c * cw, r * ch
        pnglite.fill_rect(buf, W, H, x0, y0, cw - 1, ch - 1, FLOOR)
        sp, sw, sh = scale_up(px, w, h, scale)
        blit(buf, W, H, sp, sw, sh, x0 + (cw - sw) // 2, y0 + 8 + (ch - 8 - sh))
        label = "%s-%d" % ("0" if setno == "office" else setno, idx)
        draw_text(buf, W, H, x0 + 3, y0 + 2, label, 1)

    pnglite.save(out_path, W, H, buf)
    return W, H, len(imgs)


def grid_sheet(src, tile, r0, r1, scale, out_path):
    """Label every cell of a uniform tile sheet with its `row-col` address.

    The Room Builder sheets are plain integer grids, so unlike the singles they
    need no bounding-box work: only an address, so that a pick can be written
    down as (row, col) and re-opened by the next person.
    """
    w, h, px = pnglite.load(src)
    cols, rows = w // tile, h // tile
    r1 = min(r1, rows)
    cw = ch = tile * scale + 10
    W, H = cols * cw, (r1 - r0) * ch
    buf = bytearray(bytes(BG) * (W * H))

    for r in range(r0, r1):
        for c in range(cols):
            cell = bytearray(tile * tile * 4)
            for y in range(tile):
                sy = (r * tile + y) * w
                for x in range(tile):
                    si = (sy + c * tile + x) * 4
                    cell[(y * tile + x) * 4:(y * tile + x) * 4 + 4] = px[si:si + 4]
            x0, y0 = c * cw, (r - r0) * ch
            pnglite.fill_rect(buf, W, H, x0, y0, cw - 1, ch - 1, FLOOR)
            sp, sw, sh = scale_up(cell, tile, tile, scale)
            blit(buf, W, H, sp, sw, sh, x0 + 5, y0 + 9)
            draw_text(buf, W, H, x0 + 2, y0 + 2, "%d-%d" % (r, c), 1)

    pnglite.save(out_path, W, H, buf)
    return W, H, (r1 - r0) * cols


def theme_dirs():
    ds = [d for d in os.listdir(THEME_ROOT) if os.path.isdir(os.path.join(THEME_ROOT, d))]
    return sorted(ds, key=lambda s: int(s.split("_")[0]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--set", help="theme set number, e.g. 13")
    ap.add_argument("--office", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--page", type=int, default=None)
    ap.add_argument("--per-page", type=int, default=48)
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--out", default=os.environ.get("SHEET_OUT", "/tmp/contact"))
    ap.add_argument("--sheet", help="a uniform tile sheet to label by row-col")
    ap.add_argument("--tile", type=int, default=32)
    ap.add_argument("--rows", default="0:40", help="row range for --sheet, lo:hi")
    ap.add_argument("--pick", help="comma list of set:index, e.g. 25:23,14:164,office:34")
    a = ap.parse_args()

    if a.pick:
        picks = []
        for tok in a.pick.split(","):
            s, i = tok.split(":")
            picks.append((s if s == "office" else int(s), int(i)))
        os.makedirs(a.out, exist_ok=True)
        out = os.path.join(a.out, "picks.png")
        W, H, n = pick_sheet(picks, out, a.scale, a.cols)
        print("%s  %dx%d  %d picks" % (out, W, H, n))
        return

    if a.sheet:
        lo, hi = (int(v) for v in a.rows.split(":"))
        os.makedirs(a.out, exist_ok=True)
        stem = os.path.splitext(os.path.basename(a.sheet))[0]
        out = os.path.join(a.out, "%s_r%d-%d.png" % (stem, lo, hi))
        W, H, n = grid_sheet(a.sheet, a.tile, lo, hi, a.scale, out)
        print("%s  %dx%d  %d cells" % (out, W, H, n))
        return

    if a.list:
        for d in theme_dirs():
            n = len(listdir_sorted(os.path.join(THEME_ROOT, d)))
            print("%3s  %-56s %4d" % (d.split("_")[0], d, n))
        return

    if a.office:
        root, tag = OFFICE_ROOT, "office"
    else:
        d = next((x for x in theme_dirs() if x.split("_")[0] == a.set), None)
        if d is None:
            sys.exit("no such set: %s (try --list)" % a.set)
        root, tag = os.path.join(THEME_ROOT, d), "set%s" % a.set

    files = listdir_sorted(root)
    os.makedirs(a.out, exist_ok=True)
    pages = [files[i : i + a.per_page] for i in range(0, len(files), a.per_page)]
    for p, chunk in enumerate(pages):
        if a.page is not None and p != a.page:
            continue
        out = os.path.join(a.out, "%s_p%d.png" % (tag, p))
        W, H, n = sheet(
            chunk, root, out, a.cols, a.scale, "%s-%d" % (tag.replace("set", ""), p), 0
        )
        print("%s  %dx%d  %d sprites" % (out, W, H, n))


if __name__ == "__main__":
    main()
