#!/usr/bin/env python3
"""Render a themed room at 1x, at the real panel size, with characters in it.

Why this exists
---------------
A theme that cannot be looked at cannot be chosen. The scene is SpriteKit and
needs a window server, so it cannot produce a picture in a headless review, and
"trust me, the bookcases read at 1x" is exactly the kind of claim that
docs/04-ART-DIRECTION.md refuses to accept about art. This composes the same
room the scene composes, from the *same manifest the scene loads*, and writes a
PNG.

That second point is the useful one beyond the pictures: everything here — tile
paths, prop paths, per-role content_box, the prop canvas, character frames — is
read out of assets/manifest.json. Nothing is hard-coded but the geometry, which
is transcribed from Sources/SpriteRoomScene/RoomLayout.swift and RoomScene.swift
and named after it. So if this renders a theme correctly, the manifest carries
enough for the scene to render it too, which is the claim the themed-room work
has to make. It is a *review tool*, not part of the build: it writes only where
it is told to and never touches assets/.

The geometry is a transcription, and transcriptions drift. It is deliberately
narrow — floor, wall, the four prop slots, seated bodies — and it does not draw
nameplates or badges, which live in an overlay band this is not trying to model.
Treat it as a picture of the room, not as a second implementation of the scene.

Usage
-----
    preview-theme.py --out DIR                 # every theme in the manifest
    preview-theme.py --out DIR --theme library
    preview-theme.py --out DIR --population 3

Python 3 stdlib only.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pnglite

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(REPO, "assets", "manifest.json")

# The real panel. docs/04-ART-DIRECTION.md and the notch geometry: the drop-down
# is 720x400, and 1x is the only scale a normal room uses now that the camera
# draws the room wide at every population (commit 004b587).
PANEL_W, PANEL_H = 720, 400
SCALE = 1

# Transcribed from RoomLayout.swift. Names match the Swift so a drift is
# findable by grep rather than by memory.
TILE = 32
SEAT_CAPACITY = 7
SEAT_SPACING_TILES = 3
COLUMNS = SEAT_CAPACITY * SEAT_SPACING_TILES + 4      # 25
ROWS = 6
WALL_ROWS = 2
FLOOR_ROWS = ROWS - WALL_ROWS                          # 4
WIDTH = COLUMNS * TILE                                 # 800
HEIGHT = ROWS * TILE                                   # 192
BASELINE_Y = TILE * 2                                  # 64
AISLE_Y = BASELINE_Y - TILE                            # 32
WALL_BASE_Y = FLOOR_ROWS * TILE                        # 128
DRAWN_ROWS = range(-6, ROWS + 9)
DRAWN_COLUMNS = range(-8, COLUMNS + 9)

# RoomScene.swift: the back row sits one tile behind the seat line, and the
# foreground row sits below the content band. The band needs badge and plate
# metrics the scene measures from the manifest; this only needs the bottom, and
# uses the same expression with the nameplate drop the font produces.
BACK_ROW_Y = BASELINE_Y + TILE                         # 96
PLATE_DROP_BELOW_FEET = 20
CONTENT_BAND_BOTTOM = AISLE_Y - PLATE_DROP_BELOW_FEET  # 12

VOID = (18, 18, 22, 255)


def load(path):
    return pnglite.load(os.path.join(REPO, path))


def blit(dst, dw, dh, src, sw, sh, x0, y0):
    """Alpha-over, clipped to the destination."""
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
                dst[di:di + 4] = src[si:si + 4]
            else:
                for c in range(3):
                    dst[di + c] = (src[si + c] * a + dst[di + c] * (255 - a)) // 255
                dst[di + 3] = 255


def seat_column(index):
    wrapped = index % SEAT_CAPACITY
    step = (wrapped + 1) // 2
    sign = -1 if wrapped % 2 == 0 else 1
    return COLUMNS // 2 + sign * step * SEAT_SPACING_TILES


def seat_x(index):
    return seat_column(index) * TILE + TILE // 2


def pick_tiles(theme):
    """(floor, wall) paths for a theme.

    Prefers the tiles the theme *declares*. Falls back to the heuristic the
    scene uses today — scan for fully-opaque single-colour tiles, darkest is the
    floor and lightest the wall — so a theme with no declaration still draws,
    and so this shows what the scene would actually do with it.
    """
    b = theme.get("builder", {})
    if b.get("floor") and b.get("wall"):
        return b["floor"], b["wall"], "declared"
    flats = []
    for p in b.get("tiles", []):
        w, h, px = load(p)
        colours, opaque, total_v = set(), 0, 0.0
        for i in range(0, len(px), 4):
            if px[i + 3] <= 200:
                continue
            opaque += 1
            colours.add((px[i], px[i + 1], px[i + 2]))
            total_v += max(px[i], px[i + 1], px[i + 2]) / 255.0
        if opaque == w * h and len(colours) == 1:
            flats.append((total_v / opaque, p))
    if not flats:
        first = b.get("tiles", [None])[0]
        return first, first, "fallback"
    flats.sort()
    return flats[0][1], flats[-1][1], "heuristic"


def prop_origin(role, canvas, x, y):
    """Top-left pixel for a prop whose content box's bottom-centre is (x, y).

    The whole reason content_box is in the manifest: the singles are not
    bottom-aligned in their canvas, so the canvas cannot place them.
    """
    box = role["content_box"]
    left = x - (box["x"] + box["w"] / 2.0)
    bottom_row = box["y"] + box["h"] - 1
    top = y + (canvas["h"] - 1 - bottom_row)
    return left, top


def render(theme, name, population, out_path, characters, seed_variants):
    floor_p, wall_p, how = pick_tiles(theme)
    _fw, _fh, floor_px = load(floor_p)
    _ww, _wh, wall_px = load(wall_p)

    buf = bytearray(bytes(VOID) * (PANEL_W * PANEL_H))

    # Camera: 1x, centred on the room. The room is 800 px wide and the panel is
    # 720, so a full-width room is cropped a tile and a bit each side — which is
    # what the shipped panel does at 1x.
    cam_x, cam_y = WIDTH / 2.0, HEIGHT / 2.0

    def to_screen(sx, sy):
        """Scene (y-up) -> panel pixel (y-down)."""
        return (int(round(PANEL_W / 2.0 + (sx - cam_x) * SCALE)),
                int(round(PANEL_H / 2.0 - (sy - cam_y) * SCALE)))

    # Floor and wall, over the drawn range so no zoom shows the void.
    for r in DRAWN_ROWS:
        y0 = r * TILE
        src = wall_px if y0 >= WALL_BASE_Y else floor_px
        for c in DRAWN_COLUMNS:
            sx, sy = to_screen(c * TILE, y0 + TILE)
            blit(buf, PANEL_W, PANEL_H, src, TILE, TILE, sx, sy)

    canvas = theme["props"]["canvas"]
    roles = theme["props"]["roles"]
    drawn = []   # (depth, kind, payload) — painter's order, matching zPosition

    def add_prop(role_name, x, y, bias=0.0):
        role = roles.get(role_name)
        if role is None:
            return
        left, top = prop_origin(role, canvas, x, y)
        drawn.append((y + bias, "prop", (role["file"], left, top)))

    # Back row: board and plant alternating, one tile behind the seat line.
    for seat in range(SEAT_CAPACITY):
        x = seat_column(seat) * TILE + TILE // 2 + TILE * 1.5
        if x >= WIDTH:
            continue
        add_prop("board" if seat % 2 == 0 else "plant", x, BACK_ROW_Y)

    # Foreground row, strictly below the content band.
    plant = roles.get("plant")
    if plant is not None:
        y = CONTENT_BAND_BOTTOM - plant["content_box"]["h"] - 4
        for seat in range(SEAT_CAPACITY):
            x = seat_x(seat) + TILE * 1.5
            if x >= WIDTH:
                continue
            add_prop("plant", x, y)

    # Chair and desk at every seat; a body at the occupied ones. The desk takes
    # the row depth plus a half so it occludes the seated body — at 32 px that
    # overlap is the only cue the character is sitting *at* the desk.
    for seat in range(SEAT_CAPACITY):
        add_prop("chair", seat_x(seat), BASELINE_Y, bias=-0.25)
    for seat in range(population):
        variant = seed_variants[seat % len(seed_variants)]
        frame = characters[variant]
        drawn.append((BASELINE_Y, "char", (frame, seat_x(seat))))
    for seat in range(SEAT_CAPACITY):
        add_prop("desk", seat_x(seat) + TILE * 0.875, BASELINE_Y, bias=0.5)

    # Higher y is further away, so it paints first.
    for _depth, kind, payload in sorted(drawn, key=lambda d: -d[0]):
        if kind == "prop":
            path, left, top = payload
            w, h, px = load(path)
            sx, sy = to_screen(left, top)
            blit(buf, PANEL_W, PANEL_H, px, w, h, sx, sy)
        else:
            path, x = payload
            w, h, px = load(path)
            sx, sy = to_screen(x - w / 2.0, BASELINE_Y + h)
            blit(buf, PANEL_W, PANEL_H, px, w, h, sx, sy)

    pnglite.save(out_path, PANEL_W, PANEL_H, buf)
    return how


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--theme", action="append", help="repeatable; default is all")
    ap.add_argument("--population", type=int, default=4)
    ap.add_argument("--manifest", default=MANIFEST)
    args = ap.parse_args(argv)

    with open(args.manifest) as f:
        m = json.load(f)

    sets = m.get("themes", {}).get("sets")
    if not sets:
        print("error: manifest declares no themes; run scripts/build-manifest.py.",
              file=sys.stderr)
        return 2

    variants = sorted(m["characters"]["variants"])
    seated = {}
    for v in variants:
        frames = m["characters"]["variants"][v]["states"]["working"]["frames"]["right"]
        seated[v] = frames[0]

    os.makedirs(args.out, exist_ok=True)
    names = args.theme or sorted(sets)
    for name in names:
        if name not in sets:
            print("error: no theme %r (have: %s)" % (name, ", ".join(sorted(sets))),
                  file=sys.stderr)
            return 2
        out = os.path.join(args.out, "%s.png" % name)
        how = render(sets[name], name, args.population, out, seated, variants)
        print("%-16s %-9s %s" % (name, how, os.path.relpath(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
