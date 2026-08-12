#!/usr/bin/env python3
"""Composes static multi-room floor plans from named catalogue props, as PNGs.

# Why this is a script and not a feature

The maintainer's question was "how can I trust the scenes will be any good",
and the honest answer is that a catalogue proves *availability*, not taste.
Nothing about naming 12,279 props demonstrates that a room built from them is
worth looking at. So this renders candidate rooms **before** any of it reaches
the app: no Swift, no layout refactor, no risk. If they look flat, an hour is
lost instead of a week, and the judgement is made from a picture rather than
from my description of one.

It deliberately does not import from the app or write anything the app reads.
Its only inputs are `assets/catalogue.json` and the processed art; its only
output is PNGs in a scratch directory.

# The bar, and what it taught

`assets/Modern_Office_Revamped_v1.2/6_Office_Designs/Office_Design_2.gif` and
`assets/moderninteriors-win/6_Home_Designs/Museum_Designs/32x32/` are rooms
composed by the packs' own artists from these same props. Measuring them, not
guessing, is what this file is built on:

  * A room is not "a wall band across the top". It is a **rect with four
    edges**, and the artist draws all four. Interior partitions are what make
    a picture read as a building rather than a stage set.

  * The north wall is exactly **two tiles tall** and is a single self-contained
    pair of Room Builder tiles: the *cap* tile carries a 12 px white floor-plan
    line in its top 12 rows and 20 px of wall face below it; the *body* tile
    carries 30 px more face and a 2 px dark baseboard in its bottom 2 rows.
    Measured in Office_Design_2 at x=200: line y=320..331, face y=332..381,
    baseboard y=380..383, floor from y=384. That is 12 + 52 = 64 px, on the
    tile grid, every time.

  * The other three edges are **line only** — 12 px for horizontal, 14 px for
    vertical, always 2 px dark / white / 2 px dark. You only see the *face* of
    a wall you are looking at head-on, so only the north wall gets one.

  * Doorways are not doors. They are **gaps cut clean through** the line and
    the face, with the neighbouring floor showing through.

  * Density is the whole game. Office_Design_2 packs eight desks, eight
    chairs, a monitor and scattered paper on every desk, a printer, plants in
    three corners and a wall unit into 16x17 tiles. Nothing is centred and
    nothing is alone: props come in rows, pairs and clusters, and the gaps
    between clusters are filled with small litter.

# Findings the app should take

**A catalogue name is a family, not an object.** `desk_corner_l` has 49
entries and they are five finishes of the same ten pieces, only two of which
are furniture; the other eight are modular segments. Asking for variant 0
draws a fragment. The first render of this file put six bare 6x86 partition
posts where six desks were meant to be, and it took a labelled contact sheet
to see why. `prop`'s `ink` argument selects the piece; see its docstring.

**All four seated directions are already available.** The character pack ships
`sit` in left and right only, and that has been treated as a hard limit on how
the room can be arranged. It is not. A seat is a pose *plus an occlusion*: a
standing `idle_down` planted inside the desk's footprint and depth-sorted
above it comes out as a head and shoulders behind a desk, which is what
sitting looks like from the front, and `idle_up` below the desk is a back view
that needs no trick at all. See `seat`. Nothing new has to be drawn or
imported for the room to face the camera.

**Position and depth are different numbers.** Every prop resting on another —
a monitor on a desk, a patient in a bed, a cup on a table — is drawn above the
surface's floor point, so sorting it on its own floor point puts it *behind*
the thing it stands on. The surface then paints over it. The symptom is
specific and survived two renders unread: monitors that look like screens
hovering with no base, because only the part clearing the desk's back edge
came through. See `place` and `on_desk`. A `SCENE_DEBUG=1` render draws every
ink box and floor point, which is the fastest way to see it.

The other half of the same class of bug is coordinates chosen against a room's
*rect* rather than its *floor* — the north wall eats the top two tiles, so a
5-tile room has 3 tiles of floor. `floor_of` reports anything standing outside
one, which is how the figures on walls were found rather than guessed at.

**Props have a facing, and the pack only draws one of them.** Every monitor
in 12,279 props is face-on with its keyboard below, so it can only belong to
someone sitting *below* it, facing away. `chair_conference` puts the backrest
on the far side, for someone facing the camera; `chair_office_back` puts it
nearest, for someone facing away. Get either wrong and you have people staring
at the back of their own screen and sitting the wrong way round in their
chairs — which is what the first four renders of these scenes did, and what
made them read as almost-right rather than right. `desk_pod` and `chair`
enforce both, and nothing places a chair or a screen except through them.

# Why there is a linter in here

Everything above was found by looking at pictures one prop at a time, which is
slow, misses whatever is only wrong at 1x, and had me fixing symptoms in the
order I happened to notice them. `check_continuity` replaces that with five
rules, checked exhaustively on every run:

  R1  wall decor hangs on an actual wall, and not in a doorway
  R2  furniture stands on a floor — the walkable part, not the room's rect
  R3  and on one floor: no footprint straddling a wall or the plan's edge
  R4  no two pieces of furniture in the same floor space
  R5  anything resting on a surface is fully on some particular surface
  R6  nothing stands in a doorway
  R7  nothing is drawn and then buried by what is painted over it
  R8  a row of one name is not a row of one sprite

Its first run reported **43 violations across three scenes that had already
been eyeballed and called finished**, including two figures standing on walls,
a sign hanging in a doorway, six appliances inside a 416x72 prop that turned
out to be an entire wall of fridges rather than one, and cups floating beside
a table. R5 alone found nine. None of these were visible at 1x.

R6 and R7 came later, from an outside read of the finished renders, and they
matter more than the first five because they catch what *looks* right. R6
found a ticket office parked across the full width of a doorway and a plant in
another; R7 found a 140x86 dinosaur entirely inside that ticket office, a
visitor reduced to a floating clump of hair, an exit sign under a painting and
four mugs at 100% buried. Every one of those was correctly placed by R1-R5 —
they are not misplaced, they are underneath something — and every one of them
rendered, cost draw time, and could not be seen.

R8 is the subtlest and catches the most embarrassing class. `ink` narrows a
name to one piece of its family, which also shrinks the pool it indexes into —
often to two. A stride chosen against the full family then aliases: `3 + i * 4`
over a pool of two is odd every time. The ward drew all six of its nightstands
from one file, three identical patients per row, and three identical benches in
an unbroken run that reads as a fence. Each placement was individually correct.
It is judged against what is *reachable*, so a name with one catalogue entry is
not a complaint.

The same read found three structural bugs, all invisible from inside:
`_open_at`, step 2 of `draw_plan`, and the cap tiles — a boundary drawn
correctly by each of the two rooms that share it and walled over between them;
a doorway patched with two different floors stacked; and four of eight surfaces
built on a mid-run cap tile that omits the wall's outer edge.

Uses Pillow, which the app's own pipeline avoids — fine here, because nothing
in this file is part of the build. `scripts/process-assets.py` stays stdlib.
"""

import importlib.util
import json
import os
import sys

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "assets")
CATALOGUE = os.path.join(ASSETS, "catalogue.json")
BUILDER = os.path.join(ASSETS, "processed", "room", "32x32", "builder-full")
CHARS = os.path.join(ASSETS, "processed", "characters", "32x32")
SHEET = os.path.join(ASSETS, "Modern_Office_Revamped_v1.2",
                     "1_Room_Builder_Office", "Room_Builder_Office_32x32.png")

PANEL = (720, 400)
TILE = 32
# 22x12 tiles is 704x384 — the largest whole-tile plan that fits, leaving an
# 8 px surround so the plan reads as a drawing rather than a bleeding edge.
PLAN = (22, 12)
ORIGIN = (8, 8)
OUTSIDE = (34, 34, 44)

