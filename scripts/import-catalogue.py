#!/usr/bin/env python3
"""Catalogue import pass. Brings the WHOLE of the purchased packs within reach.

`process-assets.py` imports the narrow slice the scene draws today: the Office
singles, the Room Builder, six premade characters and the badge sheet — 2,246
files out of 53,933 on disk, or 4.2% of what was bought. This script imports the
rest, so that choosing a prop is a lookup rather than a shopping trip back into
the raw packs.

# What "all files" means, and why it is not 53,933

Every themed prop ships **nine times**: three lighting treatments (with shadow,
black shadow, shadowless) at three sizes (16x16, 32x32, 48x48). Importing all
nine would be importing the same picture nine times. This takes:

  - **one lighting treatment** — the default, with the pack's own baked shadow,
    because `process-assets.py` already has `strip_shadow` for the room pass and
    a shadow can be removed but not invented;
  - **two sizes** — 32x32, which the app is built on, and 48x48, which
    `docs/ASSET-INVENTORY.md` argues is the single largest legibility lever
    available. 16x16 is skipped: nothing renders at it and it is a downscale of
    art we already have.

# Faithful, not treated

Files are **copied byte for byte**, not re-encoded and not recoloured. Two
reasons:

  - **Import must not destroy information.** The room pass desaturates and
    value-compresses under I7's ceiling. That is right for a prop standing in a
    room behind a character, and wrong as a one-way door applied to 11,000 props
    before anyone has decided what any of them is for. Measure now, treat at
    placement.
  - **A byte copy is trivially idempotent.** No encoder, no rounding, no
    parameter key. Re-running cannot change output.

Each entry is *measured* on the way through — content box, alpha coverage, peak
saturation and value — so the placement pass can filter on I7 compliance without
reopening a single PNG.

Python 3 stdlib only, like every other script here. No pip, no Pillow.
"""

import json
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
INTERIORS = os.path.join(ASSETS, "moderninteriors-win")
OFFICE = os.path.join(ASSETS, "Modern_Office_Revamped_v1.2")
USERINTERFACE = os.path.join(ASSETS, "modernuserinterface-win")
OUT = os.path.join(ASSETS, "processed", "catalogue")
INDEX = os.path.join(ASSETS, "catalogue.json")

SIZES = ("32x32", "48x48")


def measure(path):
    """Content box, coverage and the two I7 numbers, in one decode."""
    w, h, px = pnglite.load(path)
    x0, y0, x1, y1 = w, h, -1, -1
    inked = 0
    peak_sat = 0.0
    peak_val = 0.0
    min_val = 1.0
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            i = row + x * 4
            if px[i + 3] == 0:
                continue
            inked += 1
            if x < x0:
                x0 = x
            if x > x1:
                x1 = x
            if y < y0:
                y0 = y
            if y > y1:
                y1 = y
            r, g, b = px[i], px[i + 1], px[i + 2]
            high = max(r, g, b)
            low = min(r, g, b)
            val = high / 255.0
            sat = 0.0 if high == 0 else (high - low) / high
            if val > peak_val:
                peak_val = val
            if val < min_val:
                min_val = val
            if sat > peak_sat:
                peak_sat = sat
    if x1 < 0:
        return None  # fully transparent
    return {
        "canvas": {"w": w, "h": h},
        "content_box": {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1},
        "coverage": round(inked / float(w * h), 4),
        "peak_saturation": round(peak_sat, 3),
        "peak_value": round(peak_val, 3),
        "min_value": round(min_val, 3),
    }


def take(src, rel, group, size, entries, stats, extra=None):
    """Copy one source file into the catalogue and index it."""
    dst = os.path.join(OUT, size, group, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    try:
        info = measure(src)
    except Exception as exc:  # a pack file we cannot decode is data, not a crash
        stats["unreadable"].append("%s (%s)" % (src, exc))
        return
    if info is None:
        stats["empty"] += 1
        return
    if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src):
        shutil.copyfile(src, dst)
    entry = {
        "file": os.path.relpath(dst, ASSETS),
        "source": os.path.relpath(src, ASSETS),
        "group": group,
        "size_set": size,
    }
    entry.update(info)
    if extra:
        entry.update(extra)
    entries.append(entry)
    stats["imported"] += 1


def theme_singles(size, entries, stats):
    """The 24 themed interiors, exploded into individual props."""
    root = os.path.join(INTERIORS, "1_Interiors", size, "Theme_Sorter_Singles_" + size)
    if not os.path.isdir(root):
        return
    for theme in sorted(os.listdir(root)):
        tdir = os.path.join(root, theme)
        if not os.path.isdir(tdir):
            continue
        # "22_Museum_Singles_32x32" -> "museum"
        name = theme.split("_", 1)[1] if "_" in theme else theme
        for suffix in ("_Singles_" + size, "_SIngles_" + size, "_" + size):
            if name.endswith(suffix):
                name = name[: -len(suffix)]
                break
        name = name.lower()
        for f in sorted(os.listdir(tdir)):
            if f.lower().endswith(".png"):
                take(os.path.join(tdir, f), f, "interiors/" + name, size, entries, stats)


