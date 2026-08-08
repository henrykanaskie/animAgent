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
    preview-theme.py --out DIR --state working --badge sleep
    preview-theme.py --out DIR --theme library --frames        # every frame
    preview-theme.py --out DIR --animated old_tv --frames      # a candidate

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

# The back row draws `board` at every even seat, so consecutive copies are
# SEAT_SPACING_TILES apart. A board whose content is wider than that overlaps
# its own neighbours and clips them, which is not a thing you can see in a
# manifest — it is only visible once four copies are on screen. M6c hit it with
# a 120px monitor wall. Every shipping board is 30-64 px.
BACK_ROW_PITCH = SEAT_SPACING_TILES * TILE                 # 96

# RoomScene.swift: the back row sits one tile behind the seat line, and the
# foreground row sits below the content band. The band needs badge and plate
# metrics the scene measures from the manifest; this only needs the bottom, and
# uses the same expression with the nameplate drop the font produces.
BACK_ROW_Y = BASELINE_Y + TILE                         # 96
PLATE_DROP_BELOW_FEET = 20
CONTENT_BAND_BOTTOM = AISLE_Y - PLATE_DROP_BELOW_FEET  # 12

CHAR_H = 64
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


def role_placements():
    """How many times the room draws each prop role on one panel. One panel, not
    one theme: this is a fact about the *layout*, and it is the same for every
    theme because every theme fills the same four slots.

    It exists because `scripts/lint-palette.py`'s motion budget is a budget on
    what reaches the screen, and a prop placed four times costs four times as
    much as one placed once — a quantity the manifest cannot see, because the
    manifest describes art and this is geometry. Rather than transcribe the seat
    arithmetic a third time (RoomLayout.swift, `render()` below, and then the
    lint), the lint imports this, and `render()` counts what it actually drew and
    fails if the two disagree. Two copies of a number that can drift apart is how
    the 10.4%-vs-27.9% error happened; this is the same number computed once.

    The counts on the shipped 25-column layout are `board` 4, `plant` 10,
    `chair` 7, `desk` 7 — and that asymmetry is exactly the reason ADR-002 §14b
    says an animated prop may only occupy `board`. `plant` would cost two and a
    half times as much and seven of its ten copies sit in the permanently-visible
    foreground row.
    """
    counts = {"board": 0, "plant": 0, "chair": 0, "desk": 0}
    for seat in range(SEAT_CAPACITY):
        x = seat_column(seat) * TILE + TILE // 2 + TILE * 1.5
        if x >= WIDTH:
            continue
        counts["board" if seat % 2 == 0 else "plant"] += 1
    for seat in range(SEAT_CAPACITY):
        x = seat_x(seat) + TILE * 1.5
        if x >= WIDTH:
            continue
        counts["plant"] += 1
    for _seat in range(SEAT_CAPACITY):
        counts["chair"] += 1
        counts["desk"] += 1
    return counts


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
    """Scene-space top-left of a prop whose content box's bottom-centre is (x, y).

    The whole reason content_box is in the manifest: the singles are not
    bottom-aligned in their canvas, so the canvas cannot place them.

    **Corrected at M6b — this was mirrored, and it silently misplaced every prop
    in every theme.** The old expression was `y + (canvas.h - 1 - bottom_row)`,
    which is the y-*up* offset from the canvas's bottom edge to the content
    bottom — the right quantity for SpriteKit's anchorPoint, and it is what
    Manifest.swift's `anchor(inCanvas:)` correctly computes. But this function
    does not return an anchor: it returns the scene y of the image's TOP row,
    which `to_screen` then converts and `blit` fills downwards from. Those two
    offsets are measured from opposite ends of the canvas, so they agree only
    for a prop whose content bottom sits exactly halfway down it (row 47.5 of
    96) and disagree by twice the difference otherwise.

    The error was up to ~80 px at 1x — the chairs and desks in every theme
    preview were drawn most of a tile-and-a-half below the character sitting on
    them, and the room read as furniture floating in the foreground. It was
    invisible as a bug because every prop was wrong *in proportion to how low
    its art sits in its own canvas*, so the picture stayed internally plausible.
    The scene was never affected. Derivation, so the next person does not have
    to redo it: image row `r` lands at panel row `(296 - top) + r`; we want row
    `bottom_row` at panel row `296 - y`; therefore `top = y + bottom_row`.
    """
    box = role["content_box"]
    left = x - (box["x"] + box["w"] / 2.0)
    bottom_row = box["y"] + box["h"] - 1
    top = y + bottom_row
    return left, top


