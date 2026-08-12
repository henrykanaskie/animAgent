#!/usr/bin/env python3
"""Placement-band classification over the catalogued singles [M8 Phase 2a].

`assets/catalogue.json` already gives every processed single a **measured
content box** (`import-catalogue.py`) and, for 12,277 of them, a **name**
(`name-catalogue.py`, by eye). Neither says *where in a room the object goes*:
resting on a desk, standing on the floor, or hung on a wall. That is what a
scene needs and nothing in the repository computes it. This script tries to,
mechanically, and reports plainly where it cannot.

# What was tried, and what actually separates

Five candidate signals were measured against the catalogue before writing this
file (see `docs/PLACEMENT-BANDS.md` for the numbers):

  1. ink aspect ratio (content_box w/h)
  2. box fill (`coverage` scaled onto the content box instead of the canvas)
  3. bottom alignment (gap between content box and canvas bottom)
  4. **corner fill** — opacity of four 3x3 patches at the content box's own
     corners
  5. **leg ratio** — the narrowest ink row within the content box, over its
     width

(1) and (3) show no usable separation at all — every band's items span the
same range. (2) is subsumed by (4). (4) and (5) together identify a **freestanding,
non-rectangular silhouette** — legs, arms, an irregular outline — which is a
real, checkable fact about furniture that stands clear of a flat surface. nothing
in the available measurements distinguishes a wall-hung item from a desk-top
item from a *flat, boxy* piece of floor furniture (a plain cabinet or a slab
desk read exactly like a picture frame at this resolution): every one of those is
a dense rectangle with full corners. That is not a threshold that needs
tuning; it is confirmed by inspecting the actual pixels (`painting_framed`,
`desk_wood`, `keyboard` and `table_console` are all corner_fill 1.0,
leg_ratio 1.0 — geometrically the same shape).

So this script produces exactly two things with any confidence, and refuses
to guess at the third:

  - **`floor`** — freestanding furniture, high-precision, reduced recall.
  - **`fragment_excluded`** — extreme aspect ratio (>=4:1 either way):
    the modular segments and finish swatches `docs/06-SET-BUILDING.md` section
    4 warns about (`partition`'s 6x86 posts), not discrete objects at all.
  - **`band_undetermined`** — everything else: a dense, roughly rectangular
    silhouette that could be a desk-top item, a wall-hung item, or a slab of
    floor furniture, and nothing measured here says which. This is the
    overwhelming majority of the catalogue. See docs/PLACEMENT-BANDS.md for
    why, and do not fill this bucket by guessing from the `name` string — a
    name is an identity, not a placement, and turning it into one is the
    hand-typed table this script exists to avoid.

A known contamination of `floor`, found and left in rather than tuned away:
desk-standing items with a narrow foot (`monitor_lit` on a stand) measure
exactly like a chair leg (corner_fill 0.25, leg_ratio 0.27) and land in
`floor`. `floor` is therefore a *candidate* list for the one-time visual check
`docs/06-SET-BUILDING.md` section 9 already prescribes for legibility and
facing — not ground truth to build on unseen.

Scope: named, non-animated, 32x32 singles only. 48x48 is imported but unused
by the app [M8-HANDOFF.md §4] and animated spritesheets are Phase 2c's
problem, not this one's.

Python 3 stdlib only. Reads real pixels (via pnglite) for corner_fill and
leg_ratio — catalogue.json's own fields are not enough, on their own, to
answer this question.
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
CATALOGUE = os.path.join(ASSETS, "catalogue.json")
OUT = os.path.join(ASSETS, "placement-bands.json")

# Corner patch size for corner_fill, in px. 3x3 keeps the sample inside even
# the smallest content boxes seen (18px) without spilling past the edge.
CORNER_PATCH = 3

# floor: both shape signals must agree the silhouette is irregular, at a
# footprint too big to be small desk clutter caught by the same silhouette
# shape (a coffee cup is also narrow-based; it is excluded by AREA_FLOOR_MIN).
CORNER_FILL_FLOOR_MAX = 0.35
LEG_RATIO_FLOOR_MAX = 0.60
AREA_FLOOR_MIN = 600  # px^2, content_box.w * content_box.h

# fragment: long thin strips/posts/segments, not a discrete object.
ASPECT_FRAGMENT_MAX = 4.0
ASPECT_FRAGMENT_MIN = 0.25


def shape_features(path, content_box):
    """corner_fill, leg_ratio — read straight from the decoded pixels."""
    w, h, px = pnglite.load(path)
    x0, y0 = content_box["x"], content_box["y"]
    ww, hh = content_box["w"], content_box["h"]

    p = min(CORNER_PATCH, ww, hh)
    corner_fill = 0.0
    if p > 0:
        corners = [(x0, y0), (x0 + ww - p, y0),
                   (x0, y0 + hh - p), (x0 + ww - p, y0 + hh - p)]
        total = 0
        opaque = 0
        for cx, cy in corners:
            for dy in range(p):
                for dx in range(p):
                    px_x, px_y = cx + dx, cy + dy
                    if 0 <= px_x < w and 0 <= px_y < h:
                        i = (px_y * w + px_x) * 4
                        total += 1
                        if px[i + 3] > 0:
                            opaque += 1
        corner_fill = opaque / total if total else 0.0

    min_row_width = ww
    for y in range(y0, y0 + hh):
        row = y * w * 4
        count = 0
        for x in range(x0, x0 + ww):
            if px[row + x * 4 + 3] > 0:
                count += 1
        if count < min_row_width:
            min_row_width = count
    leg_ratio = (min_row_width / ww) if ww else 0.0

    return round(corner_fill, 3), round(leg_ratio, 3)


def classify(content_box, corner_fill, leg_ratio):
    w, h = content_box["w"], content_box["h"]
    area = w * h
    aspect = (w / h) if h else 0.0

    if aspect >= ASPECT_FRAGMENT_MAX or aspect <= ASPECT_FRAGMENT_MIN:
        return "fragment_excluded"
    if (corner_fill <= CORNER_FILL_FLOOR_MAX
            and leg_ratio <= LEG_RATIO_FLOOR_MAX
            and area >= AREA_FLOOR_MIN):
        return "floor"
    return "band_undetermined"


def main():
    if not os.path.exists(CATALOGUE):
        print("no assets/catalogue.json — run scripts/import-catalogue.py "
              "and scripts/name-catalogue.py first", file=sys.stderr)
        return 1

    catalogue = json.load(open(CATALOGUE))
    candidates = [e for e in catalogue["entries"]
                  if e.get("size_set") == "32x32"
                  and e.get("name")
                  and "frames" not in e]

    started = time.time()
    out_entries = []
    bands = {"floor": 0, "fragment_excluded": 0, "band_undetermined": 0}
    unreadable = []

    for e in candidates:
        path = os.path.join(ASSETS, e["file"])
        try:
            corner_fill, leg_ratio = shape_features(path, e["content_box"])
        except Exception as exc:  # a file the earlier pass could read but this can't is data
            unreadable.append("%s (%s)" % (e["file"], exc))
            continue
        band = classify(e["content_box"], corner_fill, leg_ratio)
        bands[band] += 1
        out_entries.append({
            "file": e["file"],
            "name": e["name"],
            "group": e["group"],
            "content_box": e["content_box"],
            "corner_fill": corner_fill,
            "leg_ratio": leg_ratio,
            "band": band,
        })

    index = {
        "generated_by": "scripts/catalogue-placement-bands.py",
        "note": ("Placement-band candidates over the 32x32 named singles. "
                 "'floor' is a high-precision, reduced-recall candidate list "
                 "for freestanding furniture, not ground truth — see the "
                 "module docstring and docs/PLACEMENT-BANDS.md before using "
                 "it unseen. 'wall' and 'desk-top' are not split out: no "
                 "measured signal in this catalogue separates them from each "
                 "other or from flat/boxy floor furniture, and this script "
                 "says so rather than guessing from the name string."),
        "thresholds": {
            "corner_fill_floor_max": CORNER_FILL_FLOOR_MAX,
            "leg_ratio_floor_max": LEG_RATIO_FLOOR_MAX,
            "area_floor_min": AREA_FLOOR_MIN,
            "aspect_fragment_max": ASPECT_FRAGMENT_MAX,
            "aspect_fragment_min": ASPECT_FRAGMENT_MIN,
        },
        "count": len(out_entries),
        "bands": bands,
        "entries": out_entries,
    }
    with open(OUT, "w") as fh:
        json.dump(index, fh, indent=1, sort_keys=False)

    print("placement-bands: %d/%d candidate singles classified in %.1fs"
          % (len(out_entries), len(candidates), time.time() - started))
    for band, count in sorted(bands.items(), key=lambda kv: -kv[1]):
        print("  %-20s %5d" % (band, count))
    print("output: %s (%.1f MB)"
          % (os.path.relpath(OUT, REPO), os.path.getsize(OUT) / 1e6))
    if unreadable:
        print("  (%d unreadable, skipped)" % len(unreadable))
        for bad in unreadable[:10]:
            print("  UNREADABLE %s" % bad)
    return 0


if __name__ == "__main__":
    sys.exit(main())