# ---------------------------------------------------------------------------
# Tile roles
#
# Established by rendering all 161 non-empty tiles to a labelled 3x grid and
# looking, then confirming each candidate's pixel cross-section.
#
# **We cut our own tiles rather than reading `processed/room/32x32/builder/`.**
# That directory is the app's, and `process-assets.py` drops every tile under
# 60% opaque on the grounds that a mostly-transparent tile is edge trim and
# laying it as floor would show the void behind the room. That rule is right
# for the app and wrong here: the entire thin-wall vocabulary — every plain
# horizontal and vertical run, every T-junction, every doorway jamb — is a
# 12 or 14 px line on an otherwise empty tile, so all of it falls under the
# cut. 141 tiles survive there; 161 exist. The missing 20 are exactly the
# pieces a floor plan is drawn with.
#
# So `_cut_tiles` slices the raw sheet and applies `process-assets.room_colour`
# at the same VALUE_FLOOR, which reproduces the app's own output byte for byte
# on the 141 tiles they share (verified) while keeping the other 20. Importing
# the transform rather than copying it means the two cannot drift.
#
#   rows 0-3, cols 0-9   structural thin walls. Wall = white 232 body with
#                        2 px 154,154,170 edges. Horizontal runs occupy the
#                        top 12 rows of a tile, vertical runs the left or
#                        right 14 columns. Survivors, all corners:
#                          r01_c05 r02_c01 r03_c01 r03_c04  north + east
#                          r01_c06 r02_c02 r03_c02 r03_c03  north + west
#                        WALL_CORNER below is the master they are cut from.
#   rows 0-3, cols 10-12 solid white wall mass (thick-wall interiors), plus
#                        r02_c14 which is fully transparent trim.
#   r00_c08              flat dark slab, the pack's shadow/void swatch.
#   rows 5,7,9,11 c0-c9  WALL CAP tiles: 12 px floor-plan line + 20 px face.
#                        c3/c7/c8/c9 carry the brightest cap highlight.
#   rows 6,8,10,12 c0-c9 WALL BODY tiles: 30 px face + 2 px baseboard.
#                        (c4-c6 are missing from every body row.)
#   rows 5..12, c10-c15  FLOORS, six per row-pair:
#                        r05/r06 c10-12 pale slab   c13-15 pale plank
#                        r07/r08 c10-12 grey micro  c13-15 tan carpet
#                        r09/r10 c10-12 grey lino   c13-15 tan lino
#                        r11/r12 c10-15 mauve lino
#
# Doorways are gaps rather than tiles, which is what Office_Design_2 draws
# anyway: the line and the face stop, and the floor beyond shows through.

# **Only columns 0-2 of a cap row carry the wall's top edge.** Every cap tile
# is 12 px of floor-plan line over 20 px of face, but the line is only drawn
# complete — 2 px dark, 8 px white, 2 px dark — in the first three columns.
# Columns 3-9 omit the top 2 px because they are mid-run pieces meant to butt
# against something above them. Four of these eight surfaces were built on c07
# and drew every room's north wall with its outer edge missing, which reads at
# 1x as a wall that fades into the background instead of ending.
SURFACES = {
    # name:      (floor,          cap,             body)
    "concrete":  ("tile_r07_c11.png", "tile_r07_c00.png", "tile_r08_c00.png"),
    "slab":      ("tile_r05_c11.png", "tile_r05_c00.png", "tile_r06_c00.png"),
    "plank":     ("tile_r05_c14.png", "tile_r05_c01.png", "tile_r06_c01.png"),
    "carpet":    ("tile_r07_c14.png", "tile_r09_c00.png", "tile_r10_c00.png"),
    "lino":      ("tile_r09_c11.png", "tile_r11_c00.png", "tile_r12_c00.png"),
    "lino_tan":  ("tile_r09_c14.png", "tile_r09_c02.png", "tile_r10_c02.png"),
    "mauve":     ("tile_r11_c12.png", "tile_r11_c01.png", "tile_r12_c01.png"),
    "white":     ("tile_r05_c10.png", "tile_r07_c02.png", "tile_r08_c02.png"),
}

WALL_H = 2 * TILE           # cap tile + body tile
LINE_H = 12                 # horizontal floor-plan line, measured
LINE_V = 14                 # vertical floor-plan line, measured
# Measured down x=16 of tile_r01_c01: 2 px edge, 8 px fill, 2 px edge. The
# vertical run is the same section rotated, 2/10/2 across 14 px. Knowing the
# exact section is what lets `Wall` draw runs and junctions procedurally in
# the artist's own ink instead of trying to tile pre-drawn corner pieces.
EDGE = (154, 154, 170, 255)
FILL = (232, 232, 232, 255)


# ---------------------------------------------------------------------------
# Art loading

def _cut_tiles():
    """Slice every non-empty tile out of the Room Builder sheet, once."""
    if os.path.isdir(BUILDER) and len(os.listdir(BUILDER)) >= 161:
        return
    spec = importlib.util.spec_from_file_location(
        "process_assets", os.path.join(REPO, "scripts", "process-assets.py"))
    pa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pa)
    os.makedirs(BUILDER, exist_ok=True)
    sheet = Image.open(SHEET).convert("RGBA")
    cache = {}
    for r in range(sheet.height // TILE):
        for c in range(sheet.width // TILE):
            src = sheet.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE))
            px = list(src.getdata())
            if not any(p[3] for p in px):
                continue
            out = []
            for red, green, blue, alpha in px:
                if alpha == 0:
                    out.append((0, 0, 0, 0))
                    continue
                key = (red, green, blue)
                hit = cache.get(key)
                if hit is None:
                    hit = cache[key] = pa.room_colour(red, green, blue, pa.VALUE_FLOOR)
                out.append((hit[0], hit[1], hit[2], alpha))
            im = Image.new("RGBA", (TILE, TILE))
            im.putdata(out)
            im.save(os.path.join(BUILDER, "tile_r%02d_c%02d.png" % (r, c)))


_tiles = {}


def tile(name):
    if name not in _tiles:
        _tiles[name] = Image.open(os.path.join(BUILDER, name)).convert("RGBA")
    return _tiles[name]