# Animated props are in the manifest as of M6c: a role may carry an `animation`
# object beside `file`, and `file` is frame 0. So the normal path here reads
# them out of assets/manifest.json like everything else, and `--frame`/`--frames`
# only choose which frame of the loop to draw.
#
# `--animated <id>` remains, and it is the review path for an object that has
# NOT been adopted. It stands any directory under assets/processed/animated/ in
# the `board` slot of whatever theme is being drawn, measuring its content box
# here the same way scripts/build-manifest.py measures an adopted one. That is
# how a candidate gets looked at in the room before it is written down, which is
# the rule this whole tool exists to serve.
ANIMATED_ROOT = os.path.join(REPO, "assets", "processed", "animated", "32x32")


def union_content_box(paths):
    """Tight box of the opaque pixels over every frame. Same measure as the
    manifest's, so a candidate and an adopted prop are judged identically."""
    x0, y0, x1, y1 = None, None, -1, -1
    for p in paths:
        w, h, px = load(p)
        for y in range(h):
            for x in range(w):
                if px[(y * w + x) * 4 + 3] <= 127:
                    continue
                x0 = x if x0 is None else min(x0, x)
                y0 = y if y0 is None else min(y0, y)
                x1, y1 = max(x1, x), max(y1, y)
    if x0 is None:
        return None
    return {"x": x0, "y": y0, "w": x1 - x0 + 1, "h": y1 - y0 + 1}


def animated_override(name):
    """A role-shaped dict for an animated object the manifest has not adopted."""
    d = os.path.join(ANIMATED_ROOT, name)
    if not os.path.isdir(d):
        return None
    paths = [os.path.join("assets", "processed", "animated", "32x32", name, f)
             for f in sorted(os.listdir(d)) if f.endswith(".png")]
    if not paths:
        return None
    box = union_content_box(paths)
    if box is None:
        return None
    return {"file": paths[0], "content_box": box,
            "animation": {"frames": paths, "fps": 0, "loop": True}}


def role_frames(role):
    """Every frame a role draws — one for a still prop, N for an animated one.

    `file` first and always correct is the whole point of the `animation` key's
    shape, so this reads `file` and treats `animation.frames` as an override
    rather than the other way round.
    """
    if not role:
        return []
    frames = (role.get("animation") or {}).get("frames")
    return list(frames) if frames else [role["file"]]