def office_singles(size, entries, stats):
    root = os.path.join(OFFICE, "4_Modern_Office_singles", size)
    if not os.path.isdir(root):
        return
    for f in sorted(os.listdir(root)):
        if f.lower().endswith(".png"):
            take(os.path.join(root, f), f, "office", size, entries, stats)


def animated_objects(size, entries, stats):
    """310 animated props. Frame count inferred from the strip's aspect."""
    root = os.path.join(INTERIORS, "3_Animated_objects", size, "spritesheets")
    if not os.path.isdir(root):
        return
    for f in sorted(os.listdir(root)):
        if not f.lower().endswith(".png"):
            continue
        src = os.path.join(root, f)
        extra = {}
        try:
            # 33 bytes, not a full decode — the strip's aspect is all we need
            # and `measure` is about to decode it properly anyway.
            w, h = pnglite.read_header(src)[:2]
            if h and w % h == 0:
                extra["frames"] = w // h
                extra["frame_size"] = {"w": h, "h": h}
        except Exception:
            pass
        take(src, f, "animated", size, entries, stats, extra)


def ui_emotes(entries, stats):
    """Emotes, UI sheets and the portrait generator.

    **`Animated_Spritesheets/` is 24 GIFs and no PNGs** — checked, not assumed.
    The emote *pixels* live in `UI_thinking_emotes_animation_32x32.png`, a
    320x320 sheet (a 10x10 grid of 32 px cells: ten emotes, ten frames each),
    which is taken below. The GIFs stay where they are and remain what
    `process-assets.py:gif_timing` reads frame rates out of — the one place in
    any of these packs that states how fast a thing is meant to move.
    """
    base = os.path.join(INTERIORS, "4_User_Interface_Elements")
    for f in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        if f.lower().endswith(".png") and ("32x32" in f or "48x48" in f):
            size = "48x48" if "48x48" in f else "32x32"
            take(os.path.join(base, f), f, "ui/sheets", size, entries, stats)

    # The Modern UI pack nests four deep: Animated/, and Portrait_Generator/
    # with Accessories, Hairstyles, Skins and Eyes under it. A flat listdir
    # found three files out of 304.
    uroot = os.path.join(USERINTERFACE, "32x32")
    if os.path.isdir(uroot):
        for dirpath, _dirs, files in os.walk(uroot):
            for f in sorted(files):
                if not f.lower().endswith(".png"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, f), uroot)
                take(os.path.join(dirpath, f), rel, "ui/modern", "32x32", entries, stats)


def room_builder(size, entries, stats):
    """Walls, floors, borders, entryways — the room construction kit."""
    for pack, sub in ((INTERIORS, os.path.join("1_Interiors", size, "Room_Bulder_subfiles_" + size)),
                      (INTERIORS, os.path.join("1_Interiors", size, "Room_Builder_subfiles_" + size))):
        root = os.path.join(pack, sub)
        if not os.path.isdir(root):
            continue
        for f in sorted(os.listdir(root)):
            if f.lower().endswith(".png"):
                take(os.path.join(root, f), f, "roombuilder", size, entries, stats)


def main():
    started = time.time()
    entries = []
    stats = {"imported": 0, "empty": 0, "unreadable": []}

    for size in SIZES:
        theme_singles(size, entries, stats)
        office_singles(size, entries, stats)
        animated_objects(size, entries, stats)
        room_builder(size, entries, stats)
    ui_emotes(entries, stats)

    groups = {}
    for e in entries:
        groups[e["group"]] = groups.get(e["group"], 0) + 1

    index = {
        "generated_by": "scripts/import-catalogue.py",
        "note": ("Faithful byte copies of the purchased packs, measured but not "
                 "recoloured. See the module docstring for why one lighting "
                 "treatment and two sizes rather than all nine variants."),
        "sizes": list(SIZES),
        "count": len(entries),
        "groups": dict(sorted(groups.items())),
        "entries": entries,
    }
    with open(INDEX, "w") as fh:
        json.dump(index, fh, indent=1, sort_keys=False)

    print("catalogue: %d props imported in %.1fs" % (stats["imported"], time.time() - started))
    print("index: %s (%.1f MB)" % (os.path.relpath(INDEX, REPO),
                                   os.path.getsize(INDEX) / 1e6))
    for g, n in sorted(groups.items(), key=lambda kv: -kv[1]):
        print("  %-34s %5d" % (g, n))
    if stats["empty"]:
        print("  (%d fully transparent files skipped)" % stats["empty"])
    for bad in stats["unreadable"][:10]:
        print("  UNREADABLE %s" % bad)
    return 0


if __name__ == "__main__":
    sys.exit(main())