def fill_tiled(canvas, name, box):
    """Tile `name` over `box`, phase-locked to the plan origin so the pattern
    runs continuously from room to room the way a real floor does."""
    im = tile(name)
    x0, y0, x1, y1 = box
    # Snap back to the nearest tile boundary, fill whole tiles, then crop to
    # the box — `alpha_composite` cannot take a negative offset, so the phase
    # has to come from the crop rather than from the paste.
    sx = (x0 // im.width) * im.width
    sy = (y0 // im.height) * im.height
    scratch = Image.new("RGBA", (x1 - sx, y1 - sy))
    for y in range(0, scratch.height, im.height):
        for x in range(0, scratch.width, im.width):
            scratch.alpha_composite(im, (x, y))
    canvas.alpha_composite(scratch.crop((x0 - sx, y0 - sy, x1 - sx, y1 - sy)),
                           (x0, y0))


def load_index():
    with open(CATALOGUE) as fh:
        data = json.load(fh)
    by_name = {}
    for e in data["entries"]:
        if e["size_set"] != "32x32" or "name" not in e:
            continue
        by_name.setdefault(e["name"], []).append(e)
    for v in by_name.values():
        v.sort(key=lambda e: e["file"])
    return by_name


_props = {}


def prop(by_name, name, variant=0, ink=None):
    """One named prop's image and its content box, or None if absent.

    # Why `ink` exists, and why leaving it off is usually the bug

    A catalogue name is a *family*, not an object. `desk_corner_l` has 49
    entries and they are five finishes of the same ten pieces: a 32x16 back
    strip, a 32x32 surface with no legs, a 32x32 front with legs, a 64x38
    desk and a 64x64 L-desk. Only the last two are furniture; the rest are
    **modular segments** meant to be laid in runs. `partition` is worse — its
    six entries are a 6x86 post, a 64x42 panel and a 32x86 corner, so five in
    six draws a bare pole.

    Asking for variant 0 and hoping therefore produces a floor strewn with
    fragments, which is exactly what the first pass of this file rendered:
    poles standing where desks were meant to be. Selecting on ink dimensions
    picks the *piece*, and the variant index then walks the finishes of that
    piece rather than the pieces of that finish.
    """
    entries = by_name.get(name)
    if not entries:
        return None
    if ink is not None:
        sized = [e for e in entries
                 if (e["content_box"]["w"], e["content_box"]["h"]) == ink]
        if not sized:
            return None
        entries = sized
    pool = len({e["file"] for e in entries})
    e = entries[variant % len(entries)]
    key = e["file"]
    if key not in _props:
        path = os.path.join(ASSETS, e["file"])
        if not os.path.exists(path):
            path = os.path.join(REPO, e["file"])
        if not os.path.exists(path):
            return None
        _props[key] = Image.open(path).convert("RGBA")
    return _props[key], e["content_box"], key, pool


def character(variant, pose, facing, frame=0):
    p = os.path.join(CHARS, variant, "%s_%s_%02d.png" % (pose, facing, frame))
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


# ---------------------------------------------------------------------------
# Wall runs

class Wall:
    """Accumulates wall geometry, then rasterises it in two passes so that
    every junction — corner, T, cross — closes without special-casing."""

    def __init__(self):
        self.rects = []   # (x0, y0, x1, y1) of the *white* core

    def horizontal(self, x0, x1, y):
        """Line whose 12 px section sits above the boundary at `y`."""
        self.rects.append((x0, y - LINE_H + 2, x1, y - 2))

    def vertical(self, y0, y1, x):
        """Line whose 14 px section straddles the boundary at `x`."""
        self.rects.append((x - LINE_V // 2 + 2, y0, x + LINE_V // 2 - 2, y1))

    def draw(self, canvas):
        d = ImageDraw.Draw(canvas)
        for x0, y0, x1, y1 in self.rects:
            d.rectangle([x0 - 2, y0 - 2, x1 + 1, y1 + 1], fill=EDGE)
        for x0, y0, x1, y1 in self.rects:
            d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=FILL)


# ---------------------------------------------------------------------------
# The plan

class Room(dict):
    """A rect in TILE units plus its finishes. `doors` cut the walls."""

    def __init__(self, name, x, y, w, h, surface, doors=(), band=True):
        dict.__init__(self, name=name, x=x, y=y, w=w, h=h,
                      surface=surface, doors=list(doors), band=band)

    def __getattr__(self, k):
        return self[k]


def _door_spans(room, side):
    """Doorway spans on `side`, in tile units along that side."""
    out = []
    for d in room["doors"]:
        if d[0] != side:
            continue
        out.append((d[1], d[1] + d[2]))
    return out


def _cut(spans, a, b):
    """True if tile [a, b) falls inside any doorway span."""
    return any(s <= a and b <= e for s, e in spans)


OPPOSITE = {"north": "south", "south": "north",
            "west": "east", "east": "west"}


def _open_at(rooms, room, side, t):
    """Is `room`'s `side` open at tile `t` (absolute, along that side)?

    **A boundary between two rooms belongs to both of them, and each draws its
    own half.** So a door declared by one room is walled over by its neighbour
    unless the neighbour is asked too. That is not a hypothetical: the meeting
    room declared a west door onto the open plan, the open plan drew its east
    wall across the whole shared edge, and the result was a meeting room with
    no way in — reachable only by going through the break room. It rendered as
    an unbroken wall and nothing complained, because from each room's own point
    of view the drawing was correct.

    Rather than make callers remember, every wall query comes through here and
    asks both sides.
    """
    if side in ("north", "south"):
        local = t - room.x
        edge = room.y if side == "north" else room.y + room.h
        probe = (t, edge - 1 if side == "north" else edge)
    else:
        local = t - room.y
        edge = room.x if side == "west" else room.x + room.w
        probe = (edge - 1 if side == "west" else edge, t)
    if _cut(_door_spans(room, side), local, local + 1):
        return True
    other = room_at(rooms, probe[0], probe[1])
    if other is None or other is room:
        return False
    far = OPPOSITE[side]
    base = other.x if side in ("north", "south") else other.y
    return _cut(_door_spans(other, far), t - base, t - base + 1)


def room_at(rooms, tx, ty):
    for r in rooms:
        if r.x <= tx < r.x + r.w and r.y <= ty < r.y + r.h:
            return r
    return None


def draw_plan(rooms):
    W, H = PLAN[0] * TILE, PLAN[1] * TILE
    canvas = Image.new("RGBA", (W, H), OUTSIDE + (255,))

    # 1. Floors first, over the whole rect. Anything a doorway later cuts
    #    through therefore lands on real floor, not on the void.
    for r in rooms:
        floor = SURFACES[r.surface][0]
        fill_tiled(canvas, floor,
                   (r.x * TILE, r.y * TILE, (r.x + r.w) * TILE, (r.y + r.h) * TILE))

    # 2. North wall band: cap tile row then body tile row, per column,
    #    skipping doorway columns.
    #
    #    Nothing is drawn in the gap. Step 1 already laid this room's floor
    #    across the whole rect, so leaving the band off shows a clean 64 px of
    #    it — a threshold. An earlier version patched the gap's top tile with
    #    the floor of the room *beyond*, which put two different floor
    #    materials one above the other and left a hard seam across the middle
    #    of every doorway that read as a step.
    for r in rooms:
        if not r.band:
            continue
        _, cap, body = SURFACES[r.surface]
        for tx in range(r.x, r.x + r.w):
            if _open_at(rooms, r, "north", tx):
                continue
            canvas.alpha_composite(tile(cap), (tx * TILE, r.y * TILE))
            canvas.alpha_composite(tile(body), (tx * TILE, (r.y + 1) * TILE))

    # 3. Contact shadow the wall casts onto its own floor. The artists paint
    #    this in; without it the band floats.
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ds = ImageDraw.Draw(shade)
    for r in rooms:
        if not r.band:
            continue
        for tx in range(r.x, r.x + r.w):
            if _open_at(rooms, r, "north", tx):
                continue
            y = (r.y + 2) * TILE
            for i, a in enumerate((70, 46, 26, 12)):
                ds.rectangle([tx * TILE, y + i, tx * TILE + 31, y + i],
                             fill=(24, 24, 34, a))
    canvas.alpha_composite(shade)

    # 4. The other three edges, as lines. A room's bottom edge is only drawn
    #    where no room below is about to draw its own cap line there.
    wall = Wall()
    for r in rooms:
        for tx in range(r.x, r.x + r.w):
            if _open_at(rooms, r, "south", tx):
                continue
            below = room_at(rooms, tx, r.y + r.h)
            if below is not None and below.y == r.y + r.h and below["band"]:
                continue
            wall.horizontal(tx * TILE, (tx + 1) * TILE, (r.y + r.h) * TILE)
        for side, bx in (("west", r.x), ("east", r.x + r.w)):
            for ty in range(r.y, r.y + r.h):
                if _open_at(rooms, r, side, ty):
                    continue
                wall.vertical(ty * TILE, (ty + 1) * TILE, bx * TILE)
    wall.draw(canvas)

    # 5. Jambs: a doorway cut through the 64 px band leaves two raw edges.
    d = ImageDraw.Draw(canvas)
    for r in rooms:
        if not r.band:
            continue
        for s, e in _door_spans(r, "north"):
            for tx in (r.x + s, r.x + e):
                d.rectangle([tx * TILE - 1, r.y * TILE,
                             tx * TILE, (r.y + 2) * TILE - 1], fill=EDGE)
    return canvas


# ---------------------------------------------------------------------------
# Dressing

def place(canvas, items):
    """Bottom-centre every item's *ink* on its floor point and depth-sort by
    that point's y — the same convention the app uses, so a scene that reads
    here is telling the truth about what the app could draw.

    # Position and depth are not the same number

    The convention above works for things standing on the floor and breaks for
    everything standing on something else. A monitor on a desk has to be drawn
    *higher* than the desk's floor point, because it sits on a raised surface —
    but drawing it higher means sorting it behind, so the desk paints over it
    and the desk is bare. The first version of `desk_pod` hit this from both
    sides at once: monitors vanished under desks, and the seated figure meant
    to be *occluded* by a desk was the one thing drawn in front of it.

    So an item carries a sort key separate from its floor point. `z:` in the
    spec flags offsets it: `z:+2` puts a prop just in front of the surface it
    rests on while leaving it drawn where it looks right, and a negative one
    pushes a figure behind the desk it is sitting at. The two are independent
    because in a projection like this they were never the same thing.
    """
    shade = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(shade)
    for _, im, box, x, y, sh, *_r in sorted(items, key=lambda i: (i[0], i[3])):
        if sh:
            w = max(10, (box["w"] if box else im.width // 2))
            ds.ellipse([x - w // 2, y - 5, x + w // 2, y + 4],
                       fill=(20, 20, 30, 58))
    canvas.alpha_composite(shade)
    for _, im, box, x, y, _, *_r in sorted(items, key=lambda i: (i[0], i[3])):
        if box is None:
            canvas.alpha_composite(im, (x - im.width // 2, y - im.height))
        else:
            canvas.alpha_composite(
                im, (x - (box["x"] + box["w"] // 2), y - (box["y"] + box["h"])))


def _flags(entry):
    """`("wall", "ink:64x64", "z:+2")` -> (kind, (64, 64), 2).

    `kind` is what the prop is standing on, and every continuity rule keys off
    it: "floor" for furniture, "wall" for something hung on a wall face, "on"
    for anything resting on other furniture. It used to be a single `flat` flag
    meaning only "draw no shadow", which conflated a picture on a wall with a
    mug on a desk — and a checker cannot tell those apart, so neither could I.
    """
    kind, ink, z = "floor", None, 0
    for f in (entry[4] if len(entry) > 4 else ()):
        if f == "wall":
            kind = "wall"
        elif f == "flat":
            # `flat` alone is wall decor; `flat` with a `z` is something
            # resting on furniture. The two are distinguishable without a
            # third flag because a prop on a surface *must* carry a z — with
            # z 0 it sorts behind its own support and is painted over. So a
            # flat prop with no z has nothing under it but a wall.
            kind = "wall"
        elif f == "ground":
            # Lying on the floor rather than standing on it: a mat, a rug, a
            # dropped toy, a low platform. Casts no shadow and is not wall
            # decor, and nothing is wrong with something else standing on it.
            kind = "ground"
        elif f == "seat":
            # A chair with somebody in it. Exempt from the shared-floor rule
            # for the obvious reason.
            kind = "seat"
        elif f.startswith("ink:"):
            w, h = f[4:].split("x")
            ink = (int(w), int(h))
        elif f.startswith("z:"):
            z = int(f[2:])
    return ("on" if kind == "wall" and z else kind), ink, z


def floor_of(rooms, x, y):
    """The room whose *walkable* floor contains (x, y), or None.

    A room's rect is not its floor. The north wall eats the top two tiles of
    it, so a 9x5 room has 5 tiles of rect and 3 of floor, and coordinates
    chosen against the rect land a third of the way up a wall. This is how the
    meeting room ended up with a conference table and four chairs standing on
    the break room's wall band below it — every one of those y values was
    inside the room by the rect and outside it by the floor.
    """
    for r in rooms:
        top = (r.y + 2) * TILE if r["band"] else r.y * TILE
        if r.x * TILE <= x < (r.x + r.w) * TILE and \
                top <= y <= (r.y + r.h) * TILE:
            return r
    return None


# ---------------------------------------------------------------------------
# Continuity
#
# Everything below is here because eyeballing renders does not scale. Each of
# these rules was broken in a shipped scene and found by looking at a picture
# one prop at a time, which is the slowest possible way to find any of them and
# misses the ones that are only wrong at 1x. They are cheap to check and the
# check is exhaustive, so the composer checks them on every run.

def _band_of(rooms, x, y):
    """The room whose north wall band covers (x, y), or None."""
    for r in rooms:
        if not r["band"]:
            continue
        if r.x * TILE <= x < (r.x + r.w) * TILE and \
                r.y * TILE <= y < (r.y + 2) * TILE:
            return r
    return None


def _door_gap(room, side, x, y):
    """True if (x, y) falls in a doorway cut through `room`'s `side`."""
    for s, e in _door_spans(room, side):
        if side in ("north", "south"):
            if (room.x + s) * TILE <= x < (room.x + e) * TILE:
                return True
        elif (room.y + s) * TILE <= y < (room.y + e) * TILE:
            return True
    return False


def _walls_between(rooms, x0, x1, y):
    """Vertical room boundaries strictly inside the span x0..x1 at height y.

    A boundary is a wall. Furniture whose footprint spans one is standing half
    in each of two rooms, with the wall line drawn through it.
    """
    edges = set()
    for r in rooms:
        if r.y * TILE <= y <= (r.y + r.h) * TILE:
            edges.add(r.x * TILE)
            edges.add((r.x + r.w) * TILE)
    return sorted(e for e in edges if x0 < e < x1)


def check_continuity(rooms, placed):
    """Every rule the scenes have broken, as a list of complaints.

    `placed` is (name, x, y, w, h, kind) where kind is "floor", "wall" or
    "on" — resting on other furniture, which is exempt from the floor rules
    because its support is what stands on the floor.
    """
    out = []

    # R8. A row of the same name must not be a row of the same sprite.
    #
    # `ink` narrows a name to one piece of its family, which also shrinks the
    # pool it indexes into — often to two or three. A stride chosen against the
    # full family then aliases: `3 + i * 4` over a pool of 2 is odd every time.
    # The ward drew all six of its nightstands from one file, three identical
    # patients per row, and three identical benches in an unbroken run that
    # reads as a fence. Nothing else notices, because each placement on its own
    # is correct.
    families = {}
    for name, x, y, w, h, kind, source, pool in placed:
        families.setdefault(name, [set(), 0, 0])
        families[name][0].add(source)
        families[name][1] += 1
        families[name][2] = pool
    # Judged against what is *reachable* — a name with one catalogue entry can
    # only ever draw one sprite, and a deliberate subset (only the lit screens,
    # say) is a choice rather than a bug. The complaint is using less than half
    # of what could have been used.
    for name, (sources, count, pool) in families.items():
        if count > 2 and len(sources) * 2 <= min(count, pool):
            out.append("R8 %d x %s draw from %d sprite(s), %d available"
                       % (count, name, len(sources), pool))

    for name, x, y, w, h, kind, _, _p in placed:
        left, right = x - w // 2, x - w // 2 + w
        if kind == "wall":
            # R1. Wall decor hangs on a wall, and a doorway is a hole in one.
            band = _band_of(rooms, x, y)
            if band is None:
                out.append("R1 %s@%d,%d hangs on no wall" % (name, x, y))
            elif _door_gap(band, "north", x, y):
                out.append("R1 %s@%d,%d hangs in a doorway" % (name, x, y))
            elif not (_band_of(rooms, left, y) and _band_of(rooms, right - 1, y)):
                out.append("R1 %s@%d,%d overhangs the wall's end" % (name, x, y))
        elif kind in ("floor", "ground", "seat"):
            # R2. Furniture stands on a floor.
            room = floor_of(rooms, x, y)
            if room is None:
                out.append("R2 %s@%d,%d is not on any floor" % (name, x, y))
                continue
            # R3. And on ONE floor — a footprint spanning a room boundary is
            # a desk with a wall drawn through it.
            if kind != "ground":
                for edge in _walls_between(rooms, left, right, y):
                    if not _door_gap(room, "west" if edge <= x else "east", x, y):
                        out.append("R3 %s@%d,%d straddles the wall at x=%d"
                                   % (name, x, y, edge))
    # R5. Anything resting on furniture has to be resting on some *particular*
    # piece of furniture, with its whole footprint on the surface. Otherwise it
    # is a mug in mid-air beside a desk — which looks, at panel size, exactly
    # like a mug on a desk, so this is not findable by eye.
    supports = [p for p in placed if p[5] == "floor"]
    for name, x, y, w, h, kind, _, _p in placed:
        if kind != "on":
            continue
        left, right = x - w // 2, x - w // 2 + w
        held = False
        for _, fx, fy, fw, fh, _, _s, _p in supports:
            fl = fx - fw // 2
            if fl <= left and right <= fl + fw and fy - fh <= y <= fy:
                held = True
                break
        if not held:
            out.append("R5 %s@%d,%d rests on nothing" % (name, x, y))

    # R4. Two pieces of furniture cannot occupy the same floor.
    #
    # Compared as *footprint rectangles* — the ink's bottom band, which is what
    # touches the ground. An earlier version compared horizontal spans only and
    # skipped any pair whose floor points differed by more than 10 px, which is
    # a hole you can drive furniture through: it passed a bench parked across a
    # plinth (18 px apart), a shelving unit standing inside a dinosaur skeleton
    # (6 px) and a 140 px dinosaur inside a ticket booth (28 px).
    floors = [p for p in placed if p[5] == "floor"]
    for i, (n1, x1, y1, w1, h1, _, _s1, _p1) in enumerate(floors):
        for n2, x2, y2, w2, h2, _, _s2, _p2 in floors[i + 1:]:
            d1, d2 = min(h1, 18), min(h2, 18)
            if y1 - d1 >= y2 or y2 - d2 >= y1:
                continue
            a0, a1 = x1 - w1 // 2, x1 - w1 // 2 + w1
            b0, b1 = x2 - w2 // 2, x2 - w2 // 2 + w2
            share = min(a1, b1) - max(a0, b0)
            if share > max(10, min(w1, w2) // 2):
                out.append("R4 %s@%d,%d and %s@%d,%d share %d px of floor"
                           % (n1, x1, y1, n2, x2, y2, share))

    # R6. A doorway is for walking through. Anything standing in one blocks the
    # only route between two rooms — and both R2 and R3 wave it through,
    # because a door aperture is legitimately outside the floor and legitimately
    # on a wall line. The museum had a ticket office across the whole width of
    # its north door and a potted plant in the west one.
    for name, x, y, w, h, kind, _, _p in placed:
        if kind != "floor":
            continue
        left, right = x - w // 2, x - w // 2 + w
        for r in rooms:
            for side in ("north", "south", "west", "east"):
                for s, e in _door_spans(r, side):
                    if side in ("north", "south"):
                        gy = (r.y if side == "north" else r.y + r.h) * TILE
                        g0, g1 = (r.x + s) * TILE, (r.x + e) * TILE
                        blocked = (min(right, g1) - max(left, g0) > 8
                                   and gy - TILE <= y <= gy + 2 * TILE)
                    else:
                        gx = (r.x if side == "west" else r.x + r.w) * TILE
                        g0, g1 = (r.y + s) * TILE, (r.y + e) * TILE
                        blocked = (left < gx + 10 and right > gx - 10
                                   and g0 <= y <= g1)
                    if blocked:
                        out.append("R6 %s@%d,%d blocks the %s doorway of %s"
                                   % (name, x, y, side, r["name"]))
    return out


def report_hidden(items, size, floor=0.45):
    """Items whose ink is mostly painted over by whatever is drawn after them.

    **A prop that is drawn and then buried is a bug the eye cannot find**, and
    it is the single largest category the placement rules miss. The museum had
    a 140x86 dinosaur entirely inside a ticket booth, a visitor reduced to a
    floating clump of hair, an exit sign under a painting and a picture frame
    half behind a counter. All four rendered; all four were invisible; not one
    broke R1 through R6, because none of them is *misplaced* — they are
    correctly placed underneath something.

    So this composites into an index buffer rather than pixels: every opaque
    pixel records which item drew it last, and an item's surviving share of
    its own ink is how much of it a viewer actually gets. Cheap, exhaustive,
    and it needs no judgement about what ought to be in front of what.
    """
    order = sorted(items, key=lambda i: (i[0], i[3]))
    owner = [-1] * (size[0] * size[1])
    total = [0] * len(order)
    for index, (_, im, box, x, y, _, *_r) in enumerate(order):
        if box is None:
            ox, oy = x - im.width // 2, y - im.height
        else:
            ox, oy = x - (box["x"] + box["w"] // 2), y - (box["y"] + box["h"])
        alpha = im.getchannel("A").load()
        for py in range(im.height):
            gy = oy + py
            if not 0 <= gy < size[1]:
                continue
            row = gy * size[0]
            for px in range(im.width):
                if alpha[px, py] < 128:
                    continue
                gx = ox + px
                if 0 <= gx < size[0]:
                    total[index] += 1
                    owner[row + gx] = index
    seen = [0] * len(order)
    for o in owner:
        if o >= 0:
            seen[o] += 1
    return [(order[i][6], order[i][3], order[i][4], seen[i] / total[i])
            for i in range(len(order))
            if total[i] and seen[i] / total[i] < floor]


def compose(spec, by_name, out_path):
    rooms = spec["rooms"]
    plan = draw_plan(rooms)

    wall_zones = [((r.y) * TILE, (r.y + 2) * TILE) for r in rooms if r.band]
    items, missing, tiny, placed, breaks_hidden = [], [], [], [], []
    for entry in spec["props"]:
        name, x, y = entry[0], entry[1], entry[2]
        variant = entry[3] if len(entry) > 3 else 0
        kind, ink, z = _flags(entry)
        got = prop(by_name, name, variant, ink)
        if got is None:
            missing.append(name if ink is None
                           else "%s ink %dx%d" % ((name,) + ink))
            continue
        box = got[1]
        # A furniture-sized name that resolves to a sliver is a modular segment
        # picked by accident. Report it rather than drawing a pole and calling
        # it a partition — see `prop`'s note on families versus pieces.
        if min(box["w"], box["h"]) < 8:
            tiny.append("%s#%d %dx%d" % (name, variant, box["w"], box["h"]))
        placed.append((name, x, y, box["w"], box["h"], kind, got[2], got[3]))
        items.append((y + z, got[0], box, x, y,
                      kind in ("floor", "seat"), name))
    for entry in spec.get("people", []):
        v, pose, facing, x, y = entry[:5]
        z = entry[5] if len(entry) > 5 else 0
        im = character(v, pose, facing)
        if im is None:
            missing.append("character %s %s_%s" % (v, pose, facing))
            continue
        # A figure seated facing the camera stands *inside* the desk, whose own
        # floor point is what has to be on the floor — so check where the desk
        # is, not where the head is.
        placed.append((v, x, y, im.width, im.height, "seat", v, 1))
        items.append((y + z, im, None, x, y, z >= 0, "character " + v))
    place(plan, items)

    if os.environ.get("SCENE_DEBUG"):
        # Every item's ink rect and floor point, over the finished plan. Which
        # prop is where is not answerable by reading coordinates — a prop's ink
        # sits at an arbitrary offset inside a 64x96 canvas — so the only
        # reliable way to see that a cup is on a desk is to draw the boxes.
        d = ImageDraw.Draw(plan)
        for _, im, box, x, y, _, *_r in items:
            w = box["w"] if box else im.width
            h = box["h"] if box else im.height
            left = x - w // 2
            d.rectangle([left, y - h, left + w - 1, y - 1],
                        outline=(255, 80, 80, 255))
            d.line([x - 3, y, x + 3, y], fill=(80, 255, 120, 255))

    canvas = Image.new("RGBA", PANEL, OUTSIDE + (255,))
    canvas.alpha_composite(plan, ORIGIN)
    canvas.convert("RGB").save(out_path)
    if missing:
        print("  MISSING: %s" % ", ".join(sorted(set(missing))))
    if tiny:
        print("  SLIVERS: %s" % ", ".join(sorted(set(tiny))))
    # A surface is *meant* to disappear under what stands on it — a desk with
    # two screens, a tray and an occupant is doing its job at 30% visible. So
    # anything carrying something is exempt; the rule is about props buried by
    # things that have no business on top of them.
    carrying = set()
    for _, ox, oy, ow, _, okind, _os, _op in placed:
        if okind != "on":
            continue
        for name, fx, fy, fw, fh, fkind, _fs, _fp in placed:
            fl = fx - fw // 2
            if fkind == "floor" and fl <= ox - ow // 2 and \
                    ox - ow // 2 + ow <= fl + fw and fy - fh <= oy <= fy:
                carrying.add((name, fx, fy))
    for label, hx, hy, frac in report_hidden(items,
                                             (PLAN[0] * TILE, PLAN[1] * TILE)):
        if (label, hx, hy) in carrying:
            continue
        breaks_hidden.append("R7 %s@%d,%d is %d%% buried"
                             % (label, hx, hy, 100 - int(frac * 100)))
    breaks = check_continuity(rooms, placed) + breaks_hidden
    if breaks:
        print("  CONTINUITY (%d)" % len(breaks))
        for b in breaks:
            print("    " + b)
    print("  %d props, %d people" % (len(items) - len(spec.get("people", [])),
                                     len(spec.get("people", []))))
    return out_path


# ---------------------------------------------------------------------------
# Helpers for packing rooms densely, because loneliness is what made the old
# scenes look flat.

def row(name, x0, y, n, dx, v0=0, dv=1, flags=()):
    """`n` copies marching right, each a different catalogue variant."""
    return [(name, x0 + i * dx, y, v0 + i * dv, flags) for i in range(n)]


def col(name, x, y0, n, dy, v0=0, dv=1, flags=()):
    return [(name, x, y0 + i * dy, v0 + i * dv, flags) for i in range(n)]


def grid(name, x0, y0, nx, ny, dx, dy, v0=0, flags=()):
    out = []
    for j in range(ny):
        for i in range(nx):
            out.append((name, x0 + i * dx, y0 + j * dy, v0 + j * nx + i, flags))
    return out


# The 64x64 L-desk and the 64x38 straight desk are the only two entries in the
# 49-strong `desk_corner_l` family that are furniture rather than modular
# surface segments.
#
# **The straight desk is the one to build on, and the L is a trap.** Measured
# by alpha-scanning both, relative to the floor point the ink is bottom-centred
# on:
#
#   straight 64x38   x-32..x+31 solid from y-38 down to y-7, then a single
#                    leg at x-32..x-1 for the last 6 px. A plain slab.
#   L 64x64          only the RIGHT half x+0..x+31 exists above y-39. The
#                    top-left quadrant is a 32x25 hole.
#
# The first pod used the L and put a 64-wide rig across its top edge, which
# dropped half of every monitor into that hole — the render showed screens
# hanging in the air beside each desk with nothing under them. On the slab
# there is no hole to fall into, and a 32-wide rig covers exactly half of it.
DESK = ("ink:64x38",)
DESK_TOP = 38          # desk's back edge, above the floor point

# Which of the six 32x42 `workstation_composite` entries have a *lit* screen.
# Two of the six are drawn switched off, and a dark panel at panel size reads
# as a broken monitor rather than as an idle one — the room is meant to look
# staffed.
LIT_RIGS = (0, 1, 3, 4)


def on_desk(lift, ink=None):
    """Flags for a prop resting `lift` px up the desk it stands on.

    **`z` has to exceed `lift`, and by more than one might guess.** A prop on a
    desktop is drawn above the desk's floor point, so its own floor point is
    `y - lift`; sorting on that puts it *behind* by exactly `lift` pixels, and
    a token `z:2` does not begin to cover a 16 px lift. The desk then paints
    over everything below its own back edge, which is most of the prop.

    The symptom is specific and was on screen for two renders before anyone
    read it correctly: monitors that look like screens hovering with no base,
    because only the part clearing the desk's top edge survives. `lift + 1`
    puts the prop one pixel in front of its desk and nothing else changes.
    """
    flags = ["flat", "z:%d" % (lift + 1)]
    if ink is not None:
        flags.append("ink:%dx%d" % ink)
    return tuple(flags)


# ---------------------------------------------------------------------------
# Seating a character at a desk, in all four directions
#
# The character pack ships `sit` in **left and right only** — there is no
# front- or back-facing seated pose at any size, which is why every room this
# project has drawn so far has its cast side-on. That looked like a hard limit
# on the art. It is not; it is a limit on the *pose*, and a seat is made of a
# pose and an occlusion.
#
#   facing the camera   `idle_down`, standing, planted **inside** the desk's
#                       footprint and sorted above it. `place` depth-sorts on
#                       the floor point, so the desk draws over the legs and
#                       what is left is a head and shoulders behind a desk —
#                       which is what sitting looks like from the front.
#   facing away         `idle_up`, standing below the desk with a chair. No
#                       occlusion needed; a back view is a back view.
#
# So all four directions are available today, from art already imported. The
# only thing that was ever missing was the depth sort.

# Feet this far above the desk's floor point. The figure is ~34 px tall, so
# from a back edge at y-38 this leaves head and shoulders showing and buries
# everything below them — 8 px of overlap is enough to read as "behind", and
# more starts to look decapitated.
SEAT_INSET = 30
# Feet this far below the desk for the back view. The back-view chair is 46 px
# tall against a ~34 px figure, so it swallows an occupant placed level with
# it: the render came out as three empty chairs. Sitting the figure 30 px
# higher than the chair's own floor point leaves its head and shoulders above
# the backrest, which is what somebody in a high-backed chair looks like from
# behind.
SEAT_STANDOFF = 8
CHAIR_DROP = 38     # the chair's floor point, below the desk's


def chair(x, y, v=0, facing="down", flags=()):
    """A chair drawn the right way round for whoever sits in it.

    **Chairs are not symmetric and the pack does not let you pretend they
    are.** `chair_office_swivel` and `chair_conference` are drawn with the
    backrest on the *far* side and the seat toward the viewer, which is the
    chair of somebody facing the camera. `chair_office_back` is the reverse:
    the backrest is nearest, filling the sprite, and the seat is barely
    visible — the chair of somebody facing away.

    Using one for the other is subtle enough to survive several renders and
    obvious once seen, which is the worst combination. It is also not
    checkable by the linter, because both are 'a chair on a floor'. So the
    only defence is that nothing places a chair except through here.

    Two more consequences worth stating, since they are the same rule:

      * A table has chairs on both sides and they are **different art**. The
        far row faces the camera, the near row faces away.
      * A camera-facing desk gets no chair at all — it would be behind the
        desk and entirely hidden.
    """
    if facing == "down":
        return (("chair_conference", x, y, v % 2) + (("ink:26x42",) + flags,))
    return (("chair_office_back", x, y, v % 4) + (("ink:32x46",) + flags,))


def seat(variant, x, y, facing="down"):
    """One character seated at the desk whose floor point is (x, y).

    Offset to the right of centre so the figure clears the rig, which occupies
    the desk's left half.
    """
    if facing == "down":
        return (variant, "idle", "down", x + 8, y - SEAT_INSET)
    return (variant, "idle", "up", x, y + SEAT_STANDOFF)


def desk_pod(x, y, v=0, facing="down"):
    """A desk, the kit on it, and a chair if one would be visible.

    The slab's ink is bottom-centred at (x, y): back edge y-38, front y-1. The
    rig's base lands at y-16, on the desktop rather than over its edge, and its
    screen rises 20 px above the back edge the way the pack's own office GIF
    draws a monitor. `z:` keeps all of it in front of the desk.

    A chair is only emitted for a back-facing seat. Facing the camera, the
    chair is behind the desk and would be entirely hidden — drawing one there
    just puts a stray backrest through the desktop.

    **A monitor can only belong to a seat that faces away from the camera,
    and that is a fact about the art rather than a preference.** Every screen
    in the pack is drawn face-on with its keyboard below it: `monitor_lit`,
    `monitor_dark`, `monitor_off_white`, `laptop_open_lit` and all six 32x42
    `workstation_composite` rigs. There is no rear view of a monitor anywhere
    in 12,279 props. A screen facing the camera is therefore being *looked at*
    from below, by someone sitting between it and the viewer.

    So a camera-facing occupant cannot have one. Giving them a screen puts
    them behind their own monitor looking at its back — which is what the
    first three renders of this scene showed, six times over.

    Camera-facing desks get orientation-neutral kit instead: paper, a tray, a
    mug, a lamp. Those read the same from either side, and the split gives the
    floor something the app wants anyway — desks that look like different
    kinds of work.
    """
    out = [("desk_corner_l", x, y, v, DESK)]
    if facing == "up":
        out += [
            # Two screens, filling the slab. Ink 32 wide against 64, so x-16
            # and x+16 tile it exactly. Base 16 px up the desk, screen clearing
            # the back edge by 20 px the way the pack's own GIF draws it.
            ("workstation_composite", x - 16, y - 16, LIT_RIGS[(3 * v) % 4],
             on_desk(16, (32, 42))),
            ("workstation_composite", x + 16, y - 16, LIT_RIGS[(3 * v + 1) % 4],
             on_desk(16, (32, 42))),
            chair(x, y + CHAIR_DROP, v, "up", ("seat",)),
        ]
    else:
        out += [
            # 24x24 is the loose sheaf; the 32x42 entry is a filing tower and
            # overhangs the desk's right edge when centred this close to it.
            ("document_tray", x - 16, y - 16, v % 2, on_desk(16)),
            ("paper_stack", x + 18, y - 14, (v + 1) % 3, on_desk(14, (24, 24))),
            ("coffee_cup", x + 20, y - 10, 0, on_desk(10)),
        ]
    return out


# ---------------------------------------------------------------------------
# Three plans. Coordinates are plan pixels: (0, 0) is the plan's top-left,
# 704x384 overall, TILE=32.

def engineering():
    rooms = [
        Room("open plan", 0, 0, 13, 12, "concrete",
             doors=[("east", 8, 3)]),
        # 6 tiles each. A room's floor is its rect minus the two tiles its
        # north wall eats, so 6 tiles is 128 px of floor and 5 was 96 — not
        # enough for a table with a chair row on each side, which is why the
        # first draft put four of them on the break room's wall.
        Room("meeting", 13, 0, 9, 6, "carpet",
             doors=[("west", 3, 2)]),
        Room("break", 13, 6, 9, 6, "plank", doors=[("west", 2, 3)]),
    ]
    props = []
    # Open plan: whiteboard and chart on the north face, four desk pods.
    props += [("whiteboard_blank", 90, 60, 0, ("flat",)),
              ("chart_board", 200, 60, 1, ("flat",)),
              ("picture_framed", 280, 54, 3, ("flat",)),
              ("board_schedule", 340, 58, 2, ("flat",)),
              ("clock", 30, 52, 0, ("flat",))]
    seats = [(76, 162, "down"), (200, 162, "up"), (324, 162, "down"),
             (76, 306, "up"), (200, 306, "down"), (324, 306, "up")]
    for i, (sx, sy, f) in enumerate(seats):
        props += desk_pod(sx, sy, i, f)
    # Litter between the pods. Office_Design_2's lesson is that the gaps
    # between clusters are never bare floor, so every lane here gets something.
    props += [("plant_potted", 24, 118, 2, ()),
              ("plant_potted", 24, 372, 5, ()),
              ("printer_desk_composite", 384, 190, 0, ()),
              ("printer", 384, 250, 7, ("ink:30x36",)),
              ("cabinet_drawers", 388, 300, 0, ()),
              ("cabinet_drawers", 356, 356, 2, ()),
              ("water_cooler", 384, 366, 0, ()),
              ("pc_tower", 30, 250, 1, ("ink:26x44",)),
              ("pc_tower", 136, 344, 0, ("ink:26x44",)),
              ("pc_tower", 254, 206, 2, ("ink:26x44",)),
              ("bin", 150, 250, 2, ()),
              ("bin", 252, 374, 6, ()),
              ("cabinet_drawers", 26, 302, 4, ()),
              ("plant_potted", 250, 118, 9, ()),
              ("plant_potted", 366, 118, 13, ()),
              ("backpack", 118, 226, 0, ("ground",)),
              ("backpack", 252, 356, 1, ("ground",))]
    # Meeting room: long table, chairs down both sides, screen on the face.
    #
    # The table is two 52x42 `table_metal` slabs abutted, not a run of
    # `desk_counter`: that name's 32x46 entries are counter *segments* in three
    # finishes, and stepping the variant along a row walks the finishes rather
    # than the segments, so a four-piece run came out three tan and one grey.
    props += [("tv_wall", 566, 60, 1, ("flat",)),
              ("certificate", 648, 52, 0, ("flat",)),
              ("noticeboard", 484, 56, 0, ("flat",))]
    props += row("table_metal", 522, 160, 2, 52, v0=0, dv=3,
                 flags=("ink:52x40",))
    props += [chair(512 + i * 26, 116, i, "down") for i in range(4)]
    props += [chair(514 + i * 34, 192, i, "up") for i in range(3)]
    props += [("plant_potted", 442, 110, 8, ()),
              ("plant_potted", 690, 112, 12, ()),
              ("water_cooler", 688, 182, 0, ()),
              ("printer", 444, 186, 6, ("ink:30x32",)),
              ("document_tray", 522, 148, 0, on_desk(26)),
              ("paper_stack", 574, 146, 0, on_desk(24, (24, 24))),
              ("coffee_cup", 552, 146, 0, on_desk(24)),
              ("coffee_cup", 588, 144, 0, on_desk(22))]
    # Break room: counters, cafe tables, sofa, vending.
    # The break room's north wall is 64 px of the panel's 400 and was carrying
    # two objects. The pack's own rooms hang something every two tiles.
    props += [("noticeboard", 456, 244, 1, ("flat",)),
              ("clock", 508, 232, 0, ("flat",)),
              ("sign_cafe", 640, 240, 0, ("flat",)),
              ("poster", 676, 244, 0, ("flat",))]
    props += [("coffee_machine", 458, 300, 0, ()),
              ("coffee_machine", 490, 300, 3, ()),
              ("vending_machine", 672, 306, 0, ("ink:48x68",)),
              ("water_cooler", 646, 300, 0, ()),
              ("counter_wood", 540, 300, 0, ("ink:32x30",)),
              ("counter_wood", 572, 300, 1, ("ink:32x30",)),
              ("microwave", 540, 292, 0, on_desk(22)),
              ("kettle", 574, 290, 0, on_desk(20)),
              # **No sofas and no tub chairs here.** Both are in the pack and
              # both were tried: at 1x the 62x48 sofa's checkered seat reads as
              # a grate and the 32x36 tub chair reads as a washbasin. Legibility
              # at the size the panel actually runs beats naming the right
              # object, so the break room reuses the meeting room's vocabulary —
              # a metal table with chairs round it, which reads at any size.
              ("table_metal", 500, 356, 1, ("ink:40x34",)),
              ("table_metal", 592, 356, 2, ("ink:48x40",)),
              chair(474, 330, 0, "down"), chair(526, 330, 1, "down"),
              chair(500, 382, 0, "up"),
              chair(566, 332, 0, "down"), chair(620, 332, 1, "down"),
              chair(592, 384, 1, "up"),
              ("plant_potted", 444, 372, 15, ()),
              ("bin", 662, 366, 7, ()),
              ("coffee_cup", 500, 340, 0, on_desk(18)),
              ("coffee_cup", 588, 342, 0, on_desk(20)),
              ("paper_stack", 604, 342, 0, on_desk(20, (24, 24)))]
    cast = ("06", "07", "09", "10", "17", "19")
    people = [seat(cast[i], sx, sy, f)
              for i, (sx, sy, f) in enumerate(seats)]
    return {"name": "01-engineering-office", "rooms": rooms,
            "props": props, "people": people}


def museum():
    rooms = [
        Room("gallery", 0, 0, 14, 12, "slab",
             doors=[("east", 7, 3)]),
        Room("gift shop", 14, 0, 8, 6, "lino_tan", doors=[("west", 3, 2)]),
        Room("entrance", 14, 6, 8, 6, "lino", doors=[("west", 1, 3)]),
    ]
    props = []
    # Gallery: paintings hung along the face, barrier line, then cases.
    props += [("painting_framed", 60, 58, 2, ("flat",)),
              ("painting_framed", 150, 56, 8, ("flat",)),
              ("painting_framed", 240, 58, 14, ("flat",)),
              ("painting_framed", 330, 56, 20, ("flat",)),
              ("painting_framed", 410, 58, 26, ("flat",)),
              ("wall_plaque", 105, 56, 0, ("flat",)),
              ("wall_plaque", 285, 56, 0, ("flat",))]
    props += row("rope_barrier", 40, 104, 10, 44, v0=0, flags=("ground",))
    props += [("column", 20, 200, 1, ()), ("column", 20, 340, 3, ()),
              ("column", 424, 200, 5, ()), ("column", 424, 340, 7, ())]
    props += [("display_case", 104, 196, 2, ("ink:54x88",)),
              ("display_case", 196, 196, 3, ("ink:54x88",)),
              ("display_case", 288, 196, 4, ("ink:54x88",)),
              ("artefact_case", 382, 196, 0, ()),
              ("skeleton", 210, 300, 4, ()),
              ("exhibit_platform", 210, 306, 1, ("ground",)),
              ("statue", 70, 296, 2, ()), ("statue", 350, 296, 6, ()),
              ("amphora_on_plinth", 120, 300, 1, ()),
              ("vase_on_plinth", 300, 300, 2, ()),
              ("plinth", 148, 348, 0, ()),
              ("lectern", 250, 348, 3, ()),
              ("bench", 130, 366, 0, ()), ("bench", 290, 366, 1, ()),
              ("sign_exit", 356, 56, 2, ("flat",)),
              ("plant_potted", 24, 130, 1, ()),
              ("laser_sensor", 60, 150, 0, ("ground",)),
              ("laser_sensor", 390, 150, 3, ("ground",))]
    # Gift shop: shelves along the face, tables of merch, a counter.
    props += [("poster_shirt", 500, 58, 1, ("flat",)),
              ("poster_shirt", 560, 58, 3, ("flat",)),
              ("sign_souvenir", 630, 56, 0, ("flat",))]
    props += row("shop_shelf", 480, 132, 6, 34, v0=5, flags=("ink:32x42",))
    props += [("souvenir_display", 496, 186, 0, ("ink:64x50",)),
              ("display_table", 582, 186, 2, ("ink:60x60",)),
              ("display_table", 662, 186, 5, ("ink:60x60",)),
              ("amphora_souvenir", 480, 176, 2, on_desk(24, (28, 24))),
              ("plush_dinosaur", 576, 172, 5, on_desk(28, (32, 36))),
              ("shirt_folded", 652, 174, 0, on_desk(26, (26, 24))),
              ("shirt_folded", 676, 174, 2, on_desk(26, (26, 24)))]
    # Entrance: ticket desk, turnstiles, benches, a big centrepiece.
    props += [("sign_hanging", 648, 246, 0, ("flat",)),
              ("picture_framed", 470, 250, 0, ("flat",))]
    props += [("ticket_counter", 566, 318, 0, ()),
              ("turnstile", 500, 372, 1, ()),
              ("turnstile", 534, 372, 3, ()),
              ("turnstile", 568, 372, 4, ()),
              ("security_scanner", 478, 336, 0, ()),
              ("bench", 640, 372, 2, ()),
              ("plant_potted", 676, 300, 2, ()),
              ("plant_potted", 692, 300, 0, ()),
              ("sign_exit", 690, 250, 4, ("flat",))]
    people = [("17", "idle", "up", 140, 150), ("07", "idle", "up", 320, 150),
              ("09", "idle", "down", 220, 340), ("19", "idle", "left", 542, 184),
              ("10", "idle", "up", 660, 348), ("06", "walk", "right", 480, 340)]
    return {"name": "02-museum", "rooms": rooms, "props": props,
            "people": people}


def hospital():
    rooms = [
        Room("ward", 0, 0, 12, 12, "white",
             doors=[("east", 8, 3)]),
        Room("reception", 12, 0, 10, 6, "lino", doors=[("west", 3, 2)]),
        Room("play area", 12, 6, 10, 6, "mauve", doors=[("west", 1, 3)]),
    ]
    props = []
    # Ward: two rows of beds head-to-wall, curtains, nightstands, IVs.
    props += [("window", 32, 60, 2, ("flat",)),
              ("clock", 138, 52, 0, ("flat",)),
              ("window", 248, 60, 4, ("flat",)),
              ("sign_medical", 358, 54, 0, ("flat",))]
    # `hospital_bed` has 49 entries across two orientations. The 64x44 piece is
    # the bed seen lengthways, and it is the only one `patient_lying` fits:
    # that prop is a 44x36 figure lying head-to-the-left, so laying it on the
    # 32x72 upright bed would put a sideways person across a vertical mattress.
    # Pairing them by ink is the difference between a ward and a furniture pile.
    BED = ("ink:64x44",)
    IV = ("ink:30x60",)
    for i, x in enumerate((66, 176, 286)):
        props += [("hospital_bed", x, 158, i, BED),
                  ("patient_lying", x - 2, 150, i * 2, on_desk(8, (44, 36))),
                  ("nightstand", x + 48, 176, i, ("ink:32x40",)),
                  ("iv_stand", x - 44, 154, i, IV),
                  ("board_schedule", x + 4, 56, i, ("flat",))]
    for i, x in enumerate((66, 176, 286)):
        props += [("hospital_bed", x, 306, 3 + i, BED),
                  ("patient_lying", x - 2, 298, 1 + i * 2, on_desk(8, (44, 36))),
                  ("nightstand", x + 46, 308, i + 3, ("ink:32x40",)),
                  ("iv_stand", x - 44, 302, 3 + i, IV),
                  chair(x + 20, 348, i, "up")]
    props += [("privacy_screen", 220, 236, 0, ()),
              ("room_divider", 350, 330, 1, ()),
              ("cabinet_medical", 36, 212, 0, ("ink:54x78",)),
              ("shelf_medical", 38, 264, 0, ("ink:58x68",)),
              ("sink_wall", 348, 60, 0, ("flat",)),
              ("dispenser_soap", 316, 60, 0, ("flat",)),
              ("bin", 320, 372, 11, ()),
              ("plant_potted", 24, 372, 1, ()),
              ("wheelchair", 360, 372, 3, ())]
    # Reception: counter, waiting chairs, notice board, vending.
    props += [("counter_reception", 440, 150, 0, ()),
              ("counter_reception", 504, 150, 2, ()),
              ("counter_medical", 568, 150, 0, ()),
              ("plant_potted", 424, 122, 6, ()),
              ("printer", 620, 148, 7, ("ink:30x36",)),
              ("noticeboard", 470, 58, 0, ("flat",)),
              ("board_schedule", 560, 58, 3, ("flat",)),
              ("tv_wall", 640, 58, 2, ("flat",)),
              ("kiosk_touchscreen", 676, 150, 0, ())]
    props += row("chair_waiting", 440, 186, 3, 66, v0=0, dv=1,
                 flags=("ink:62x36",))
    props += [("table_coffee", 620, 188, 6, ("ink:40x36",)),
              ("vending_machine", 664, 188, 0, ("ink:48x68",)),
              ("stanchion_rope", 424, 166, 0, ("ground",)),
              ("stanchion_rope", 600, 166, 2, ("ground",)),
              ("fire_extinguisher", 690, 58, 0, ("flat",))]
    # Play area: mats, kid chairs, toy boxes, easels.
    props += [("chalk_drawing", 470, 250, 0, ("flat",)),
              ("chalk_drawing", 612, 250, 2, ("flat",)),
              ("poster", 640, 248, 0, ("flat",))]
    props += [("play_mat", 500, 320, 0, ("ground",)),
              ("table_round", 590, 320, 3, ("ink:54x54",)),
              ("chair_kids", 560, 316, 2, ()),
              ("chair_kids", 620, 316, 8, ()),
              ("chair_kids", 618, 348, 14, ()),
              ("toy_box", 440, 300, 1, ()),
              ("toy_box_animal", 440, 340, 2, ()),
              ("toy_bin_animal", 676, 300, 1, ()),
              ("easel_chalkboard", 660, 350, 4, ()),
              ("cabinet_kids", 470, 292, 3, ()),
              ("cabinet_kids", 510, 292, 9, ()),
              ("toy_plush", 520, 344, 1, ()),
              ("toy_plush", 546, 350, 4, ()),
              ("toy_figure", 486, 356, 2, ("ground",)),
              ("toy_stacking_ring", 630, 378, 0, ()),
              ("toy_block", 466, 378, 0, ("ground",)),
              ("bench", 600, 380, 3, ())]
    people = [("17", "idle", "down", 120, 200), ("07", "idle", "left", 336, 208),
              ("19", "idle", "down", 500, 132), ("09", "idle", "down", 556, 296),
              ("10", "idle", "down", 448, 366), ("06", "walk", "down", 400, 120)]
    return {"name": "03-hospital", "rooms": rooms, "props": props,
            "people": people}


SCENES = [engineering, museum, hospital]


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else \
        "/Users/henrykanaskie/.claude/jobs/6d016a50/tmp/scenes-v2"
    os.makedirs(out_dir, exist_ok=True)
    _cut_tiles()
    by_name = load_index()
    for build in SCENES:
        spec = build()
        path = os.path.join(out_dir, spec["name"] + ".png")
        print(spec["name"])
        compose(spec, by_name, path)
    print("\n%d scenes -> %s" % (len(SCENES), out_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