def render(theme, name, population, out_path, characters, seed_variants,
           badge=None, animated=None, frame=0):
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
    roles = dict(theme["props"]["roles"])
    # A candidate that is not in the manifest stands in the `board` slot — the
    # standing object against the back wall, and the only one of the four whose
    # art does not also appear in the foreground row or under a character.
    if animated:
        override = animated_override(animated)
        if override is not None:
            roles["board"] = override
    board = roles.get("board")
    if board is not None and board["content_box"]["w"] > BACK_ROW_PITCH:
        print("  warning: %s board content is %d px wide against a %d px back-row "
              "pitch — its four copies overlap and clip each other"
              % (name, board["content_box"]["w"], BACK_ROW_PITCH), file=sys.stderr)

    drawn = []   # (depth, kind, payload) — painter's order, matching zPosition
    census = {}  # role -> how many copies this render actually placed

    def add_prop(role_name, x, y, bias=0.0):
        role = roles.get(role_name)
        if role is None:
            return
        frames = role_frames(role)
        left, top = prop_origin(role, canvas, x, y)
        census[role_name] = census.get(role_name, 0) + 1
        drawn.append((y + bias, "prop", (frames[frame % len(frames)], left, top)))

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
        drawn.append((BASELINE_Y, "char", (characters[variant], seat_x(seat))))
    for seat in range(SEAT_CAPACITY):
        add_prop("desk", seat_x(seat) + TILE * 0.875, BASELINE_Y, bias=0.5)

    # What was placed must match what `role_placements()` says is placed, because
    # the lint's motion budget multiplies a prop's own motion by that count and
    # never renders anything. A silent disagreement here would make the budget
    # wrong by a factor, which is the exact class of defect the budget exists to
    # catch. Only roles this theme actually declares are compared — a theme
    # missing a role draws none of it, which is not a drift.
    expected = role_placements()
    for role_name, n in sorted(census.items()):
        if expected.get(role_name) != n:
            raise SystemExit(
                "internal: %s drew %d copies of `%s` but role_placements() says %s. "
                "These are the same arithmetic and scripts/lint-palette.py trusts "
                "the second one." % (name, n, role_name, expected.get(role_name)))

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

    # Badges last, and above everything, which is where the scene puts them.
    # This tool does not model the overlay band; it draws one badge over every
    # occupied seat so a new badge can be looked at in the room it will appear
    # in. The anchor is the manifest's own: bubble bottom-centre on the point
    # `head_top_px` above the character's feet.
    if badge is not None:
        bw, bh, bpx = load(badge["file"])
        for seat in range(population):
            head_top = BASELINE_Y + CHAR_H - badge["head_top_px"]
            sx, sy = to_screen(seat_x(seat) - bw / 2.0, head_top + bh)
            blit(buf, PANEL_W, PANEL_H, bpx, bw, bh, sx, sy)

    pnglite.save(out_path, PANEL_W, PANEL_H, buf)
    return how


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True)
    ap.add_argument("--theme", action="append", help="repeatable; default is all")
    ap.add_argument("--population", type=int, default=4)
    ap.add_argument("--state", default="working",
                    help="body state to seat the cast in (default: working)")
    ap.add_argument("--badge", help="draw this badges.states entry over every "
                                    "occupied seat, e.g. sleep")
    ap.add_argument("--animated", help="review path: an assets/processed/animated/ "
                                       "object id that the manifest has NOT adopted, "
                                       "stood in the back row's board slot")
    ap.add_argument("--frames", action="store_true",
                    help="write one PNG per animation frame of whatever the theme's "
                         "animated prop is (or of --animated)")
    ap.add_argument("--frame", type=int, default=0,
                    help="draw this frame of the loop (default 0, which is `file`)")
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
        states = m["characters"]["variants"][v]["states"]
        if args.state not in states:
            print("error: no state %r (have: %s)"
                  % (args.state, ", ".join(sorted(states))), file=sys.stderr)
            return 2
        frames = states[args.state]["frames"]["right"]
        seated[v] = frames[0]

    badge = None
    if args.badge:
        entry = m.get("badges", {}).get("states", {}).get(args.badge)
        if entry is None:
            print("error: no badges.states %r (have: %s)"
                  % (args.badge,
                     ", ".join(sorted(m.get("badges", {}).get("states", {})))),
                  file=sys.stderr)
            return 2
        badge = {"file": entry["file"],
                 "head_top_px": m["characters"]["variants"][variants[0]]["head_top_px"]}

    if args.animated and animated_override(args.animated) is None:
        print("error: no frames under assets/processed/animated/32x32/%s — "
              "run scripts/process-assets.py" % args.animated, file=sys.stderr)
        return 2

    os.makedirs(args.out, exist_ok=True)
    names = args.theme or sorted(sets)
    for name in names:
        if name not in sets:
            print("error: no theme %r (have: %s)" % (name, ", ".join(sorted(sets))),
                  file=sys.stderr)
            return 2
        # How many frames this theme actually has. A theme with no animated prop
        # has one, whatever --frames says, rather than silently writing six
        # copies of the same picture.
        if args.animated:
            loop = len(animated_override(args.animated)["animation"]["frames"])
        else:
            loop = max([len(role_frames(r))
                        for r in sets[name]["props"]["roles"].values()] or [1])
        n_frames = loop if args.frames else 1
        for f in range(n_frames):
            suffix = "_f%02d" % f if (args.frames and loop > 1) else ""
            out = os.path.join(args.out, "%s%s.png" % (name, suffix))
            how = render(sets[name], name, args.population, out, seated, variants,
                         badge=badge, animated=args.animated,
                         frame=f if args.frames else args.frame)
            print("%-16s %-9s %s" % (name, how, os.path.relpath(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
